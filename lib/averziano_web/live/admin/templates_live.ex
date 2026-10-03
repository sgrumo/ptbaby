defmodule AverzianoWeb.Admin.TemplatesLive do
  @moduledoc """
  The template library. `?use=<template>` opens the "Nuovo programma da"
  panel (optionally preselecting `client`), `?save=program` the panel that
  saves an existing program as a template.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.AdminComponents

  alias Averziano.{Accounts, Errors, Training}
  alias Averziano.Training.Changes.GenerateSessions
  alias AverzianoWeb.Admin.PlanParams
  alias AverzianoWeb.TrainingLabels

  @impl true
  def mount(_params, _session, socket) do
    {:ok, clients} = Accounts.list_clients(actor: socket.assigns.actor)

    {:ok,
     socket
     |> assign(nav: :templates, page_title: "Template", query: "", clients: clients)
     |> load_templates()}
  end

  defp load_templates(socket) do
    {:ok, templates} =
      Training.list_templates(actor: socket.assigns.actor, load: [:clients_count, :days_per_week])

    assign(socket, :templates, templates)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(panel: nil, using: nil, client_param: params["client"])
     |> open_panel(params)}
  end

  defp open_panel(socket, %{"use" => id} = params) do
    case Enum.find(socket.assigns.templates, &(&1.id == id)) do
      nil ->
        socket

      template ->
        starts_on = Date.utc_today() |> Date.beginning_of_week() |> Date.add(7)

        assign(socket,
          panel: :use,
          using: template,
          new_program: %{
            "client_id" => params["client"] || "",
            "name" => template.name,
            "starts_on" => Date.to_iso8601(starts_on),
            "ends_on" => Date.to_iso8601(ends_on(starts_on, template.weeks_count)),
            "open_editor" => "true"
          }
        )
    end
  end

  defp open_panel(socket, %{"save" => "program"}) do
    {:ok, programs} = Training.list_coached_programs(actor: socket.assigns.actor, load: [:client])
    assign(socket, panel: :save, programs: programs)
  end

  defp open_panel(socket, _params), do: socket

  defp use_path(template, nil), do: ~p"/admin/templates?#{[use: template.id]}"

  defp use_path(template, client_id),
    do: ~p"/admin/templates?#{[use: template.id, client: client_id]}"

  defp ends_on(starts_on, weeks), do: Date.add(starts_on, weeks * 7 - 1)

  @impl true
  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, assign(socket, :query, query)}

  def handle_event("new_template", _params, socket) do
    params = %{
      name: "Nuovo template",
      weeks_count: 4,
      days: [%{title: "Giorno A", weekdays: [], exercises: []}]
    }

    case Training.create_template(params, actor: socket.assigns.actor) do
      {:ok, template} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/templates/#{template.id}/edit")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("delete_template", %{"id" => id}, socket) do
    template = Enum.find(socket.assigns.templates, &(&1.id == id))

    case Training.destroy_template(template, actor: socket.assigns.actor) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Template eliminato")
         |> load_templates()
         |> push_patch(to: ~p"/admin/templates")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  # Moving the start keeps the length of the template; the end stays editable.
  def handle_event("change_program", %{"program" => params}, socket) do
    previous = socket.assigns.new_program

    params =
      if params["starts_on"] != previous["starts_on"] do
        case Date.from_iso8601(params["starts_on"] || "") do
          {:ok, starts_on} ->
            Map.put(
              params,
              "ends_on",
              Date.to_iso8601(ends_on(starts_on, socket.assigns.using.weeks_count))
            )

          _ ->
            params
        end
      else
        params
      end

    {:noreply, assign(socket, :new_program, params)}
  end

  def handle_event("create_program", %{"program" => params}, socket) do
    %{using: template, actor: actor} = socket.assigns

    attrs = %{
      name: params["name"],
      client_id: params["client_id"],
      starts_on: params["starts_on"],
      ends_on: params["ends_on"],
      weeks_count: template.weeks_count,
      template_id: template.id,
      days: PlanParams.to_days(PlanParams.from_days(template.days))
    }

    with {:ok, program} <- Training.create_program(attrs, actor: actor),
         {:ok, program} <- maybe_publish(program, params["open_editor"] == "true", actor) do
      {:noreply,
       if program.published_at do
         socket
         |> put_flash(:info, "#{program.name} pubblicato")
         |> push_navigate(to: ~p"/admin/clients/#{program.client_id}")
       else
         push_navigate(socket, to: ~p"/admin/programs/#{program.id}/edit")
       end}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("save_program", %{"template" => %{"program_id" => id, "name" => name}}, socket) do
    with %{} = program <- Enum.find(socket.assigns.programs, &(&1.id == id)),
         {:ok, template} <-
           Training.create_template(
             %{
               name: name,
               weeks_count: program.weeks_count,
               days: PlanParams.to_days(PlanParams.from_days(program.days))
             },
             actor: socket.assigns.actor
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Template #{template.name} salvato")
       |> load_templates()
       |> push_patch(to: ~p"/admin/templates")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Scegli un programma")}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp maybe_publish(program, true = _open_editor, _actor), do: {:ok, program}
  defp maybe_publish(program, false, actor), do: Training.publish_program(program, actor: actor)

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

  defp visible(templates, ""), do: templates

  defp visible(templates, query) do
    query = String.downcase(String.trim(query))
    Enum.filter(templates, &String.contains?(String.downcase(&1.name), query))
  end

  defp exercises_count(template),
    do: template.days |> Enum.map(&length(&1.exercises)) |> Enum.sum()

  defp tags(template) do
    exercises = Enum.flat_map(template.days, & &1.exercises)

    kinds =
      exercises
      |> Enum.map(& &1.kind)
      |> Enum.uniq()
      |> Enum.sort_by(&Enum.find_index([:reps, :max, :time, :sequence], fn k -> k == &1 end))

    bodyweight? = Enum.any?(exercises, &(&1.kind in [:reps, :max] and is_nil(&1.target_load_kg)))

    Enum.map(kinds, &TrainingLabels.kind/1) ++ if(bodyweight?, do: ["Corpo libero"], else: [])
  end

  defp usage(%{clients_count: 0}), do: "Mai usato"
  defp usage(%{clients_count: 1}), do: "Usato da 1 cliente"
  defp usage(%{clients_count: count}), do: "Usato da #{count} clienti"

  defp all_weekdays(template),
    do: template.days |> Enum.flat_map(& &1.weekdays) |> Enum.uniq() |> TrainingLabels.weekdays()

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header title="Template">
      <:actions>
        <form id="template-search" phx-change="search" class="w-[280px]" onsubmit="return false">
          <label class="flex h-10 items-center gap-2 rounded-lg border border-neutral-200 px-3 text-sm focus-within:border-primary-500">
            <.icon name="hero-magnifying-glass" class="h-4 w-4 text-neutral-400" />
            <input
              type="search"
              name="q"
              value={@query}
              placeholder="Cerca template"
              aria-label="Cerca template"
              phx-debounce="150"
              class="w-full border-0 p-0 text-sm placeholder:text-neutral-400 focus:ring-0"
            />
          </label>
        </form>
        <.button phx-click="new_template" icon="hero-plus">Nuovo template</.button>
      </:actions>
    </.page_header>

    <div class={["grid min-h-0 flex-1", @panel && "grid-cols-[minmax(0,1fr)_400px]"]}>
      <div class="flex flex-col gap-4 p-8">
        <p class="text-sm text-neutral-600">
          Un template è un programma senza cliente e senza date. Usalo per creare un nuovo programma, poi personalizzalo.
        </p>
        <div class="grid grid-cols-2 gap-4">
          <article
            :for={template <- visible(@templates, @query)}
            id={"template-#{template.id}"}
            class={[
              "flex flex-col gap-3.5 rounded-xl p-5",
              @using && @using.id == template.id && "border-2 border-primary-600 !p-[19px]",
              !(@using && @using.id == template.id) && "border border-neutral-200"
            ]}
          >
            <div class="flex items-start justify-between gap-2">
              <div class="flex flex-col gap-0.5">
                <.link
                  navigate={~p"/admin/templates/#{template.id}/edit"}
                  class="text-base font-semibold hover:text-primary-600"
                >
                  {template.name}
                </.link>
                <span class="text-[13px] text-neutral-600">
                  {template.weeks_count} settimane · {template.days_per_week} giorni/sett. · {exercises_count(
                    template
                  )} esercizi
                </span>
              </div>
              <.menu id={"template-menu-#{template.id}"} label={"Azioni per #{template.name}"}>
                <:item>
                  <.link navigate={~p"/admin/templates/#{template.id}/edit"}>Modifica</.link>
                </:item>
                <:item>
                  <button
                    type="button"
                    phx-click="delete_template"
                    phx-value-id={template.id}
                    data-confirm={"Eliminare il template #{template.name}? I programmi creati restano."}
                    class="text-danger-600"
                  >
                    Elimina
                  </button>
                </:item>
              </.menu>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <span
                :for={tag <- tags(template)}
                class="rounded-pill bg-neutral-50 px-2 py-0.5 text-xs text-neutral-600"
              >{tag}</span>
            </div>
            <div class="h-px bg-neutral-100"></div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-neutral-500">{usage(template)}</span>
              <.button
                size={:sm}
                variant={if @using && @using.id == template.id, do: :primary, else: :outline}
                patch={use_path(template, @client_param)}
              >
                Usa template
              </.button>
            </div>
          </article>
          <.link
            patch={~p"/admin/templates?#{[save: "program"]}"}
            class="flex min-h-[180px] flex-col items-center justify-center gap-1.5 rounded-xl border border-dashed border-neutral-300 p-5 text-sm font-semibold text-primary-600 hover:bg-neutral-50"
          >
            <.icon name="hero-arrow-down-tray" class="h-[22px] w-[22px]" />
            Salva un programma esistente come template
          </.link>
        </div>
      </div>

      <aside
        :if={@panel == :use}
        id="use-panel"
        class="flex flex-col gap-5 border-l border-neutral-100 p-6"
      >
        <div class="flex items-start justify-between">
          <div class="flex flex-col gap-0.5">
            <span class="text-[13px] text-neutral-500">Nuovo programma da</span>
            <span class="text-xl font-semibold leading-7">{@using.name}</span>
          </div>
          <.link patch={~p"/admin/templates"} aria-label="Chiudi" class="text-neutral-500"><.icon
            name="hero-x-mark"
            class="h-[22px] w-[22px]"
          /></.link>
        </div>
        <.form
          for={%{}}
          as={:program}
          id="new-program-form"
          phx-change="change_program"
          phx-submit="create_program"
          class="flex flex-1 flex-col gap-5"
        >
          <div class="flex flex-col gap-4">
            <.field label="Cliente" for="program-client">
              <select id="program-client" name="program[client_id]" class={input_class()} required>
                <option value="" disabled selected={@new_program["client_id"] == ""}>
                  Scegli un cliente
                </option>
                <option
                  :for={client <- @clients}
                  value={client.id}
                  selected={@new_program["client_id"] == client.id}
                >
                  {client.name}
                </option>
              </select>
            </.field>
            <.field label="Nome programma" for="program-name">
              <input
                id="program-name"
                name="program[name]"
                value={@new_program["name"]}
                class={input_class()}
                required
              />
            </.field>
            <div class="grid grid-cols-2 gap-3">
              <.field label="Inizio" for="program-starts-on">
                <input
                  id="program-starts-on"
                  type="date"
                  name="program[starts_on]"
                  value={@new_program["starts_on"]}
                  class={input_class()}
                  required
                />
              </.field>
              <.field label="Scadenza" for="program-ends-on">
                <input
                  id="program-ends-on"
                  type="date"
                  name="program[ends_on]"
                  value={@new_program["ends_on"]}
                  class={input_class()}
                  required
                />
              </.field>
            </div>
            <span class="-mt-2 text-xs text-neutral-500">Scadenza calcolata da {@using.weeks_count} settimane, modificabile.</span>
          </div>
          <div class="flex flex-col gap-2.5 rounded-xl bg-neutral-50 p-4 text-sm">
            <span class="text-[13px] font-semibold">Contenuto</span>
            <div :for={{day, index} <- Enum.with_index(@using.days)} class="flex justify-between">
              <span class="text-neutral-600">Giorno {GenerateSessions.day_label(index)} · {day.title}</span>
              <span>{length(day.exercises)} esercizi</span>
            </div>
            <div class="flex justify-between">
              <span class="text-neutral-600">Ripetizione</span><span>{all_weekdays(@using)}</span>
            </div>
          </div>
          <label class="flex items-center gap-2.5 text-sm">
            <input type="hidden" name="program[open_editor]" value="false" />
            <input
              type="checkbox"
              name="program[open_editor]"
              value="true"
              checked={@new_program["open_editor"] == "true"}
              class="rounded text-primary-600 focus:ring-primary-500"
            /> Apri nell'editor prima di pubblicare
          </label>
          <div class="flex-1"></div>
          <div class="flex flex-col gap-2">
            <.button type="submit" class="!h-11 w-full !text-[15px]" phx-disable-with="Creazione…">Crea programma</.button>
            <span class="text-center text-xs text-neutral-500">Le modifiche al programma non cambiano il template.</span>
          </div>
        </.form>
      </aside>

      <aside
        :if={@panel == :save}
        id="save-panel"
        class="flex flex-col gap-5 border-l border-neutral-100 p-6"
      >
        <div class="flex items-start justify-between">
          <span class="text-xl font-semibold leading-7">Salva come template</span>
          <.link patch={~p"/admin/templates"} aria-label="Chiudi" class="text-neutral-500"><.icon
            name="hero-x-mark"
            class="h-[22px] w-[22px]"
          /></.link>
        </div>
        <.form
          for={%{}}
          as={:template}
          id="save-program-form"
          phx-submit="save_program"
          class="flex flex-col gap-4"
        >
          <.field label="Programma" for="save-program">
            <select id="save-program" name="template[program_id]" class={input_class()} required>
              <option value="">Scegli un programma</option>
              <option :for={program <- @programs} value={program.id}>
                {program.name} · {program.client.name}
              </option>
            </select>
          </.field>
          <.field label="Nome template" for="save-name">
            <input id="save-name" name="template[name]" class={input_class()} required />
          </.field>
          <.button type="submit">Salva template</.button>
        </.form>
      </aside>
    </div>
    """
  end
end
