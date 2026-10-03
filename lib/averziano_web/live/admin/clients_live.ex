defmodule AverzianoWeb.Admin.ClientsLive do
  @moduledoc """
  Console home ("Clienti"): every client with their program, progress, last
  completed day and status, the feed of completed days to review, and the
  "Aggiungi cliente" dialog (`:invite` action).
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.AdminComponents
  import AverzianoWeb.ClientComponents, only: [badge: 1]

  alias AshPhoenix.Form
  alias Averziano.{Accounts, Training}
  alias Averziano.Accounts.User
  alias AverzianoWeb.TrainingLabels

  @program_load [
    :sessions_count,
    :completed_sessions_count,
    :to_review_count,
    :missed_count,
    :last_completed_at,
    :last_completed_week,
    :last_completed_day
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(nav: :clients, page_title: "Clienti", query: "", today: Date.utc_today())
     |> load()}
  end

  defp load(%{assigns: %{actor: actor}} = socket) do
    {:ok, clients} = Accounts.list_clients(actor: actor)
    {:ok, programs} = Training.list_coached_programs(actor: actor, load: @program_load)

    {:ok, feed} =
      Training.list_completed_sessions(
        actor: actor,
        load: [:sets_total, :sets_logged, program: [:client]]
      )

    {:ok, templates} = Training.list_templates(actor: actor)

    assign(socket,
      rows: Enum.map(clients, &{&1, main_program(programs, &1.id)}),
      feed: feed,
      to_review: programs |> Enum.map(& &1.to_review_count) |> Enum.sum(),
      templates: templates
    )
  end

  # The latest published program, else the latest draft.
  defp main_program(programs, client_id) do
    programs
    |> Enum.filter(&(&1.client_id == client_id))
    |> Enum.sort_by(&{&1.published_at != nil, &1.starts_on}, :desc)
    |> List.first()
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign_invite(socket, socket.assigns.live_action)}
  end

  defp assign_invite(socket, :invite) do
    form =
      User
      |> Form.for_create(:invite_client, actor: socket.assigns.actor)
      |> to_form()

    assign(socket, invite_form: form, page_title: "Aggiungi cliente")
  end

  defp assign_invite(socket, _action), do: assign(socket, invite_form: nil, page_title: "Clienti")

  @impl true
  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, assign(socket, :query, query)}

  def handle_event("validate_invite", %{"form" => params}, socket) do
    {:noreply, update(socket, :invite_form, &Form.validate(&1, params))}
  end

  def handle_event("invite", %{"form" => params} = all_params, socket) do
    case Form.submit(socket.assigns.invite_form, params: params) do
      {:ok, client} ->
        socket = put_flash(socket, :info, "#{client.name} aggiunto ai clienti")

        case all_params["template_id"] do
          id when id in [nil, ""] ->
            {:noreply, socket |> load() |> push_patch(to: ~p"/admin")}

          template_id ->
            {:noreply,
             push_navigate(socket,
               to: ~p"/admin/templates?#{[use: template_id, client: client.id]}"
             )}
        end

      {:error, form} ->
        {:noreply, assign(socket, :invite_form, form)}
    end
  end

  defp visible_rows(rows, ""), do: rows

  defp visible_rows(rows, query) do
    query = String.downcase(String.trim(query))

    Enum.filter(rows, fn {client, _program} ->
      String.contains?(String.downcase(client.name), query)
    end)
  end

  defp status(_client, %{published_at: nil}), do: {:neutral, "Bozza"}

  defp status(_client, %{to_review_count: count}) when count > 0,
    do: {:warning, "#{count} da revisionare"}

  defp status(_client, %{missed_count: 1}), do: {:danger, "1 giornata saltata"}

  defp status(_client, %{missed_count: count}) when count > 1,
    do: {:danger, "#{count} giornate saltate"}

  defp status(_client, %{}), do: {:success, "In regola"}
  defp status(%{invited_at: %DateTime{}}, nil), do: {:info, "Invito inviato"}
  defp status(_client, nil), do: {:muted, "Nessun programma"}

  attr :client, :map, required: true
  attr :program, :map, default: nil
  attr :today, Date, required: true

  defp client_row(assigns) do
    assigns = assign(assigns, :status, status(assigns.client, assigns.program))

    ~H"""
    <.link
      id={"client-#{@client.id}"}
      navigate={~p"/admin/clients/#{@client.id}"}
      class="grid grid-cols-[2fr_2fr_1.4fr_1.8fr_1.3fr] items-center border-b border-neutral-100 px-5 py-4 text-sm last:border-b-0 hover:bg-neutral-50"
    >
      <span class="flex items-center gap-2.5">
        <.avatar name={@client.name} tone={if @program, do: :soft, else: :muted} />
        <span class="font-semibold">{@client.name}</span>
      </span>
      <%= if @program do %>
        <span>{@program.name}</span>
        <span class="flex flex-col gap-1.5 pr-6">
          <span class="text-[13px]">{@program.completed_sessions_count} / {@program.sessions_count}</span>
          <.progress done={@program.completed_sessions_count} total={@program.sessions_count} />
        </span>
        <span :if={@program.last_completed_at} class="flex flex-col">
          <span>{TrainingLabels.moment(@program.last_completed_at, @today)}</span>
          <span class="text-xs text-neutral-500">
            S{@program.last_completed_week} · Giorno {@program.last_completed_day}
          </span>
        </span>
        <span :if={!@program.last_completed_at} class="text-neutral-500">—</span>
      <% else %>
        <span class="text-neutral-500">Nessun programma</span>
        <span class="text-neutral-500">—</span>
        <span class="text-neutral-500">—</span>
      <% end %>
      <.badge tone={elem(@status, 0)} class="justify-self-start">{elem(@status, 1)}</.badge>
    </.link>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header title="Clienti">
      <:actions>
        <form id="client-search" phx-change="search" class="w-[280px]" onsubmit="return false">
          <label class="flex h-10 items-center gap-2 rounded-lg border border-neutral-200 px-3 text-sm focus-within:border-primary-500">
            <.icon name="hero-magnifying-glass" class="h-4 w-4 text-neutral-400" />
            <input
              type="search"
              name="q"
              value={@query}
              placeholder="Cerca cliente"
              aria-label="Cerca cliente"
              phx-debounce="150"
              class="w-full border-0 p-0 text-sm placeholder:text-neutral-400 focus:ring-0"
            />
          </label>
        </form>
        <a
          href="#feed"
          aria-label={"#{@to_review} giornate da revisionare"}
          class="relative flex h-10 w-10 items-center justify-center rounded-full border border-neutral-200"
        >
          <.icon name="hero-bell" class="h-[18px] w-[18px]" />
          <span
            :if={@to_review > 0}
            class="absolute -right-1 -top-1 flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-primary-600 px-1.5 text-[11px] font-semibold text-white"
          >
            {@to_review}
          </span>
        </a>
        <.button patch={~p"/admin/clients/new"} icon="hero-user-plus">Aggiungi cliente</.button>
      </:actions>
    </.page_header>

    <div class="grid items-start gap-8 p-8 xl:grid-cols-[minmax(0,1fr)_360px]">
      <div class="overflow-hidden rounded-xl border border-neutral-200">
        <div class="grid grid-cols-[2fr_2fr_1.4fr_1.8fr_1.3fr] border-b border-neutral-200 bg-neutral-50 px-5 py-3 text-xs font-semibold tracking-[0.02em] text-neutral-600">
          <span>Cliente</span><span>Programma</span><span>Avanzamento</span><span>Ultima giornata</span><span>Stato</span>
        </div>
        <div id="clients">
          <.client_row
            :for={{client, program} <- visible_rows(@rows, @query)}
            client={client}
            program={program}
            today={@today}
          />
        </div>
        <p
          :if={visible_rows(@rows, @query) == []}
          class="px-5 py-8 text-center text-sm text-neutral-500"
        >
          {if @rows == [],
            do: "Nessun cliente ancora. Aggiungine uno per iniziare.",
            else: "Nessun cliente trovato."}
        </p>
      </div>

      <section id="feed" class="flex flex-col rounded-xl border border-neutral-200">
        <div class="flex items-center justify-between border-b border-neutral-100 px-5 py-4">
          <h2 class="text-base font-semibold">Giornate completate</h2>
          <span class="text-xs text-neutral-500">{@to_review} nuove</span>
        </div>
        <p :if={@feed == []} class="px-5 py-6 text-sm text-neutral-500">
          Nessuna giornata completata.
        </p>
        <div
          :for={session <- @feed}
          id={"feed-#{session.id}"}
          class="flex gap-3 border-b border-neutral-100 px-5 py-4 last:border-b-0"
        >
          <span class={[
            "mt-[7px] h-2 w-2 shrink-0 rounded-full",
            session.reviewed_at && "bg-neutral-200",
            !session.reviewed_at && "bg-primary-600"
          ]}></span>
          <div class="flex flex-1 flex-col gap-1">
            <span class={["text-sm", session.reviewed_at && "text-neutral-600"]}>
              <b>{session.program.client.name}</b>
              ha completato S{session.week_number} · Giorno {session.day_label}
            </span>
            <span class="text-xs text-neutral-500">
              {TrainingLabels.moment(session.completed_at, @today)} ·
              <%= if session.reviewed_at do %>
                Revisionata
              <% else %>
                {session.sets_logged}/{session.sets_total} serie{if session.client_note,
                  do: " · con nota"}
              <% end %>
            </span>
            <.link
              :if={!session.reviewed_at}
              navigate={~p"/admin/clients/#{session.program.client_id}?#{[session: session.id]}"}
              class="text-[13px] font-semibold text-primary-600 hover:text-primary-700"
            >
              Revisiona
            </.link>
          </div>
        </div>
      </section>
    </div>

    <.modal
      :if={@invite_form}
      id="invite-modal"
      title="Aggiungi cliente"
      subtitle="Riceverà un'email con il link per accedere alla piattaforma."
      on_cancel={JS.patch(~p"/admin")}
    >
      <.form for={@invite_form} id="invite-form" phx-change="validate_invite" phx-submit="invite">
        <div class="flex flex-col gap-4 p-6">
          <div class="grid grid-cols-2 gap-3">
            <.field label="Nome" for="invite-first-name">
              <.input field={@invite_form[:first_name]} id="invite-first-name" class={input_class()} />
            </.field>
            <.field label="Cognome" for="invite-last-name">
              <.input field={@invite_form[:last_name]} id="invite-last-name" class={input_class()} />
            </.field>
          </div>
          <.field label="Email" for="invite-email">
            <.input field={@invite_form[:email]} id="invite-email" type="email" class={input_class()} />
          </.field>
          <.field label="Telefono · opzionale" for="invite-phone">
            <.input
              field={@invite_form[:phone]}
              id="invite-phone"
              type="tel"
              placeholder="+39"
              class={input_class()}
            />
          </.field>
          <.field label="Assegna programma · opzionale" for="invite-template">
            <select id="invite-template" name="template_id" class={input_class()}>
              <option value="">Crea dopo</option>
              <option :for={template <- @templates} value={template.id}>
                Da template: {template.name}
              </option>
            </select>
          </.field>
        </div>
        <div class="flex justify-end gap-2 border-t border-neutral-100 px-6 py-4">
          <.button variant={:outline} patch={~p"/admin"}>Annulla</.button>
          <.button type="submit" icon="hero-paper-airplane" phx-disable-with="Invio…">Invia invito</.button>
        </div>
      </.form>
    </.modal>
    """
  end
end
