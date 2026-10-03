defmodule Averziano.Training.Changes.RecordSet do
  @moduledoc """
  Prepares a `SetLog` for its exercise: assigns the next set number, rejects
  sets beyond the prescribed count or for an already completed session, and
  requires the value the exercise kind is logged with. A complete sequence
  set records the sequence total as its reps.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Averziano.Training.Exercise

  @impl true
  def change(changeset, _opts, _context) do
    with exercise_id when not is_nil(exercise_id) <-
           Changeset.get_attribute(changeset, :exercise_id),
         {:ok, %Exercise{} = exercise} <- load_exercise(exercise_id) do
      record(changeset, exercise)
    else
      _ -> Changeset.add_error(changeset, field: :exercise_id, message: "esercizio non trovato")
    end
  end

  defp load_exercise(id) do
    Ash.get(Exercise, id,
      load: [:logged_sets_count, :session],
      authorize?: false,
      error?: false
    )
  end

  defp record(changeset, %Exercise{} = exercise) do
    cond do
      exercise.session.completed_at ->
        Changeset.add_error(changeset,
          field: :exercise_id,
          message: "la giornata è già completata"
        )

      exercise.logged_sets_count >= exercise.sets_count ->
        Changeset.add_error(changeset,
          field: :exercise_id,
          message: "tutte le serie sono già registrate"
        )

      true ->
        changeset
        |> Changeset.force_change_attribute(:set_number, exercise.logged_sets_count + 1)
        |> require_value(exercise)
    end
  end

  defp require_value(changeset, %Exercise{kind: kind}) when kind in [:reps, :max],
    do: require_attribute(changeset, :reps)

  defp require_value(changeset, %Exercise{kind: :time}),
    do: require_attribute(changeset, :seconds)

  defp require_value(changeset, %Exercise{kind: :sequence, sequence: sequence}) do
    changeset = require_attribute(changeset, :outcome)

    if Changeset.get_attribute(changeset, :outcome) == :complete and
         is_nil(Changeset.get_attribute(changeset, :reps)) do
      Changeset.force_change_attribute(changeset, :reps, Enum.sum(sequence))
    else
      changeset
    end
  end

  defp require_attribute(changeset, field) do
    if is_nil(Changeset.get_attribute(changeset, field)) do
      Changeset.add_error(changeset, field: field, message: "is required")
    else
      changeset
    end
  end
end
