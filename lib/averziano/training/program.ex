defmodule Averziano.Training.Program do
  @moduledoc """
  A training block a coach assigns to a client, e.g. "Forza Base — Blocco 1".

  A program starts as a draft whose plan (`days`) the coach edits. Publishing
  it generates one dated `Session` per training day and week, and only then
  does the client see it. Each session is an independent copy, so its targets
  can change later without touching the plan.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Averziano.Training.{Changes, Checks, Validations}

  postgres do
    table "programs"
    repo Averziano.Repo

    references do
      reference :client, on_delete: :delete
      reference :coach, on_delete: :delete
      reference :template, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :starts_on, :ends_on, :weeks_count, :client_id, :template_id, :days]
      change set_attribute(:coach_id, actor("sub"))
    end

    update :update_plan do
      description "Edits a draft."
      accept [:name, :starts_on, :ends_on, :weeks_count, :client_id, :days]
      require_atomic? false

      validate {Validations.Unset,
                attribute: :published_at, message: "il programma è già pubblicato"}
    end

    update :publish do
      description "Makes a draft visible to the client and generates its sessions."
      accept []
      require_atomic? false

      validate {Validations.Unset,
                attribute: :published_at, message: "il programma è già pubblicato"}

      validate Validations.PublishablePlan
      change set_attribute(:published_at, &DateTime.utc_now/0)
      change Changes.GenerateSessions
    end

    read :current do
      description "The actor's active program: the most recent published one that has not expired yet."
      get? true

      filter expr(client_id == ^actor("sub") and not is_nil(published_at) and ends_on >= today())

      prepare build(sort: [starts_on: :desc], limit: 1)
    end

    read :coached do
      description "Programs the actor coaches, newest first."
      filter expr(coach_id == ^actor("sub"))
      prepare build(sort: [inserted_at: :desc])
    end

    read :latest_for_client do
      description "The most recent published program of one of the actor's clients."
      get? true

      argument :client_id, :uuid, allow_nil?: false

      filter expr(
               client_id == ^arg(:client_id) and coach_id == ^actor("sub") and
                 not is_nil(published_at)
             )

      prepare build(sort: [starts_on: :desc], limit: 1)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(client_id == ^actor("sub"))
      authorize_if expr(coach_id == ^actor("sub"))
    end

    policy action_type(:update) do
      authorize_if expr(coach_id == ^actor("sub"))
    end

    policy action([:create, :update_plan]) do
      authorize_if Checks.ActorCoachesClient
    end
  end

  validations do
    validate compare(:ends_on, greater_than_or_equal_to: :starts_on),
      message: "la scadenza deve seguire l'inizio"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :starts_on, :date do
      allow_nil? false
      public? true
    end

    attribute :ends_on, :date do
      allow_nil? false
      public? true
    end

    attribute :weeks_count, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 52
    end

    attribute :days, {:array, Averziano.Training.PlanDay} do
      allow_nil? false
      public? true
      default []
    end

    attribute :published_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :client, Averziano.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :coach, Averziano.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :template, Averziano.Training.Template do
      public? true
    end

    has_many :sessions, Averziano.Training.Session do
      public? true
      sort scheduled_on: :asc
    end
  end

  calculations do
    calculate :days_per_week, :integer, Averziano.Training.Calculations.DaysPerWeek do
      public? true
    end
  end

  aggregates do
    count :sessions_count, :sessions do
      public? true
    end

    count :completed_sessions_count, :sessions do
      public? true
      filter expr(not is_nil(completed_at))
    end

    count :to_review_count, :sessions do
      description "Completed sessions the coach has not reviewed yet."
      public? true
      filter expr(not is_nil(completed_at) and is_nil(reviewed_at))
    end

    count :missed_count, :sessions do
      description "Past sessions the client did not complete."
      public? true
      filter expr(is_nil(completed_at) and scheduled_on < today())
    end

    first :last_completed_at, :sessions, :completed_at do
      public? true
      sort completed_at: :desc
      filter expr(not is_nil(completed_at))
    end

    first :last_completed_week, :sessions, :week_number do
      public? true
      sort completed_at: :desc
      filter expr(not is_nil(completed_at))
    end

    first :last_completed_day, :sessions, :day_label do
      public? true
      sort completed_at: :desc
      filter expr(not is_nil(completed_at))
    end
  end
end
