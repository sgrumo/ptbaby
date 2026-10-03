defmodule Averziano.TrainingTest do
  use Averziano.DataCase, async: true

  alias Averziano.Errors
  alias Averziano.Training

  setup do
    coach = generate(user(name: "Davide Moretti"))
    client = generate(user(name: "Giulia Rossi"))
    program = generate(program(coach: coach, client_id: client.id))
    session = generate(session(program_id: program.id))

    %{
      coach: coach,
      client: client,
      program: program,
      session: session,
      as_client: %{"sub" => client.id},
      as_coach: %{"sub" => coach.id}
    }
  end

  describe "current_program/1" do
    test "returns the client's latest unexpired program, and nothing to anyone else", ctx do
      generate(
        program(
          coach: ctx.coach,
          client_id: ctx.client.id,
          name: "Scaduto",
          starts_on: Date.add(Date.utc_today(), -60),
          ends_on: Date.add(Date.utc_today(), -1)
        )
      )

      assert {:ok, program} = Training.current_program(actor: ctx.as_client)
      assert program.id == ctx.program.id

      other = generate(user())
      assert {:ok, nil} = Training.current_program(actor: %{"sub" => other.id})
    end
  end

  describe "log_set/2" do
    test "numbers sets in order and stops at the prescribed count", ctx do
      exercise = generate(exercise(session_id: ctx.session.id, sets_count: 2))
      params = %{exercise_id: exercise.id, reps: 5, load_kg: 50}

      assert {:ok, %{set_number: 1}} = Training.log_set(params, actor: ctx.as_client)
      assert {:ok, %{set_number: 2}} = Training.log_set(params, actor: ctx.as_client)

      assert {:error, error} = Training.log_set(params, actor: ctx.as_client)

      assert {:error, :unprocessable_entity,
              %{exercise_id: ["tutte le serie sono già registrate"]}} =
               Errors.normalize({:error, error})
    end

    test "requires the value the exercise kind is logged with", ctx do
      timed = generate(exercise(session_id: ctx.session.id, kind: :time, target_seconds: 30))

      assert {:error, error} =
               Training.log_set(%{exercise_id: timed.id, reps: 3}, actor: ctx.as_client)

      assert {:error, :unprocessable_entity, %{seconds: _}} = Errors.normalize({:error, error})

      assert {:ok, %{seconds: 28}} =
               Training.log_set(%{exercise_id: timed.id, seconds: 28}, actor: ctx.as_client)
    end

    test "a complete sequence set records the sequence total as reps", ctx do
      sequence =
        generate(
          exercise(
            session_id: ctx.session.id,
            kind: :sequence,
            target_reps: nil,
            sequence: [1, 2, 3, 2, 1]
          )
        )

      assert {:ok, %{outcome: :complete, reps: 9}} =
               Training.log_set(%{exercise_id: sequence.id, outcome: :complete},
                 actor: ctx.as_client
               )
    end

    test "only the program's client can log sets", ctx do
      exercise = generate(exercise(session_id: ctx.session.id))

      assert {:error, error} =
               Training.log_set(%{exercise_id: exercise.id, reps: 5}, actor: ctx.as_coach)

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "complete_session/3" do
    test "stores the client's note once and closes the session to new sets", ctx do
      exercise = generate(exercise(session_id: ctx.session.id))

      assert {:ok, session} =
               Training.complete_session(ctx.session, %{client_note: "Tutto ok"},
                 actor: ctx.as_client
               )

      assert session.client_note == "Tutto ok"
      assert %DateTime{} = session.completed_at

      # The stale `ctx.session` still has no completed_at: the stored row is what counts.
      assert {:error, error} = Training.complete_session(ctx.session, %{}, actor: ctx.as_client)

      assert {:error, :unprocessable_entity,
              %{completed_at: ["la giornata è già stata completata"]}} =
               Errors.normalize({:error, error})

      assert {:error, error} =
               Training.log_set(%{exercise_id: exercise.id, reps: 5}, actor: ctx.as_client)

      assert {:error, :unprocessable_entity, %{exercise_id: ["la giornata è già completata"]}} =
               Errors.normalize({:error, error})
    end

    test "the coach cannot complete the client's session", ctx do
      assert {:error, error} = Training.complete_session(ctx.session, %{}, actor: ctx.as_coach)
      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "previous_performance/4" do
    test "returns the latest earlier occurrence of the exercise with logged sets", ctx do
      today = Date.utc_today()

      for {days_ago, reps} <- [{7, 6}, {3, 8}, {1, nil}] do
        session =
          generate(session(program_id: ctx.program.id, scheduled_on: Date.add(today, -days_ago)))

        exercise = generate(exercise(session_id: session.id, kind: :max, target_reps: nil))
        if reps, do: generate(set_log(exercise_id: exercise.id, reps: reps))
      end

      assert {:ok, previous} =
               Training.previous_performance(ctx.program.id, "Squat frontale", today,
                 actor: ctx.as_client,
                 load: [:set_logs]
               )

      assert [%{reps: 8}] = previous.set_logs

      assert {:ok, nil} =
               Training.previous_performance(ctx.program.id, "Plank", today, actor: ctx.as_client)
    end
  end

  describe "update_exercise_target/3" do
    test "the coach changes the target and the change is flagged", ctx do
      exercise = generate(exercise(session_id: ctx.session.id))

      assert {:ok, updated} =
               Training.update_exercise_target(exercise, %{target_reps: 8}, actor: ctx.as_coach)

      assert updated.target_reps == 8
      assert %DateTime{} = updated.target_updated_at

      assert {:error, error} =
               Training.update_exercise_target(exercise, %{target_reps: 3}, actor: ctx.as_client)

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end
end
