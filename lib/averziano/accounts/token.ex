defmodule Averziano.Accounts.Token do
  @moduledoc """
  Authentication tokens (sessions and magic links). Every issued token is
  stored, so signing out or using a magic link revokes it for good.
  """

  use Ash.Resource,
    otp_app: :averziano,
    domain: Averziano.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
    repo Averziano.Repo
  end

  actions do
    defaults [:read, :destroy]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
