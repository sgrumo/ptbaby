defmodule Averziano.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Averziano.Repo

      require Ash.Query

      import Averziano.DataCase
      import Averziano.Generator
    end
  end

  setup tags do
    Averziano.DataCase.setup_sandbox(tags)
    :ok
  end

  @spec setup_sandbox(map()) :: :ok
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Averziano.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  The actor used by tests for authorized domain calls. Mirrors the claims
  returned by `Averziano.Auth.TokenMock` for `"valid_token"`.
  """
  @spec actor() :: map()
  def actor, do: %{"sub" => "test-user-id"}
end
