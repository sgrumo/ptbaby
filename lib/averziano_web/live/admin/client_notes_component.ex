defmodule AverzianoWeb.Admin.ClientNotesComponent do
  @moduledoc """
  The "Note" tab of a client: the coach's general notes and dated reviews,
  each one editable in place. Programs that are ending (or have ended)
  without a review get a shortcut to an end-of-program review.

  Sends `{:notes_count, count}` to the parent LiveView when notes change.
  """

  use AverzianoWeb, :live_component

  import AverzianoWeb.AdminComponents
  import AverzianoWeb.ClientComponents, only: [badge: 1]

  alias AshPhoenix.Form
  alias Averziano.Training
  alias Averziano.Training.ClientNote
  alias AverzianoWeb.TrainingLabels

  # How long before its end a program asks for its review.
  @review_window_days 14

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Parent re-renders must not wipe what the coach is typing.
    if socket.assigns[:general_form] do
      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(editing: nil, edit_form: nil)
       |> load_notes()
       |> reset_form(:general)
       |> reset_form(:review)}
    end
  end

  defp load_notes(%{assigns: %{client: client, actor: actor}} = socket) do
    {:ok, notes} = Training.list_client_notes(client.id, actor: actor, load: [:program])
    {general, reviews} = Enum.split_with(notes, &(&1.kind == :general))
    assign(socket, general: general, reviews: reviews)
  end

  defp reset_form(socket, kind, params \\ %{}) do
    %{client: client, actor: actor} = socket.assigns

    form =
      ClientNote
      |> Form.for_create(:create,
        actor: actor,
        as: "#{kind}_note",
        params: params,
        transform_params: fn _form, params, _action ->
          Map.merge(params, %{"client_id" => client.id, "kind" => Atom.to_string(kind)})
        end
      )
      |> to_form()

    assign(socket, :"#{kind}_form", form)
  end

  @impl true
  def handle_event("validate", %{"kind" => kind} = params, socket) do
    key = form_key(kind)
    {:noreply, update(socket, key, &Form.validate(&1, params[form_name(kind)]))}
  end

  def handle_event("save", %{"kind" => kind} = params, socket) do
    case Form.submit(socket.assigns[form_key(kind)], params: params[form_name(kind)]) do
      {:ok, _note} ->
        {:noreply, socket |> load_notes() |> reset(kind) |> notify()}

      {:error, form} ->
        {:noreply, assign(socket, form_key(kind), form)}
    end
  end

  def handle_event("review_program", %{"id" => program_id}, socket) do
    program = Enum.find(socket.assigns.programs, &(&1.id == program_id))

    params = %{
      "noted_on" => Date.to_iso8601(program.ends_on),
      "program_id" => program.id,
      "title" => "Fine programma · #{program.name}"
    }

    {:noreply, reset_form(socket, :review, params)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    note = Enum.find(socket.assigns.general ++ socket.assigns.reviews, &(&1.id == id))

    form =
      note |> Form.for_update(:update, actor: socket.assigns.actor, as: "edit_note") |> to_form()

    {:noreply, assign(socket, editing: id, edit_form: form)}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, reset(socket, "edit")}

  def handle_event("delete", %{"id" => id}, socket) do
    note = Enum.find(socket.assigns.general ++ socket.assigns.reviews, &(&1.id == id))

    case Training.destroy_client_note(note, actor: socket.assigns.actor) do
      :ok -> {:noreply, socket |> load_notes() |> notify()}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "Impossibile eliminare la nota")}
    end
  end

  defp reset(socket, "edit"), do: assign(socket, editing: nil, edit_form: nil)
  defp reset(socket, kind), do: reset_form(socket, String.to_existing_atom(kind))

  defp form_key("edit"), do: :edit_form
  defp form_key(kind), do: :"#{kind}_form"

  defp form_name(kind), do: "#{kind}_note"

  defp notify(socket) do
    send(self(), {:notes_count, length(socket.assigns.general) + length(socket.assigns.reviews)})
    socket
  end

  # Published programs ending within the window (or already ended) without a review.
  defp due_reviews(programs, reviews, today) do
    reviewed = MapSet.new(reviews, & &1.program_id)

    Enum.filter(programs, fn program ->
      program.published_at && program.id not in reviewed &&
        Date.diff(program.ends_on, today) <= @review_window_days
    end)
  end

  defp program_label(%{program: %{ends_on: ends_on} = program, noted_on: ends_on}),
    do: "Fine programma · #{program.name}"

  defp program_label(%{program: %{name: name}}), do: name
  defp program_label(_note), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="grid items-start gap-8 p-8 xl:grid-cols-2">
      <section class="flex flex-col gap-4" aria-labelledby="general-notes-title">
        <div class="flex flex-col gap-1">
          <h2 id="general-notes-title" class="text-base font-semibold">Note generali</h2>
          <p class="text-sm text-neutral-600">
            Obiettivi, infortuni, preferenze: valgono per tutti i programmi. Solo tu le vedi.
          </p>
        </div>

        <.form
          for={@general_form}
          id="general-note-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="flex flex-col gap-2"
        >
          <input type="hidden" name="kind" value="general" />
          <.input
            field={@general_form[:body]}
            type="textarea"
            rows="3"
            placeholder={"Una nota su #{TrainingLabels.first_name(@client.name)}…"}
            aria-label="Nuova nota generale"
            class="block w-full rounded-xl border border-neutral-200 px-3.5 py-3 text-[15px] leading-[22px] focus:border-primary-500 focus:ring-0"
          />
          <.button type="submit" size={:sm} icon="hero-plus" class="self-end">Aggiungi nota</.button>
        </.form>

        <p :if={@general == []} class="text-sm text-neutral-500">Nessuna nota generale.</p>
        <.note_card
          :for={note <- @general}
          note={note}
          editing={@editing}
          edit_form={@edit_form}
          myself={@myself}
        />
      </section>

      <section class="flex flex-col gap-4" aria-labelledby="reviews-title">
        <div class="flex flex-col gap-1">
          <h2 id="reviews-title" class="text-base font-semibold">Revisioni</h2>
          <p class="text-sm text-neutral-600">
            Note datate: a fine programma o quando vuoi fare il punto.
          </p>
        </div>

        <div
          :for={program <- due_reviews(@programs, @reviews, @today)}
          id={"due-review-#{program.id}"}
          class="flex items-center justify-between gap-3 rounded-xl bg-warning-100 px-4 py-3 text-sm text-warning-800"
        >
          <span>
            <b>{program.name}</b>
            {if Date.before?(program.ends_on, @today), do: "è terminato il", else: "termina il"}
            {TrainingLabels.short_date(program.ends_on)}: nessuna revisione ancora.
          </span>
          <.button
            size={:sm}
            variant={:outline}
            phx-click="review_program"
            phx-value-id={program.id}
            phx-target={@myself}
          >
            Aggiungi revisione di fine programma
          </.button>
        </div>

        <.form
          for={@review_form}
          id="review-note-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="flex flex-col gap-3 rounded-xl border border-neutral-200 p-4"
        >
          <input type="hidden" name="kind" value="review" />
          <.review_fields form={@review_form} programs={@programs} />
          <.button type="submit" size={:sm} icon="hero-plus" class="self-end">Aggiungi revisione</.button>
        </.form>

        <p :if={@reviews == []} class="text-sm text-neutral-500">Nessuna revisione.</p>
        <.note_card
          :for={note <- @reviews}
          note={note}
          editing={@editing}
          edit_form={@edit_form}
          programs={@programs}
          myself={@myself}
        />
      </section>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :programs, :list, required: true

  defp review_fields(assigns) do
    ~H"""
    <div class="grid grid-cols-[160px_minmax(0,1fr)] gap-3">
      <.field label="Data" for={@form[:noted_on].id}>
        <.input field={@form[:noted_on]} type="date" class={input_class()} />
      </.field>
      <.field label="Programma · opzionale" for={@form[:program_id].id}>
        <select id={@form[:program_id].id} name={@form[:program_id].name} class={input_class()}>
          <option value="">Nessun programma</option>
          <option
            :for={program <- @programs}
            value={program.id}
            selected={to_string(@form[:program_id].value) == program.id}
          >
            {program.name}{if is_nil(program.published_at), do: " (bozza)"}
          </option>
        </select>
      </.field>
    </div>
    <.field label="Titolo · opzionale" for={@form[:title].id}>
      <.input field={@form[:title]} placeholder="Es. Check dopo 3 mesi" class={input_class()} />
    </.field>
    <.field label="Nota" for={@form[:body].id}>
      <.input
        field={@form[:body]}
        type="textarea"
        rows="3"
        class="block w-full rounded-lg border border-neutral-200 px-3 py-2.5 text-sm focus:border-primary-500 focus:ring-0"
      />
    </.field>
    """
  end

  attr :note, ClientNote, required: true
  attr :editing, :string, default: nil, doc: "id of the note being edited"
  attr :edit_form, Phoenix.HTML.Form, default: nil
  attr :programs, :list, default: []
  attr :myself, :any, required: true

  defp note_card(assigns) do
    assigns = assign(assigns, :editing?, assigns.editing == assigns.note.id)

    ~H"""
    <article
      id={"note-#{@note.id}"}
      class="flex flex-col gap-2 rounded-xl border border-neutral-200 p-4"
    >
      <%= if @editing? do %>
        <.form
          for={@edit_form}
          id={"edit-note-#{@note.id}"}
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="flex flex-col gap-3"
        >
          <input type="hidden" name="kind" value="edit" />
          <%= if @note.kind == :review do %>
            <.review_fields form={@edit_form} programs={@programs} />
          <% else %>
            <.input
              field={@edit_form[:body]}
              type="textarea"
              rows="3"
              aria-label="Nota"
              class="block w-full rounded-lg border border-neutral-200 px-3 py-2.5 text-sm focus:border-primary-500 focus:ring-0"
            />
          <% end %>
          <div class="flex justify-end gap-2">
            <.button
              type="button"
              size={:sm}
              variant={:ghost}
              phx-click="cancel_edit"
              phx-target={@myself}
            >
              Annulla
            </.button>
            <.button type="submit" size={:sm}>Salva</.button>
          </div>
        </.form>
      <% else %>
        <div :if={@note.kind == :review} class="flex flex-wrap items-center gap-2">
          <span class="text-sm font-semibold">{TrainingLabels.short_date_year(@note.noted_on)}</span>
          <.badge :if={label = program_label(@note)} tone={:brand_soft}>{label}</.badge>
        </div>
        <span :if={@note.title} class="text-[15px] font-semibold">{@note.title}</span>
        <p class="whitespace-pre-line text-[15px] leading-[22px]">{@note.body}</p>
        <div class="flex items-center justify-between">
          <span class="text-xs text-neutral-500">
            Aggiornata il {TrainingLabels.short_date_year(DateTime.to_date(@note.updated_at))}
          </span>
          <div class="flex gap-1">
            <.button
              size={:sm}
              variant={:ghost}
              phx-click="edit"
              phx-value-id={@note.id}
              phx-target={@myself}
            >
              Modifica
            </.button>
            <.button
              size={:sm}
              variant={:ghost}
              phx-click="delete"
              phx-value-id={@note.id}
              phx-target={@myself}
              data-confirm="Eliminare la nota?"
              class="!text-danger-600"
            >
              Elimina
            </.button>
          </div>
        </div>
      <% end %>
    </article>
    """
  end
end
