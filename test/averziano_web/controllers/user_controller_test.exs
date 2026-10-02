defmodule AverzianoWeb.UserControllerTest do
  use AverzianoWeb.ConnCase, async: true

  setup %{conn: conn} do
    {:ok, conn: conn |> authenticate() |> put_req_header("accept", "application/json")}
  end

  test "rejects unauthenticated requests", %{conn: conn} do
    conn = delete_req_header(conn, "authorization")

    assert %{"errors" => %{"detail" => "Unauthorized"}} =
             conn |> get(~p"/api/users") |> json_response(401)
  end

  test "GET /api/users lists users", %{conn: conn} do
    users = generate_many(user(), 2)

    assert %{"data" => data} = conn |> get(~p"/api/users") |> json_response(200)
    assert Enum.sort(Enum.map(data, & &1["id"])) == Enum.sort(Enum.map(users, & &1.id))
  end

  test "GET /api/users/:id returns the user or 404", %{conn: conn} do
    user = generate(user(name: "Ada"))

    assert %{"data" => %{"id" => id, "name" => "Ada", "email" => email}} =
             conn |> get(~p"/api/users/#{user.id}") |> json_response(200)

    assert id == user.id
    assert email == to_string(user.email)

    assert %{"errors" => %{"detail" => "Not Found"}} =
             conn |> get(~p"/api/users/#{Ash.UUID.generate()}") |> json_response(404)
  end

  test "POST /api/users creates a user and returns 422 on invalid input", %{conn: conn} do
    params = %{"email" => "ada@example.com", "name" => "Ada"}

    created = conn |> post(~p"/api/users", user: params) |> json_response(201)
    assert %{"data" => %{"id" => id, "email" => "ada@example.com", "name" => "Ada"}} = created

    assert %{"data" => %{"id" => ^id}} =
             conn |> get(~p"/api/users/#{id}") |> json_response(200)

    assert %{"errors" => %{"name" => [_ | _]}} =
             conn
             |> post(~p"/api/users", user: %{"email" => "bob@example.com"})
             |> json_response(422)
  end

  test "PATCH /api/users/:id updates and DELETE removes the user", %{conn: conn} do
    user = generate(user())

    assert %{"data" => %{"name" => "Renamed"}} =
             conn
             |> patch(~p"/api/users/#{user.id}", user: %{"name" => "Renamed"})
             |> json_response(200)

    assert conn |> delete(~p"/api/users/#{user.id}") |> response(204)
    assert conn |> get(~p"/api/users/#{user.id}") |> json_response(404)
  end
end
