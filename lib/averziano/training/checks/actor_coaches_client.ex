defmodule Averziano.Training.Checks.ActorCoachesClient do
  @moduledoc "Authorizes a change whose `client_id` is a client of the actor (who is therefore a coach)."

  use Ash.Policy.SimpleCheck

  alias Averziano.Accounts.User

  @impl true
  def describe(_opts), do: "the program's client is coached by the actor"

  @impl true
  def match?(%{"sub" => actor_id}, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    with client_id when not is_nil(client_id) <-
           Ash.Changeset.get_attribute(changeset, :client_id),
         {:ok, %User{role: :client, coach_id: ^actor_id}} <-
           Ash.get(User, client_id, authorize?: false, error?: false) do
      true
    else
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
