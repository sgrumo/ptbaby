defmodule Averziano.Training.Session do
  @moduledoc """
  One scheduled training day of a program ("giornata"), e.g. week 2, day C,
  "Total body" on Friday. The client completes it with an optional note for
  the coach.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_sessions"
    repo Averziano.Repo

    references do
      reference :program, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:program_id, :week_number, :day_label, :title, :scheduled_on, :coach_note]
    end

    update :complete do
      accept [:client_note]

      validate {Averziano.Training.Validations.Unset,
                attribute: :completed_at, message: "la giornata è già stata completata"}

      change atomic_update(:completed_at, expr(now()))
    end

    update :review do
      description "The coach reviews a completed session, optionally with a comment for the client."
      accept [:coach_comment]
      require_atomic? false

      validate present(:completed_at), message: "la giornata non è ancora stata completata"

      validate {Averziano.Training.Validations.Unset,
                attribute: :reviewed_at, message: "la giornata è già stata revisionata"}

      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    read :completed_for_coach do
      description "The latest sessions completed by the actor's clients."
      filter expr(program.coach_id == ^actor("sub") and not is_nil(completed_at))
      prepare build(sort: [completed_at: :desc], limit: 10)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(program.client_id == ^actor("sub"))
      authorize_if expr(program.coach_id == ^actor("sub"))
    end

    policy action_type(:create) do
      authorize_if {Averziano.Training.Checks.ActorOwnsProgram, role: :coach}
    end

    policy action(:complete) do
      authorize_if expr(program.client_id == ^actor("sub"))
    end

    policy action(:review) do
      authorize_if expr(program.coach_id == ^actor("sub"))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :week_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :day_label, :string do
      description ~s(Training day of the week template, e.g. "A", "B", "C".)
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :scheduled_on, :date do
      allow_nil? false
      public? true
    end

    attribute :coach_note, :string do
      public? true
    end

    attribute :client_note, :string do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :coach_comment, :string do
      description "The coach's comment after reviewing the completed session."
      public? true
    end

    attribute :reviewed_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :program, Averziano.Training.Program do
      allow_nil? false
      public? true
    end

    has_many :exercises, Averziano.Training.Exercise do
      public? true
      sort position: :asc
    end
  end

  aggregates do
    count :exercises_count, :exercises do
      public? true
    end

    sum :sets_total, :exercises, :sets_count do
      public? true
      default 0
    end

    count :sets_logged, [:exercises, :set_logs] do
      public? true
    end
  end
end
