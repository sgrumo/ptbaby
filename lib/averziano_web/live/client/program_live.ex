defmodule AverzianoWeb.Client.ProgramLive do
  @moduledoc """
  Client home ("Programma"): the active program, its progress, the next
  session to train and the sessions of the selected week.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.ClientComponents

  alias Averziano.{Accounts, Training}
  alias AverzianoWeb.TrainingLabels

  @impl true
  def mount(_params, _session, socket) do
    %{actor: actor, current_user_id: user_id} = socket.assigns
    today = Date.utc_today()

    {:ok, program} =
      Training.current_program(
        actor: actor,
        load: [
          :sessions_count,
          :completed_sessions_count,
          :days_per_week,
          sessions: [:exercises_count, :sets_total]
        ]
      )

    name =
      case Accounts.get_user(user_id, actor: actor) do
        {:ok, user} -> user.name
        {:error, _} -> ""
      end

    {:ok,
     assign(socket,
       page_title: "Programma",
       name: name,
       today: today,
       program: program,
       featured: program && featured_session(program.sessions, today)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :week, selected_week(params, socket.assigns))}
  end

  # The session to train next: the first open one from today on.
  defp featured_session(sessions, today) do
    Enum.find(
      sessions,
      &(is_nil(&1.completed_at) and Date.compare(&1.scheduled_on, today) != :lt)
    )
  end

  defp selected_week(_params, %{program: nil}), do: nil

  defp selected_week(params, %{program: program, featured: featured}) do
    weeks = program.weeks_count
    default = if featured, do: featured.week_number, else: weeks

    case Integer.parse(params["week"] || "") do
      {week, ""} when week >= 1 and week <= weeks -> week
      _ -> default
    end
  end

  defp week_sessions(program, week), do: Enum.filter(program.sessions, &(&1.week_number == week))

  defp week_done?(program, week) do
    case week_sessions(program, week) do
      [] -> false
      sessions -> Enum.all?(sessions, & &1.completed_at)
    end
  end

  defp status(session, today) do
    cond do
      session.completed_at -> :completed
      session.scheduled_on == today -> :today
      Date.before?(session.scheduled_on, today) -> :missed
      true -> :upcoming
    end
  end

  defp progress_percent(%{sessions_count: 0}), do: 0

  defp progress_percent(program),
    do: round(program.completed_sessions_count * 100 / program.sessions_count)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col pb-8">
      <div class="flex flex-col gap-1.5 px-6 pt-6">
        <div class="flex items-center justify-between">
          <span class="text-sm text-neutral-500">Ciao {TrainingLabels.first_name(@name)}</span>
          <div class="flex items-center gap-3">
            <.theme_toggle />
            <.link
              href={~p"/sign-out"}
              method="delete"
              class="text-[13px] font-medium text-neutral-500"
            >
              Esci
            </.link>
            <span class="flex h-9 w-9 items-center justify-center rounded-full bg-primary-100 text-[13px] font-semibold text-primary-800">
              {TrainingLabels.initials(@name)}
            </span>
          </div>
        </div>

        <%= if @program do %>
          <h1 class="font-display text-[28px] font-semibold leading-[34px] tracking-[-0.01em]">
            {@program.name}
          </h1>
          <div class="flex gap-4 text-sm text-neutral-600">
            <span class="flex items-center gap-1">
              <.icon name="hero-calendar" class="h-4 w-4" />Scade il {TrainingLabels.short_date(
                @program.ends_on
              )}
            </span>
            <span>{@program.weeks_count} sett. · {@program.days_per_week} giorni/sett.</span>
          </div>
        <% end %>
      </div>

      <div :if={!@program} id="no-program" class="mx-4 mt-6 rounded-2xl border border-neutral-200 p-5">
        <p class="font-semibold">Nessun programma attivo</p>
        <p class="mt-1 text-sm text-neutral-600">
          Il tuo coach non ti ha ancora assegnato un programma. Lo troverai qui appena sarà pronto.
        </p>
      </div>

      <%= if @program do %>
        <div class="mx-4 mt-5 flex flex-col gap-2.5 rounded-2xl border border-neutral-200 p-4">
          <div class="flex justify-between text-sm">
            <span class="text-neutral-600">Avanzamento</span>
            <span id="progress" class="font-semibold">
              {@program.completed_sessions_count} di {@program.sessions_count} giorni
            </span>
          </div>
          <div class="h-2 overflow-hidden rounded-lg bg-neutral-100">
            <div
              class="h-full rounded-lg bg-primary-600"
              style={"width: #{progress_percent(@program)}%"}
            >
            </div>
          </div>
        </div>

        <div
          :if={@featured}
          id="featured-session"
          class="mx-4 mt-3 flex flex-col gap-3.5 rounded-[20px] bg-primary-600 p-5 text-white"
        >
          <div class="flex flex-col gap-0.5">
            <span class="text-[13px] text-white/80">
              {if @featured.scheduled_on == @today, do: "Oggi", else: "Prossimo"} · {TrainingLabels.long_date(
                @featured.scheduled_on
              )}
            </span>
            <span class="text-[22px] font-semibold leading-7">
              Giorno {@featured.day_label} · {@featured.title}
            </span>
            <span class="text-sm text-white/80">
              {@featured.exercises_count} esercizi · {@featured.sets_total} serie
            </span>
          </div>
          <.action_button
            navigate={~p"/app/sessions/#{@featured.id}"}
            variant={:inverse}
            icon="hero-play-solid"
            class="!h-12 !text-[15px]"
          >
            Inizia allenamento
          </.action_button>
        </div>

        <nav class="flex gap-2 px-4 pt-6" aria-label="Settimane">
          <.link
            :for={week <- 1..@program.weeks_count//1}
            patch={~p"/app?#{[week: week]}"}
            aria-current={week == @week && "page"}
            class={[
              "flex h-11 flex-1 items-center justify-center gap-1 rounded-pill text-sm font-medium",
              week == @week && "bg-neutral-800 text-neutral-50",
              week != @week && "border border-neutral-200"
            ]}
          >
            <.icon
              :if={week != @week and week_done?(@program, week)}
              name="hero-check-mini"
              class="h-4 w-4 text-success-600"
            />Sett. {week}
          </.link>
        </nav>

        <div id="week-sessions" class="flex flex-col gap-2 px-4 pt-4">
          <.link
            :for={session <- week_sessions(@program, @week)}
            id={"session-#{session.id}"}
            navigate={~p"/app/sessions/#{session.id}"}
            class={[
              "flex items-center gap-3 rounded-2xl p-3",
              status(session, @today) == :today && "border-2 border-primary-600",
              status(session, @today) != :today && "border border-neutral-100"
            ]}
          >
            <div class={[
              "flex h-12 w-12 flex-col items-center justify-center rounded-xl",
              status(session, @today) == :today && "bg-primary-100 text-primary-800",
              status(session, @today) != :today && "bg-neutral-50"
            ]}>
              <span class={["text-[11px]", status(session, @today) != :today && "text-neutral-500"]}>
                {TrainingLabels.weekday_abbr(session.scheduled_on)}
              </span>
              <span class="text-[17px] font-semibold leading-5">{session.scheduled_on.day}</span>
            </div>
            <div class="flex flex-1 flex-col">
              <span class="text-[15px] font-semibold">{session.title}</span>
              <span class="text-[13px] text-neutral-500">
                Giorno {session.day_label} · {session.exercises_count} esercizi
              </span>
            </div>
            <%= case status(session, @today) do %>
              <% :completed -> %>
                <.badge tone={:success}>Completato</.badge>
              <% :today -> %>
                <.badge tone={:brand}>Oggi</.badge>
              <% :missed -> %>
                <.badge>Non svolto</.badge>
              <% :upcoming -> %>
            <% end %>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
