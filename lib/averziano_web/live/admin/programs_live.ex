defmodule AverzianoWeb.Admin.ProgramsLive do
  @moduledoc """
  Every program the coach has built: drafts open in the editor, published
  ones on their client's page.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.AdminComponents
  import AverzianoWeb.ClientComponents, only: [badge: 1]

  alias Averziano.Training
  alias AverzianoWeb.TrainingLabels

  @impl true
  def mount(_params, _session, socket) do
    {:ok, programs} =
      Training.list_coached_programs(
        actor: socket.assigns.actor,
        load: [:sessions_count, :completed_sessions_count, :client, :template]
      )

    {:ok,
     assign(socket,
       nav: :programs,
       page_title: "Programmi",
       programs: programs,
       today: Date.utc_today()
     )}
  end

  defp status(%{published_at: nil}, _today), do: {:neutral, "Bozza"}

  defp status(program, today) do
    if Date.before?(program.ends_on, today), do: {:muted, "Concluso"}, else: {:success, "Attivo"}
  end

  defp path(%{published_at: nil} = program), do: ~p"/admin/programs/#{program.id}/edit"
  defp path(program), do: ~p"/admin/clients/#{program.client_id}"

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header title="Programmi">
      <:actions>
        <.button navigate={~p"/admin/templates"} icon="hero-plus">Nuovo programma</.button>
      </:actions>
    </.page_header>

    <div class="p-8">
      <div class="overflow-hidden rounded-xl border border-neutral-200">
        <div class="grid grid-cols-[2fr_1.6fr_1.4fr_1.4fr_1fr] border-b border-neutral-200 bg-neutral-50 px-5 py-3 text-xs font-semibold tracking-[0.02em] text-neutral-600">
          <span>Programma</span><span>Cliente</span><span>Periodo</span><span>Avanzamento</span><span>Stato</span>
        </div>
        <.link
          :for={program <- @programs}
          id={"program-#{program.id}"}
          navigate={path(program)}
          class="grid grid-cols-[2fr_1.6fr_1.4fr_1.4fr_1fr] items-center border-b border-neutral-100 px-5 py-4 text-sm last:border-b-0 hover:bg-neutral-50"
        >
          <span class="flex flex-col">
            <span class="font-semibold">{program.name}</span>
            <span :if={program.template} class="text-xs text-neutral-500">Da template: {program.template.name}</span>
          </span>
          <span class="flex items-center gap-2.5"><.avatar name={program.client.name} />{program.client.name}</span>
          <span>{TrainingLabels.short_date(program.starts_on)} – {TrainingLabels.short_date_year(
            program.ends_on
          )}</span>
          <span :if={program.published_at} class="flex flex-col gap-1.5 pr-6">
            <span class="text-[13px]">{program.completed_sessions_count} / {program.sessions_count}</span>
            <.progress done={program.completed_sessions_count} total={program.sessions_count} />
          </span>
          <span :if={!program.published_at} class="text-neutral-500">—</span>
          <.badge tone={elem(status(program, @today), 0)} class="justify-self-start">
            {elem(status(program, @today), 1)}
          </.badge>
        </.link>
        <p :if={@programs == []} class="px-5 py-8 text-center text-sm text-neutral-500">
          Nessun programma ancora. Creane uno da un template.
        </p>
      </div>
    </div>
    """
  end
end
