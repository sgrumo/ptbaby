defmodule Averziano.Training.Exercise do
  @moduledoc """
  An exercise prescribed in a session, with its target. The `kind` decides how
  each set is prescribed and logged:

    * `:reps` — `sets_count` × `target_reps`, optionally at `target_load_kg`
    * `:max` — `sets_count` × as many reps as possible
    * `:time` — `sets_count` × `target_seconds` held
    * `:sequence` — `sets_count` × a rep `sequence` (e.g. 1-2-3-2-1), logged as complete or partial

  A `nil` `target_load_kg` means bodyweight ("corpo libero").
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "exercises"
    repo Averziano.Repo

    references do
      reference :session, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :session_id,
        :position,
        :name,
        :kind,
        :sets_count,
        :target_reps,
        :target_load_kg,
        :target_seconds,
        :sequence,
        :sequence_rest_seconds,
        :rest_seconds,
        :notes,
        :videos
      ]
    end

    update :update_target do
      description "The coach changes the target of this session's exercise."
      accept [:sets_count, :target_reps, :target_load_kg, :target_seconds, :sequence]

      change atomic_update(:target_updated_at, expr(now()))
    end

    read :replicas do
      description """
      The open occurrences of an exercise in the same program day after a date:
      the sessions a target change can still apply to.
      """

      argument :program_id, :uuid, allow_nil?: false
      argument :day_label, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :after, :date, allow_nil?: false

      filter expr(
               session.program_id == ^arg(:program_id) and session.day_label == ^arg(:day_label) and
                 name == ^arg(:name) and session.scheduled_on > ^arg(:after) and
                 is_nil(session.completed_at)
             )

      prepare build(sort: [scheduled_on: :asc], load: [:scheduled_on])
    end

    action :retarget, {:array, :struct} do
      description "Changes the target of the next (or all future) open replicas of an exercise."
      constraints items: [instance_of: __MODULE__]
      transaction? true

      argument :exercise_id, :uuid, allow_nil?: false

      argument :scope, :atom do
        allow_nil? false
        constraints one_of: [:next, :future]
      end

      argument :target, :map, allow_nil?: false

      run Averziano.Training.Actions.Retarget
    end

    read :previous do
      description "The most recent earlier occurrence of an exercise in a program that has logged sets."

      argument :program_id, :uuid, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :before, :date, allow_nil?: false

      filter expr(
               session.program_id == ^arg(:program_id) and name == ^arg(:name) and
                 session.scheduled_on < ^arg(:before) and exists(set_logs, true)
             )

      prepare build(sort: [scheduled_on: :desc], limit: 1)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(session.program.client_id == ^actor("sub"))
      authorize_if expr(session.program.coach_id == ^actor("sub"))
    end

    policy action_type(:create) do
      authorize_if {Averziano.Training.Checks.ActorOwnsProgram, role: :coach}
    end

    policy action(:retarget) do
      description "Each replica is then authorized by `update_target`."
      authorize_if actor_present()
    end

    policy action(:update_target) do
      authorize_if expr(session.program.coach_id == ^actor("sub"))
    end
  end

  validations do
    validate present(:target_reps), where: [attribute_equals(:kind, :reps)]
    validate present(:target_seconds), where: [attribute_equals(:kind, :time)]
    validate present(:sequence), where: [attribute_equals(:kind, :sequence)]
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:reps, :max, :time, :sequence]
    end

    attribute :sets_count, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :target_reps, :integer do
      public? true
      constraints min: 1
    end

    attribute :target_load_kg, :decimal do
      public? true
      constraints min: 0
    end

    attribute :target_seconds, :integer do
      public? true
      constraints min: 1
    end

    attribute :sequence, {:array, :integer} do
      public? true
      constraints min_length: 1, items: [min: 1]
    end

    attribute :sequence_rest_seconds, :integer do
      description "Rest between the steps of a sequence."
      public? true
      constraints min: 0
    end

    attribute :rest_seconds, :integer do
      description "Rest after each completed set."
      allow_nil? false
      public? true
      default 90
      constraints min: 0
    end

    attribute :notes, :string do
      public? true
    end

    attribute :videos, {:array, Averziano.Training.Video} do
      allow_nil? false
      public? true
      default []
    end

    attribute :target_updated_at, :utc_datetime_usec do
      description "When the coach last changed the target after the program was built."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :session, Averziano.Training.Session do
      allow_nil? false
      public? true
    end

    has_many :set_logs, Averziano.Training.SetLog do
      public? true
      sort set_number: :asc
    end
  end

  calculations do
    calculate :scheduled_on, :date, expr(session.scheduled_on)
  end

  aggregates do
    count :logged_sets_count, :set_logs do
      public? true
    end
  end
end
