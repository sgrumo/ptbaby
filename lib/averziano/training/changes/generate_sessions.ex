defmodule Averziano.Training.Changes.GenerateSessions do
  @moduledoc """
  After a program is published, creates its sessions: for every week and
  every weekday of every plan day, a dated copy of the day with its
  exercises. Week 1 is the (Monday-based) week of `starts_on`; dates outside
  `starts_on..ends_on` are skipped.
  """

  use Ash.Resource.Change

  alias Averziano.Training.{Exercise, PlanDay, Program, Session}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, program ->
      program |> schedule() |> Enum.each(&create_session(program, &1))
      {:ok, program}
    end)
  end

  @doc "The `{week, day_index, %PlanDay{}, date}` occurrences of a program, by date."
  @spec schedule(Program.t()) :: [{pos_integer(), non_neg_integer(), PlanDay.t(), Date.t()}]
  def schedule(%{days: days, weeks_count: weeks, starts_on: starts_on, ends_on: ends_on}) do
    monday = Date.beginning_of_week(starts_on)

    for week <- 1..weeks//1,
        {day, index} <- Enum.with_index(days),
        weekday <- day.weekdays,
        date = Date.add(monday, (week - 1) * 7 + weekday - 1),
        Date.compare(date, starts_on) != :lt and Date.compare(date, ends_on) != :gt do
      {week, index, day, date}
    end
    |> Enum.sort_by(&elem(&1, 3), Date)
  end

  @doc "The letter of the day at `index` in a plan: 0 → \"A\"."
  @spec day_label(non_neg_integer()) :: String.t()
  def day_label(index), do: <<?A + index>>

  defp create_session(program, {week, index, day, date}) do
    session =
      Ash.create!(
        Session,
        %{
          program_id: program.id,
          week_number: week,
          day_label: day_label(index),
          title: day.title,
          scheduled_on: date
        },
        action: :create,
        authorize?: false
      )

    day.exercises
    |> Enum.with_index(1)
    |> Enum.each(fn {exercise, position} ->
      Ash.create!(
        Exercise,
        exercise
        |> Map.take([
          :name,
          :kind,
          :sets_count,
          :target_reps,
          :target_load_kg,
          :target_seconds,
          :sequence,
          :sequence_rest_seconds,
          :rest_seconds,
          :notes
        ])
        |> Map.merge(%{
          session_id: session.id,
          position: position,
          videos: Enum.map(exercise.videos, &Map.take(&1, [:title, :url]))
        }),
        action: :create,
        authorize?: false
      )
    end)
  end
end
