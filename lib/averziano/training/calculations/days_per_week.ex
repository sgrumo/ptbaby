defmodule Averziano.Training.Calculations.DaysPerWeek do
  @moduledoc "How many sessions a week a plan schedules: the weekdays of all its days."

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:days]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record -> record.days |> Enum.map(&length(&1.weekdays)) |> Enum.sum() end)
  end
end
