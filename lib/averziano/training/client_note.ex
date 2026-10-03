defmodule Averziano.Training.ClientNote do
  @moduledoc """
  A coach's private note about a client: either `:general` (goals, injuries,
  anything that holds across programs) or a dated `:review` — a check-in
  after a period of time, optionally tied to a program (e.g. at its end).
  Clients never see these notes.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "client_notes"
    repo Averziano.Repo

    references do
      reference :client, on_delete: :delete
      reference :coach, on_delete: :delete
      reference :program, on_delete: :nilify
    end
  end

  actions do
    defaults [:destroy]

    create :create do
      accept [:client_id, :kind, :title, :body, :noted_on, :program_id]
      change set_attribute(:coach_id, actor("sub"))
    end

    update :update do
      accept [:title, :body, :noted_on, :program_id]
      require_atomic? false
    end

    read :for_client do
      description "The actor's notes about one client: dated reviews newest first, then general notes."

      argument :client_id, :uuid, allow_nil?: false

      filter expr(client_id == ^arg(:client_id) and coach_id == ^actor("sub"))
      prepare build(sort: [noted_on: :desc_nils_last, inserted_at: :desc])
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

  validations do
    validate present(:noted_on),
      where: [attribute_equals(:kind, :review)],
      message: "una revisione ha bisogno di una data"

    validate Averziano.Training.Validations.ProgramOfClient
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:general, :review]
    end

    attribute :title, :string do
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      public? true
    end

    attribute :noted_on, :date do
      description "The day a review refers to; general notes have none."
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

    belongs_to :program, Averziano.Training.Program do
      description "The program a review is about, e.g. at its end."
      public? true
    end
  end
end
