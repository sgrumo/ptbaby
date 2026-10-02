defmodule Averziano.AccountsTest do
  use Averziano.DataCase, async: true

  alias Averziano.Accounts
  alias Averziano.Accounts.User
  alias Averziano.Errors

  describe "register_user/2" do
    test "creates a user with a case-insensitive unique email" do
      assert {:ok, %User{} = user} =
               Accounts.register_user(%{email: "Ada@Example.com", name: "Ada"}, actor: actor())

      assert to_string(user.email) == "Ada@Example.com"

      assert {:error, error} =
               Accounts.register_user(%{email: "ada@example.com", name: "Dup"}, actor: actor())

      assert {:error, :unprocessable_entity, %{email: [message]}} =
               Errors.normalize({:error, error})

      assert message =~ "already been taken"
    end

    test "returns field errors for missing attributes" do
      assert {:error, error} = Accounts.register_user(%{}, actor: actor())

      assert {:error, :unprocessable_entity, errors} = Errors.normalize({:error, error})
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :name)
    end
  end

  describe "get_user/2" do
    test "returns the user, or a not found error" do
      user = generate(user())

      assert {:ok, %User{id: id}} = Accounts.get_user(user.id, actor: actor())
      assert id == user.id

      assert {:error, error} = Accounts.get_user(Ash.UUID.generate(), actor: actor())
      assert Errors.normalize({:error, error}) == {:error, :not_found}
    end
  end

  describe "update_user/3 and delete_user/2" do
    test "updates the name and deletes the user" do
      user = generate(user(name: "Before"))

      assert {:ok, %User{name: "After"}} =
               Accounts.update_user(user, %{name: "After"}, actor: actor())

      assert :ok = Accounts.delete_user(user, actor: actor())
      assert {:ok, []} = Accounts.list_users(actor: actor())
    end
  end

  describe "policies" do
    test "without an actor, reads are filtered to nothing and writes are forbidden" do
      user = generate(user())

      # `no_filter_static_forbidden_reads?: false` turns a forbidden read into an empty result.
      assert {:ok, []} = Accounts.list_users()

      assert {:error, error} = Accounts.register_user(%{email: "x@example.com", name: "X"})
      assert Errors.normalize({:error, error}) == {:error, :forbidden}

      assert {:error, error} = Accounts.update_user(user, %{name: "Nope"})
      assert Errors.normalize({:error, error}) == {:error, :forbidden}
    end
  end
end
