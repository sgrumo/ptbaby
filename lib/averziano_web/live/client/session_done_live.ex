defmodule AverzianoWeb.Client.SessionDoneLive do
  @moduledoc """
  End of the day ("Fine giornata"): what was logged, and the note sent to the
  coach together with the sets when the session is completed.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.ClientComponents

  alias Averziano.{Errors, Training}
  alias AverzianoWeb.TrainingLabels

  @impl true
  def mount(%{"session_id" => id}, _session, socket) do
    case load_session(id, socket.assigns.actor) do
      {:ok, session} ->
        {:ok,
         assign(socket,
           page_title: "Fine giornata",
           session: session,
           form: to_form(%{"client_note" => session.client_note || ""})
         )}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Giornata non trovata") |> push_navigate(to: ~p"/app")}
    end
  end

  defp load_session(id, actor) do
    Training.get_session(id,
      actor: actor,
      load: [:sets_total, :sets_logged, exercises: [:logged_sets_count], program: [:coach]]
    )
  end

  @impl true
  def handle_event("send", %{"client_note" => note}, socket) do
    %{session: session, actor: actor} = socket.assigns
    note = if String.trim(note) == "", do: nil, else: note

    case Training.complete_session(session, %{client_note: note}, actor: actor) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> put_flash(:info, "Giornata inviata a #{coach_name(session)}")
         |> push_navigate(to: ~p"/app?#{[week: session.week_number]}")}

      {:error, error} ->
        message =
          case Errors.normalize({:error, error}) do
            {:error, :unprocessable_entity, %{completed_at: [message | _]}} -> message
            _ -> "Impossibile inviare la giornata"
          end

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp coach_name(session), do: TrainingLabels.first_name(session.program.coach.name)

  defp exercises_done(session) do
    Enum.count(session.exercises, &(&1.logged_sets_count >= &1.sets_count))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 flex-col">
      <div class="flex flex-col items-center gap-3 px-6 pt-12 text-center">
        <span class="flex h-[72px] w-[72px] items-center justify-center rounded-full bg-success-100 text-success-600">
          <.icon name="hero-check-badge" class="h-9 w-9" />
        </span>
        <h1 class="font-display text-[28px] font-semibold leading-[34px]">Giornata completata</h1>
        <span class="text-[15px] text-neutral-600">
          Settimana {@session.week_number} · Giorno {@session.day_label} · {@session.title}
        </span>
      </div>

      <dl class="mx-4 mt-7 grid grid-cols-2 rounded-2xl border border-neutral-200">
        <div class="flex flex-col gap-0.5 px-4 py-3.5">
          <dt class="text-xs text-neutral-500">Esercizi</dt>
          <dd id="exercises-done" class="text-[22px] font-semibold">
            {exercises_done(@session)} di {length(@session.exercises)}
          </dd>
        </div>
        <div class="flex flex-col gap-0.5 border-l border-neutral-100 px-4 py-3.5">
          <dt class="text-xs text-neutral-500">Serie</dt>
          <dd id="sets-done" class="text-[22px] font-semibold">
            {@session.sets_logged} di {@session.sets_total}
          </dd>
        </div>
      </dl>

      <%= if @session.completed_at do %>
        <div id="sent-note" class="flex flex-col gap-2 px-4 pt-6">
          <span class="px-1 text-sm font-semibold">La tua nota</span>
          <p class="rounded-xl bg-neutral-50 px-4 py-3.5 text-[15px] leading-[22px]">
            {@session.client_note || "Nessuna nota"}
          </p>
          <span class="px-1 text-[13px] text-neutral-500">Inviata a {coach_name(@session)}.</span>
        </div>

        <div class="sticky bottom-0 mt-auto flex flex-col gap-2 bg-surface px-4 pb-4 pt-6">
          <.action_button navigate={~p"/app?#{[week: @session.week_number]}"}>Torna al programma</.action_button>
        </div>
      <% else %>
        <.form for={@form} id="session-note" phx-submit="send" class="flex flex-1 flex-col">
          <div class="flex flex-col gap-2 px-4 pt-6">
            <label for="client-note" class="px-1 text-sm font-semibold">Com'è andata?</label>
            <.input
              field={@form[:client_note]}
              id="client-note"
              type="textarea"
              rows="5"
              placeholder="Energia, fatica, cosa è stato difficile…"
              class="block min-h-[132px] w-full rounded-xl border-2 border-neutral-200 px-4 py-3.5 text-[15px] leading-[22px] focus:border-primary-500 focus:ring-0"
            />
            <span class="px-1 text-[13px] text-neutral-500">
              {coach_name(@session)} vedrà la nota insieme alle serie registrate.
            </span>
          </div>

          <div class="sticky bottom-0 mt-auto flex flex-col gap-2 bg-surface px-4 pb-4 pt-6">
            <.action_button type="submit" phx-disable-with="Invio…">Invia al coach</.action_button>
            <.link
              :if={exercise = List.first(@session.exercises)}
              navigate={~p"/app/sessions/#{@session.id}/exercises/#{exercise.id}"}
              class="flex h-11 items-center justify-center text-[15px] font-medium text-neutral-600"
            >
              Rivedi le serie
            </.link>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end
end
