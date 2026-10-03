defmodule AverzianoWeb.DevSessionController do
  @moduledoc """
  Development-only sign-in: puts a user id in the session so the session-based
  LiveViews (`AverzianoWeb.Live.AuthHook`) can be used before real login exists.
  Routed only when `:dev_routes` is enabled.
  """

  use AverzianoWeb, :html_controller

  alias Averziano.Accounts
  alias Averziano.Accounts.User

  @doc "Coaches land on the console, everyone else on the client app."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user_id" => user_id}) do
    home =
      case Accounts.get_user(user_id, actor: %{"sub" => user_id}) do
        {:ok, %User{role: :coach}} -> ~p"/admin"
        _ -> ~p"/app"
      end

    conn
    |> configure_session(renew: true)
    |> put_session(:current_user_id, user_id)
    |> redirect(to: home)
  end
end
