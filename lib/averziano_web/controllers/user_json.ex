defmodule AverzianoWeb.UserJSON do
  @moduledoc false

  alias Averziano.Accounts.User

  @spec index(%{users: [User.t()]}) :: map()
  def index(%{users: users}), do: %{data: Enum.map(users, &data/1)}

  @spec show(%{user: User.t()}) :: map()
  def show(%{user: user}), do: %{data: data(user)}

  defp data(%User{} = user) do
    %{
      id: user.id,
      email: to_string(user.email),
      name: user.name,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
