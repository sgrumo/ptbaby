defmodule Averziano.Generator do
  @moduledoc """
  Test data generators built on `Ash.Generator`.

  Use `generate/1` and `generate_many/2` (imported with this module) to turn a
  generator into persisted records:

      user = generate(user(name: "Ada"))
      users = generate_many(user(), 3)

  Generators go through the resource's real actions with authorization
  disabled, so validations and defaults still apply.
  """

  use Ash.Generator

  alias Averziano.Accounts.User
  alias Averziano.Training.{Exercise, Program, Session, SetLog, Template}

  @spec user(keyword()) :: StreamData.t(Ash.Changeset.t())
  def user(opts \\ []) do
    changeset_generator(User, :register,
      defaults: [
        email: sequence(:user_email, &"user#{&1}@example.com"),
        name: "Test User"
      ],
      overrides: opts,
      authorize?: false
    )
  end

  @doc "A user with the coach role."
  @spec coach(keyword()) :: StreamData.t(Ash.Changeset.t())
  def coach(opts \\ []) do
    changeset_generator(User, :register_coach,
      defaults: [email: sequence(:coach_email, &"coach#{&1}@example.com"), name: "Davide Moretti"],
      overrides: opts,
      authorize?: false
    )
  end

  @doc "A client invited by `coach` (a user)."
  @spec client(keyword()) :: StreamData.t(Ash.Changeset.t())
  def client(opts) do
    {coach, opts} = Keyword.pop!(opts, :coach)

    changeset_generator(User, :invite_client,
      defaults: [
        email: sequence(:client_email, &"client#{&1}@example.com"),
        first_name: "Giulia",
        last_name: "Rossi"
      ],
      overrides: opts,
      actor: %{"sub" => coach.id},
      authorize?: false
    )
  end

  @doc """
  A published program for `client_id`, coached by `coach` (a user), running
  today and the next four weeks by default. Seeded directly so tests choose
  its sessions; use `draft_program/1` to go through the plan and publishing.
  """
  @spec program(keyword()) :: StreamData.t(Program.t())
  def program(opts) do
    {coach, opts} = Keyword.pop!(opts, :coach)
    today = Date.utc_today()

    seed_generator(
      %Program{
        name: "Forza Base — Blocco 1",
        starts_on: today,
        ends_on: Date.add(today, 27),
        weeks_count: 4,
        days: [],
        coach_id: coach.id,
        published_at: DateTime.utc_now()
      },
      overrides: opts
    )
  end

  @doc "A draft program for `client_id`, built by `coach` (a user) with the `:create` action."
  @spec draft_program(keyword()) :: StreamData.t(Ash.Changeset.t())
  def draft_program(opts) do
    {coach, opts} = Keyword.pop!(opts, :coach)
    monday = Date.utc_today() |> Date.beginning_of_week() |> Date.add(7)

    changeset_generator(Program, :create,
      defaults: [
        name: "Ipertrofia — Blocco 2",
        starts_on: monday,
        ends_on: Date.add(monday, 13),
        weeks_count: 2,
        days: [plan_day()]
      ],
      overrides: opts,
      actor: %{"sub" => coach.id},
      authorize?: false
    )
  end

  @doc "A template of `coach` (a user) with one day by default."
  @spec template(keyword()) :: StreamData.t(Ash.Changeset.t())
  def template(opts) do
    {coach, opts} = Keyword.pop!(opts, :coach)

    changeset_generator(Template, :create,
      defaults: [name: "Ipertrofia 6 sett.", weeks_count: 6, days: [plan_day()]],
      overrides: opts,
      actor: %{"sub" => coach.id},
      authorize?: false
    )
  end

  @doc "Plan day params: \"Upper body\" on Monday and Thursday with a bench press."
  @spec plan_day(map()) :: map()
  def plan_day(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Upper body",
        weekdays: [1, 4],
        exercises: [
          %{
            name: "Panca con manubri",
            kind: :reps,
            sets_count: 4,
            target_reps: 10,
            target_load_kg: 20
          }
        ]
      },
      overrides
    )
  end

  @doc "A session of `program_id`, scheduled today by default."
  @spec session(keyword()) :: StreamData.t(Ash.Changeset.t())
  def session(opts) do
    changeset_generator(Session, :create,
      defaults: [
        week_number: 1,
        day_label: "A",
        title: "Total body",
        scheduled_on: Date.utc_today()
      ],
      overrides: opts,
      authorize?: false
    )
  end

  @doc "A `:reps` exercise of `session_id` (5 × 5 at 50 kg) by default."
  @spec exercise(keyword()) :: StreamData.t(Ash.Changeset.t())
  def exercise(opts) do
    changeset_generator(Exercise, :create,
      defaults: [
        position: 1,
        name: "Squat frontale",
        kind: :reps,
        sets_count: 5,
        target_reps: 5,
        target_load_kg: Decimal.new(50)
      ],
      overrides: opts,
      authorize?: false
    )
  end

  @doc "The next set of `exercise_id`."
  @spec set_log(keyword()) :: StreamData.t(Ash.Changeset.t())
  def set_log(opts) do
    changeset_generator(SetLog, :log, overrides: opts, authorize?: false)
  end
end
