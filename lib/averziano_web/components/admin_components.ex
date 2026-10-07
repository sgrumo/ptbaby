defmodule AverzianoWeb.AdminComponents do
  @moduledoc """
  Building blocks of the coach console (desktop), styled after the Quinck
  Design System "Console PT" screens.
  """

  use Phoenix.Component

  import AverzianoWeb.CoreComponents, only: [icon: 1]

  alias AverzianoWeb.TrainingLabels
  alias Phoenix.LiveView.JS

  @doc "A sidebar entry."
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  @spec nav_link(map()) :: Phoenix.LiveView.Rendered.t()
  def nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "flex h-10 items-center gap-2.5 rounded-lg px-3 text-sm",
        @active && "bg-primary-100 font-semibold text-primary-800",
        !@active && "font-medium text-neutral-600 hover:bg-neutral-100"
      ]}
    >
      <.icon name={@icon} class="h-[18px] w-[18px]" />{render_slot(@inner_block)}
    </.link>
    """
  end

  @doc "Round initials of a person."
  attr :name, :string, required: true
  attr :tone, :atom, default: :soft, values: [:soft, :dark, :muted]
  attr :class, :any, default: "h-8 w-8 text-xs"

  @spec avatar(map()) :: Phoenix.LiveView.Rendered.t()
  def avatar(assigns) do
    ~H"""
    <span class={[
      "flex shrink-0 items-center justify-center rounded-full font-semibold",
      @tone == :soft && "bg-primary-100 text-primary-800",
      @tone == :dark && "bg-neutral-800 text-neutral-50",
      @tone == :muted && "bg-neutral-100 text-neutral-600",
      @class
    ]}>
      {TrainingLabels.initials(@name)}
    </span>
    """
  end

  @doc "The 72px top bar of a page: title (or a custom heading) and actions."
  attr :title, :string, default: nil
  slot :heading
  slot :actions

  @spec page_header(map()) :: Phoenix.LiveView.Rendered.t()
  def page_header(assigns) do
    ~H"""
    <header class="flex min-h-[72px] items-center gap-4 border-b border-neutral-100 px-8 py-3">
      <h1 :if={@title} class="flex-1 text-2xl font-semibold">{@title}</h1>
      <div :if={@heading != []} class="flex min-w-0 flex-1 flex-col">{render_slot(@heading)}</div>
      {render_slot(@actions)}
    </header>
    """
  end

  @doc "A pill button, or a link when `navigate`/`patch` is given."
  attr :variant, :atom, default: :primary, values: [:primary, :outline, :ghost]
  attr :size, :atom, default: :md, values: [:md, :sm]
  attr :icon, :string, default: nil
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(type disabled form name value)
  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex shrink-0 items-center justify-center gap-1.5 rounded-pill font-semibold transition disabled:opacity-50",
        assigns.size == :md && "h-10 px-4 text-sm",
        assigns.size == :sm && "h-8 px-3 text-[13px]",
        assigns.variant == :primary && "bg-primary-600 text-white hover:bg-primary-700",
        assigns.variant == :outline && "border border-neutral-200 bg-surface hover:bg-neutral-50",
        assigns.variant == :ghost && "text-neutral-600 hover:bg-neutral-50",
        assigns.class
      ])

    ~H"""
    <.link :if={@navigate || @patch} navigate={@navigate} patch={@patch} class={@classes} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-4 w-4" />{render_slot(@inner_block)}
    </.link>
    <button :if={!(@navigate || @patch)} class={@classes} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-4 w-4" />{render_slot(@inner_block)}
    </button>
    """
  end

  @doc "A label above a control, with an optional hint underneath."
  attr :label, :string, required: true
  attr :for, :string, default: nil
  attr :hint, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  @spec field(map()) :: Phoenix.LiveView.Rendered.t()
  def field(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @class]}>
      <label for={@for} class="text-xs text-neutral-600">{@label}</label>
      {render_slot(@inner_block)}
      <span :if={@hint} class="text-xs text-neutral-500">{@hint}</span>
    </div>
    """
  end

  @doc "Classes of a text-like control of the console."
  @spec input_class() :: String.t()
  def input_class do
    "block h-10 w-full rounded-lg border border-neutral-200 bg-surface px-3 text-sm focus:border-primary-500 focus:ring-0"
  end

  @doc "A thin progress bar."
  attr :done, :integer, required: true
  attr :total, :integer, required: true

  @spec progress(map()) :: Phoenix.LiveView.Rendered.t()
  def progress(assigns) do
    assigns =
      assign(
        assigns,
        :percent,
        if(assigns.total > 0, do: round(assigns.done * 100 / assigns.total), else: 0)
      )

    ~H"""
    <div class="h-1 rounded bg-neutral-100">
      <div class="h-full rounded bg-primary-600" style={"width: #{@percent}%"}></div>
    </div>
    """
  end

  @doc "A centered dialog over a dimmed page; `on_cancel` runs on close, Escape or a click outside."
  attr :id, :string, required: true
  attr :on_cancel, JS, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  @spec modal(map()) :: Phoenix.LiveView.Rendered.t()
  def modal(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-40 flex items-center justify-center bg-black/50 p-6">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-click-away={@on_cancel}
        phx-window-keydown={@on_cancel}
        phx-key="escape"
        class="flex w-[520px] max-w-full flex-col rounded-2xl bg-surface shadow-[0_16px_24px_-4px_rgba(30,41,59,0.16)]"
      >
        <div class="flex items-start justify-between px-6 pt-6">
          <div class="flex flex-col gap-1">
            <h2 id={"#{@id}-title"} class="text-xl font-semibold">{@title}</h2>
            <p :if={@subtitle} class="text-sm text-neutral-600">{@subtitle}</p>
          </div>
          <button type="button" phx-click={@on_cancel} aria-label="Chiudi" class="text-neutral-500">
            <.icon name="hero-x-mark" class="h-[22px] w-[22px]" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "A ⋮ menu toggled in place."
  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :item, required: true

  @spec menu(map()) :: Phoenix.LiveView.Rendered.t()
  def menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        aria-label={@label}
        phx-click={JS.toggle(to: "##{@id}", display: "flex")}
        class="flex h-7 w-7 items-center justify-center rounded-full text-neutral-500 hover:bg-neutral-50"
      >
        <.icon name="hero-ellipsis-vertical" class="h-[18px] w-[18px]" />
      </button>
      <div
        id={@id}
        phx-click-away={JS.hide(to: "##{@id}")}
        class="absolute right-0 top-8 z-10 hidden w-40 flex-col rounded-xl border border-neutral-200 bg-surface py-1 shadow-q200 [&>*]:px-3 [&>*]:py-2 [&>*]:text-left [&>*]:text-sm hover:[&>*]:bg-neutral-50"
      >
        {render_slot(@item)}
      </div>
    </div>
    """
  end
end
