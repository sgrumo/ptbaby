defmodule AverzianoWeb.TrainingLabels do
  @moduledoc """
  Italian, human-readable labels for training data: prescriptions
  ("5 × 5 rip · 50 kg"), logged sets, loads, durations and dates.
  """

  alias Averziano.Training.{Exercise, PlanExercise, SetLog}

  @typedoc "A dated exercise or a plan exercise: both carry a kind and targets."
  @type exercise :: Exercise.t() | PlanExercise.t()

  @weekdays ~w(lunedì martedì mercoledì giovedì venerdì sabato domenica)
  @weekday_initials ~w(L M M G V S D)
  @months ~w(gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre)

  @doc "The exercise kind, as the coach console names it."
  @spec kind(%{kind: atom()} | atom()) :: String.t()
  def kind(%{kind: kind}), do: kind(kind)
  def kind(:reps), do: "Serie × Rip"
  def kind(:max), do: "Serie × Max"
  def kind(:time), do: "Serie × Tempo"
  def kind(:sequence), do: "Sequenza"

  @doc "The exercise kind spelled out, as the review screen names it."
  @spec kind_long(%{kind: atom()} | atom()) :: String.t()
  def kind_long(%{kind: kind}), do: kind_long(kind)
  def kind_long(:reps), do: "Serie × Ripetizioni"
  def kind_long(kind), do: kind(kind)

  @doc ~S"""
  The whole prescription of an exercise.

      "5 × 5 rip · 50 kg"   "2 × Max"   "4 × 30 s"   "1-2-3-2-1"
  """
  @spec prescription(exercise()) :: String.t()
  def prescription(%{kind: :reps} = exercise),
    do: "#{exercise.sets_count} × #{set_target(exercise)}"

  def prescription(%{kind: :max, sets_count: sets}), do: "#{sets} × Max"

  def prescription(%{kind: :time} = exercise),
    do: "#{exercise.sets_count} × #{set_target(exercise)}"

  def prescription(%{kind: :sequence, sequence: sequence}), do: sequence(sequence)

  @doc "The prescription with the detail the workout header shows next to the position."
  @spec header_detail(exercise()) :: String.t()
  def header_detail(%{kind: :max} = exercise),
    do: "#{prescription(exercise)} · #{load(exercise.target_load_kg)}"

  def header_detail(%{kind: :sequence, sets_count: sets}), do: "#{sets} serie · sequenza"
  def header_detail(%{} = exercise), do: prescription(exercise)

  @doc "The target of a single set, e.g. \"5 rip · 50 kg\"."
  @spec set_target(exercise()) :: String.t()
  def set_target(%{kind: :reps, target_load_kg: nil, target_reps: reps}),
    do: "#{reps} rip"

  def set_target(%{kind: :reps} = exercise),
    do: "#{exercise.target_reps} rip · #{load(exercise.target_load_kg)}"

  def set_target(%{kind: :max}), do: "Max rip"
  def set_target(%{kind: :time, target_seconds: seconds}), do: "#{seconds} s"
  def set_target(%{kind: :sequence, sequence: sequence}), do: sequence(sequence)

  @doc "What the current set asks for, shown in its card."
  @spec set_goal(exercise()) :: String.t()
  def set_goal(%{kind: :max}), do: "Massimo ripetizioni"
  def set_goal(%{kind: :sequence}), do: "Una registrazione per serie"
  def set_goal(%{} = exercise), do: "Obiettivo #{set_target(exercise)}"

  @doc ~s(A logged set, e.g. "5 rip · 50 kg" or "1-2-3-2-1 · completa".)
  @spec set_result(exercise(), SetLog.t()) :: String.t()
  def set_result(%{kind: :time}, %SetLog{seconds: seconds}), do: "#{seconds} s"

  def set_result(%{kind: :sequence, sequence: sequence}, %SetLog{outcome: outcome}),
    do: "#{sequence(sequence)} · #{if outcome == :complete, do: "completa", else: "parziale"}"

  def set_result(%{}, %SetLog{reps: reps, load_kg: nil}), do: "#{reps} rip"

  def set_result(%{}, %SetLog{reps: reps, load_kg: load_kg}),
    do: "#{reps} rip · #{load(load_kg)}"

  @doc "A rep sequence, e.g. \"1-2-3-2-1\"."
  @spec sequence([pos_integer()]) :: String.t()
  def sequence(steps), do: Enum.join(steps, "-")

  @doc "A load in kilograms with an Italian decimal comma; `nil` is bodyweight."
  @spec load(Decimal.t() | nil) :: String.t()
  def load(nil), do: "corpo libero"
  def load(%Decimal{} = kg), do: "#{number(kg)} kg"

  @doc "A decimal without trailing zeros and with a decimal comma: 52.50 → \"52,5\"."
  @spec number(Decimal.t()) :: String.t()
  def number(%Decimal{} = value) do
    value |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")
  end

  @doc "Seconds as m:ss, e.g. 84 → \"1:24\"."
  @spec clock(non_neg_integer()) :: String.t()
  def clock(seconds) do
    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc "e.g. \"venerdì 2 ottobre\"."
  @spec long_date(Date.t()) :: String.t()
  def long_date(%Date{} = date), do: "#{weekday(date)} #{date.day} #{month(date)}"

  @doc "e.g. \"18 ott\"."
  @spec short_date(Date.t()) :: String.t()
  def short_date(%Date{} = date), do: "#{date.day} #{String.slice(month(date), 0, 3)}"

  @doc "e.g. \"VEN\"."
  @spec weekday_abbr(Date.t()) :: String.t()
  def weekday_abbr(%Date{} = date), do: date |> weekday() |> String.slice(0, 3) |> String.upcase()

  @doc "e.g. \"venerdì\"."
  @spec weekday(Date.t()) :: String.t()
  def weekday(%Date{} = date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  @doc "e.g. \"18 ott 2026\"."
  @spec short_date_year(Date.t()) :: String.t()
  def short_date_year(%Date{} = date), do: "#{short_date(date)} #{date.year}"

  @doc "e.g. \"Lun 21\"."
  @spec day_date(Date.t()) :: String.t()
  def day_date(%Date{} = date), do: "#{weekday_short(Date.day_of_week(date))} #{date.day}"

  @doc "An ISO weekday (1 = Monday) as \"Lun\"."
  @spec weekday_short(1..7) :: String.t()
  def weekday_short(weekday),
    do: @weekdays |> Enum.at(weekday - 1) |> String.slice(0, 3) |> String.capitalize()

  @doc "An ISO weekday (1 = Monday) as its initial, \"L\"."
  @spec weekday_initial(1..7) :: String.t()
  def weekday_initial(weekday), do: Enum.at(@weekday_initials, weekday - 1)

  @doc "ISO weekdays as \"Lun · Gio\"."
  @spec weekdays([1..7]) :: String.t()
  def weekdays(weekdays), do: weekdays |> Enum.sort() |> Enum.map_join(" · ", &weekday_short/1)

  @doc ~s(The Monday-to-Sunday week starting on `monday`: "21–27 set" or "28 set–4 ott".)
  @spec week_range(Date.t()) :: String.t()
  def week_range(%Date{} = monday) do
    sunday = Date.add(monday, 6)

    if monday.month == sunday.month,
      do: "#{monday.day}–#{short_date(sunday)}",
      else: "#{short_date(monday)}–#{short_date(sunday)}"
  end

  @doc ~s(A past moment relative to `today`: "Oggi, 07:40", "Ieri, 18:20" or "30 set, 19:05".)
  @spec moment(DateTime.t(), Date.t()) :: String.t()
  def moment(%DateTime{} = datetime, %Date{} = today) do
    time = Calendar.strftime(datetime, "%H:%M")

    case Date.diff(today, DateTime.to_date(datetime)) do
      0 -> "Oggi, #{time}"
      1 -> "Ieri, #{time}"
      _ -> "#{short_date(DateTime.to_date(datetime))}, #{time}"
    end
  end

  defp month(%Date{month: month}), do: Enum.at(@months, month - 1)

  @doc "The first word of a full name."
  @spec first_name(String.t()) :: String.t()
  def first_name(name), do: name |> String.split() |> List.first("")

  @doc ~s(Up to two initials of a full name, e.g. "Giulia Rossi" → "GR".)
  @spec initials(String.t()) :: String.t()
  def initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
