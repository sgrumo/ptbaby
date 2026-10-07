defmodule AverzianoWeb.Client.ExerciseLive do
  @moduledoc """
  Exercise detail: the embedded reference video, the target, the coach's
  notes and the list of linked videos.
  """

  use AverzianoWeb, :live_view

  import AverzianoWeb.ClientComponents

  alias Averziano.Training
  alias AverzianoWeb.TrainingLabels

  @youtube_id ~r"(?:youtube\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/)|youtu\.be/)([\w-]{11})"

  @impl true
  def mount(%{"session_id" => session_id, "exercise_id" => id}, _session, socket) do
    case Training.get_exercise(id,
           actor: socket.assigns.actor,
           load: [session: [:exercises_count]]
         ) do
      {:ok, %{session_id: ^session_id} = exercise} ->
        {:ok, assign(socket, page_title: exercise.name, exercise: exercise)}

      _ ->
        {:ok, socket |> put_flash(:error, "Esercizio non trovato") |> push_navigate(to: ~p"/app")}
    end
  end

  defp embed_url(videos) do
    Enum.find_value(videos, fn video ->
      case Regex.run(@youtube_id, video.url) do
        [_, id] -> "https://www.youtube-nocookie.com/embed/#{id}"
        nil -> nil
      end
    end)
  end

  # Coaches paste links with or without a scheme; only http(s) ever reaches the href.
  defp external_url("http://" <> _ = url), do: url
  defp external_url("https://" <> _ = url), do: url
  defp external_url(url), do: "https://" <> url

  defp bodyweight?(exercise),
    do: exercise.kind in [:reps, :max] and is_nil(exercise.target_load_kg)

  defp stats(%{kind: :time} = exercise) do
    [
      {"Serie", exercise.sets_count},
      {"Durata", "#{exercise.target_seconds} s"},
      load_stat(exercise)
    ]
  end

  defp stats(exercise) do
    reps =
      case exercise.kind do
        :reps -> exercise.target_reps
        :max -> "Max"
        :sequence -> Enum.sum(exercise.sequence)
      end

    [{"Serie", exercise.sets_count}, {"Ripetizioni", reps}, load_stat(exercise)]
  end

  defp load_stat(%{target_load_kg: nil}), do: {"Carico", "Corpo libero"}
  defp load_stat(%{target_load_kg: kg}), do: {"Carico", TrainingLabels.load(kg)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 flex-col">
      <.top_bar
        back={~p"/app/sessions/#{@exercise.session_id}"}
        context={"Esercizio #{@exercise.position} di #{@exercise.session.exercises_count}"}
      />

      <div
        :if={url = embed_url(@exercise.videos)}
        class="mx-4 mt-1 aspect-video overflow-hidden rounded-2xl bg-neutral-100"
      >
        <iframe
          id="exercise-video"
          src={url}
          title={"Video: #{@exercise.name}"}
          class="h-full w-full"
          allow="accelerometer; encrypted-media; gyroscope; picture-in-picture"
          allowfullscreen
          loading="lazy"
        ></iframe>
      </div>

      <div class="flex flex-col gap-2 px-6 pt-5">
        <h1 class="font-display text-[28px] font-semibold leading-[34px]">{@exercise.name}</h1>
        <div class="flex gap-1.5">
          <.badge>{TrainingLabels.kind(@exercise)}</.badge>
          <.badge :if={bodyweight?(@exercise)} tone={:info}>Corpo libero</.badge>
        </div>
      </div>

      <dl class="mx-4 mt-4 grid grid-cols-3 rounded-2xl border border-neutral-200">
        <div
          :for={{{label, value}, index} <- Enum.with_index(stats(@exercise))}
          class={["flex flex-col gap-0.5 p-3.5", index > 0 && "border-l border-neutral-100"]}
        >
          <dt class="text-xs text-neutral-500">{label}</dt>
          <dd class={[
            "font-semibold",
            value == "Corpo libero" && "text-[15px] leading-[30px] text-neutral-600",
            value != "Corpo libero" && "text-[22px]"
          ]}>
            {value}
          </dd>
        </div>
      </dl>

      <div :if={@exercise.notes} class="flex flex-col gap-1.5 px-6 pt-5">
        <span class="text-sm font-semibold">Note del coach</span>
        <p class="text-[15px] leading-[22px] text-neutral-600">{@exercise.notes}</p>
      </div>

      <div :if={@exercise.videos != []} class="flex flex-col gap-2 px-4 pt-5">
        <span class="px-2 text-sm font-semibold">Video</span>
        <a
          :for={video <- @exercise.videos}
          href={external_url(video.url)}
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center gap-3 rounded-xl border border-neutral-200 px-4 py-3 hover:bg-neutral-50"
        >
          <.icon name="hero-play-circle-solid" class="h-[22px] w-[22px] text-danger-600" />
          <span class="flex-1 text-sm font-medium">{video.title}</span>
          <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4 text-neutral-400" />
        </a>
      </div>

      <div class="sticky bottom-0 mt-auto bg-surface px-4 pb-4 pt-6">
        <.action_button
          navigate={~p"/app/sessions/#{@exercise.session_id}/exercises/#{@exercise.id}"}
          variant={:outline}
        >
          Torna alla serie
        </.action_button>
      </div>
    </div>
    """
  end
end
