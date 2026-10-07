defmodule AverzianoWeb.AdminLiveTest do
  use AverzianoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Averziano.Training

  setup %{conn: conn} do
    coach = generate(coach())
    client = generate(client(coach: coach))
    program = generate(program(coach: coach, client_id: client.id))
    today = Date.utc_today()

    [done, next] =
      for {days, week} <- [{0, 1}, {7, 2}] do
        session =
          generate(
            session(
              program_id: program.id,
              week_number: week,
              day_label: "B",
              title: "Stacchi + tirata",
              scheduled_on: Date.add(today, days)
            )
          )

        generate(
          exercise(session_id: session.id, name: "Stacco rumeno", sets_count: 1, target_reps: 10)
        )

        session
      end

    as_client = %{"sub" => client.id}
    [exercise] = Training.get_session!(done.id, actor: as_client, load: [:exercises]).exercises
    Training.log_set!(%{exercise_id: exercise.id, reps: 8, load_kg: 50}, actor: as_client)
    done = Training.complete_session!(done, %{client_note: "Schiena stanca"}, actor: as_client)

    %{
      conn: sign_in(conn, coach),
      coach: coach,
      client: client,
      program: program,
      done: done,
      next: next,
      as_coach: %{"sub" => coach.id},
      as_client: as_client
    }
  end

  test "the console is for coaches only", ctx do
    assert {:error, {:redirect, %{to: "/app"}}} =
             live(sign_in(build_conn(), ctx.client), ~p"/admin")
  end

  describe "clients" do
    test "lists clients with their status and the days to review", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin")

      row = view |> element("#client-#{ctx.client.id}") |> render()
      assert row =~ "Forza Base — Blocco 1"
      assert row =~ "1 da revisionare"

      feed = view |> element("#feed-#{ctx.done.id}") |> render()
      assert feed =~ "ha completato S1 · Giorno B"
      assert feed =~ "con nota"
      assert feed =~ "Revisiona"
    end

    test "invites a client", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/clients/new")

      view
      |> form("#invite-form",
        form: %{first_name: "Luca", last_name: "Ferri", email: "luca@example.com"}
      )
      |> render_submit()

      assert_patch(view, ~p"/admin")
      assert render(view) =~ "Luca Ferri aggiunto ai clienti"
      assert view |> element("#clients") |> render() =~ "Invito inviato"
    end

    test "edits a client's details", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/clients/#{ctx.client.id}")

      view |> element("a", "Modifica") |> render_click()
      assert_patch(view, ~p"/admin/clients/#{ctx.client.id}/edit")

      assert view
             |> form("#edit-client-form", form: %{name: ""})
             |> render_change() =~ "is required"

      view
      |> form("#edit-client-form",
        form: %{name: "Giulia Bianchi", email: "giulia@example.com", phone: "+39 333 1234567"}
      )
      |> render_submit()

      assert_patch(view, ~p"/admin/clients/#{ctx.client.id}")
      assert render(view) =~ "Dati di Giulia Bianchi aggiornati"

      assert view |> element("#client-contacts") |> render() =~
               "giulia@example.com · +39 333 1234567"
    end

    test "someone who isn't the coach's client is not found", ctx do
      stranger = generate(user())

      assert {:error, {:live_redirect, %{to: "/admin"}}} =
               live(ctx.conn, ~p"/admin/clients/#{stranger.id}")
    end
  end

  describe "client review" do
    test "changes the target of the next replica and reviews the day with a comment", ctx do
      {:ok, view, html} =
        live(ctx.conn, ~p"/admin/clients/#{ctx.client.id}?#{[session: ctx.done.id]}")

      assert html =~ "Schiena stanca"
      assert view |> element("#day-#{ctx.done.id}") |> render() =~ "Da revisionare"

      view |> element("button", "Modifica obiettivo") |> render_click()

      view
      |> form("#target-form",
        target: %{sets_count: "4", target_reps: "8", target_load_kg: "50"},
        scope: "future"
      )
      |> render_submit()

      assert render(view) =~ "Obiettivo di Stacco rumeno aggiornato su 1 giornata"

      [replica] =
        Training.get_session!(ctx.next.id, actor: ctx.as_coach, load: [:exercises]).exercises

      assert %{sets_count: 4, target_reps: 8, target_updated_at: %DateTime{}} = replica

      view
      |> form("#review-form", comment: "Scendiamo a 8 ripetizioni.")
      |> render_submit(%{intent: "comment"})

      assert view |> element("#review-done") |> render() =~ "Scendiamo a 8 ripetizioni."
      assert view |> element("#day-#{ctx.done.id}") |> render() =~ "Revisionato"
    end
  end

  describe "templates and the plan editor" do
    test "creates a draft from a template, edits it and publishes it to the client", ctx do
      template = generate(template(coach: ctx.coach))

      {:ok, view, _html} =
        live(ctx.conn, ~p"/admin/templates?#{[use: template.id, client: ctx.client.id]}")

      assert view |> element("#use-panel") |> render() =~ "Giorno A · Upper body"

      {:ok, editor, _html} =
        view
        |> form("#new-program-form",
          program: %{name: "Ipertrofia — Blocco 2", open_editor: "true"}
        )
        |> render_submit()
        |> follow_redirect(ctx.conn)

      assert editor |> element("#plan-title") |> render() =~ "Ipertrofia — Blocco 2"
      # Two weeks from next Monday, Monday and Thursday.
      assert editor |> element("#sessions-count") |> render() =~ "12"

      editor |> element("button", "Aggiungi esercizio") |> render_click()
      assert editor |> element("#exercises") |> render() =~ "Nuovo esercizio"

      {:ok, _client_view, html} =
        editor
        |> element("button", "Pubblica a Giulia")
        |> render_click()
        |> follow_redirect(ctx.conn, ~p"/admin/clients/#{ctx.client.id}")

      assert html =~ "Ipertrofia — Blocco 2 pubblicato a Giulia"

      {:ok, program} =
        Training.latest_client_program(ctx.client.id,
          actor: ctx.as_coach,
          load: [sessions: [:exercises]]
        )

      assert program.template_id == template.id
      assert length(program.sessions) == 12

      assert Enum.map(hd(program.sessions).exercises, & &1.name) == [
               "Panca con manubri",
               "Nuovo esercizio"
             ]
    end

    test "edits and saves a template", ctx do
      template = generate(template(coach: ctx.coach))
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/templates/#{template.id}/edit")

      view |> form("#plan-meta", plan: %{name: "Ipertrofia 8 sett."}) |> render_change()
      view |> element("button[phx-value-delta=\"1\"]") |> render_click()
      view |> element("button[phx-value-weekday=\"6\"]") |> render_click()
      view |> element("button", "Salva template") |> render_click()

      assert render(view) =~ "Template salvato"

      {:ok, saved} = Training.get_template(template.id, actor: ctx.as_coach)
      assert %{name: "Ipertrofia 8 sett.", weeks_count: 7} = saved
      assert [%{weekdays: [1, 4, 6]}] = saved.days
    end
  end

  describe "client notes" do
    test "adds, edits and deletes a general note", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/clients/#{ctx.client.id}?#{[tab: "note"]}")

      view
      |> form("#general-note-form",
        general_note: %{body: "Ernia lombare: niente stacchi da terra."}
      )
      |> render_submit()

      [note] = Training.list_client_notes!(ctx.client.id, actor: ctx.as_coach)
      assert view |> element("#note-#{note.id}") |> render() =~ "Ernia lombare"
      assert view |> element("#tab-notes") |> render() =~ "1"

      view |> element("#note-#{note.id} button", "Modifica") |> render_click()

      view
      |> form("#edit-note-#{note.id}",
        edit_note: %{body: "Ernia lombare: stacchi solo da rialzo."}
      )
      |> render_submit()

      assert view |> element("#note-#{note.id}") |> render() =~ "stacchi solo da rialzo"

      view |> element("#note-#{note.id} button", "Elimina") |> render_click()
      refute has_element?(view, "#note-#{note.id}")
    end

    test "suggests the review of a program that is ending and records it", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/clients/#{ctx.client.id}?#{[tab: "note"]}")

      # The seeded program ends within four weeks: not yet due.
      refute has_element?(view, "#due-review-#{ctx.program.id}")

      Ash.Seed.update!(ctx.program, %{ends_on: Date.add(Date.utc_today(), 3)})
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/clients/#{ctx.client.id}?#{[tab: "note"]}")

      view |> element("#due-review-#{ctx.program.id} button") |> render_click()

      view
      |> form("#review-note-form", review_note: %{body: "Squat +5 kg, trazioni da 6 a 9."})
      |> render_submit()

      [review] = Training.list_client_notes!(ctx.client.id, actor: ctx.as_coach)
      assert review.kind == :review
      assert review.program_id == ctx.program.id
      assert review.noted_on == Date.add(Date.utc_today(), 3)

      html = view |> element("#note-#{review.id}") |> render()
      assert html =~ "Fine programma · Forza Base — Blocco 1"
      refute has_element?(view, "#due-review-#{ctx.program.id}")
    end

    test "a review without a date shows the error", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/clients/#{ctx.client.id}?#{[tab: "note"]}")

      html =
        view
        |> form("#review-note-form", review_note: %{body: "Check", noted_on: ""})
        |> render_submit()

      assert html =~ "una revisione ha bisogno di una data"
      assert Training.list_client_notes!(ctx.client.id, actor: ctx.as_coach) == []
    end
  end
end
