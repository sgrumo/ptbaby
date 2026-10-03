defmodule Averziano.Training.Validations.PublishablePlan do
  @moduledoc "A program can be published once every day of its plan has weekdays and exercises."

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    days = Ash.Changeset.get_attribute(changeset, :days)

    cond do
      days == [] ->
        error("aggiungi almeno un giorno")

      Enum.any?(days, &(&1.weekdays == [])) ->
        error("ogni giorno deve avere almeno un giorno della settimana")

      Enum.any?(days, &(&1.exercises == [])) ->
        error("ogni giorno deve avere almeno un esercizio")

      true ->
        :ok
    end
  end

  defp error(message), do: {:error, InvalidAttribute.exception(field: :days, message: message)}
end
