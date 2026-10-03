defmodule Averziano.Training.Actions.Retarget do
  @moduledoc """
  Applies a new target to the open replicas of an exercise that come after
  its session: the next one only (`scope: :next`) or all of them (`:future`).
  Each replica goes through `update_target`, so the coach check applies to
  every record.
  """

  use Ash.Resource.Actions.Implementation

  alias Averziano.Training.Exercise

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)
    %{exercise_id: exercise_id, scope: scope, target: target} = input.arguments

    with {:ok, exercise} <- Ash.get(Exercise, exercise_id, Keyword.put(opts, :load, [:session])),
         {:ok, replicas} <- replicas(exercise, opts) do
      replicas
      |> Enum.take(if scope == :next, do: 1, else: length(replicas))
      |> update_all(target, Keyword.put(opts, :action, :update_target))
    end
  end

  defp update_all(replicas, target, opts) do
    Enum.reduce_while(replicas, {:ok, []}, fn replica, {:ok, updated} ->
      case Ash.update(replica, target, opts) do
        {:ok, replica} -> {:cont, {:ok, updated ++ [replica]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp replicas(%Exercise{session: session, name: name}, opts) do
    Exercise
    |> Ash.Query.for_read(
      :replicas,
      %{
        program_id: session.program_id,
        day_label: session.day_label,
        name: name,
        after: session.scheduled_on
      },
      opts
    )
    |> Ash.read()
  end
end
