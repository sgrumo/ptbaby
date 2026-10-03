defmodule Averziano.Accounts.Checks.ActorIsCoach do
  @moduledoc "Authorizes actors whose user has the `:coach` role."

  use Ash.Policy.SimpleCheck

  alias Averziano.Accounts.User

  @impl true
  def describe(_opts), do: "actor is a coach"

  @impl true
  def match?(%{"sub" => user_id}, _context, _opts) do
    match?({:ok, %User{role: :coach}}, Ash.get(User, user_id, authorize?: false, error?: false))
  end

  def match?(_actor, _context, _opts), do: false
end
