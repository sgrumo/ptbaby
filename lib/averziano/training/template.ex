defmodule Averziano.Training.Template do
  @moduledoc """
  A reusable plan: a program without client and dates. A coach creates
  programs from it and then customises them; changing a program never changes
  its template.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "templates"
    repo Averziano.Repo

    references do
      reference :coach, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :weeks_count, :days]
      change set_attribute(:coach_id, actor("sub"))
    end

    update :update do
      accept [:name, :weeks_count, :days]
      require_atomic? false
    end

    read :library do
      description "The actor's templates."
      filter expr(coach_id == ^actor("sub"))
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if Averziano.Accounts.Checks.ActorIsCoach
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(coach_id == ^actor("sub"))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :weeks_count, :integer do
      allow_nil? false
      public? true
      default 4
      constraints min: 1, max: 52
    end

    attribute :days, {:array, Averziano.Training.PlanDay} do
      allow_nil? false
      public? true
      default []
    end

    timestamps()
  end

  relationships do
    belongs_to :coach, Averziano.Accounts.User do
      allow_nil? false
      public? true
    end

    has_many :programs, Averziano.Training.Program do
      public? true
    end
  end

  calculations do
    calculate :days_per_week, :integer, Averziano.Training.Calculations.DaysPerWeek do
      public? true
    end
  end

  aggregates do
    count :clients_count, :programs do
      description "How many clients have a program made from this template."
      public? true
      field :client_id
      uniq? true
    end
  end
end
