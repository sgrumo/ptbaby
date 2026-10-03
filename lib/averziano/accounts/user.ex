defmodule Averziano.Accounts.User do
  @moduledoc false

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "users"
    repo Averziano.Repo

    references do
      reference :coach, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:email, :name]
    end

    create :register_coach do
      description "Coach accounts are only created from trusted code (seeds, iex), never through a request."
      accept [:email, :name]
      change set_attribute(:role, :coach)
    end

    create :invite_client do
      description "A coach adds a client, who will receive an invitation to the platform."
      accept [:email, :phone]

      argument :first_name, :string, allow_nil?: false
      argument :last_name, :string, allow_nil?: false

      change Averziano.Accounts.Changes.FullName
      change set_attribute(:role, :client)
      change set_attribute(:coach_id, actor("sub"))
      change set_attribute(:invited_at, &DateTime.utc_now/0)
    end

    read :clients do
      description "The actor's clients."
      filter expr(coach_id == ^actor("sub") and role == :client)
      prepare build(sort: [name: :asc])
    end

    update :update do
      accept [:name]
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end

    policy action(:invite_client) do
      authorize_if Averziano.Accounts.Checks.ActorIsCoach
    end

    policy action(:register_coach) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      allow_nil? false
      public? true
      default :client
      constraints one_of: [:client, :coach]
    end

    attribute :phone, :string do
      public? true
    end

    attribute :invited_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :coach, __MODULE__ do
      description "The coach who follows this client."
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
