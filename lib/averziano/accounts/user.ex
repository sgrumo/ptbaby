defmodule Averziano.Accounts.User do
  @moduledoc """
  A person who signs in: the coach or one of their clients.

  Nobody can sign up. The single coach account is created from trusted code
  (`register_coach`, from a remote console); clients exist only because the
  coach invited them. Everyone signs in with a magic link sent to their email.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  postgres do
    table "users"
    repo Averziano.Repo

    references do
      reference :coach, on_delete: :nilify
    end

    custom_indexes do
      # At most one coach can ever exist: a second `register_coach` fails.
      index [:role],
        name: "users_single_coach_index",
        unique: true,
        where: "role = 'coach'",
        message: "esiste già un coach",
        error_fields: [:role]
    end
  end

  authentication do
    tokens do
      enabled?(true)
      token_resource(Averziano.Accounts.Token)
      signing_secret(Averziano.Secrets)
      store_all_tokens?(true)
      require_token_presence_for_authentication?(true)
    end

    strategies do
      magic_link do
        identity_field(:email)
        registration_enabled?(false)
        require_interaction?(true)
        sender(Averziano.Accounts.User.Senders.SendMagicLink)
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description "Not available to requests: users are invited, never self-registered."
      accept [:email, :name]
    end

    create :register_coach do
      description "Coach accounts are only created from trusted code (seeds, iex), never through a request."
      accept [:email, :name]
      change set_attribute(:role, :coach)
    end

    create :invite_client do
      description "A coach adds a client, who receives an invitation email."
      accept [:email, :phone]

      argument :first_name, :string, allow_nil?: false
      argument :last_name, :string, allow_nil?: false

      change Averziano.Accounts.Changes.FullName
      change set_attribute(:role, :client)
      change set_attribute(:coach_id, actor("sub"))
      change set_attribute(:invited_at, &DateTime.utc_now/0)
      change Averziano.Accounts.Changes.SendInvitation
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
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Yourself, your clients and your coach."
      authorize_if expr(id == ^actor("sub"))
      authorize_if expr(coach_id == ^actor("sub"))
      authorize_if expr(exists(clients, id == ^actor("sub")))
    end

    policy action([:register, :register_coach]) do
      forbid_if always()
    end

    policy action(:invite_client) do
      authorize_if Averziano.Accounts.Checks.ActorIsCoach
    end

    policy action(:update) do
      authorize_if expr(id == ^actor("sub"))
    end

    policy action(:destroy) do
      authorize_if expr(coach_id == ^actor("sub"))
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

    has_many :clients, __MODULE__ do
      destination_attribute :coach_id
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
