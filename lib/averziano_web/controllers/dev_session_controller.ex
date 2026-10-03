defmodule AverzianoWeb.DevSessionController do
  @moduledoc """
  Development-only sign-in without email: issues a session token for a user
  the same way a magic link would. Routed only when `:dev_routes` is enabled,
  so it does not exist in production builds.
  """

  use AverzianoWeb, :html_controller

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]

  alias Averziano.Accounts.User
  alias AverzianoWeb.AuthController

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user_id" => user_id}) do
    with {:ok, %User{} = user} <- Ash.get(User, user_id, authorize?: false, error?: false),
         {:ok, token, _claims} <- AshAuthentication.Jwt.token_for_user(user) do
      conn
      |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
      |> redirect(to: AuthController.home_path(user))
    else
      _ -> conn |> put_flash(:error, "Utente non trovato") |> redirect(to: ~p"/sign-in")
    end
  end
end
