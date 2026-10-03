defmodule AverzianoWeb.AuthTest do
  use AverzianoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    coach = generate(coach())
    client = generate(client(coach: coach, email: "giulia@example.com"))
    # The invitation sent while creating the client.
    assert_received {:email, _invitation}
    %{coach: coach, client: client}
  end

  defp request_link(conn, email) do
    {:ok, view, _html} = live(conn, ~p"/sign-in")
    view |> form("#sign-in-form", email: email) |> render_submit()
  end

  defp token_from_email(to) do
    assert_received {:email, %{to: [{"", ^to}], text_body: body}}
    [_, token] = Regex.run(~r{/sign-in/(\S+)}, body)
    token
  end

  test "the coach signs in with a magic link and lands on the console", %{
    conn: conn,
    coach: coach
  } do
    html = request_link(conn, to_string(coach.email))
    assert html =~ "ti abbiamo inviato un link"

    token = token_from_email(to_string(coach.email))

    {:ok, _view, html} = live(conn, ~p"/sign-in/#{token}")
    assert html =~ "Accedi"

    conn = post(conn, ~p"/auth/user/magic_link", token: token)
    assert redirected_to(conn) == ~p"/admin"

    {:ok, _view, html} = conn |> recycle() |> live(~p"/admin")
    assert html =~ "Clienti"
  end

  test "a client lands on the app, and a link works only once", %{conn: conn} do
    request_link(conn, "giulia@example.com")
    token = token_from_email("giulia@example.com")

    signed_in = post(conn, ~p"/auth/user/magic_link", token: token)
    assert redirected_to(signed_in) == ~p"/app"

    again = post(build_conn(), ~p"/auth/user/magic_link", token: token)
    assert redirected_to(again) == ~p"/sign-in"
    assert Phoenix.Flash.get(again.assigns.flash, :error) =~ "non è valido o è scaduto"
  end

  test "unknown addresses get the same answer and no email", %{conn: conn} do
    assert request_link(conn, "nobody@example.com") =~ "ti abbiamo inviato un link"
    refute_received {:email, _}
  end

  test "signing out revokes the session token", %{conn: conn, coach: coach} do
    signed_in = sign_in(conn, coach)
    token = get_session(signed_in, "user_token")
    assert {:ok, _view, _html} = signed_in |> live(~p"/admin")

    signed_out = delete(signed_in, ~p"/sign-out")
    assert redirected_to(signed_out) == ~p"/sign-in"

    # Even a copy of the old session cookie no longer works.
    stale = init_test_session(build_conn(), %{"user_token" => token})
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(stale, ~p"/admin")
  end

  test "/ sends people where they belong", %{conn: conn, client: client} do
    assert conn |> get(~p"/") |> redirected_to() == ~p"/sign-in"
    assert conn |> sign_in(client) |> get(~p"/") |> redirected_to() == ~p"/app"
  end
end
