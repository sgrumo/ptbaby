defmodule Averziano.Secrets do
  @moduledoc """
  Secrets AshAuthentication asks for. The token signing secret comes from
  `config :averziano, :token_signing_secret` (`TOKEN_SIGNING_SECRET` in prod).
  """

  use AshAuthentication.Secret

  @impl true
  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Averziano.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:averziano, :token_signing_secret)
  end
end
