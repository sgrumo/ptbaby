defmodule Averziano.Training.SetLog do
  @moduledoc """
  A set the client performed for an exercise. Which values are filled depends
  on the exercise kind: `reps` (and `load_kg`) for `:reps`/`:max`, `seconds`
  for `:time`, `outcome` for `:sequence`.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "set_logs"
    repo Averziano.Repo

    references do
      reference :exercise, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :log do
      description "Logs the next set of an exercise; the set number is assigned automatically."
      accept [:exercise_id, :reps, :load_kg, :seconds, :outcome, :note]

      change Averziano.Training.Changes.RecordSet
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exercise.session.program.client_id == ^actor("sub"))
      authorize_if expr(exercise.session.program.coach_id == ^actor("sub"))
    end

    policy action(:log) do
      authorize_if {Averziano.Training.Checks.ActorOwnsProgram, role: :client}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :set_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :reps, :integer do
      public? true
      constraints min: 0
    end

    attribute :load_kg, :decimal do
      public? true
      constraints min: 0
    end

    attribute :seconds, :integer do
      public? true
      constraints min: 0
    end

    attribute :outcome, :atom do
      public? true
      constraints one_of: [:complete, :partial]
    end

    attribute :note, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :exercise, Averziano.Training.Exercise do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_set_number, [:exercise_id, :set_number]
  end
end
