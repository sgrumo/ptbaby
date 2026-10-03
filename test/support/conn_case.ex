defmodule AverzianoWeb.ConnCase do
  use ExUnit.CaseTemplate

  alias AshAuthentication.{Jwt, Plug.Helpers}
  alias Averziano.Accounts.User
  alias Phoenix.ConnTest
  alias Plug.Conn

  using do
    quote do
      @endpoint AverzianoWeb.Endpoint

      use AverzianoWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import AverzianoWeb.ConnCase
      import Averziano.Generator
    end
  end

  setup tags do
    Averziano.DataCase.setup_sandbox(tags)
    {:ok, conn: ConnTest.build_conn()}
  end

  @doc """
  Adds a valid Bearer token to the connection for authenticated API tests.
  """
  @spec authenticate(Conn.t()) :: Conn.t()
  def authenticate(conn) do
    Conn.put_req_header(conn, "authorization", "Bearer valid_token")
  end

  @doc """
  Signs `user` in for the LiveViews with a real session token, as a magic
  link would.
  """
  @spec sign_in(Conn.t(), User.t()) :: Conn.t()
  def sign_in(conn, user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)

    conn
    |> ConnTest.init_test_session(%{})
    |> Helpers.store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end

  @doc "Adds a Bearer token acting as `user` for authenticated API tests."
  @spec authenticate(Conn.t(), %{id: String.t()}) :: Conn.t()
  def authenticate(conn, %{id: user_id}) do
    Conn.put_req_header(conn, "authorization", "Bearer user:#{user_id}")
  end

  @doc """
  Adds a superadmin Bearer token to the connection.
  """
  @spec authenticate_superadmin(Conn.t()) :: Conn.t()
  def authenticate_superadmin(conn) do
    Conn.put_req_header(conn, "authorization", "Bearer valid_superadmin_token")
  end
end
