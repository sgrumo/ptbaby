defmodule AverzianoWeb.Admin.ClientEquipmentComponent do
  @moduledoc """
  The "Attrezzatura" tab of a client: what they have available to train
  with, each item with optional details and editable in place. Common items
  not yet on the list can be added with one click.

  Sends `{:equipment_count, count}` to the parent LiveView when the list changes.
  """

  use AverzianoWeb, :live_component

  import AverzianoWeb.AdminComponents

  alias AshPhoenix.Form
  alias Averziano.Training
  alias Averziano.Training.Equipment
  alias AverzianoWeb.TrainingLabels

  @suggestions [
    "Palestra attrezzata",
    "Manubri",
    "Bilanciere",
    "Dischi",
    "Kettlebell",
    "Panca",
    "Rack",
    "Sbarra per trazioni",
    "Elastici",
    "TRX",
    "Anelli",
    "Fitball",
    "Step",
    "Tappetino",
    "Corda per saltare",
    "Cyclette",
    "Tapis roulant"
  ]

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Parent re-renders must not wipe what the coach is typing.
    if socket.assigns[:form] do
      {:ok, socket}
    else
      {:ok, socket |> assign(editing: nil, edit_form: nil) |> load_items() |> reset_form()}
    end
  end

  defp load_items(%{assigns: %{client: client, actor: actor}} = socket) do
    {:ok, items} = Training.list_client_equipment(client.id, actor: actor)
    assign(socket, :items, items)
  end

  defp reset_form(%{assigns: %{client: client, actor: actor}} = socket) do
    form =
      Equipment
      |> Form.for_create(:create,
        actor: actor,
        as: "equipment",
        transform_params: fn _form, params, _action ->
          Map.put(params, "client_id", client.id)
        end
      )
      |> to_form()

    assign(socket, :form, form)
  end

  @impl true
  def handle_event("validate", %{"equipment" => params}, socket),
    do: {:noreply, update(socket, :form, &Form.validate(&1, params))}

  def handle_event("add", %{"equipment" => params}, socket) do
    case Form.submit(socket.assigns.form, params: params) do
      {:ok, _item} -> {:noreply, socket |> load_items() |> reset_form() |> notify()}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("quick_add", %{"name" => name}, socket) do
    %{client: client, actor: actor} = socket.assigns

    case Training.add_equipment(%{client_id: client.id, name: name}, actor: actor) do
      {:ok, _item} -> {:noreply, socket |> load_items() |> notify()}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "Impossibile aggiungere #{name}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    form =
      socket.assigns.items
      |> Enum.find(&(&1.id == id))
      |> Form.for_update(:update, actor: socket.assigns.actor, as: "edit_equipment")
      |> to_form()

    {:noreply, assign(socket, editing: id, edit_form: form)}
  end

  def handle_event("validate_edit", %{"edit_equipment" => params}, socket),
    do: {:noreply, update(socket, :edit_form, &Form.validate(&1, params))}

  def handle_event("save_edit", %{"edit_equipment" => params}, socket) do
    case Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, _item} ->
        {:noreply, socket |> load_items() |> assign(editing: nil, edit_form: nil)}

      {:error, form} ->
        {:noreply, assign(socket, :edit_form, form)}
    end
  end

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, editing: nil, edit_form: nil)}

  def handle_event("remove", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == id))

    case Training.remove_equipment(item, actor: socket.assigns.actor) do
      :ok ->
        {:noreply, socket |> load_items() |> notify()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Impossibile rimuovere #{item.name}")}
    end
  end

  defp notify(socket) do
    send(self(), {:equipment_count, length(socket.assigns.items)})
    socket
  end

  # Common items the client doesn't have on their list yet.
  defp suggestions(items) do
    taken = MapSet.new(items, &String.downcase(to_string(&1.name)))
    Enum.reject(@suggestions, &(String.downcase(&1) in taken))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex max-w-3xl flex-col gap-6 p-8">
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-semibold">Attrezzatura</h2>
        <p class="text-sm text-neutral-600">
          Cosa ha a disposizione {TrainingLabels.first_name(@client.name)} per allenarsi. La trovi anche mentre costruisci i suoi programmi.
        </p>
      </div>

      <.form
        for={@form}
        id="equipment-form"
        phx-change="validate"
        phx-submit="add"
        phx-target={@myself}
        class="flex flex-col gap-3 rounded-xl border border-neutral-200 p-4"
      >
        <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)_auto] items-end gap-3">
          <.field label="Attrezzo" for="equipment-name">
            <.input
              field={@form[:name]}
              id="equipment-name"
              placeholder="Es. Manubri"
              class={input_class()}
            />
          </.field>
          <.field label="Dettagli · opzionale" for="equipment-details">
            <.input
              field={@form[:details]}
              id="equipment-details"
              placeholder="Es. coppia fino a 20 kg"
              class={input_class()}
            />
          </.field>
          <.button type="submit" icon="hero-plus" class="self-start mt-5">Aggiungi</.button>
        </div>

        <div :if={suggestions(@items) != []} class="flex flex-wrap items-center gap-1.5">
          <span class="mr-1 text-xs text-neutral-500">Aggiungi al volo:</span>
          <button
            :for={name <- suggestions(@items)}
            type="button"
            phx-click="quick_add"
            phx-value-name={name}
            phx-target={@myself}
            class="flex h-7 items-center gap-1 rounded-pill border border-neutral-200 px-2.5 text-xs font-medium text-neutral-600 hover:border-primary-500 hover:text-primary-600"
          >
            <.icon name="hero-plus-micro" class="h-3.5 w-3.5" />{name}
          </button>
        </div>
      </.form>

      <p :if={@items == []} id="no-equipment" class="text-sm text-neutral-500">
        Nessuna attrezzatura ancora: aggiungi cosa ha a casa o se si allena in palestra.
      </p>

      <ul :if={@items != []} id="equipment" class="flex flex-col rounded-xl border border-neutral-200">
        <li
          :for={item <- @items}
          id={"equipment-#{item.id}"}
          class="flex items-center gap-3 border-b border-neutral-100 px-4 py-3 last:border-b-0"
        >
          <%= if @editing == item.id do %>
            <.form
              for={@edit_form}
              id={"edit-equipment-#{item.id}"}
              phx-change="validate_edit"
              phx-submit="save_edit"
              phx-target={@myself}
              class="grid flex-1 grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)_auto] items-start gap-2"
            >
              <.input field={@edit_form[:name]} aria-label="Attrezzo" class={input_class()} />
              <.input field={@edit_form[:details]} aria-label="Dettagli" class={input_class()} />
              <div class="flex gap-1">
                <.button
                  type="button"
                  size={:sm}
                  variant={:ghost}
                  phx-click="cancel_edit"
                  phx-target={@myself}
                  class="mt-1"
                >
                  Annulla
                </.button>
                <.button type="submit" size={:sm} class="mt-1">Salva</.button>
              </div>
            </.form>
          <% else %>
            <.icon name="hero-check-circle" class="h-5 w-5 shrink-0 text-success-600" />
            <div class="flex min-w-0 flex-1 flex-col">
              <span class="text-sm font-semibold">{item.name}</span>
              <span :if={item.details} class="text-[13px] text-neutral-600">{item.details}</span>
            </div>
            <.button
              size={:sm}
              variant={:ghost}
              phx-click="edit"
              phx-value-id={item.id}
              phx-target={@myself}
            >
              Modifica
            </.button>
            <.button
              size={:sm}
              variant={:ghost}
              phx-click="remove"
              phx-value-id={item.id}
              phx-target={@myself}
              aria-label={"Rimuovi #{item.name}"}
              class="!text-danger-600"
            >
              Rimuovi
            </.button>
          <% end %>
        </li>
      </ul>
    </div>
    """
  end
end
