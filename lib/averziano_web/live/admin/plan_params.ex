defmodule AverzianoWeb.Admin.PlanParams do
  @moduledoc """
  The plan as the console edits it, and its conversion to and from the
  `Averziano.Training.PlanDay` / `PlanExercise` attributes.

  While editing, numbers stay the strings typed in the inputs so a half-typed
  value is never lost; they are parsed only when the plan is saved, and Ash
  validates the result.
  """

  alias Averziano.Training.{PlanDay, PlanExercise}
  alias AverzianoWeb.TrainingLabels

  @type exercise :: %{
          id: pos_integer(),
          name: String.t(),
          kind: :reps | :max | :time | :sequence,
          sets_count: String.t(),
          target_reps: String.t(),
          target_load_kg: String.t(),
          load?: boolean(),
          target_seconds: String.t(),
          sequence: String.t(),
          sequence_rest_seconds: String.t(),
          rest_seconds: String.t(),
          notes: String.t(),
          videos: [%{title: String.t(), url: String.t()}]
        }

  @type day :: %{id: pos_integer(), title: String.t(), weekdays: [1..7], exercises: [exercise()]}

  @text_fields ~w(name sets_count target_reps target_load_kg target_seconds sequence sequence_rest_seconds rest_seconds notes)a

  @sequence_presets [
    {"Piramide 1→5→1", "1-2-3-4-5-4-3-2-1"},
    {"Scala 2→8→2", "2-4-6-8-6-4-2"},
    {"Crescente 1→10", "1-2-3-4-5-6-7-8-9-10"}
  ]

  @doc "Ready-made rep sequences: `{label, sequence}`."
  @spec sequence_presets() :: [{String.t(), String.t()}]
  def sequence_presets, do: @sequence_presets

  @doc "Editable days from stored plan days."
  @spec from_days([PlanDay.t()]) :: [day()]
  def from_days(days) do
    Enum.map(days, fn day ->
      %{
        id: id(),
        title: day.title,
        weekdays: Enum.sort(day.weekdays),
        exercises: Enum.map(day.exercises, &from_exercise/1)
      }
    end)
  end

  defp from_exercise(%PlanExercise{} = exercise) do
    %{
      id: id(),
      name: exercise.name,
      kind: exercise.kind,
      sets_count: text(exercise.sets_count),
      target_reps: text(exercise.target_reps),
      target_load_kg:
        if(exercise.target_load_kg, do: TrainingLabels.number(exercise.target_load_kg), else: ""),
      load?: not is_nil(exercise.target_load_kg),
      target_seconds: text(exercise.target_seconds),
      sequence: if(exercise.sequence, do: TrainingLabels.sequence(exercise.sequence), else: ""),
      sequence_rest_seconds: text(exercise.sequence_rest_seconds),
      rest_seconds: text(exercise.rest_seconds),
      notes: exercise.notes || "",
      videos: Enum.map(exercise.videos, &%{title: &1.title, url: &1.url})
    }
  end

  @doc "An empty day."
  @spec new_day(String.t()) :: day()
  def new_day(title), do: %{id: id(), title: title, weekdays: [], exercises: []}

  @doc "A copy of `day` with new ids and no weekdays (they belong to the original)."
  @spec duplicate_day(day()) :: day()
  def duplicate_day(day) do
    %{
      day
      | id: id(),
        title: "#{day.title} (copia)",
        weekdays: [],
        exercises: Enum.map(day.exercises, &%{&1 | id: id()})
    }
  end

  @doc "A new exercise: 3 × 10 reps, bodyweight, 90 s rest."
  @spec new_exercise() :: exercise()
  def new_exercise do
    %{
      id: id(),
      name: "Nuovo esercizio",
      kind: :reps,
      sets_count: "3",
      target_reps: "10",
      target_load_kg: "",
      load?: false,
      target_seconds: "30",
      sequence: "1-2-3-2-1",
      sequence_rest_seconds: "",
      rest_seconds: "90",
      notes: "",
      videos: []
    }
  end

  @doc "Applies the exercise form params (string keys) to an exercise."
  @spec update_exercise(exercise(), map()) :: exercise()
  def update_exercise(exercise, params) do
    exercise =
      Enum.reduce(@text_fields, exercise, fn field, exercise ->
        case Map.fetch(params, Atom.to_string(field)) do
          {:ok, value} -> Map.put(exercise, field, value)
          :error -> exercise
        end
      end)

    case params["load"] do
      nil -> exercise
      value -> %{exercise | load?: value == "true"}
    end
  end

  @doc "Plan day attributes from the edited days."
  @spec to_days([day()]) :: [map()]
  def to_days(days) do
    Enum.map(days, fn day ->
      %{
        title: day.title,
        weekdays: Enum.sort(day.weekdays),
        exercises: Enum.map(day.exercises, &to_exercise/1)
      }
    end)
  end

  defp to_exercise(exercise) do
    Map.merge(
      %{
        name: exercise.name,
        kind: exercise.kind,
        sets_count: int(exercise.sets_count),
        rest_seconds: int(exercise.rest_seconds) || 0,
        sequence_rest_seconds:
          if(exercise.kind == :sequence, do: int(exercise.sequence_rest_seconds)),
        notes: blank_to_nil(exercise.notes),
        videos: exercise.videos
      },
      target(
        exercise.kind,
        exercise |> Map.new(fn {key, value} -> {to_string(key), value} end) |> with_load(exercise)
      )
    )
  end

  defp with_load(params, %{load?: false}), do: Map.put(params, "target_load_kg", "")
  defp with_load(params, _exercise), do: params

  @doc """
  The target attributes of an exercise kind from form params (string keys):
  the ones the kind uses, the others cleared. These are what
  `update_target` accepts.
  """
  @spec target(atom(), map()) :: map()
  def target(kind, params) do
    cleared = %{
      sets_count: int(params["sets_count"]),
      target_reps: nil,
      target_load_kg: nil,
      target_seconds: nil,
      sequence: nil
    }

    case kind do
      :reps ->
        %{
          cleared
          | target_reps: int(params["target_reps"]),
            target_load_kg: decimal(params["target_load_kg"])
        }

      :max ->
        %{cleared | target_load_kg: decimal(params["target_load_kg"])}

      :time ->
        %{cleared | target_seconds: int(params["target_seconds"])}

      :sequence ->
        %{cleared | sequence: sequence(params["sequence"])}
    end
  end

  @doc "A whole number from input text, or `nil`."
  @spec int(String.t() | nil) :: integer() | nil
  def int(text) do
    case Integer.parse(String.trim(text || "")) do
      {value, ""} -> value
      _ -> nil
    end
  end

  @doc "A decimal from input text, accepting a decimal comma, or `nil`."
  @spec decimal(String.t() | nil) :: Decimal.t() | nil
  def decimal(text) do
    case text |> to_string() |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {value, ""} -> value
      _ -> nil
    end
  end

  @doc ~s|A rep sequence from text such as "1-2-3-2-1" (any non-digit separates steps), or `nil`.|
  @spec sequence(String.t() | nil) :: [pos_integer()] | nil
  def sequence(text) do
    steps =
      text
      |> to_string()
      |> String.split(~r/\D+/, trim: true)
      |> Enum.map(&String.to_integer/1)

    if steps != [] and Enum.all?(steps, &(&1 > 0)), do: steps
  end

  defp text(nil), do: ""
  defp text(value), do: to_string(value)

  defp blank_to_nil(text), do: if(String.trim(text || "") == "", do: nil, else: text)

  defp id, do: System.unique_integer([:positive])
end
