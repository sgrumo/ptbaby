defmodule Averziano.CoachingTest do
  use Averziano.DataCase, async: true

  alias Averziano.{Accounts, Errors, Training}

  setup do
    coach = generate(coach())
    client = generate(client(coach: coach))

    %{
      coach: coach,
      client: client,
      as_coach: %{"sub" => coach.id},
      as_client: %{"sub" => client.id}
    }
  end

  describe "invite_client/2 and list_clients/1" do
    test "a coach adds clients to their own list", ctx do
      params = %{
        first_name: " Luca ",
        last_name: "Ferri",
        email: "luca@example.com",
        phone: "+39 333"
      }

      assert {:ok, luca} = Accounts.invite_client(params, actor: ctx.as_coach)
      assert %{name: "Luca Ferri", role: :client, phone: "+39 333"} = luca
      assert luca.coach_id == ctx.coach.id
      assert %DateTime{} = luca.invited_at

      assert_received {:email, %{to: [{"", "luca@example.com"}]} = invitation}
      assert invitation.subject == "Davide Moretti ti ha invitato su Work Baby"
      assert invitation.text_body =~ "/sign-in"

      # Someone who isn't the coach's client.
      generate(user())

      assert {:ok, clients} = Accounts.list_clients(actor: ctx.as_coach)
      assert clients |> Enum.map(& &1.name) |> Enum.sort() == ["Giulia Rossi", "Luca Ferri"]
    end

    test "only coaches can invite", ctx do
      params = %{first_name: "Eva", last_name: "Neri", email: "eva@example.com"}

      assert {:error, error} = Accounts.invite_client(params, actor: ctx.as_client)
      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "programs" do
    test "a coach builds programs only for their own clients", ctx do
      other_client = generate(user())
      monday = Date.utc_today() |> Date.beginning_of_week() |> Date.add(7)

      params = %{
        name: "Ipertrofia",
        starts_on: monday,
        ends_on: Date.add(monday, 13),
        weeks_count: 2,
        days: [plan_day()]
      }

      assert {:ok, _draft} =
               Training.create_program(Map.put(params, :client_id, ctx.client.id),
                 actor: ctx.as_coach
               )

      assert {:error, error} =
               Training.create_program(Map.put(params, :client_id, other_client.id),
                 actor: ctx.as_coach
               )

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end

    test "publishing generates a session per planned weekday and shows the program to the client",
         ctx do
      draft =
        generate(
          draft_program(
            coach: ctx.coach,
            client_id: ctx.client.id,
            days: [plan_day(), plan_day(%{title: "Lower body", weekdays: [2]})]
          )
        )

      assert {:ok, nil} = Training.current_program(actor: ctx.as_client)

      assert {:ok, published} = Training.publish_program(draft, actor: ctx.as_coach)
      assert %DateTime{} = published.published_at

      {:ok, program} =
        Training.current_program(actor: ctx.as_client, load: [sessions: [:exercises]])

      assert program.id == draft.id

      # 2 weeks × (Mon + Thu for day A, Tue for day B), in date order.
      assert Enum.map(
               program.sessions,
               &{&1.week_number, &1.day_label, Date.day_of_week(&1.scheduled_on)}
             ) ==
               [{1, "A", 1}, {1, "B", 2}, {1, "A", 4}, {2, "A", 1}, {2, "B", 2}, {2, "A", 4}]

      assert [%{name: "Panca con manubri", target_reps: 10, position: 1}] =
               hd(program.sessions).exercises

      assert {:error, error} = Training.publish_program(published, actor: ctx.as_coach)

      assert {:error, :unprocessable_entity, %{published_at: _}} =
               Errors.normalize({:error, error})

      assert {:error, error} =
               Training.update_program_plan(published, %{name: "Nuovo"}, actor: ctx.as_coach)

      assert {:error, :unprocessable_entity, %{published_at: _}} =
               Errors.normalize({:error, error})
    end

    test "a plan without exercises can't be published", ctx do
      draft =
        generate(
          draft_program(
            coach: ctx.coach,
            client_id: ctx.client.id,
            days: [plan_day(%{exercises: []})]
          )
        )

      assert {:error, error} = Training.publish_program(draft, actor: ctx.as_coach)

      assert {:error, :unprocessable_entity,
              %{days: ["ogni giorno deve avere almeno un esercizio"]}} =
               Errors.normalize({:error, error})
    end
  end

  describe "review_session/3" do
    setup ctx do
      program = generate(program(coach: ctx.coach, client_id: ctx.client.id))
      %{session: generate(session(program_id: program.id))}
    end

    test "the coach reviews a completed session once, with a comment", ctx do
      assert {:error, error} = Training.review_session(ctx.session, %{}, actor: ctx.as_coach)

      assert {:error, :unprocessable_entity, %{completed_at: _}} =
               Errors.normalize({:error, error})

      {:ok, completed} = Training.complete_session(ctx.session, %{}, actor: ctx.as_client)

      assert {:error, error} = Training.review_session(completed, %{}, actor: ctx.as_client)
      assert Errors.normalize({:error, error}) == {:error, :forbidden}

      assert {:ok, reviewed} =
               Training.review_session(completed, %{coach_comment: "Brava!"}, actor: ctx.as_coach)

      assert reviewed.coach_comment == "Brava!"
      assert %DateTime{} = reviewed.reviewed_at

      assert {:error, _} = Training.review_session(reviewed, %{}, actor: ctx.as_coach)
    end
  end

  describe "retarget_exercise/4" do
    setup ctx do
      program = generate(program(coach: ctx.coach, client_id: ctx.client.id))
      today = Date.utc_today()

      [reviewed, done, next, later] =
        for days <- [0, 7, 14, 21] do
          session =
            generate(
              session(program_id: program.id, day_label: "B", scheduled_on: Date.add(today, days))
            )

          generate(exercise(session_id: session.id, name: "Stacco rumeno", target_reps: 10))
        end

      {:ok, done_session} = Training.get_session(done.session_id, actor: ctx.as_client)
      Training.complete_session!(done_session, %{}, actor: ctx.as_client)

      %{reviewed: reviewed, next: next, later: later}
    end

    test "changes the next or all future open replicas", ctx do
      assert {:ok, [updated]} =
               Training.retarget_exercise(ctx.reviewed.id, :next, %{target_reps: 8},
                 actor: ctx.as_coach
               )

      assert updated.id == ctx.next.id
      assert updated.target_reps == 8

      assert {:ok, updated} =
               Training.retarget_exercise(ctx.reviewed.id, :future, %{target_reps: 6},
                 actor: ctx.as_coach
               )

      assert Enum.map(updated, &{&1.id, &1.target_reps}) == [{ctx.next.id, 6}, {ctx.later.id, 6}]
    end

    test "the client cannot change targets", ctx do
      assert {:error, error} =
               Training.retarget_exercise(ctx.reviewed.id, :future, %{target_reps: 20},
                 actor: ctx.as_client
               )

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "templates" do
    test "the coach sees the library, with how many clients use each template", ctx do
      template = generate(template(coach: ctx.coach))

      for _ <- 1..2 do
        generate(
          draft_program(coach: ctx.coach, client_id: ctx.client.id, template_id: template.id)
        )
      end

      assert {:ok, [listed]} =
               Training.list_templates(actor: ctx.as_coach, load: [:clients_count])

      assert listed.id == template.id
      assert listed.clients_count == 1

      assert {:ok, []} = Training.list_templates(actor: ctx.as_client)

      assert {:error, error} = Training.create_template(%{name: "X"}, actor: ctx.as_client)
      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "the coach account" do
    test "there can be only one, and nobody can become coach through a request", ctx do
      assert {:error, error} =
               Accounts.register_coach(%{email: "second@example.com", name: "Second"},
                 authorize?: false
               )

      assert {:error, :unprocessable_entity, %{role: ["esiste già un coach"]}} =
               Errors.normalize({:error, error})

      assert {:error, error} =
               Accounts.register_coach(%{email: "x@example.com", name: "X"}, actor: ctx.as_coach)

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "client notes" do
    test "a coach keeps general notes and dated reviews about a client", ctx do
      program = generate(program(coach: ctx.coach, client_id: ctx.client.id))

      assert {:ok, general} =
               Training.create_client_note(
                 %{
                   client_id: ctx.client.id,
                   kind: :general,
                   body: "Ernia lombare: niente stacchi da terra."
                 },
                 actor: ctx.as_coach
               )

      assert {:ok, review} =
               Training.create_client_note(
                 %{
                   client_id: ctx.client.id,
                   kind: :review,
                   title: "Fine blocco",
                   body: "Squat +5 kg.",
                   noted_on: program.ends_on,
                   program_id: program.id
                 },
                 actor: ctx.as_coach
               )

      assert {:ok, [first, second]} =
               Training.list_client_notes(ctx.client.id, actor: ctx.as_coach)

      assert {first.id, second.id} == {review.id, general.id}

      assert {:ok, %{body: "Squat +7,5 kg."}} =
               Training.update_client_note(review, %{body: "Squat +7,5 kg."}, actor: ctx.as_coach)

      assert :ok = Training.destroy_client_note(general, actor: ctx.as_coach)
      assert {:ok, [_review]} = Training.list_client_notes(ctx.client.id, actor: ctx.as_coach)
    end

    test "a review needs a date and can only refer to the client's own programs", ctx do
      assert {:error, error} =
               Training.create_client_note(%{client_id: ctx.client.id, kind: :review, body: "?"},
                 actor: ctx.as_coach
               )

      assert {:error, :unprocessable_entity, %{noted_on: _}} = Errors.normalize({:error, error})

      other_client = generate(client(coach: ctx.coach))
      other_program = generate(program(coach: ctx.coach, client_id: other_client.id))

      assert {:error, error} =
               Training.create_client_note(
                 %{
                   client_id: ctx.client.id,
                   kind: :review,
                   body: "?",
                   noted_on: Date.utc_today(),
                   program_id: other_program.id
                 },
                 actor: ctx.as_coach
               )

      assert {:error, :unprocessable_entity, %{program_id: _}} = Errors.normalize({:error, error})
    end

    test "notes are private to the client's coach", ctx do
      note =
        Training.create_client_note!(%{client_id: ctx.client.id, kind: :general, body: "Privata"},
          actor: ctx.as_coach
        )

      other_client = %{"sub" => generate(client(coach: ctx.coach)).id}

      assert {:ok, []} = Training.list_client_notes(ctx.client.id, actor: ctx.as_client)
      assert {:ok, []} = Training.list_client_notes(ctx.client.id, actor: other_client)

      assert {:error, error} =
               Training.create_client_note(%{client_id: ctx.client.id, kind: :general, body: "x"},
                 actor: other_client
               )

      assert Errors.normalize({:error, error}) == {:error, :forbidden}

      assert {:error, error} =
               Training.update_client_note(note, %{body: "x"}, actor: ctx.as_client)

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "client equipment" do
    test "a coach keeps the list of what a client can train with", ctx do
      assert {:ok, dumbbells} =
               Training.add_equipment(
                 %{client_id: ctx.client.id, name: "Manubri", details: "coppia fino a 20 kg"},
                 actor: ctx.as_coach
               )

      assert {:ok, _} =
               Training.add_equipment(%{client_id: ctx.client.id, name: "Elastici"},
                 actor: ctx.as_coach
               )

      assert {:ok, items} = Training.list_client_equipment(ctx.client.id, actor: ctx.as_coach)
      assert Enum.map(items, &to_string(&1.name)) == ["Elastici", "Manubri"]

      assert {:ok, %{details: "coppia fino a 24 kg"}} =
               Training.update_equipment(dumbbells, %{details: "coppia fino a 24 kg"},
                 actor: ctx.as_coach
               )

      assert :ok = Training.remove_equipment(dumbbells, actor: ctx.as_coach)

      assert {:ok, [_elastics]} =
               Training.list_client_equipment(ctx.client.id, actor: ctx.as_coach)
    end

    test "each item appears once per client, regardless of case", ctx do
      generate(equipment(client: ctx.client, name: "Kettlebell"))

      assert {:error, error} =
               Training.add_equipment(%{client_id: ctx.client.id, name: "kettlebell"},
                 actor: ctx.as_coach
               )

      assert {:error, :unprocessable_entity, %{name: ["è già nella lista"]}} =
               Errors.normalize({:error, error})
    end

    test "the list is private to the client's coach", ctx do
      generate(equipment(client: ctx.client))
      other_client = %{"sub" => generate(client(coach: ctx.coach)).id}

      assert {:ok, []} = Training.list_client_equipment(ctx.client.id, actor: ctx.as_client)

      assert {:error, error} =
               Training.add_equipment(%{client_id: ctx.client.id, name: "Panca"},
                 actor: other_client
               )

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end
end
