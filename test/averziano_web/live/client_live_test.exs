defmodule AverzianoWeb.ClientLiveTest do
  use AverzianoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Averziano.Training

  setup %{conn: conn} do
    coach = generate(user(name: "Davide Moretti"))
    client = generate(user(name: "Giulia Rossi"))
    program = generate(program(coach: coach, client_id: client.id))

    session =
      generate(
        session(
          program_id: program.id,
          day_label: "C",
          title: "Total body",
          coach_note: "Oggi squat a 50 kg."
        )
      )

    squat = generate(exercise(session_id: session.id, sets_count: 2, rest_seconds: 120))

    %{
      conn: sign_in(conn, client),
      client: client,
      program: program,
      session: session,
      squat: squat
    }
  end

  test "the client app requires a signed-in user" do
    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/app")
  end

  describe "program" do
    test "shows the program, its progress and today's session", ctx do
      {:ok, view, html} = live(ctx.conn, ~p"/app")

      assert html =~ "Ciao Giulia"
      assert html =~ "Forza Base — Blocco 1"
      assert view |> element("#progress") |> render() =~ "0 di 1 giorni"
      assert view |> element("#featured-session") |> render() =~ "Giorno C · Total body"
      assert view |> element("#session-#{ctx.session.id}") |> render() =~ "Oggi"
    end

    test "tells a client without a program that none is assigned yet" do
      conn = sign_in(build_conn(), generate(user()))
      {:ok, view, _html} = live(conn, ~p"/app")

      assert has_element?(view, "#no-program")
    end
  end

  describe "session" do
    test "lists the exercises and starts the workout at the first open one", ctx do
      {:ok, view, html} = live(ctx.conn, ~p"/app/sessions/#{ctx.session.id}")

      assert html =~ "Oggi squat a 50 kg."
      assert view |> element("#exercise-#{ctx.squat.id}") |> render() =~ "2 × 5 rip · 50 kg"

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#start-workout") |> render_click()

      assert to == ~p"/app/sessions/#{ctx.session.id}/exercises/#{ctx.squat.id}"
    end

    test "a session of another client is not found", ctx do
      conn = sign_in(build_conn(), generate(user()))

      assert {:error,
              {:live_redirect, %{to: "/app", flash: %{"error" => "Giornata non trovata"}}}} =
               live(conn, ~p"/app/sessions/#{ctx.session.id}")
    end
  end

  describe "workout" do
    test "completing a set logs it, starts the rest timer and moves to the next set", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/app/sessions/#{ctx.session.id}/exercises/#{ctx.squat.id}")

      refute has_element?(view, "#rest-banner")
      assert view |> element("#current-set") |> render() =~ "Serie 1"

      view |> element("#complete-set") |> render_click()

      assert view |> element("#set-1") |> render() =~ "5 rip · 50 kg"
      assert view |> element("#current-set") |> render() =~ "Serie 2"
      assert view |> element("#rest-banner") |> render() =~ "2:00"

      view |> element("button", "Salta") |> render_click()
      refute has_element?(view, "#rest-banner")

      view |> element(~s{button[phx-click="inc"][phx-value-field="load_kg"]}) |> render_click()
      assert view |> element("#draft-load_kg") |> render() =~ "52,5"
      view |> element("#complete-set") |> render_click()

      assert view |> element("#set-2") |> render() =~ "5 rip · 52,5 kg"
      refute has_element?(view, "#current-set")
      assert view |> element("#next-step") |> render() =~ "Fine giornata"
    end

    test "a sequence set is logged as partial with a note", ctx do
      pyramid =
        generate(
          exercise(
            session_id: ctx.session.id,
            position: 2,
            name: "Piegamenti piramidali",
            kind: :sequence,
            target_reps: nil,
            target_load_kg: nil,
            sets_count: 2,
            sequence: [1, 2, 3, 2, 1]
          )
        )

      {:ok, view, _html} =
        live(ctx.conn, ~p"/app/sessions/#{ctx.session.id}/exercises/#{pyramid.id}")

      view |> element("button", "Parziale") |> render_click()
      view |> element("button", "Aggiungi nota") |> render_click()
      view |> element("#set-note") |> render_change(%{note: "Ultimi step sulle ginocchia"})
      view |> element("#complete-set") |> render_click()

      assert view |> element("#set-1") |> render() =~ "1-2-3-2-1 · parziale"

      {:ok, exercise} =
        Training.get_exercise(pyramid.id, actor: %{"sub" => ctx.client.id}, load: [:set_logs])

      assert [%{outcome: :partial, note: "Ultimi step sulle ginocchia"}] = exercise.set_logs
    end

    test "a timed set records how long the hold lasted when stopped", ctx do
      plank =
        generate(
          exercise(
            session_id: ctx.session.id,
            position: 2,
            name: "Hollow hold",
            kind: :time,
            target_reps: nil,
            target_seconds: 30
          )
        )

      {:ok, view, _html} =
        live(ctx.conn, ~p"/app/sessions/#{ctx.session.id}/exercises/#{plank.id}")

      assert view |> element("#draft-seconds") |> render() =~ "30"

      view |> element("button", "Avvia timer") |> render_click()
      view |> element("button", "Ferma") |> render_click()

      assert view |> element("#draft-seconds") |> render() =~ ">0<"
      assert has_element?(view, "button", "Avvia timer")
    end
  end

  describe "session done" do
    test "sends the note to the coach and completes the session", ctx do
      {:ok, view, html} = live(ctx.conn, ~p"/app/sessions/#{ctx.session.id}/done")

      assert html =~ "Davide vedrà la nota"

      {:ok, _program_view, html} =
        view
        |> form("#session-note", %{client_note: "Squat ok, ultima serie pesante."})
        |> render_submit()
        |> follow_redirect(ctx.conn, ~p"/app?#{[week: 1]}")

      assert html =~ "Giornata inviata a Davide"
      assert html =~ "Completato"

      {:ok, session} = Training.get_session(ctx.session.id, actor: %{"sub" => ctx.client.id})
      assert session.client_note == "Squat ok, ultima serie pesante."
      assert session.completed_at

      {:ok, _view, html} = live(ctx.conn, ~p"/app/sessions/#{ctx.session.id}/done")
      assert html =~ "Inviata a Davide."
    end
  end
end
