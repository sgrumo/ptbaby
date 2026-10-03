defmodule Averziano.Training.Checks.ActorOwnsProgram do
  @moduledoc """
  Authorizes creating a record that belongs to a program of the actor, as its
  `role` (`:client` or `:coach`). The program is found through whichever of
  `program_id`, `session_id` or `exercise_id` the changeset sets. Expression
  checks can't follow relationships of a record that doesn't exist yet, so
  the program is looked up here.

      authorize_if {ActorOwnsProgram, role: :coach}
  """

  use Ash.Policy.SimpleCheck

  alias Averziano.Training.{Exercise, Program, Session}

  @impl true
  def describe(opts), do: "actor is the #{opts[:role]} of the program"

  @impl true
  def match?(%{"sub" => actor_id}, %{changeset: %Ash.Changeset{} = changeset}, opts) do
    case program(changeset) do
      %Program{} = program -> Map.fetch!(program, owner_field(opts[:role])) == actor_id
      nil -> false
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp owner_field(:client), do: :client_id
  defp owner_field(:coach), do: :coach_id

  defp program(changeset) do
    attribute = &Ash.Changeset.get_attribute(changeset, &1)

    cond do
      id = attribute.(:program_id) ->
        fetch(Program, id, [])

      id = attribute.(:session_id) ->
        fetch(Session, id, [:program]) |> then(&(&1 && &1.program))

      id = attribute.(:exercise_id) ->
        fetch(Exercise, id, session: :program) |> then(&(&1 && &1.session.program))

      true ->
        nil
    end
  end

  defp fetch(resource, id, load) do
    case Ash.get(resource, id, load: load, authorize?: false, error?: false) do
      {:ok, record} -> record
      _ -> nil
    end
  end
end
