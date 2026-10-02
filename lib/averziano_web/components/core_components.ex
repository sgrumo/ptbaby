defmodule AverzianoWeb.CoreComponents do
  use Phoenix.Component

  use Gettext, backend: AverzianoWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :name, :string, required: true
  attr :class, :string, default: nil

  @spec icon(map()) :: Phoenix.LiveView.Rendered.t()
  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders flash messages.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], required: true

  @spec flash_message(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_message(assigns) do
    ~H"""
    <div :if={msg = Phoenix.Flash.get(@flash, @kind)} role="alert">
      <p>{msg}</p>
      <button phx-click={JS.push("lv:clear-flash", value: %{key: @kind})}>
        <.icon name="hero-x-mark" class="h-5 w-5" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a flash group (info + error). Only used inside layouts.
  """
  attr :flash, :map, required: true

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <.flash_message flash={@flash} kind={:info} />
    <.flash_message flash={@flash} kind={:error} />
    """
  end

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(placeholder required disabled readonly)

  @spec input(map()) :: Phoenix.LiveView.Rendered.t()
  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        {@rest}
      />
      <p :for={msg <- @errors} class="text-red-600 text-sm">{msg}</p>
    </div>
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
