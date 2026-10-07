defmodule AverzianoWeb.Admin.PlanEditorLive do
  @moduledoc """
  The plan editor ("Costruzione programma"): name, dates and weeks, the
  training days with the weekdays they repeat on, and each day's exercises.
  It edits a draft program (`:program`, which it can also publish or save as
  a template) or a template (`:template`). The plan lives in the socket until
  it is saved; see `AverzianoWeb.Admin.PlanParams`.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.AdminComponents

  alias Averziano.{Accounts, Errors, Training}
  alias Averziano.Training.Changes.GenerateSessions
  alias AverzianoWeb.Admin.PlanParams
  alias AverzianoWeb.TrainingLabels

  @kinds [reps: "Serie × Rip", time: "Serie × Tempo", sequence: "Sequenza", max: "Serie × Max"]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load(socket.assigns.live_action, id, socket.assigns) do
      {:ok, socket_assigns} ->
        first_exercise =
          socket_assigns.plan.days
          |> List.first(%{exercises: []})
          |> Map.get(:exercises)
          |> List.first()

        {:ok,
         socket
         |> assign(socket_assigns)
         |> assign(
           day_index: 0,
           open: MapSet.new(List.wrap(first_exercise && first_exercise.id)),
           adding_video: nil
         )}

      {:redirect, to, message} ->
        {:ok, socket |> put_flash(:error, message) |> push_navigate(to: to)}
    end
  end

  defp load(:program, id, %{actor: actor, current_user: coach}) do
    case Training.get_program(id, actor: actor, load: [:client, :template]) do
      {:ok, %{coach_id: coach_id, published_at: nil} = program} when coach_id == coach.id ->
        {:ok, clients} = Accounts.list_clients(actor: actor)

        {:ok,
         %{
           nav: :programs,
           page_title: program.name,
           record: program,
           clients: clients,
           equipment: client_equipment(program.client_id, actor),
           plan: %{
             name: program.name,
             client_id: program.client_id,
             starts_on: Date.to_iso8601(program.starts_on),
             ends_on: Date.to_iso8601(program.ends_on),
             weeks_count: program.weeks_count,
             days: PlanParams.from_days(program.days)
           }
         }}

      {:ok, %{published_at: %DateTime{}} = program} ->
        {:redirect, ~p"/admin/clients/#{program.client_id}", "Il programma è già pubblicato"}

      _ ->
        {:redirect, ~p"/admin/programs", "Programma non trovato"}
    end
  end

  defp load(:template, id, %{actor: actor}) do
    case Training.get_template(id, actor: actor) do
      {:ok, template} ->
        {:ok,
         %{
           nav: :templates,
           page_title: template.name,
           record: template,
           plan: %{
             name: template.name,
             weeks_count: template.weeks_count,
             days: PlanParams.from_days(template.days)
           }
         }}

      _ ->
        {:redirect, ~p"/admin/templates", "Template non trovato"}
    end
  end

  defp client_equipment(client_id, actor) do
    {:ok, equipment} = Training.list_client_equipment(client_id, actor: actor)
    equipment
  end

  # The equipment shown follows the client picked in the plan.
  defp maybe_switch_client(%{assigns: %{plan: %{client_id: client_id}}} = socket, new_id)
       when is_binary(new_id) and new_id != client_id,
       do: assign(socket, :equipment, client_equipment(new_id, socket.assigns.actor))

  defp maybe_switch_client(socket, _client_id), do: socket

  ## Plan meta

  @impl true
  def handle_event("meta", %{"plan" => params}, socket) do
    {:noreply,
     socket
     |> maybe_switch_client(params["client_id"])
     |> update(:plan, fn plan ->
       moved? = Map.has_key?(plan, :starts_on) and params["starts_on"] != plan.starts_on

       plan
       |> Map.merge(
         params
         |> Map.take(~w(name client_id starts_on ends_on))
         |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
       )
       |> then(&if(moved?, do: recompute_end(&1), else: &1))
     end)}
  end

  def handle_event("weeks", %{"delta" => delta}, socket) do
    delta = if delta == "1", do: 1, else: -1

    {:noreply,
     update(socket, :plan, fn plan ->
       recompute_end(%{plan | weeks_count: min(max(plan.weeks_count + delta, 1), 52)})
     end)}
  end

  ## Days

  def handle_event("select_day", %{"index" => index}, socket),
    do: {:noreply, assign(socket, :day_index, String.to_integer(index))}

  def handle_event("add_day", _params, socket) do
    socket = update_days(socket, &(&1 ++ [PlanParams.new_day("Nuovo giorno")]))
    {:noreply, assign(socket, :day_index, length(socket.assigns.plan.days) - 1)}
  end

  def handle_event("duplicate_day", _params, %{assigns: %{day_index: index}} = socket) do
    socket =
      update_days(
        socket,
        &List.insert_at(&1, index + 1, PlanParams.duplicate_day(Enum.at(&1, index)))
      )

    {:noreply, assign(socket, :day_index, index + 1)}
  end

  def handle_event("delete_day", _params, %{assigns: %{day_index: index}} = socket) do
    socket = update_days(socket, &if(length(&1) > 1, do: List.delete_at(&1, index), else: &1))
    {:noreply, assign(socket, :day_index, max(index - 1, 0))}
  end

  def handle_event("day_title", %{"day" => %{"title" => title}}, socket),
    do: {:noreply, update_day(socket, &%{&1 | title: title})}

  def handle_event("toggle_weekday", %{"weekday" => weekday}, socket) do
    weekday = String.to_integer(weekday)

    if weekday in taken_weekdays(socket.assigns.plan.days, socket.assigns.day_index) do
      {:noreply, socket}
    else
      {:noreply,
       update_day(socket, fn day ->
         weekdays =
           if weekday in day.weekdays,
             do: List.delete(day.weekdays, weekday),
             else: Enum.sort([weekday | day.weekdays])

         %{day | weekdays: weekdays}
       end)}
    end
  end

  ## Exercises

  def handle_event("toggle_exercise", %{"id" => id}, socket) do
    id = String.to_integer(id)
    open = socket.assigns.open

    {:noreply,
     assign(
       socket,
       :open,
       if(id in open, do: MapSet.delete(open, id), else: MapSet.put(open, id))
     )}
  end

  def handle_event("add_exercise", _params, socket) do
    exercise = PlanParams.new_exercise()

    {:noreply,
     socket
     |> update_day(&%{&1 | exercises: &1.exercises ++ [exercise]})
     |> update(:open, &MapSet.put(&1, exercise.id))}
  end

  def handle_event("delete_exercise", %{"id" => id}, socket) do
    id = String.to_integer(id)

    {:noreply,
     update_day(
       socket,
       &%{&1 | exercises: Enum.reject(&1.exercises, fn exercise -> exercise.id == id end)}
     )}
  end

  def handle_event("move_exercise", %{"id" => id, "dir" => dir}, socket) do
    id = String.to_integer(id)

    {:noreply,
     update_day(socket, fn day ->
       index = Enum.find_index(day.exercises, &(&1.id == id))
       target = if dir == "up", do: index - 1, else: index + 1

       if target in 0..(length(day.exercises) - 1)//1 do
         {exercise, rest} = List.pop_at(day.exercises, index)
         %{day | exercises: List.insert_at(rest, target, exercise)}
       else
         day
       end
     end)}
  end

  def handle_event("exercise_change", %{"ref" => id, "exercise" => params}, socket),
    do: {:noreply, update_exercise(socket, id, &PlanParams.update_exercise(&1, params))}

  def handle_event("set_kind", %{"id" => id, "kind" => kind}, socket) do
    kind =
      Enum.find_value(@kinds, fn {value, _label} ->
        if Atom.to_string(value) == kind, do: value
      end)

    {:noreply, update_exercise(socket, id, &%{&1 | kind: kind})}
  end

  def handle_event("sequence_preset", %{"id" => id, "sequence" => sequence}, socket),
    do: {:noreply, update_exercise(socket, id, &%{&1 | sequence: sequence})}

  def handle_event("add_video", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :adding_video, String.to_integer(id))}

  def handle_event(
        "save_video",
        %{"ref" => id, "video" => %{"title" => title, "url" => url}},
        socket
      ) do
    title = if String.trim(title) == "", do: "Video", else: String.trim(title)

    if String.trim(url) == "" do
      {:noreply, assign(socket, :adding_video, nil)}
    else
      {:noreply,
       socket
       |> update_exercise(
         id,
         &%{&1 | videos: &1.videos ++ [%{title: title, url: String.trim(url)}]}
       )
       |> assign(:adding_video, nil)}
    end
  end

  def handle_event("remove_video", %{"id" => id, "index" => index}, socket),
    do:
      {:noreply,
       update_exercise(
         socket,
         id,
         &%{&1 | videos: List.delete_at(&1.videos, String.to_integer(index))}
       )}

  ## Saving

  def handle_event("save", _params, socket) do
    case save(socket) do
      {:ok, socket} ->
        {:noreply, put_flash(socket, :info, saved_message(socket.assigns.live_action))}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("publish", _params, socket) do
    with {:ok, socket} <- save(socket),
         {:ok, program} <- publish(socket) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "#{program.name} pubblicato a #{TrainingLabels.first_name(client_name(socket.assigns))}"
       )
       |> push_navigate(to: ~p"/admin/clients/#{program.client_id}")}
    else
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("save_as_template", _params, %{assigns: %{plan: plan, actor: actor}} = socket) do
    case Training.create_template(
           %{name: plan.name, weeks_count: plan.weeks_count, days: PlanParams.to_days(plan.days)},
           actor: actor
         ) do
      {:ok, template} -> {:noreply, put_flash(socket, :info, "Template #{template.name} salvato")}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp save(%{assigns: %{live_action: action, record: record, plan: plan, actor: actor}} = socket) do
    result =
      case action do
        :program ->
          Training.update_program_plan(record, attrs(action, plan),
            actor: actor,
            load: [:client, :template]
          )

        :template ->
          Training.update_template(record, attrs(action, plan), actor: actor)
      end

    case result do
      {:ok, record} -> {:ok, assign(socket, record: record, page_title: record.name)}
      {:error, error} -> {:error, put_flash(socket, :error, error_message(error))}
    end
  end

  defp publish(%{assigns: %{record: program, actor: actor}} = socket) do
    case Training.publish_program(program, actor: actor) do
      {:ok, program} -> {:ok, program}
      {:error, error} -> {:error, put_flash(socket, :error, error_message(error))}
    end
  end

  defp attrs(:program, plan) do
    plan
    |> Map.take([:name, :client_id, :starts_on, :ends_on, :weeks_count])
    |> Map.put(:days, PlanParams.to_days(plan.days))
  end

  defp attrs(:template, plan),
    do: %{name: plan.name, weeks_count: plan.weeks_count, days: PlanParams.to_days(plan.days)}

  defp saved_message(:program), do: "Bozza salvata"
  defp saved_message(:template), do: "Template salvato"

  defp error_message(error) do
    case Errors.normalize({:error, error}) do
      {:error, :unprocessable_entity, errors} ->
        "Controlla il programma: " <>
          Enum.map_join(errors, "; ", fn {field, messages} ->
            "#{field_label(field)} #{Enum.join(messages, ", ")}"
          end)

      {:error, :forbidden} ->
        "Operazione non consentita"

      _ ->
        "Si è verificato un errore"
    end
  end

  @field_labels %{
    name: "nome",
    client_id: "cliente",
    starts_on: "inizio",
    ends_on: "scadenza",
    weeks_count: "settimane",
    days: "giorni",
    title: "nome del giorno",
    sets_count: "serie",
    target_reps: "ripetizioni",
    target_seconds: "secondi",
    target_load_kg: "carico",
    sequence: "sequenza",
    rest_seconds: "recupero"
  }

  defp field_label(field), do: Map.get(@field_labels, field, to_string(field))

  ## Helpers

  defp recompute_end(%{starts_on: starts_on, weeks_count: weeks} = plan) do
    case Date.from_iso8601(starts_on) do
      {:ok, date} -> %{plan | ends_on: date |> Date.add(weeks * 7 - 1) |> Date.to_iso8601()}
      _ -> plan
    end
  end

  defp recompute_end(plan), do: plan

  defp update_days(socket, fun), do: update(socket, :plan, &%{&1 | days: fun.(&1.days)})

  defp update_day(%{assigns: %{day_index: index}} = socket, fun),
    do: update_days(socket, &List.update_at(&1, index, fun))

  defp update_exercise(socket, id, fun) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    update_day(
      socket,
      &%{
        &1
        | exercises:
            Enum.map(&1.exercises, fn exercise ->
              if exercise.id == id, do: fun.(exercise), else: exercise
            end)
      }
    )
  end

  defp taken_weekdays(days, index) do
    days |> List.delete_at(index) |> Enum.flat_map(& &1.weekdays)
  end

  defp taken_note(days, index) do
    days
    |> Enum.with_index()
    |> Enum.reject(fn {day, other} -> other == index or day.weekdays == [] end)
    |> Enum.map_join("; ", fn {day, other} ->
      "#{Enum.map_join(day.weekdays, " e ", &TrainingLabels.weekday_short/1)} occupati dal Giorno #{GenerateSessions.day_label(other)}"
    end)
  end

  defp client_name(%{clients: clients, plan: plan}) do
    Enum.find_value(clients, "", &(&1.id == plan.client_id && &1.name))
  end

  defp per_week(days), do: days |> Enum.map(&length(&1.weekdays)) |> Enum.sum()

  defp schedule(%{starts_on: starts_on, ends_on: ends_on} = plan) do
    with {:ok, starts_on} <- Date.from_iso8601(starts_on),
         {:ok, ends_on} <- Date.from_iso8601(ends_on) do
      GenerateSessions.schedule(%{
        days: plan.days,
        weeks_count: plan.weeks_count,
        starts_on: starts_on,
        ends_on: ends_on
      })
    else
      _ -> []
    end
  end

  defp sessions_count(%{starts_on: _} = plan), do: length(schedule(plan))
  defp sessions_count(plan), do: plan.weeks_count * per_week(plan.days)

  defp session_date(date),
    do:
      "#{TrainingLabels.weekday_short(Date.day_of_week(date))} #{TrainingLabels.short_date(date)}"

  defp exercise_summary(exercise) do
    detail =
      case exercise.kind do
        :reps ->
          "#{exercise.sets_count} × #{exercise.target_reps}#{if exercise.load?, do: " · #{exercise.target_load_kg} kg"}"

        :max ->
          "#{exercise.sets_count} serie"

        :time ->
          "#{exercise.sets_count} × #{exercise.target_seconds} s"

        :sequence ->
          exercise.sequence
      end

    videos =
      case length(exercise.videos) do
        0 -> nil
        1 -> "1 video"
        count -> "#{count} video"
      end

    [TrainingLabels.kind(exercise.kind), detail, videos]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp steps(exercise), do: PlanParams.sequence(exercise.sequence) || []

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :day, Enum.at(assigns.plan.days, assigns.day_index))

    ~H"""
    <.page_header>
      <:heading>
        <span class="text-[13px] text-neutral-500">
          <%= if @live_action == :program do %>
            <.link navigate={~p"/admin/programs"} class="hover:text-neutral-800">Programmi</.link>
            / {if @record.template, do: "Nuovo da template", else: "Bozza"}
          <% else %>
            <.link navigate={~p"/admin/templates"} class="hover:text-neutral-800">Template</.link>
            / Modifica
          <% end %>
        </span>
        <div class="flex items-center gap-2.5">
          <span id="plan-title" class="truncate text-[22px] font-semibold leading-7">{@plan.name}</span>
          <span
            :if={@live_action == :program && @record.template}
            class="flex shrink-0 items-center gap-1 rounded-pill bg-primary-100 px-2.5 py-1 text-xs font-semibold text-primary-800"
          >
            <.icon name="hero-square-3-stack-3d" class="h-3.5 w-3.5" />Da template: {@record.template.name}
          </span>
        </div>
      </:heading>
      <:actions>
        <%= if @live_action == :program do %>
          <.button variant={:ghost} icon="hero-arrow-down-tray" phx-click="save_as_template">Salva come template</.button>
          <.button variant={:outline} phx-click="save">Salva bozza</.button>
          <.button
            icon="hero-paper-airplane"
            phx-click="publish"
            data-confirm={"Pubblicare il programma? #{TrainingLabels.first_name(client_name(assigns))} lo vedrà subito."}
          >
            Pubblica a {TrainingLabels.first_name(client_name(assigns))}
          </.button>
        <% else %>
          <.button phx-click="save">Salva template</.button>
        <% end %>
      </:actions>
    </.page_header>

    <div class="grid items-start gap-8 px-8 py-6 xl:grid-cols-[minmax(0,1fr)_320px]">
      <div class="flex min-w-0 flex-col gap-6">
        <.form
          for={%{}}
          as={:plan}
          id="plan-meta"
          phx-change="meta"
          class={[
            "grid gap-3",
            @live_action == :program && "grid-cols-[2fr_1.4fr_1fr_1fr_1fr]",
            @live_action == :template && "grid-cols-[2fr_1fr]"
          ]}
        >
          <.field label="Nome programma" for="plan-name">
            <input
              id="plan-name"
              name="plan[name]"
              value={@plan.name}
              phx-debounce="300"
              class={input_class()}
            />
          </.field>
          <%= if @live_action == :program do %>
            <.field label="Cliente" for="plan-client">
              <select id="plan-client" name="plan[client_id]" class={input_class()}>
                <option
                  :for={client <- @clients}
                  value={client.id}
                  selected={client.id == @plan.client_id}
                >
                  {client.name}
                </option>
              </select>
            </.field>
            <.field label="Inizio" for="plan-starts-on">
              <input
                id="plan-starts-on"
                type="date"
                name="plan[starts_on]"
                value={@plan.starts_on}
                class={input_class()}
              />
            </.field>
            <.field label="Scadenza" for="plan-ends-on">
              <input
                id="plan-ends-on"
                type="date"
                name="plan[ends_on]"
                value={@plan.ends_on}
                class={input_class()}
              />
            </.field>
          <% end %>
          <.field label="Settimane" for="plan-weeks">
            <div class="flex h-10 items-center justify-between rounded-lg border border-neutral-200 text-sm">
              <button
                type="button"
                phx-click="weeks"
                phx-value-delta="-1"
                aria-label="Una settimana in meno"
                class="flex h-full w-9 items-center justify-center text-neutral-500"
              >
                <.icon name="hero-minus" class="h-4 w-4" />
              </button>
              <b id="plan-weeks">{@plan.weeks_count}</b>
              <button
                type="button"
                phx-click="weeks"
                phx-value-delta="1"
                aria-label="Una settimana in più"
                class="flex h-full w-9 items-center justify-center text-neutral-500"
              >
                <.icon name="hero-plus" class="h-4 w-4" />
              </button>
            </div>
          </.field>
        </.form>

        <div class="flex items-stretch gap-2 border-b border-neutral-100" role="tablist">
          <button
            :for={{day, index} <- Enum.with_index(@plan.days)}
            type="button"
            role="tab"
            aria-selected={to_string(index == @day_index)}
            phx-click="select_day"
            phx-value-index={index}
            class={[
              "-mb-px flex flex-col px-4 py-2.5 text-left",
              index == @day_index && "border-b-2 border-primary-600",
              index != @day_index && "text-neutral-600"
            ]}
          >
            <span class={[
              "text-sm",
              index == @day_index && "font-semibold",
              index != @day_index && "font-medium"
            ]}>
              Giorno {GenerateSessions.day_label(index)} · {day.title}
            </span>
            <span class="text-xs text-neutral-500">
              {if day.weekdays == [], do: "Nessun giorno", else: TrainingLabels.weekdays(day.weekdays)} · {length(
                day.exercises
              )} esercizi
            </span>
          </button>
          <button
            type="button"
            phx-click="add_day"
            class="flex items-center gap-1.5 px-4 py-2.5 text-sm font-semibold text-primary-600"
          >
            <.icon name="hero-plus" class="h-4 w-4" />Aggiungi giorno
          </button>
          <div class="flex-1"></div>
          <button
            type="button"
            phx-click="duplicate_day"
            class="flex items-center gap-1.5 py-2.5 text-sm font-medium text-neutral-600"
          >
            <.icon name="hero-document-duplicate" class="h-4 w-4" />Duplica giorno
          </button>
          <button
            :if={length(@plan.days) > 1}
            type="button"
            phx-click="delete_day"
            data-confirm={"Eliminare il Giorno #{GenerateSessions.day_label(@day_index)} e i suoi esercizi?"}
            aria-label="Elimina giorno"
            class="flex items-center px-2 py-2.5 text-neutral-500 hover:text-danger-600"
          >
            <.icon name="hero-trash" class="h-4 w-4" />
          </button>
        </div>

        <div class="flex flex-wrap items-center gap-4">
          <.form for={%{}} as={:day} id="day-meta" phx-change="day_title" class="w-56">
            <input
              name="day[title]"
              value={@day.title}
              aria-label="Nome del giorno"
              phx-debounce="300"
              class={input_class()}
            />
          </.form>
          <span class="text-sm font-semibold">Ripeti ogni settimana il</span>
          <div class="flex gap-1.5">
            <button
              :for={weekday <- 1..7}
              type="button"
              phx-click="toggle_weekday"
              phx-value-weekday={weekday}
              disabled={weekday in taken_weekdays(@plan.days, @day_index)}
              aria-pressed={to_string(weekday in @day.weekdays)}
              class={[
                "flex h-9 min-w-[52px] items-center justify-center rounded-pill px-3 text-[13px]",
                weekday in @day.weekdays && "bg-primary-600 font-semibold text-white",
                weekday not in @day.weekdays && "border border-neutral-200",
                weekday in taken_weekdays(@plan.days, @day_index) &&
                  "cursor-not-allowed text-neutral-300"
              ]}
            >
              {TrainingLabels.weekday_short(weekday)}
            </button>
          </div>
          <span class="text-[13px] text-neutral-500">{taken_note(@plan.days, @day_index)}</span>
        </div>

        <div id="exercises" class="flex flex-col gap-3">
          <.exercise_editor
            :for={{exercise, index} <- Enum.with_index(@day.exercises)}
            exercise={exercise}
            open?={exercise.id in @open}
            first?={index == 0}
            last?={index == length(@day.exercises) - 1}
            adding_video?={@adding_video == exercise.id}
          />
          <button
            type="button"
            phx-click="add_exercise"
            class="flex h-12 items-center justify-center gap-1.5 rounded-xl border border-dashed border-neutral-300 text-sm font-semibold text-primary-600 hover:bg-neutral-50"
          >
            <.icon name="hero-plus" class="h-4 w-4" />Aggiungi esercizio
          </button>
        </div>
      </div>

      <aside id="plan-summary" class="flex flex-col gap-4 rounded-xl border border-neutral-200 p-5">
        <span class="text-base font-semibold">Riepilogo</span>
        <div class="flex flex-col gap-0.5">
          <span id="sessions-count" class="font-display text-[40px] font-semibold leading-[44px]">{sessions_count(
            @plan
          )}</span>
          <span class="text-sm text-neutral-600">
            sessioni · {@plan.weeks_count} settimane × {per_week(@plan.days)} giorni
          </span>
        </div>
        <div class="h-px bg-neutral-100"></div>
        <span class="text-[13px] font-semibold text-neutral-600">Settimana tipo</span>
        <div class="grid grid-cols-7 gap-1">
          <div :for={weekday <- 1..7} class="flex flex-col items-center gap-1">
            <span class="text-[11px] text-neutral-500">{TrainingLabels.weekday_initial(weekday)}</span>
            <%= case Enum.find_index(@plan.days, &(weekday in &1.weekdays)) do %>
              <% nil -> %>
                <div class="h-10 w-full rounded-md bg-neutral-50"></div>
              <% index -> %>
                <div class={[
                  "flex h-10 w-full items-center justify-center rounded-md text-xs font-semibold",
                  rem(index, 2) == 0 && "bg-primary-600 text-white",
                  rem(index, 2) == 1 && "bg-primary-100 text-primary-800"
                ]}>
                  {GenerateSessions.day_label(index)}
                </div>
            <% end %>
          </div>
        </div>
        <%= if @live_action == :program do %>
          <div class="h-px bg-neutral-100"></div>
          <dl :if={schedule = schedule(@plan)} class="flex flex-col gap-2 text-sm">
            <div :if={schedule != []} class="flex justify-between">
              <dt class="text-neutral-600">Prima sessione</dt>
              <dd class="font-semibold">{session_date(elem(hd(schedule), 3))}</dd>
            </div>
            <div :if={schedule != []} class="flex justify-between">
              <dt class="text-neutral-600">Ultima sessione</dt>
              <dd class="font-semibold">{session_date(elem(List.last(schedule), 3))}</dd>
            </div>
            <div :if={match?({:ok, _}, Date.from_iso8601(@plan.ends_on))} class="flex justify-between">
              <dt class="text-neutral-600">Scadenza</dt>
              <dd class="font-semibold">
                {TrainingLabels.short_date(Date.from_iso8601!(@plan.ends_on))}
              </dd>
            </div>
          </dl>
        <% end %>
        <%= if @live_action == :program do %>
          <div class="h-px bg-neutral-100"></div>
          <div id="client-equipment" class="flex flex-col gap-2">
            <div class="flex items-center justify-between">
              <span class="text-[13px] font-semibold text-neutral-600">
                Attrezzatura di {TrainingLabels.first_name(client_name(assigns))}
              </span>
              <.link
                navigate={~p"/admin/clients/#{@plan.client_id}?#{[tab: "attrezzatura"]}"}
                class="text-[13px] font-semibold text-primary-600 hover:text-primary-700"
              >
                Modifica
              </.link>
            </div>
            <p :if={@equipment == []} class="text-[13px] text-neutral-500">
              Nessuna attrezzatura indicata.
            </p>
            <ul :if={@equipment != []} class="flex flex-col gap-1.5 text-sm">
              <li :for={item <- @equipment} class="flex gap-2">
                <.icon name="hero-check-mini" class="mt-0.5 h-4 w-4 shrink-0 text-success-600" />
                <span>
                  <span class="font-medium">{item.name}</span>
                  <span :if={item.details} class="text-neutral-500">· {item.details}</span>
                </span>
              </li>
            </ul>
          </div>
        <% end %>
        <div class="flex gap-2 rounded-xl bg-info-100 px-3.5 py-3 text-[13px] leading-[18px] text-info-800">
          <.icon name="hero-information-circle" class="h-4 w-4 shrink-0" />
          <span>
            Ogni giornata è una copia modificabile: potrai cambiare l'obiettivo di un singolo giorno o di tutte le repliche future.
          </span>
        </div>
      </aside>
    </div>
    """
  end

  attr :exercise, :map, required: true
  attr :open?, :boolean, required: true
  attr :first?, :boolean, required: true
  attr :last?, :boolean, required: true
  attr :adding_video?, :boolean, required: true

  defp exercise_editor(%{open?: false} = assigns) do
    ~H"""
    <div
      id={"plan-exercise-#{@exercise.id}"}
      class="flex items-center gap-3 rounded-xl border border-neutral-200 px-5 py-4"
    >
      <.move_buttons exercise={@exercise} first?={@first?} last?={@last?} />
      <button
        type="button"
        phx-click="toggle_exercise"
        phx-value-id={@exercise.id}
        class="flex flex-1 items-center gap-3 text-left"
      >
        <span class="flex flex-1 flex-col">
          <span class="text-[15px] font-semibold">{@exercise.name}</span>
          <span class="text-[13px] text-neutral-600">{exercise_summary(@exercise)}</span>
        </span>
        <.icon name="hero-chevron-down" class="h-5 w-5 text-neutral-500" />
      </button>
    </div>
    """
  end

  defp exercise_editor(assigns) do
    assigns = assign(assigns, kinds: @kinds, presets: PlanParams.sequence_presets())

    ~H"""
    <div
      id={"plan-exercise-#{@exercise.id}"}
      class="flex flex-col gap-3.5 rounded-xl border border-neutral-200 px-5 py-4"
    >
      <form
        id={"exercise-form-#{@exercise.id}"}
        phx-change="exercise_change"
        class="flex flex-col gap-3.5"
      >
        <input type="hidden" name="ref" value={@exercise.id} />
        <div class="flex items-center gap-3">
          <.move_buttons exercise={@exercise} first?={@first?} last?={@last?} />
          <input
            name="exercise[name]"
            value={@exercise.name}
            aria-label="Nome esercizio"
            phx-debounce="300"
            class={[input_class(), "flex-1 !text-[15px] font-semibold"]}
          />
          <div
            class="flex rounded-pill border border-neutral-100 bg-neutral-50 p-[3px]"
            role="radiogroup"
            aria-label="Tipo di serie"
          >
            <button
              :for={{kind, label} <- @kinds}
              type="button"
              role="radio"
              aria-checked={to_string(@exercise.kind == kind)}
              phx-click="set_kind"
              phx-value-id={@exercise.id}
              phx-value-kind={kind}
              class={[
                "flex h-8 items-center rounded-pill px-3 text-[13px]",
                @exercise.kind == kind &&
                  "bg-surface font-semibold shadow-[0_1px_2px_0_rgba(30,41,59,0.12)] dark:bg-neutral-200",
                @exercise.kind != kind && "text-neutral-600"
              ]}
            >
              {label}
            </button>
          </div>
          <button
            type="button"
            phx-click="delete_exercise"
            phx-value-id={@exercise.id}
            aria-label={"Elimina #{@exercise.name}"}
            class="text-neutral-500 hover:text-danger-600"
          >
            <.icon name="hero-trash" class="h-[18px] w-[18px]" />
          </button>
          <button
            type="button"
            phx-click="toggle_exercise"
            phx-value-id={@exercise.id}
            aria-label="Chiudi"
            class="text-neutral-500"
          >
            <.icon name="hero-chevron-up" class="h-5 w-5" />
          </button>
        </div>

        <div class="flex flex-wrap items-end gap-3 pl-[30px]">
          <.field label="Serie" class="w-20">
            <input
              name="exercise[sets_count]"
              type="number"
              min="1"
              value={@exercise.sets_count}
              class={input_class()}
            />
          </.field>
          <.field :if={@exercise.kind == :reps} label="Ripetizioni" class="w-24">
            <input
              name="exercise[target_reps]"
              type="number"
              min="1"
              value={@exercise.target_reps}
              class={input_class()}
            />
          </.field>
          <.field :if={@exercise.kind == :time} label="Secondi" class="w-24">
            <input
              name="exercise[target_seconds]"
              type="number"
              min="1"
              value={@exercise.target_seconds}
              class={input_class()}
            />
          </.field>
          <div :if={@exercise.kind in [:reps, :max]} class="flex w-28 flex-col gap-1">
            <label class="flex items-center gap-1.5 text-xs text-neutral-600">
              Carico kg <input type="hidden" name="exercise[load]" value="false" />
              <input
                type="checkbox"
                name="exercise[load]"
                value="true"
                checked={@exercise.load?}
                class="peer sr-only"
                aria-label="Con carico"
              />
              <span class="flex h-4 w-7 items-center rounded-full bg-neutral-300 p-0.5 transition peer-checked:justify-end peer-checked:bg-primary-600">
                <span class="h-3 w-3 rounded-full bg-white"></span>
              </span>
            </label>
            <input
              :if={@exercise.load?}
              name="exercise[target_load_kg]"
              inputmode="decimal"
              value={@exercise.target_load_kg}
              aria-label="Carico in kg"
              class={input_class()}
            />
            <span :if={!@exercise.load?} class="flex h-10 items-center text-sm text-neutral-500">Corpo libero</span>
          </div>
          <.field label="Recupero (s)" class="w-24">
            <input
              name="exercise[rest_seconds]"
              type="number"
              min="0"
              value={@exercise.rest_seconds}
              class={input_class()}
            />
          </.field>
          <.field label="Note" class="min-w-[200px] flex-1">
            <input
              name="exercise[notes]"
              value={@exercise.notes}
              phx-debounce="300"
              class={input_class()}
            />
          </.field>
        </div>

        <div :if={@exercise.kind == :sequence} class="flex flex-col gap-2.5 pl-[30px]">
          <div class="flex flex-wrap items-end gap-3">
            <.field label="Sequenza ripetizioni" class="w-[260px]">
              <input
                name="exercise[sequence]"
                value={@exercise.sequence}
                phx-debounce="300"
                class={[input_class(), "tracking-[0.04em]"]}
              />
            </.field>
            <.field label="Recupero tra step (s)" class="w-36">
              <input
                name="exercise[sequence_rest_seconds]"
                type="number"
                min="0"
                value={@exercise.sequence_rest_seconds}
                class={input_class()}
              />
            </.field>
            <button
              :for={{label, sequence} <- @presets}
              type="button"
              phx-click="sequence_preset"
              phx-value-id={@exercise.id}
              phx-value-sequence={sequence}
              class="flex h-8 items-center rounded-pill border border-neutral-200 px-3 text-[13px] hover:bg-neutral-50"
            >
              {label}
            </button>
          </div>
          <div class="flex items-center gap-2">
            <div class="flex flex-wrap gap-1">
              <span
                :for={step <- steps(@exercise)}
                class="flex h-7 w-7 items-center justify-center rounded-md bg-primary-100 text-xs font-semibold text-primary-800"
              >
                {step}
              </span>
            </div>
            <span class="text-[13px] text-neutral-500">
              <%= if steps(@exercise) == [] do %>
                Sequenza non valida
              <% else %>
                {length(steps(@exercise))} step · {Enum.sum(steps(@exercise))} ripetizioni totali
              <% end %>
            </span>
          </div>
        </div>
      </form>

      <div class="flex flex-wrap items-center gap-2 pl-[30px]">
        <span
          :for={{video, index} <- Enum.with_index(@exercise.videos)}
          class="flex h-8 items-center gap-1.5 rounded-pill bg-neutral-50 px-3 text-[13px]"
          title={video.url}
        >
          <.icon name="hero-play-circle-solid" class="h-4 w-4 text-danger-600" />{video.title}
          <button
            type="button"
            phx-click="remove_video"
            phx-value-id={@exercise.id}
            phx-value-index={index}
            aria-label={"Rimuovi #{video.title}"}
            class="text-neutral-500"
          >
            <.icon name="hero-x-mark" class="h-3.5 w-3.5" />
          </button>
        </span>
        <form
          :if={@adding_video?}
          id={"video-form-#{@exercise.id}"}
          phx-submit="save_video"
          class="flex items-center gap-2"
        >
          <input type="hidden" name="ref" value={@exercise.id} />
          <input
            name="video[title]"
            placeholder="Titolo"
            aria-label="Titolo del video"
            class={[input_class(), "!h-8 w-40"]}
          />
          <input
            name="video[url]"
            placeholder="youtube.com/watch?v=…"
            aria-label="Link del video"
            class={[input_class(), "!h-8 w-64"]}
            required
          />
          <.button type="submit" size={:sm}>Aggiungi</.button>
        </form>
        <button
          :if={!@adding_video?}
          type="button"
          phx-click="add_video"
          phx-value-id={@exercise.id}
          class="flex h-8 items-center gap-1.5 rounded-pill border border-dashed border-neutral-300 px-3 text-[13px] font-medium text-primary-600"
        >
          <.icon name="hero-link" class="h-4 w-4" />Aggiungi video
        </button>
      </div>
    </div>
    """
  end

  attr :exercise, :map, required: true
  attr :first?, :boolean, required: true
  attr :last?, :boolean, required: true

  defp move_buttons(assigns) do
    ~H"""
    <div class="flex flex-col text-neutral-400">
      <button
        type="button"
        phx-click="move_exercise"
        phx-value-id={@exercise.id}
        phx-value-dir="up"
        disabled={@first?}
        aria-label={"Sposta su #{@exercise.name}"}
        class="hover:text-neutral-800 disabled:opacity-30"
      >
        <.icon name="hero-chevron-up-mini" class="h-4 w-4" />
      </button>
      <button
        type="button"
        phx-click="move_exercise"
        phx-value-id={@exercise.id}
        phx-value-dir="down"
        disabled={@last?}
        aria-label={"Sposta giù #{@exercise.name}"}
        class="hover:text-neutral-800 disabled:opacity-30"
      >
        <.icon name="hero-chevron-down-mini" class="h-4 w-4" />
      </button>
    </div>
    """
  end
end
