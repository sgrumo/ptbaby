# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seed through the domain code interfaces (or `Ash.Seed` to bypass actions)
# so validations and defaults apply.
#
# Seeds a coach (Davide) with three templates and four clients:
#   * Giulia — "Forza Base" since last Monday; days logged, the latest to review
#   * Sara   — "Ipertrofia" since three weeks ago; two days to review
#   * Marco  — "Forza Base", trained twice then skipped
#   * Luca   — invited, no program yet
# Programs are published through the real action, which generates sessions.
# Sign in in dev at the URLs printed at the end.

# Demo data, including a coach account: never in production.
if Mix.env() != :dev do
  Mix.raise("priv/repo/seeds.exs creates demo accounts (including a coach) and only runs in dev")
end

alias Averziano.{Accounts, Training}

require Ash.Query

coach_email = "davide.moretti@example.com"

sign_in_links = fn ->
  for email <- [coach_email, "giulia.rossi@example.com"],
      user =
        Accounts.User |> Ash.Query.filter(email == ^email) |> Ash.read_one!(authorize?: false) do
    IO.puts("Sign in as #{user.name} in dev: http://localhost:4000/dev/sign-in/#{user.id}")
  end
end

if Accounts.User |> Ash.Query.filter(email == ^coach_email) |> Ash.exists?(authorize?: false) do
  IO.puts("Seeds already loaded, skipping.")
  sign_in_links.()
