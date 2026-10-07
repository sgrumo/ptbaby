defmodule Averziano.Training.Equipment do
  @moduledoc """
  A piece of equipment a client has available to train with ("attrezzatura"),
  e.g. "Manubri" with details "coppia fino a 24 kg". The coach keeps the list
  to plan programs around it; clients never see it.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "client_equipment"
    repo Averziano.Repo

    references do
      reference :client, on_delete: :delete
      reference :coach, on_delete: :delete
    end
  end

  actions do
    defaults [:destroy]

    create :create do
      accept [:client_id, :name, :details]
      change set_attribute(:coach_id, actor("sub"))
    end

    update :update do
      accept [:name, :details]
      require_atomic? false
    end

    read :for_client do
      description "The equipment of one of the actor's clients, by name."

      argument :client_id, :uuid, allow_nil?: false

      filter expr(client_id == ^arg(:client_id) and coach_id == ^actor("sub"))
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if Averziano.Training.Checks.ActorCoachesClient
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(coach_id == ^actor("sub"))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :details, :string do
      description "Weights, sizes or anything else worth knowing, e.g. \"fino a 24 kg\"."
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
  end

  identities do
    identity :unique_name_per_client, [:client_id, :name] do
      field_names [:name]
      message "è già nella lista"
    end
  end
end
