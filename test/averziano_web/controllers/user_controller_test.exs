defmodule AverzianoWeb.UserControllerTest do
  use AverzianoWeb.ConnCase, async: true

  setup %{conn: conn} do
    coach = generate(coach())
    client = generate(client(coach: coach))

    {:ok,
     conn: conn |> authenticate(coach) |> put_req_header("accept", "application/json"),
     coach: coach,
     client: client}
  end

  test "rejects unauthenticated requests", %{conn: conn} do
    conn = delete_req_header(conn, "authorization")

    assert %{"errors" => %{"detail" => "Unauthorized"}} =
             conn |> get(~p"/api/users") |> json_response(401)
  end

  test "GET /api/users lists the coach and their clients only", ctx do
    generate(user())

    assert %{"data" => data} = ctx.conn |> get(~p"/api/users") |> json_response(200)
    assert data |> Enum.map(& &1["id"]) |> Enum.sort() == Enum.sort([ctx.coach.id, ctx.client.id])
  end

  test "GET /api/users/:id returns a visible user, 404 for anyone else", ctx do
    assert %{"data" => %{"id" => id, "email" => email}} =
             ctx.conn |> get(~p"/api/users/#{ctx.client.id}") |> json_response(200)

    assert id == ctx.client.id
    assert email == to_string(ctx.client.email)

    stranger = generate(user())

    assert %{"errors" => %{"detail" => "Not Found"}} =
             ctx.conn |> get(~p"/api/users/#{stranger.id}") |> json_response(404)
  end

  test "POST /api/users is forbidden: users are invited", ctx do
    assert ctx.conn
           |> post(~p"/api/users", user: %{"email" => "bob@example.com", "name" => "Bob"})
           |> json_response(403)
  end

  test "PATCH renames yourself, DELETE removes a client", ctx do
    assert %{"data" => %{"name" => "Renamed"}} =
             ctx.conn
             |> patch(~p"/api/users/#{ctx.coach.id}", user: %{"name" => "Renamed"})
             |> json_response(200)

    assert ctx.conn |> delete(~p"/api/users/#{ctx.client.id}") |> response(204)
    assert ctx.conn |> get(~p"/api/users/#{ctx.client.id}") |> json_response(404)
  end
end
