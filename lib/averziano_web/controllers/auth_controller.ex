defmodule AverzianoWeb.AuthController do
  @moduledoc """
  Completes AshAuthentication sign-ins (the magic link confirmation posts
  here) and signs out, revoking the session token.
  """

  use AverzianoWeb, :html_controller
  use AshAuthentication.Phoenix.Controller

  alias Averziano.Accounts.User

  @impl AshAuthentication.Phoenix.Controller
  def success(conn, _activity, user, _token) do
    conn
    |> store_in_session(user)
    |> redirect(to: home_path(user))
  end

  @impl AshAuthentication.Phoenix.Controller
  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Il link non è valido o è scaduto. Richiedine uno nuovo.")
    |> redirect(to: ~p"/sign-in")
  end

  @impl AshAuthentication.Phoenix.Controller
  def sign_out(conn, _params) do
    conn
    |> clear_session(:averziano)
    |> put_flash(:info, "Sei uscito.")
    |> redirect(to: ~p"/sign-in")
  end

  @doc "Where a signed-in user lands: the console for the coach, the app for clients."
  @spec home_path(User.t()) :: String.t()
  def home_path(%User{role: :coach}), do: ~p"/admin"
  def home_path(%User{}), do: ~p"/app"

  @doc "`/`: the user's home when signed in, otherwise the sign-in page."
  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    case conn.assigns[:current_user] do
      %User{} = user -> redirect(conn, to: home_path(user))
      nil -> redirect(conn, to: ~p"/sign-in")
    end
  end
end
