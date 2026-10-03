defmodule Averziano.Accounts do
  @moduledoc """
  Accounts domain. The `define`d code interface is the public API of this
  domain; the web layer never calls `Ash` on resources directly.
  """

  use Ash.Domain, otp_app: :averziano

  resources do
    resource Averziano.Accounts.User do
      define :register_user, action: :register
      define :register_coach, action: :register_coach
      define :invite_client, action: :invite_client
      define :list_clients, action: :clients
      define :list_users, action: :read
      define :get_user, action: :read, get_by: [:id]
      define :update_user, action: :update
      define :delete_user, action: :destroy
    end
  end
end
