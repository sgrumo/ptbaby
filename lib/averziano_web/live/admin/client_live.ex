defmodule AverzianoWeb.Admin.ClientLive do
  @moduledoc """
  A client in the console ("Revisione giornata"): the weeks of their program
  with each day's status, and the selected day (`?session=`) with the logged
  sets against the targets. From here the coach changes the target of the
  next or all future replicas of an exercise and reviews the day, optionally
  with a comment. The `:edit` action opens the "Modifica cliente" dialog.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.AdminComponents
  import AverzianoWeb.ClientComponents, only: [badge: 1]

  alias AshPhoenix.Form
  alias Averziano.{Accounts, Errors, Training}
  alias Averziano.Accounts.User
  alias AverzianoWeb.Admin.PlanParams
  alias AverzianoWeb.TrainingLabels

  @impl true
  def mount(%{"client_id" => client_id}, _session, socket) do
    %{actor: actor, current_user: coach} = socket.assigns

    case Accounts.get_user(client_id, actor: actor) do
      {:ok, %User{coach_id: coach_id} = client} when coach_id == coach.id ->
        {:ok,
         socket
         |> assign(
           nav: :clients,
           client: client,
           today: Date.utc_today(),
           notes_count: client.id |> Training.list_client_notes!(actor: actor) |> length()
         )
         |> load_program()}

      _ ->
        {:ok, socket |> put_flash(:error, "Cliente non trovato") |> push_navigate(to: ~p"/admin")}
    end
  end

  defp load_program(%{assigns: %{actor: actor, client: client}} = socket) do
    {:ok, program} =
      Training.latest_client_program(client.id,
        actor: actor,
        load: [:sessions_count, :completed_sessions_count, sessions: [:sets_total, :sets_logged]]
      )

    {:ok, programs} = Training.list_coached_programs(actor: actor)
    client_programs = Enum.filter(programs, &(&1.client_id == client.id))

    assign(socket,
      program: program,
      client_programs: client_programs,
      drafts: Enum.filter(client_programs, &is_nil(&1.published_at))
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "note", do: :notes, else: :training

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> select_session(params)
     |> assign_edit(socket.assigns.live_action)}
  end

  defp assign_edit(%{assigns: %{client: client, actor: actor}} = socket, :edit) do
    form = client |> Form.for_update(:update_client, actor: actor) |> to_form()
    assign(socket, edit_form: form, page_title: "Modifica cliente")
  end

  defp assign_edit(socket, _action),
    do: assign(socket, edit_form: nil, page_title: socket.assigns.client.name)

  defp select_session(%{assigns: %{program: %{} = program}} = socket, params) do
    session =
      Enum.find(program.sessions, &(&1.id == params["session"])) ||
        default_session(program.sessions, socket.assigns.today)

    socket |> assign(editing: nil, comment: "") |> load_session(session.id)
  end

  defp select_session(socket, _params), do: assign(socket, session: nil)

  @impl true
  def handle_info({:notes_count, count}, socket),
    do: {:noreply, assign(socket, :notes_count, count)}

  # The oldest day to review, else the last completed one, else the next to train.
  defp default_session(sessions, today) do
    Enum.find(sessions, &(&1.completed_at && is_nil(&1.reviewed_at))) ||
      sessions |> Enum.filter(& &1.completed_at) |> List.last() ||
      Enum.find(sessions, &(Date.compare(&1.scheduled_on, today) != :lt)) ||
      List.last(sessions)
  end

  defp load_session(socket, id) do
    {:ok, session} =
      Training.get_session(id,
        actor: socket.assigns.actor,
        load: [:sets_total, :sets_logged, exercises: [:set_logs]]
      )

    assign(socket, :session, session)
  end

  @impl true
  def handle_event("validate_client", %{"form" => params}, socket) do
    {:noreply, update(socket, :edit_form, &Form.validate(&1, params))}
  end

  def handle_event("save_client", %{"form" => params}, socket) do
    case Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, client} ->
        {:noreply,
         socket
         |> assign(:client, client)
         |> put_flash(:info, "Dati di #{client.name} aggiornati")
         |> push_patch(to: ~p"/admin/clients/#{client.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :edit_form, form)}
    end
  end

  def handle_event("edit_target", %{"id" => id}, socket) do
    exercise = Enum.find(socket.assigns.session.exercises, &(&1.id == id))

    {:noreply,
     assign(socket, :editing, %{
       exercise: exercise,
       params: target_params(exercise),
       scope: "future"
     })}
  end

  def handle_event("cancel_target", _params, socket),
    do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("change_target", %{"target" => params, "scope" => scope}, socket) do
    {:noreply, update(socket, :editing, &%{&1 | params: params, scope: scope})}
  end

  def handle_event("apply_target", %{"target" => params, "scope" => scope}, socket) do
    %{editing: %{exercise: exercise}, actor: actor} = socket.assigns
    scope = if scope == "next", do: :next, else: :future

    case Training.retarget_exercise(exercise.id, scope, PlanParams.target(exercise.kind, params),
           actor: actor
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> put_flash(
           :info,
           "Obiettivo di #{exercise.name} aggiornato su #{days(length(updated))}"
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("update_comment", %{"comment" => comment}, socket),
    do: {:noreply, assign(socket, :comment, comment)}

  def handle_event("review", %{"comment" => comment, "intent" => intent}, socket) do
    comment = String.trim(comment)

    if intent == "comment" and comment == "" do
      {:noreply, put_flash(socket, :error, "Scrivi un commento prima di inviarlo")}
    else
      params = if intent == "comment", do: %{coach_comment: comment}, else: %{}

      case Training.review_session(socket.assigns.session, params, actor: socket.assigns.actor) do
        {:ok, session} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             if(intent == "comment", do: "Commento inviato", else: "Giornata revisionata")
           )
           |> load_program()
           |> load_session(session.id)}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, error_message(error))}
      end
    end
  end

  defp error_message(error) do
    case Errors.normalize({:error, error}) do
      {:error, :unprocessable_entity, errors} ->
        errors |> Map.values() |> List.flatten() |> Enum.join(", ")

      {:error, :forbidden} ->
        "Operazione non consentita"

      _ ->
        "Si è verificato un errore"
    end
  end

  defp days(1), do: "1 giornata"
  defp days(count), do: "#{count} giornate"

  defp target_params(exercise) do
    %{
      "sets_count" => to_string(exercise.sets_count),
      "target_reps" => to_string(exercise.target_reps || ""),
      "target_load_kg" =>
        if(exercise.target_load_kg, do: TrainingLabels.number(exercise.target_load_kg), else: ""),
      "target_seconds" => to_string(exercise.target_seconds || ""),
      "sequence" =>
        if(exercise.sequence, do: TrainingLabels.sequence(exercise.sequence), else: "")
    }
  end

  # Open sessions of the same day of the plan after the selected one.
  defp replicas(program, session) do
    Enum.filter(
      program.sessions,
      &(&1.day_label == session.day_label and Date.after?(&1.scheduled_on, session.scheduled_on) and
          is_nil(&1.completed_at))
    )
  end

  # e.g. "S3 mer 7 ott"
  defp replica_label(%{week_number: week, scheduled_on: date}) do
    weekday = date |> Date.day_of_week() |> TrainingLabels.weekday_short() |> String.downcase()
    "S#{week} #{weekday} #{TrainingLabels.short_date(date)}"
  end

  defp weeks(program) do
    program.sessions
    |> Enum.group_by(& &1.week_number)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp columns(program) do
    program.sessions
    |> Enum.frequencies_by(& &1.week_number)
    |> Map.values()
    |> Enum.max(fn -> 1 end)
  end

  defp day_status(session, today) do
    cond do
      session.reviewed_at -> {:success, "Revisionato"}
      session.completed_at -> {:warning, "Da revisionare"}
      session.scheduled_on == today -> {:brand, "Oggi"}
      Date.before?(session.scheduled_on, today) -> {:danger, "Saltato"}
      true -> {:muted, "In arrivo"}
    end
  end

  # How a logged set compares with the target: :met, :short or :missing.
  defp set_outcome(_exercise, nil), do: :missing

  defp set_outcome(%{kind: :reps, target_reps: target}, log),
    do: if(log.reps >= target, do: :met, else: :short)

  defp set_outcome(%{kind: :time, target_seconds: target}, log),
    do: if(log.seconds >= target, do: :met, else: :short)

  defp set_outcome(%{kind: :sequence}, log),
    do: if(log.outcome == :complete, do: :met, else: :short)

  defp set_outcome(%{kind: :max}, _log), do: :met

  defp set_value(%{kind: :reps} = exercise, log),
    do:
      "#{log.reps}/#{exercise.target_reps}#{if log.load_kg, do: " · #{TrainingLabels.load(log.load_kg)}"}"

  defp set_value(%{kind: :max}, log), do: "#{log.reps} rip"
  defp set_value(%{kind: :time}, log), do: "#{log.seconds} s"

  defp set_value(%{kind: :sequence}, log),
    do: if(log.outcome == :complete, do: "completa", else: "parziale")

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header>
      <:heading>
        <div class="flex items-center gap-4">
          <.avatar name={@client.name} class="h-12 w-12 text-base" />
          <div class="flex min-w-0 flex-col gap-0.5">
            <span class="text-[13px] text-neutral-500">
              <.link navigate={~p"/admin"} class="hover:text-neutral-800">Clienti</.link>
              / {@client.name}
            </span>
            <span class="text-[22px] font-semibold leading-7">{@client.name}</span>
            <span id="client-contacts" class="truncate text-[13px] text-neutral-500">
              {@client.email}{if @client.phone, do: " · #{@client.phone}"}
            </span>
          </div>
        </div>
      </:heading>
      <:actions>
        <dl :if={@program} class="flex gap-6 pr-2 text-[13px]">
          <div class="flex flex-col">
            <dt class="text-neutral-500">Programma</dt><dd class="font-semibold">{@program.name}</dd>
          </div>
          <div class="flex flex-col">
            <dt class="text-neutral-500">Scadenza</dt>
            <dd class="font-semibold">{TrainingLabels.short_date_year(@program.ends_on)}</dd>
          </div>
          <div class="flex flex-col">
            <dt class="text-neutral-500">Avanzamento</dt>
            <dd id="program-progress" class="font-semibold">
              {@program.completed_sessions_count} / {@program.sessions_count} giorni
            </dd>
          </div>
        </dl>
        <.button variant={:outline} patch={~p"/admin/clients/#{@client.id}/edit"} icon="hero-pencil">
          Modifica
        </.button>
        <.button
          variant={:outline}
          navigate={~p"/admin/templates?#{[client: @client.id]}"}
          icon="hero-plus"
        >
          Nuovo programma
        </.button>
      </:actions>
    </.page_header>

    <nav class="flex gap-2 border-b border-neutral-100 px-8" aria-label="Sezioni cliente">
      <.link
        :for={
          {tab, label, query} <- [{:training, "Allenamento", []}, {:notes, "Note", [tab: "note"]}]
        }
        id={"tab-#{tab}"}
        patch={~p"/admin/clients/#{@client.id}?#{query}"}
        aria-current={@tab == tab && "page"}
        class={[
          "-mb-px flex items-center gap-1.5 px-4 py-2.5 text-sm",
          @tab == tab && "border-b-2 border-primary-600 font-semibold",
          @tab != tab && "font-medium text-neutral-600"
        ]}
      >
        {label}
        <span
          :if={tab == :notes and @notes_count > 0}
          class="rounded-pill bg-neutral-100 px-1.5 text-xs font-semibold text-neutral-600"
        >
          {@notes_count}
        </span>
      </.link>
    </nav>

    <.live_component
      :if={@tab == :notes}
      module={AverzianoWeb.Admin.ClientNotesComponent}
      id="client-notes"
      client={@client}
      programs={@client_programs}
      actor={@actor}
      today={@today}
    />

    <div
      :if={@tab == :training and !@program}
      id="no-program"
      class="flex flex-col items-start gap-3 p-8"
    >
      <p class="text-base font-semibold">
        {TrainingLabels.first_name(@client.name)} non ha ancora un programma pubblicato.
      </p>
      <p :if={@client.invited_at} class="text-sm text-neutral-600">
        Invitato il {TrainingLabels.short_date_year(DateTime.to_date(@client.invited_at))}.
      </p>
      <div :for={draft <- @drafts} class="flex items-center gap-3 text-sm">
        <span>Bozza: <b>{draft.name}</b></span>
        <.button size={:sm} variant={:outline} navigate={~p"/admin/programs/#{draft.id}/edit"}>Continua</.button>
      </div>
      <.button navigate={~p"/admin/templates?#{[client: @client.id]}"} icon="hero-square-3-stack-3d">
        Crea da template
      </.button>
    </div>

    <div
      :if={@tab == :training and @program}
      class="grid min-h-0 flex-1 grid-cols-[400px_minmax(0,1fr)]"
    >
      <nav
        class="flex flex-col gap-5 border-r border-neutral-100 py-6 pl-8 pr-6"
        aria-label="Settimane"
      >
        <h2 class="text-base font-semibold">Settimane</h2>
        <div :for={{week, sessions} <- weeks(@program)} class="flex flex-col gap-2">
          <span class="text-xs font-semibold text-neutral-600">
            Settimana {week} · {TrainingLabels.week_range(
              Date.beginning_of_week(hd(sessions).scheduled_on)
            )}
          </span>
          <div
            class="grid gap-2"
            style={"grid-template-columns: repeat(#{columns(@program)}, minmax(0, 1fr))"}
          >
            <.link
              :for={session <- sessions}
              id={"day-#{session.id}"}
              patch={~p"/admin/clients/#{@client.id}?#{[session: session.id]}"}
              aria-current={@session && session.id == @session.id && "page"}
              class={[
                "flex flex-col gap-1.5 rounded-[10px] border p-2.5 hover:bg-neutral-50",
                @session && session.id == @session.id &&
                  "border-2 border-primary-600 bg-neutral-50 !p-[9px]",
                !(@session && session.id == @session.id) && "border-neutral-200"
              ]}
            >
              <span class="text-[13px] font-semibold">Giorno {session.day_label}</span>
              <span class="text-xs text-neutral-500">{TrainingLabels.day_date(session.scheduled_on)}</span>
              <.badge
                tone={elem(day_status(session, @today), 0)}
                class="self-start !px-2 !py-0.5 !text-[11px]"
              >
                {elem(day_status(session, @today), 1)}
              </.badge>
            </.link>
          </div>
        </div>
      </nav>

      <section :if={@session} id="selected-session" class="flex min-w-0 flex-col gap-5 px-8 py-6">
        <div class="flex items-start justify-between gap-4">
          <div class="flex flex-col gap-1">
            <span class="text-[13px] text-neutral-500">
              Settimana {@session.week_number} · Giorno {@session.day_label} · {TrainingLabels.long_date(
                @session.scheduled_on
              )}
            </span>
            <h2 class="font-display text-[28px] font-semibold leading-9">{@session.title}</h2>
          </div>
          <.badge
            :if={@session.completed_at}
            tone={:success}
            class="gap-1.5 !px-3 !py-1.5 !text-[13px]"
          >
            <.icon name="hero-check-mini" class="h-4 w-4" />
            Completato {TrainingLabels.moment(@session.completed_at, @today)} · {@session.sets_logged}/{@session.sets_total} serie
          </.badge>
          <.badge :if={!@session.completed_at} tone={:muted} class="!px-3 !py-1.5 !text-[13px]">
            {@session.sets_logged}/{@session.sets_total} serie registrate
          </.badge>
        </div>

        <div :if={@session.client_note} class="flex gap-3 rounded-xl bg-neutral-50 px-5 py-4">
          <.icon name="hero-chat-bubble-bottom-center-text" class="h-5 w-5 shrink-0 text-primary-600" />
          <div class="flex flex-col gap-1">
            <span class="text-[13px] font-semibold">Nota di {TrainingLabels.first_name(@client.name)}</span>
            <span class="text-[15px] leading-[22px]">{@session.client_note}</span>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.exercise_card
            :for={exercise <- @session.exercises}
            exercise={exercise}
            editing={@editing}
            replicas={replicas(@program, @session)}
          />
        </div>

        <div :if={@session.completed_at && is_nil(@session.reviewed_at)} class="flex flex-col gap-2">
          <form
            id="review-form"
            phx-submit="review"
            phx-change="update_comment"
            class="flex flex-col gap-2"
          >
            <label for="review-comment" class="text-sm font-semibold">Commento per la giornata</label>
            <.input
              type="textarea"
              id="review-comment"
              name="comment"
              value={@comment}
              rows="3"
              placeholder={"Un riscontro per #{TrainingLabels.first_name(@client.name)}…"}
              class="block min-h-[88px] w-full rounded-xl border border-neutral-200 px-3.5 py-3 text-[15px] leading-[22px] focus:border-primary-500 focus:ring-0"
            />
            <div class="flex justify-end gap-2">
              <.button type="submit" name="intent" value="mark" variant={:outline}>Segna come revisionata</.button>
              <.button type="submit" name="intent" value="comment" icon="hero-paper-airplane">Invia commento</.button>
            </div>
          </form>
        </div>

        <div :if={@session.reviewed_at} id="review-done" class="flex flex-col gap-2">
          <span class="text-sm font-semibold">Commento per la giornata</span>
          <p class="rounded-xl bg-neutral-50 px-3.5 py-3 text-[15px] leading-[22px]">
            {@session.coach_comment || "Nessun commento."}
          </p>
          <span class="text-xs text-neutral-500">
            Revisionata {TrainingLabels.moment(@session.reviewed_at, @today) |> String.downcase()}
          </span>
        </div>
      </section>
    </div>

    <.modal
      :if={@edit_form}
      id="edit-client-modal"
      title="Modifica cliente"
      subtitle="Con la nuova email il cliente riceverà lì i link di accesso."
      on_cancel={JS.patch(~p"/admin/clients/#{@client.id}")}
    >
      <.form
        for={@edit_form}
        id="edit-client-form"
        phx-change="validate_client"
        phx-submit="save_client"
      >
        <div class="flex flex-col gap-4 p-6">
          <.field label="Nome e cognome" for="edit-client-name">
            <.input field={@edit_form[:name]} id="edit-client-name" class={input_class()} />
          </.field>
          <.field label="Email" for="edit-client-email">
            <.input
              field={@edit_form[:email]}
              id="edit-client-email"
              type="email"
              class={input_class()}
            />
          </.field>
          <.field label="Telefono · opzionale" for="edit-client-phone">
            <.input
              field={@edit_form[:phone]}
              id="edit-client-phone"
              type="tel"
              placeholder="+39"
              class={input_class()}
            />
          </.field>
        </div>
        <div class="flex justify-end gap-2 border-t border-neutral-100 px-6 py-4">
          <.button variant={:outline} patch={~p"/admin/clients/#{@client.id}"}>Annulla</.button>
          <.button type="submit" phx-disable-with="Salvataggio…">Salva</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :exercise, :map, required: true
  attr :editing, :map, default: nil
  attr :replicas, :list, required: true

  defp exercise_card(assigns) do
    assigns =
      assign(assigns,
        editing?: assigns.editing && assigns.editing.exercise.id == assigns.exercise.id,
        wide?: assigns.exercise.kind in [:reps, :max]
      )

    ~H"""
    <div
      id={"review-#{@exercise.id}"}
      class={[
        "flex flex-col rounded-xl border border-neutral-200",
        (@wide? or @editing?) && "col-span-2"
      ]}
    >
      <div class="flex flex-col gap-3.5 px-5 py-4">
        <div class="flex items-center gap-3">
          <div class="flex flex-1 flex-col">
            <span class="text-[15px] font-semibold">{@exercise.name}</span>
            <span class="text-[13px] text-neutral-600">
              {TrainingLabels.kind_long(@exercise)} · {TrainingLabels.prescription(@exercise)}
            </span>
          </div>
          <span :if={@editing?} class="text-[13px] text-neutral-500">In modifica</span>
          <.button
            :if={!@editing? and @replicas != []}
            size={:sm}
            variant={:outline}
            icon="hero-pencil-square"
            phx-click="edit_target"
            phx-value-id={@exercise.id}
          >
            Modifica obiettivo
          </.button>
        </div>
        <div class="flex flex-wrap gap-2">
          <div
            :for={number <- 1..@exercise.sets_count//1}
            class={[
              "flex flex-col rounded-lg px-3 py-2 text-xs",
              set_outcome(@exercise, Enum.at(@exercise.set_logs, number - 1)) == :met &&
                "bg-success-100 text-success-800",
              set_outcome(@exercise, Enum.at(@exercise.set_logs, number - 1)) == :short &&
                "bg-warning-100 text-warning-800",
              set_outcome(@exercise, Enum.at(@exercise.set_logs, number - 1)) == :missing &&
                "bg-neutral-50 text-neutral-500"
            ]}
          >
            <span>S{number}</span>
            <span class="text-sm font-semibold">
              <%= if log = Enum.at(@exercise.set_logs, number - 1) do %>
                {set_value(@exercise, log)}
              <% else %>
                —
              <% end %>
            </span>
          </div>
        </div>
      </div>

      <form
        :if={@editing?}
        id="target-form"
        phx-change="change_target"
        phx-submit="apply_target"
        class="flex flex-col gap-3.5 rounded-b-xl border-t border-neutral-100 bg-neutral-50 px-5 py-4"
      >
        <span class="text-[13px] font-semibold">Nuovo obiettivo</span>
        <div class="flex flex-wrap items-end gap-3">
          <.field label="Serie" for="target-sets" class="w-[88px]">
            <input
              id="target-sets"
              name="target[sets_count]"
              type="number"
              min="1"
              value={@editing.params["sets_count"]}
              class={input_class()}
            />
          </.field>
          <.field :if={@exercise.kind == :reps} label="Ripetizioni" for="target-reps" class="w-[88px]">
            <input
              id="target-reps"
              name="target[target_reps]"
              type="number"
              min="1"
              value={@editing.params["target_reps"]}
              class={input_class()}
            />
          </.field>
          <.field
            :if={@exercise.kind in [:reps, :max]}
            label="Carico kg"
            for="target-load"
            class="w-[88px]"
          >
            <input
              id="target-load"
              name="target[target_load_kg]"
              inputmode="decimal"
              value={@editing.params["target_load_kg"]}
              placeholder="—"
              class={input_class()}
            />
          </.field>
          <.field :if={@exercise.kind == :time} label="Secondi" for="target-seconds" class="w-[88px]">
            <input
              id="target-seconds"
              name="target[target_seconds]"
              type="number"
              min="1"
              value={@editing.params["target_seconds"]}
              class={input_class()}
            />
          </.field>
          <.field
            :if={@exercise.kind == :sequence}
            label="Sequenza ripetizioni"
            for="target-sequence"
            class="w-[260px]"
          >
            <input
              id="target-sequence"
              name="target[sequence]"
              value={@editing.params["sequence"]}
              class={input_class()}
            />
          </.field>
        </div>
        <fieldset class="flex flex-col gap-2 text-sm">
          <legend class="sr-only">Applica a</legend>
          <label class="flex items-center gap-2.5">
            <input
              type="radio"
              name="scope"
              value="future"
              checked={@editing.scope == "future"}
              class="text-primary-600 focus:ring-primary-500"
            />
            <span>
              <b>Repliche future del Giorno {hd(@replicas).day_label}</b>
              · {Enum.map_join(@replicas, ", ", &replica_label/1)}
            </span>
          </label>
          <label class="flex items-center gap-2.5 text-neutral-600">
            <input
              type="radio"
              name="scope"
              value="next"
              checked={@editing.scope == "next"}
              class="text-primary-600 focus:ring-primary-500"
            />
            <span>Solo la prossima replica · {replica_label(hd(@replicas))}</span>
          </label>
        </fieldset>
        <div class="flex justify-end gap-2">
          <.button type="button" variant={:ghost} size={:sm} phx-click="cancel_target">Annulla</.button>
          <.button type="submit" size={:sm}>
            Applica a {days(if @editing.scope == "next", do: 1, else: length(@replicas))}
          </.button>
        </div>
      </form>
    </div>
    """
  end
end
