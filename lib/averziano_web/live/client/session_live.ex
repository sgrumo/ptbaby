defmodule AverzianoWeb.Client.SessionLive do
  @moduledoc """
  A day of the program ("Giornata"): the coach's note, the exercises with
  their targets and the button that starts (or resumes) the workout.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.ClientComponents

  alias Averziano.Training
  alias AverzianoWeb.TrainingLabels

  @impl true
  def mount(%{"session_id" => id}, _session, socket) do
    case Training.get_session(id,
           actor: socket.assigns.actor,
           load: [:sets_total, :sets_logged, exercises: [:logged_sets_count]]
         ) do
      {:ok, session} ->
        {:ok, assign(socket, page_title: session.title, session: session)}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Giornata non trovata") |> push_navigate(to: ~p"/app")}
    end
  end

  defp done?(exercise), do: exercise.logged_sets_count >= exercise.sets_count

  defp resume_exercise(%{exercises: exercises}) do
    Enum.find(exercises, List.first(exercises), &(not done?(&1)))
  end

  defp start_label(session) do
    cond do
      session.completed_at -> "Rivedi le serie"
      session.sets_logged > 0 -> "Continua allenamento"
      true -> "Inizia allenamento"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 flex-col">
      <.top_bar
        back={~p"/app?#{[week: @session.week_number]}"}
        context={"Settimana #{@session.week_number} · Giorno #{@session.day_label}"}
      />

      <div class="flex flex-col gap-1 px-6 pt-1">
        <h1 class="font-display text-[28px] font-semibold leading-[34px]">{@session.title}</h1>
        <span id="session-summary" class="text-sm text-neutral-600">
          {String.capitalize(TrainingLabels.long_date(@session.scheduled_on))} · {@session.sets_logged} di {@session.sets_total} serie
        </span>
      </div>

      <.coach_note :if={@session.coach_note} title="Nota del coach" class="mx-4 mt-4">
        {@session.coach_note}
      </.coach_note>

      <.coach_note :if={@session.coach_comment} title="Commento del coach" class="mx-4 mt-4">
        <span id="coach-comment">{@session.coach_comment}</span>
      </.coach_note>

      <div class="flex flex-col gap-2 px-4 pt-4">
        <.link
          :for={exercise <- @session.exercises}
          id={"exercise-#{exercise.id}"}
          navigate={~p"/app/sessions/#{@session.id}/exercises/#{exercise.id}/info"}
          class="flex items-center gap-3 rounded-2xl border border-neutral-200 px-4 py-3.5 hover:bg-neutral-50"
        >
          <span
            :if={!done?(exercise)}
            class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-neutral-50 text-[13px] font-semibold"
          >
            {exercise.position}
          </span>
          <span
            :if={done?(exercise)}
            class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-success-600 text-white"
            aria-label="Completato"
          >
            <.icon name="hero-check-mini" class="h-4 w-4" />
          </span>
          <div class="flex flex-1 flex-col gap-0.5">
            <span class="text-[15px] font-semibold">{exercise.name}</span>
            <span class="text-[13px] text-neutral-600">{TrainingLabels.prescription(exercise)}</span>
            <.badge
              :if={exercise.target_updated_at}
              tone={:warning}
              class="mt-1 self-start !px-2 !py-0.5 !text-[11px]"
            >
              Obiettivo aggiornato
            </.badge>
          </div>
          <.icon name="hero-chevron-right" class="h-5 w-5 text-neutral-400" />
        </.link>
      </div>

      <div
        :if={exercise = resume_exercise(@session)}
        class="sticky bottom-0 mt-auto bg-surface px-4 pb-4 pt-6"
      >
        <.action_button
          id="start-workout"
          navigate={~p"/app/sessions/#{@session.id}/exercises/#{exercise.id}"}
          icon={if @session.completed_at, do: nil, else: "hero-play-solid"}
        >
          {start_label(@session)}
        </.action_button>
      </div>
    </div>
    """
  end
end
