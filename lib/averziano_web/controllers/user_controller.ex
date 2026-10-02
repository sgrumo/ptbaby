defmodule AverzianoWeb.UserController do
  use AverzianoWeb, :controller

  alias Averziano.Accounts

  action_fallback AverzianoWeb.FallbackController

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    with {:ok, users} <- Accounts.list_users(actor: actor(conn)) do
      render(conn, :index, users: users)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with {:ok, user} <- Accounts.get_user(id, actor: actor(conn)) do
      render(conn, :show, user: user)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user" => params}) do
    with {:ok, user} <- Accounts.register_user(params, actor: actor(conn)) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/users/#{user}")
      |> render(:show, user: user)
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id, "user" => params}) do
    actor = actor(conn)

    with {:ok, user} <- Accounts.get_user(id, actor: actor),
         {:ok, user} <- Accounts.update_user(user, params, actor: actor) do
      render(conn, :show, user: user)
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    actor = actor(conn)

    with {:ok, user} <- Accounts.get_user(id, actor: actor),
         :ok <- Accounts.delete_user(user, actor: actor) do
      send_resp(conn, :no_content, "")
    end
  end

  defp actor(conn), do: Ash.PlugHelpers.get_actor(conn)
end