else
  coach =
    Accounts.register_coach!(%{email: coach_email, name: "Davide Moretti"}, authorize?: false)

  as_coach = %{"sub" => coach.id}

  invite = fn first_name, last_name ->
    email = "#{String.downcase(first_name)}.#{String.downcase(last_name)}@example.com"

    Accounts.invite_client!(%{first_name: first_name, last_name: last_name, email: email},
      actor: as_coach
    )
  end

  [giulia, sara, marco, _luca] =
    Enum.map(
      [{"Giulia", "Rossi"}, {"Sara", "Conti"}, {"Marco", "Bianchi"}, {"Luca", "Ferri"}],
      fn {first, last} ->
        invite.(first, last)
      end
    )

  chin_ups = %{
    name: "Trazioni presa supina",
    kind: :max,
    sets_count: 2,
    rest_seconds: 120,
    notes:
      "Parti da braccia completamente distese, mento sopra la sbarra. Fermati una ripetizione prima del cedimento. Recupero 2 minuti.",
    videos: [
      %{
        title: "Tecnica delle trazioni supine",
        url: "https://www.youtube.com/watch?v=brhRXlOhsAM"
      },
      %{
        title: "Attivazione scapolare alla sbarra",
        url: "https://www.youtube.com/watch?v=FgYoc4O-cio"
      }
    ]
  }

  forza_base = [
    %{
      title: "Gambe + spinta",
      weekdays: [1],
      exercises: [
        %{name: "Back squat", kind: :reps, sets_count: 4, target_reps: 8, target_load_kg: 55},
        %{
          name: "Panca con manubri",
          kind: :reps,
          sets_count: 3,
          target_reps: 12,
          target_load_kg: 18,
          notes: "Scapole addotte, 3 s in discesa."
        },
        %{name: "Wall sit", kind: :time, sets_count: 3, target_seconds: 60, rest_seconds: 60},
        %{
          name: "Burpee a scala",
          kind: :sequence,
          sets_count: 2,
          sequence: [2, 4, 6, 8, 6, 4, 2],
          sequence_rest_seconds: 20
        }
      ]
    },
    %{
      title: "Stacchi + tirata",
      weekdays: [3],
      exercises: [
        %{name: "Stacco rumeno", kind: :reps, sets_count: 4, target_reps: 10, target_load_kg: 50},
        %{
          name: "Rematore con manubrio",
          kind: :reps,
          sets_count: 3,
          target_reps: 10,
          target_load_kg: 16
        },
        %{name: "Plank", kind: :time, sets_count: 3, target_seconds: 45, rest_seconds: 45},
        chin_ups
      ]
    },
    %{
      title: "Total body",
      weekdays: [5],
      exercises: [
        %{
          name: "Squat frontale",
          kind: :reps,
          sets_count: 5,
          target_reps: 5,
          target_load_kg: 50,
          rest_seconds: 120,
          videos: [
            %{title: "Front squat: tecnica", url: "https://www.youtube.com/watch?v=v-mQm_droHg"}
          ]
        },
        chin_ups,
        %{name: "Hollow hold", kind: :time, sets_count: 4, target_seconds: 30, rest_seconds: 45},
        %{
          name: "Piegamenti piramidali",
          kind: :sequence,
          sets_count: 2,
          sequence: [1, 2, 3, 4, 5, 4, 3, 2, 1],
          sequence_rest_seconds: 15
        }
      ]
    }
  ]

  ipertrofia = [
    %{
      title: "Upper body",
      weekdays: [1, 4],
      exercises: [
        %{
          name: "Panca con manubri",
          kind: :reps,
          sets_count: 4,
          target_reps: 10,
          target_load_kg: 20,
          notes: "Scapole addotte, 3 s in discesa.",
          videos: [
            %{title: "Panca con manubri", url: "https://www.youtube.com/watch?v=VmB1G1K7v94"}
          ]
        },
        Map.put(chin_ups, :sets_count, 3),
        %{name: "Plank", kind: :time, sets_count: 3, target_seconds: 45, rest_seconds: 45},
        %{
          name: "Piegamenti piramidali",
          kind: :sequence,
          sets_count: 2,
          sequence: [1, 2, 3, 4, 5, 4, 3, 2, 1],
          sequence_rest_seconds: 15
        }
      ]
    },
    %{
      title: "Lower body",
      weekdays: [2, 5],
      exercises: [
        %{name: "Back squat", kind: :reps, sets_count: 4, target_reps: 10, target_load_kg: 50},
        %{name: "Stacco rumeno", kind: :reps, sets_count: 4, target_reps: 10, target_load_kg: 45},
        %{
          name: "Affondi camminati",
          kind: :reps,
          sets_count: 3,
          target_reps: 12,
          target_load_kg: 10
        },
        %{name: "Wall sit", kind: :time, sets_count: 3, target_seconds: 60, rest_seconds: 60}
      ]
    }
  ]

  mobilita = [
    %{
      title: "Mobilità",
      weekdays: [2, 4],
      exercises: [
        %{name: "Cat-cow", kind: :reps, sets_count: 2, target_reps: 10, rest_seconds: 30},
        %{name: "Hip airplane", kind: :reps, sets_count: 2, target_reps: 6, rest_seconds: 30},
        %{
          name: "Deep squat hold",
          kind: :time,
          sets_count: 3,
          target_seconds: 45,
          rest_seconds: 30
        }
      ]
    },
    %{
      title: "Core",
      weekdays: [6],
      exercises: [
        %{name: "Dead bug", kind: :reps, sets_count: 3, target_reps: 10, rest_seconds: 45},
        %{name: "Hollow hold", kind: :time, sets_count: 4, target_seconds: 30, rest_seconds: 45},
        %{name: "Side plank", kind: :time, sets_count: 3, target_seconds: 30, rest_seconds: 30}
      ]
    }
  ]

  [forza_template, ipertrofia_template, _mobilita_template] =
    for {name, weeks, days} <- [
          {"Forza Base", 4, forza_base},
          {"Ipertrofia 6 sett.", 6, ipertrofia},
          {"Mobilità e core", 4, mobilita}
        ] do
      Training.create_template!(%{name: name, weeks_count: weeks, days: days}, actor: as_coach)
    end

  today = Date.utc_today()
  last_monday = today |> Date.beginning_of_week() |> Date.add(-7)

  publish = fn client, template, days, name, starts_on ->
    program =
      Training.create_program!(
        %{
          name: name,
          client_id: client.id,
          starts_on: starts_on,
          ends_on: Date.add(starts_on, template.weeks_count * 7 - 1),
          weeks_count: template.weeks_count,
          template_id: template.id,
          days: days
        },
        actor: as_coach
      )

    Training.publish_program!(program, actor: as_coach)
    Training.get_program!(program.id, actor: as_coach, load: [sessions: [:exercises]])
  end

  # A plausible logged set; `short?` makes the last set fall short of the target.
  log_params = fn exercise, set_number, short? ->
    short? = short? and set_number == exercise.sets_count

    case exercise.kind do
      :reps ->
        %{
          reps: if(short?, do: exercise.target_reps - 2, else: exercise.target_reps),
          load_kg: exercise.target_load_kg
        }

      :max ->
        %{reps: max(9 - 2 * set_number, 1)}

      :time ->
        %{seconds: if(short?, do: exercise.target_seconds - 15, else: exercise.target_seconds)}

      :sequence ->
        %{outcome: if(short?, do: :partial, else: :complete)}
    end
  end

  # Logs and completes `session` the evening it was scheduled; reviews it unless `review?` is false.
  train = fn session, client, opts ->
    as_client = %{"sub" => client.id}

    for exercise <- session.exercises, set_number <- 1..exercise.sets_count do
      short? = exercise.name in Keyword.get(opts, :short, [])

      Training.log_set!(
        Map.put(log_params.(exercise, set_number, short?), :exercise_id, exercise.id),
        actor: as_client
      )
    end

    session = Training.complete_session!(session, %{client_note: opts[:note]}, actor: as_client)
    completed_at = DateTime.new!(session.scheduled_on, ~T[18:30:00])
    session = Ash.Seed.update!(session, %{completed_at: completed_at})

    if Keyword.get(opts, :review?, true) do
      session =
        Training.review_session!(session, %{coach_comment: opts[:comment]}, actor: as_coach)

      Ash.Seed.update!(session, %{reviewed_at: DateTime.add(completed_at, 14, :hour)})
    end
  end

  past = fn program -> Enum.filter(program.sessions, &Date.before?(&1.scheduled_on, today)) end

  # Giulia: everything logged, the latest day waits for review with a note.
  giulia_program =
    publish.(giulia, forza_template, forza_base, "Forza Base — Blocco 1", last_monday)

  giulia_past = past.(giulia_program)

  # What went wrong on the latest day, depending on which day it was.
  latest_day = %{
    "A" => {["Wall sit"], "Squat ok. Al wall sit ho mollato a 45 secondi nell'ultima serie."},
    "B" =>
      {["Stacco rumeno"],
       "Stacchi pesanti oggi, all'ultima serie ho perso un po' la schiena e mi sono fermata a 8."},
    "C" =>
      {["Hollow hold", "Piegamenti piramidali"],
       "Squat ok, ultima serie pesante ma pulita. Hollow hold durissimo."}
  }

  for session <- giulia_past do
    latest? = session == List.last(giulia_past)
    {short, note} = if latest?, do: Map.fetch!(latest_day, session.day_label), else: {[], nil}

    train.(session, giulia,
      review?: not latest?,
      short: short,
      note: note,
      comment: if(session.day_label == "A", do: "Ottimo inizio, continua così.")
    )
  end

  # The coach lowered the reps of the deadlift for the coming weeks, and left a note for the next day.
  if deadlift =
       giulia_past |> Enum.flat_map(& &1.exercises) |> Enum.find(&(&1.name == "Stacco rumeno")) do
    Training.retarget_exercise!(
      deadlift.id,
      :future,
      %{sets_count: 4, target_reps: 8, target_load_kg: 50},
      actor: as_coach
    )
  end

  if next = Enum.find(giulia_program.sessions, &(not Date.before?(&1.scheduled_on, today))) do
    Ash.Seed.update!(next, %{
      coach_note:
        "Ottimo lavoro la settimana scorsa. Sullo stacco scendiamo a 8 ripetizioni, così teniamo la schiena neutra fino in fondo."
    })
  end

  # The coach's private notes about Giulia.
  for note <- [
        %{kind: :general, body: "Obiettivo: prima trazione libera entro dicembre."},
        %{
          kind: :general,
          body: "Ginocchio destro sensibile negli affondi profondi: preferire lo squat frontale."
        },
        %{
          kind: :review,
          title: "Valutazione iniziale",
          body:
            "Squat frontale 45 kg × 5 pulito, 4 trazioni con elastico. Buona mobilità di caviglia.",
          noted_on: Date.add(last_monday, -3)
        }
      ] do
    Training.create_client_note!(Map.put(note, :client_id, giulia.id), actor: as_coach)
  end

  # Sara: three weeks in, the last two days to review.
  sara_program =
    publish.(
      sara,
      ipertrofia_template,
      ipertrofia,
      "Ipertrofia — Blocco 2",
      Date.add(last_monday, -14)
    )

  sara_past = past.(sara_program)

  for session <- sara_past do
    to_review? = session in Enum.take(sara_past, -2)

    train.(session, sara,
      review?: not to_review?,
      note:
        if(session == List.last(sara_past),
          do: "Panca ok, sulle trazioni ho perso la presa alla terza serie."
        )
    )
  end

  # Marco: trained the first two days, then skipped.
  marco_program =
    publish.(
      marco,
      forza_template,
      forza_base,
      "Forza Base — Blocco 1",
      Date.add(last_monday, -7)
    )

  marco_program |> past.() |> Enum.take(2) |> Enum.each(&train.(&1, marco, []))

  IO.puts("Seeded coach #{coach.name} with 3 templates and 4 clients.")
  sign_in_links.()
end
