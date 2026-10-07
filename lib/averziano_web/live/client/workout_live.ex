defmodule AverzianoWeb.Client.WorkoutLive do
  @moduledoc """
  The workout timeline of one exercise: every set is listed, logged sets in
  green and only the current one editable. Completing a set starts the rest
  timer. The current set's editor depends on the exercise kind (reps × load,
  max reps, timed hold, rep sequence).
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.ClientComponents

  alias Averziano.{Errors, Training}
  alias AverzianoWeb.TrainingLabels

  @load_step Decimal.new("2.5")

  @impl true
  def mount(%{"session_id" => id}, _session, socket) do
    case load_session(id, socket.assigns.actor) do
      {:ok, session} ->
        {:ok, assign(socket, session: session, rest: nil)}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Giornata non trovata") |> push_navigate(to: ~p"/app")}
    end
  end

  @impl true
  def handle_params(
        %{"exercise_id" => exercise_id},
        _uri,
        %{assigns: %{session: session}} = socket
      ) do
    case Enum.find_index(session.exercises, &(&1.id == exercise_id)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Esercizio non trovato")
         |> push_navigate(to: ~p"/app/sessions/#{session.id}")}

      index ->
        {:noreply,
         socket
         |> assign(index: index, hold: nil, note_open?: false)
         |> assign_exercise()
         |> assign_previous()}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load_session(id, actor) do
    Training.get_session(id, actor: actor, load: [exercises: [:set_logs], program: [:coach]])
  end

  defp assign_exercise(%{assigns: %{session: session, index: index}} = socket) do
    exercise = Enum.at(session.exercises, index)
    assign(socket, page_title: exercise.name, exercise: exercise, draft: draft(exercise))
  end

  # "Ultima volta" — only max-rep sets show how the previous occurrence went.
  defp assign_previous(
         %{assigns: %{exercise: %{kind: :max} = exercise, session: session}} = socket
       ) do
    {:ok, previous} =
      Training.previous_performance(session.program_id, exercise.name, session.scheduled_on,
        actor: socket.assigns.actor,
        load: [:set_logs, :scheduled_on]
      )

    assign(socket, :previous, previous)
  end

  defp assign_previous(socket), do: assign(socket, :previous, nil)

  # The editor starts from the last logged set, else from the target.
  defp draft(exercise) do
    last = List.last(exercise.set_logs)

    %{
      reps: (last && last.reps) || exercise.target_reps || 0,
      load_kg: (last && last.load_kg) || exercise.target_load_kg,
      seconds: exercise.target_seconds || 0,
      outcome: :complete,
      note: ""
    }
  end

  @impl true
  def handle_event("inc", %{"field" => field}, socket), do: {:noreply, step(socket, field, 1)}
  def handle_event("dec", %{"field" => field}, socket), do: {:noreply, step(socket, field, -1)}

  def handle_event("set_outcome", %{"outcome" => outcome}, socket) do
    outcome = if outcome == "partial", do: :partial, else: :complete
    {:noreply, update(socket, :draft, &%{&1 | outcome: outcome})}
  end

  def handle_event("open_note", _params, socket),
    do: {:noreply, assign(socket, :note_open?, true)}

  def handle_event("update_note", %{"note" => note}, socket) do
    {:noreply, update(socket, :draft, &%{&1 | note: note})}
  end

  def handle_event("complete_set", _params, socket) do
    %{exercise: exercise, draft: draft, actor: actor, session: session} = socket.assigns
    params = exercise |> log_params(draft) |> Map.put(:exercise_id, exercise.id)

    case Training.log_set(params, actor: actor) do
      {:ok, _set_log} ->
        {:ok, session} = load_session(session.id, actor)

        {:noreply,
         socket
         |> assign(session: session, hold: nil, note_open?: false)
         |> assign_exercise()
         |> start_rest()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("skip_rest", _params, socket), do: {:noreply, assign(socket, :rest, nil)}

  def handle_event("rest_finished", %{"key" => key}, socket) do
    {:noreply,
     if(timer_key?(socket.assigns.rest, key), do: assign(socket, :rest, nil), else: socket)}
  end

  def handle_event("start_hold", _params, socket) do
    hold = %{
      key: timer_key(),
      started_at: now_ms(),
      seconds: socket.assigns.exercise.target_seconds
    }

    {:noreply, assign(socket, :hold, hold)}
  end

  def handle_event("stop_hold", _params, %{assigns: %{hold: %{} = hold}} = socket) do
    held = min(div(now_ms() - hold.started_at, 1000), hold.seconds)
    {:noreply, socket |> assign(:hold, nil) |> update(:draft, &%{&1 | seconds: held})}
  end

  def handle_event("hold_finished", %{"key" => key}, %{assigns: %{hold: %{} = hold}} = socket) do
    if timer_key?(hold, key) do
      {:noreply, socket |> assign(:hold, nil) |> update(:draft, &%{&1 | seconds: hold.seconds})}
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ["stop_hold", "hold_finished"],
    do: {:noreply, socket}

  defp step(socket, "reps", dir), do: update(socket, :draft, &%{&1 | reps: max(&1.reps + dir, 0)})

  defp step(socket, "seconds", dir),
    do: update(socket, :draft, &%{&1 | seconds: max(&1.seconds + dir, 0)})

  defp step(socket, "load_kg", dir) do
    update(socket, :draft, fn draft ->
      load = Decimal.add(draft.load_kg || Decimal.new(0), Decimal.mult(@load_step, dir))
      %{draft | load_kg: Decimal.max(load, Decimal.new(0))}
    end)
  end

  defp step(socket, _field, _dir), do: socket

  defp log_params(%{kind: :reps}, draft), do: %{reps: draft.reps, load_kg: draft.load_kg}

  defp log_params(%{kind: :max} = exercise, draft),
    do: %{reps: draft.reps, load_kg: exercise.target_load_kg}

  defp log_params(%{kind: :time}, draft), do: %{seconds: draft.seconds}

  defp log_params(%{kind: :sequence}, draft) do
    %{outcome: draft.outcome, note: if(String.trim(draft.note) == "", do: nil, else: draft.note)}
  end

  defp error_message(error) do
    case Errors.normalize({:error, error}) do
      {:error, :unprocessable_entity, errors} ->
        errors |> Map.values() |> List.flatten() |> Enum.join(", ")

      _ ->
        "Impossibile registrare la serie"
    end
  end

  # Rest starts after every completed set while any set of the session is left.
  defp start_rest(%{assigns: %{exercise: exercise, session: session}} = socket) do
    if exercise.rest_seconds > 0 and Enum.any?(session.exercises, &(not exercise_done?(&1))) do
      assign(socket, :rest, %{key: timer_key(), ends_at: now_ms() + exercise.rest_seconds * 1000})
    else
      assign(socket, :rest, nil)
    end
  end

  defp exercise_done?(exercise), do: length(exercise.set_logs) >= exercise.sets_count

  defp timer_key, do: System.unique_integer([:positive])
  defp timer_key?(timer, key), do: timer != nil and to_string(timer.key) == key
  defp now_ms, do: System.system_time(:millisecond)
  defp remaining_ms(%{ends_at: ends_at}), do: max(ends_at - now_ms(), 0)

  defp remaining_ms(%{started_at: started_at, seconds: seconds}),
    do: max(started_at + seconds * 1000 - now_ms(), 0)

  defp countdown(ms), do: TrainingLabels.clock(div(ms + 999, 1000))

  defp current_set_number(session, exercise) do
    if is_nil(session.completed_at) and not exercise_done?(exercise),
      do: length(exercise.set_logs) + 1
  end

  defp exercise_path(session, exercise),
    do: ~p"/app/sessions/#{session.id}/exercises/#{exercise.id}"

  # Within the session the next exercise is a patch; after the last one, the wrap-up page.
  defp next_link(session, nil), do: [navigate: ~p"/app/sessions/#{session.id}/done"]
  defp next_link(session, next), do: [patch: exercise_path(session, next)]

  defp coach_name(%{program: %{coach: %{name: name}}}), do: TrainingLabels.first_name(name)
  defp coach_name(_session), do: nil

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        prev: assigns.index > 0 && Enum.at(assigns.session.exercises, assigns.index - 1),
        next: Enum.at(assigns.session.exercises, assigns.index + 1),
        current: current_set_number(assigns.session, assigns.exercise)
      )

    ~H"""
    <div class="flex flex-1 flex-col">
      <.top_bar
        back={~p"/app/sessions/#{@session.id}"}
        context={"Esercizio #{@index + 1} di #{length(@session.exercises)} · #{TrainingLabels.header_detail(@exercise)}"}
        title={@exercise.name}
      >
        <:action>
          <.link
            navigate={~p"/app/sessions/#{@session.id}/exercises/#{@exercise.id}/info"}
            class="flex h-9 items-center gap-1.5 rounded-pill bg-neutral-50 px-3 text-[13px] font-medium"
          >
            <%= if @exercise.videos != [] do %>
              <.icon name="hero-play-circle" class="h-4 w-4 text-primary-600" />Video
            <% else %>
              <.icon name="hero-information-circle" class="h-4 w-4 text-primary-600" />Info
            <% end %>
          </.link>
        </:action>
      </.top_bar>

      <div
        :if={@rest}
        id="rest-banner"
        class="mx-4 mt-2 flex items-center justify-between rounded-xl bg-neutral-800 px-4 py-3 text-neutral-50"
      >
        <div class="flex items-center gap-2.5">
          <.icon name="hero-clock" class="h-5 w-5" />
          <span class="text-sm">Recupero</span>
          <span
            id={"rest-#{@rest.key}"}
            phx-hook="Countdown"
            phx-update="ignore"
            data-key={@rest.key}
            data-remaining={remaining_ms(@rest)}
            data-event="rest_finished"
            class="font-display text-[22px] font-semibold"
          >{countdown(remaining_ms(@rest))}</span>
        </div>
        <button
          type="button"
          phx-click="skip_rest"
          class="text-sm font-semibold underline underline-offset-2"
        >
          Salta
        </button>
      </div>

      <div class="flex flex-col gap-2 px-4 pt-5">
        <%= for number <- 1..@exercise.sets_count//1 do %>
          <%= cond do %>
            <% log = Enum.at(@exercise.set_logs, number - 1) -> %>
              <.set_row number={number} done={true} label={TrainingLabels.set_result(@exercise, log)} />
            <% number == @current -> %>
              <.current_set
                number={number}
                exercise={@exercise}
                draft={@draft}
                hold={@hold}
                previous={@previous}
                note_open?={@note_open?}
                coach={coach_name(@session)}
              />
            <% true -> %>
              <.set_row number={number} done={false} label={TrainingLabels.set_target(@exercise)} />
          <% end %>
        <% end %>
      </div>

      <div class="sticky bottom-0 mt-auto flex items-center justify-between border-t border-neutral-100 bg-surface px-4 py-3">
        <.link
          :if={@prev}
          patch={exercise_path(@session, @prev)}
          class="flex h-11 min-w-0 items-center gap-1.5 px-3 text-sm font-medium text-neutral-600"
        >
          <.icon name="hero-arrow-left" class="h-4 w-4 shrink-0" /><span class="truncate">{@prev.name}</span>
        </.link>
        <span :if={!@prev} class="flex h-11 items-center gap-1.5 px-3 text-sm text-neutral-300">
          <.icon name="hero-arrow-left" class="h-4 w-4" />Precedente
        </span>

        <.link
          id="next-step"
          {next_link(@session, @next)}
          class={[
            "flex h-11 min-w-0 items-center gap-1.5 rounded-pill px-4 text-sm font-medium",
            is_nil(@current) && "bg-primary-600 text-white",
            @current && "border border-neutral-200"
          ]}
        >
          <span class="truncate">{if @next, do: @next.name, else: "Fine giornata"}</span>
          <.icon name="hero-arrow-right" class="h-4 w-4 shrink-0" />
        </.link>
      </div>
    </div>
    """
  end

  attr :number, :integer, required: true
  attr :exercise, :map, required: true
  attr :draft, :map, required: true
  attr :hold, :map, default: nil
  attr :previous, :map, default: nil
  attr :note_open?, :boolean, required: true
  attr :coach, :string, default: nil

  defp current_set(assigns) do
    ~H"""
    <div id="current-set" class="flex flex-col gap-5 rounded-[20px] border-2 border-primary-600 p-5">
      <div class="flex items-baseline justify-between">
        <span class="text-base font-semibold">Serie {@number}</span>
        <span class="text-[13px] text-neutral-500">{TrainingLabels.set_goal(@exercise)}</span>
      </div>

      <%= case @exercise.kind do %>
        <% :reps -> %>
          <div class={["grid gap-3", @draft.load_kg && "grid-cols-2"]}>
            <.stepper label="Ripetizioni" field="reps" value={to_string(@draft.reps)} />
            <.stepper
              :if={@draft.load_kg}
              label="Carico kg"
              field="load_kg"
              value={TrainingLabels.number(@draft.load_kg)}
            />
          </div>
        <% :max -> %>
          <.stepper label="Ripetizioni fatte" field="reps" value={to_string(@draft.reps)} />
          <div
            :if={@previous}
            id="previous-performance"
            class="flex justify-between rounded-xl bg-neutral-50 px-3 py-2.5 text-sm"
          >
            <span class="text-neutral-600">Ultima volta · {TrainingLabels.short_date(
              @previous.scheduled_on
            )}</span>
            <span class="font-semibold">{Enum.map_join(@previous.set_logs, " · ", & &1.reps)} rip</span>
          </div>
        <% :time -> %>
          <div class="flex flex-col items-center gap-3 py-2">
            <%= if @hold do %>
              <span
                id={"hold-#{@hold.key}"}
                phx-hook="Countdown"
                phx-update="ignore"
                data-key={@hold.key}
                data-remaining={remaining_ms(@hold)}
                data-event="hold_finished"
                class="font-display text-[72px] font-semibold leading-[76px] tracking-[-0.02em]"
              >{countdown(remaining_ms(@hold))}</span>
              <button
                type="button"
                phx-click="stop_hold"
                class="flex h-11 items-center gap-2 rounded-pill bg-neutral-800 px-6 text-[15px] font-semibold text-neutral-50"
              >
                <.icon name="hero-stop-solid" class="h-[18px] w-[18px]" />Ferma
              </button>
            <% else %>
              <span class="font-display text-[72px] font-semibold leading-[76px] tracking-[-0.02em]">
                {TrainingLabels.clock(@exercise.target_seconds)}
              </span>
              <button
                type="button"
                phx-click="start_hold"
                class="flex h-11 items-center gap-2 rounded-pill bg-neutral-800 px-6 text-[15px] font-semibold text-neutral-50"
              >
                <.icon name="hero-play-solid" class="h-[18px] w-[18px]" />Avvia timer
              </button>
            <% end %>
          </div>
          <div class="flex items-center justify-between rounded-xl bg-neutral-50 px-3 py-2.5">
            <span class="text-sm text-neutral-600">Tempo tenuto (s)</span>
            <div class="flex items-center gap-2.5">
              <.step_button event="dec" field="seconds" label="Diminuisci tempo tenuto" />
              <span id="draft-seconds" class="min-w-8 text-center text-[22px] font-semibold">{@draft.seconds}</span>
              <.step_button event="inc" field="seconds" label="Aumenta tempo tenuto" />
            </div>
          </div>
        <% :sequence -> %>
          <div class="flex flex-col gap-1.5">
            <span class="font-display text-[32px] font-semibold leading-10 tracking-[0.01em]">
              {TrainingLabels.sequence(@exercise.sequence)}
            </span>
            <span class="text-[13px] text-neutral-600">
              {Enum.sum(@exercise.sequence)} ripetizioni totali<span :if={
                @exercise.sequence_rest_seconds
              }> · recupero {@exercise.sequence_rest_seconds} s tra gli step</span>
            </span>
          </div>
          <div class="flex flex-col gap-2">
            <span class="text-[13px] text-neutral-600">Com'è andata?</span>
            <div class="flex gap-2">
              <button
                :for={{outcome, label} <- [complete: "Completa", partial: "Parziale"]}
                type="button"
                phx-click="set_outcome"
                phx-value-outcome={outcome}
                aria-pressed={to_string(@draft.outcome == outcome)}
                class={[
                  "flex h-11 flex-1 items-center justify-center rounded-pill text-sm",
                  @draft.outcome == outcome && "bg-neutral-800 font-semibold text-neutral-50",
                  @draft.outcome != outcome && "border border-neutral-200 font-medium"
                ]}
              >
                {label}
              </button>
            </div>
          </div>
          <button
            :if={!@note_open?}
            type="button"
            phx-click="open_note"
            class="flex items-center gap-1.5 self-start text-sm font-medium text-primary-600"
          >
            <.icon name="hero-pencil-square" class="h-[18px] w-[18px]" />Aggiungi nota
          </button>
          <form :if={@note_open?} id="set-note" phx-change="update_note" phx-submit="complete_set">
            <.input
              type="textarea"
              id="set-note-input"
              name="note"
              value={@draft.note}
              rows="2"
              placeholder="Nota per il coach"
              aria-label="Nota sulla serie"
              class="block w-full rounded-xl border-2 border-neutral-200 px-4 py-3 text-[15px] focus:border-primary-500 focus:ring-0"
            />
          </form>
      <% end %>

      <.coach_note :if={@exercise.notes} class="!px-3.5 !py-3 !text-[13px] !leading-[18px]">
        {@exercise.notes}<span :if={@coach}> — {@coach}</span>
      </.coach_note>

      <.action_button
        id="complete-set"
        type="button"
        phx-click="complete_set"
        icon="hero-check"
        class="!h-[52px]"
      >
        Completa serie {@number}
      </.action_button>
    </div>
    """
  end
end
