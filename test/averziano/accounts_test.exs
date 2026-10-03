defmodule Averziano.AccountsTest do
  use Averziano.DataCase, async: true

  alias Averziano.Accounts
  alias Averziano.Accounts.User
  alias Averziano.Errors

  setup do
    coach = generate(coach())
    client = generate(client(coach: coach))

    %{
      coach: coach,
      client: client,
      as_coach: %{"sub" => coach.id},
      as_client: %{"sub" => client.id}
    }
  end

  describe "invite_client/2" do
    test "emails are unique regardless of case", ctx do
      params = %{first_name: "Ada", last_name: "Lovelace", email: "Ada@Example.com"}
      assert {:ok, %User{} = ada} = Accounts.invite_client(params, actor: ctx.as_coach)
      assert to_string(ada.email) == "Ada@Example.com"

      assert {:error, error} =
               Accounts.invite_client(%{params | email: "ada@example.com"}, actor: ctx.as_coach)

      assert {:error, :unprocessable_entity, %{email: [message]}} =
               Errors.normalize({:error, error})

      assert message =~ "already been taken"
    end

    test "returns field errors for missing attributes", ctx do
      assert {:error, error} = Accounts.invite_client(%{}, actor: ctx.as_coach)

      assert {:error, :unprocessable_entity, errors} = Errors.normalize({:error, error})
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :first_name)
    end
  end

  describe "register_user/2" do
    test "nobody can sign up: users are invited", ctx do
      assert {:error, error} =
               Accounts.register_user(%{email: "x@example.com", name: "X"}, actor: ctx.as_client)

      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end

  describe "get_user/2 and list_users/1" do
    test "users see themselves, their coach and their clients, nobody else", ctx do
      stranger = generate(user())

      assert {:ok, _} = Accounts.get_user(ctx.client.id, actor: ctx.as_client)
      assert {:ok, _} = Accounts.get_user(ctx.coach.id, actor: ctx.as_client)
      assert {:ok, _} = Accounts.get_user(ctx.client.id, actor: ctx.as_coach)

      assert {:error, error} = Accounts.get_user(stranger.id, actor: ctx.as_coach)
      assert Errors.normalize({:error, error}) == {:error, :not_found}

      assert {:ok, users} = Accounts.list_users(actor: ctx.as_coach)
      assert users |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([ctx.coach.id, ctx.client.id])
    end
  end

  describe "update_user/3 and delete_user/2" do
    test "users rename themselves; the coach removes their clients", ctx do
      assert {:ok, %User{name: "After"}} =
               Accounts.update_user(ctx.client, %{name: "After"}, actor: ctx.as_client)

      assert {:error, error} =
               Accounts.update_user(ctx.client, %{name: "Nope"}, actor: ctx.as_coach)

      assert Errors.normalize({:error, error}) == {:error, :forbidden}

      assert {:error, error} = Accounts.delete_user(ctx.coach, actor: ctx.as_client)
      assert Errors.normalize({:error, error}) == {:error, :forbidden}

      assert :ok = Accounts.delete_user(ctx.client, actor: ctx.as_coach)
      assert {:ok, []} = Accounts.list_clients(actor: ctx.as_coach)
    end
  end

  describe "policies" do
    test "without an actor, reads are filtered to nothing and writes are forbidden", ctx do
      # `no_filter_static_forbidden_reads?: false` turns a forbidden read into an empty result.
      assert {:ok, []} = Accounts.list_users()

      assert {:error, error} = Accounts.update_user(ctx.client, %{name: "Nope"})
      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end
end
