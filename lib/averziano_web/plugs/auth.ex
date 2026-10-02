defmodule AverzianoWeb.Plugs.Auth do
  @moduledoc """
  Verifies the Bearer token and exposes the verified claims both as
  `conn.assigns.current_user_claims` and as the Ash actor
  (readable with `Ash.PlugHelpers.get_actor/1`).
  """

  import Plug.Conn

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    token_verifier = Application.fetch_env!(:averziano, :token_verifier)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- token_verifier.verify_token(token) do
      conn
      |> assign(:current_user_claims, claims)
      |> Ash.PlugHelpers.set_actor(claims)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{errors: %{detail: "Unauthorized"}})
        |> halt()
    end
  end
end
