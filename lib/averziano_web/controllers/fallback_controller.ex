defmodule AverzianoWeb.FallbackController do
  use AverzianoWeb, :controller

  alias Averziano.Errors

  @status_map %{
    bad_request: 400,
    unauthorized: 401,
    forbidden: 403,
    not_found: 404,
    conflict: 409,
    unprocessable_entity: 422,
    internal_server_error: 500
  }

  @spec call(Plug.Conn.t(), {:error, term()} | {:error, atom(), String.t() | map()}) ::
          Plug.Conn.t()
  def call(conn, {:error, reason}) when is_map_key(@status_map, reason) do
    status = Map.fetch!(@status_map, reason)

    conn
    |> put_status(status)
    |> put_view(json: AverzianoWeb.ErrorJSON)
    |> render("#{status}.json")
  end

  def call(conn, {:error, reason, details}) when is_map_key(@status_map, reason) do
    status = Map.fetch!(@status_map, reason)

    conn
    |> put_status(status)
    |> json(%{errors: error_body(details)})
  end

  def call(conn, {:error, error}) do
    case Errors.normalize({:error, error}) do
      {:error, ^error} -> call(conn, {:error, :internal_server_error})
      normalized -> call(conn, normalized)
    end
  end

  defp error_body(details) when is_map(details), do: details
  defp error_body(message), do: %{detail: message}
end
