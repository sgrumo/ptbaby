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
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:email, :name]
    end

    update :update do
      accept [:name]
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
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

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end
end
