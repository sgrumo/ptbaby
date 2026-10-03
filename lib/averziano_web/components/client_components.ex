defmodule AverzianoWeb.ClientComponents do
  @moduledoc """
  Building blocks of the client (mobile) app, styled after the Quinck Design
  System "App cliente" screens.
  """

  use Phoenix.Component

  import AverzianoWeb.CoreComponents, only: [icon: 1]

  @doc "A row with a back chevron and a short context line, optionally a title below."
  attr :back, :string, required: true, doc: "path the chevron navigates to"
  attr :context, :string, required: true
  attr :title, :string, default: nil
  slot :action

  @spec top_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def top_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-4 py-2">
      <.link
        navigate={@back}
        aria-label="Indietro"
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full hover:bg-neutral-50"
      >
        <.icon name="hero-chevron-left" class="h-6 w-6" />
      </.link>
      <div :if={@title} class="flex min-w-0 flex-1 flex-col">
        <span class="truncate text-xs text-neutral-500">{@context}</span>
        <span class="truncate text-lg font-semibold leading-6">{@title}</span>
      </div>
      <span :if={!@title} class="flex-1 text-sm text-neutral-600">{@context}</span>
      {render_slot(@action)}
    </div>
    """
  end

  @doc "A small pill label."
  attr :tone, :atom,
    default: :neutral,
    values: [:neutral, :muted, :success, :brand, :brand_soft, :info, :warning, :danger]

  attr :class, :any, default: nil
  slot :inner_block, required: true

  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center whitespace-nowrap rounded-pill px-2.5 py-1 text-xs font-semibold",
      @tone == :neutral && "bg-neutral-50 text-neutral-600",
      @tone == :muted && "bg-neutral-100 text-neutral-600",
      @tone == :danger && "bg-danger-100 text-danger-800",
      @tone == :success && "bg-success-100 text-success-800",
      @tone == :brand && "bg-primary-600 text-white",
      @tone == :brand_soft && "bg-primary-100 text-primary-800",
      @tone == :info && "bg-info-100 text-info-800",
      @tone == :warning && "bg-warning-100 text-warning-800",
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc "A note from the coach, on the brand-soft background."
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  @spec coach_note(map()) :: Phoenix.LiveView.Rendered.t()
  def coach_note(assigns) do
    ~H"""
    <div class={[
      "flex gap-2.5 rounded-xl bg-primary-100 px-4 py-3.5 text-sm text-primary-800",
      @class
    ]}>
      <.icon name="hero-chat-bubble-bottom-center-text" class="h-[18px] w-[18px] shrink-0" />
      <div class="flex flex-col gap-0.5">
        <span :if={@title} class="font-semibold">{@title}</span>
        <span>{render_slot(@inner_block)}</span>
      </div>
    </div>
    """
  end

  @doc "A logged (green) or upcoming (grey) set in the workout timeline."
  attr :number, :integer, required: true
  attr :done, :boolean, required: true
  attr :label, :string, required: true

  @spec set_row(map()) :: Phoenix.LiveView.Rendered.t()
  def set_row(assigns) do
    ~H"""
    <div
      id={"set-#{@number}"}
      class={[
        "flex h-[52px] items-center gap-3 rounded-xl px-4 text-sm",
        @done && "bg-success-100 text-success-800",
        !@done && "border border-neutral-100 text-neutral-500"
      ]}
    >
      <span
        :if={@done}
        class="flex h-6 w-6 items-center justify-center rounded-full bg-success-600 text-white"
      >
        <.icon name="hero-check-mini" class="h-4 w-4" />
      </span>
      <span :if={!@done} class="h-6 w-6 rounded-full border-[1.5px] border-neutral-300"></span>
      <span class="w-14 font-semibold">Serie {@number}</span>
      <span>{@label}</span>
    </div>
    """
  end

  @doc "A round +/- button that pushes `inc`/`dec` for a field of the set draft."
  attr :event, :string, required: true, values: ["inc", "dec"]
  attr :field, :string, required: true
  attr :label, :string, required: true

  @spec step_button(map()) :: Phoenix.LiveView.Rendered.t()
  def step_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-field={@field}
      aria-label={@label}
      class="flex h-11 w-11 items-center justify-center rounded-full border border-neutral-200 bg-white active:bg-neutral-50"
    >
      <.icon name={if @event == "inc", do: "hero-plus", else: "hero-minus"} class="h-5 w-5" />
    </button>
    """
  end

  @doc "A big number with its label and +/- buttons underneath."
  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, required: true

  @spec stepper(map()) :: Phoenix.LiveView.Rendered.t()
  def stepper(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 rounded-xl bg-neutral-50 p-3">
      <span class="text-xs text-neutral-600">{@label}</span>
      <span id={"draft-#{@field}"} class="font-display text-[44px] font-semibold leading-[48px]">
        {@value}
      </span>
      <div class="flex gap-2">
        <.step_button event="dec" field={@field} label={"Diminuisci #{String.downcase(@label)}"} />
        <.step_button event="inc" field={@field} label={"Aumenta #{String.downcase(@label)}"} />
      </div>
    </div>
    """
  end

  @doc "Full-width primary action (a button, or a link when `navigate` is given)."
  attr :navigate, :string, default: nil
  attr :icon, :string, default: nil
  attr :variant, :atom, default: :primary, values: [:primary, :outline, :inverse]
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(type disabled form)
  slot :inner_block, required: true

  @spec action_button(map()) :: Phoenix.LiveView.Rendered.t()
  def action_button(assigns) do
    assigns =
      assign(assigns, :classes, [
        "flex h-14 w-full items-center justify-center gap-2 rounded-pill text-base font-semibold transition",
        assigns.variant == :primary &&
          "bg-primary-600 text-white hover:bg-primary-700 active:bg-primary-800",
        assigns.variant == :outline && "border border-neutral-200 bg-white hover:bg-neutral-50",
        assigns.variant == :inverse && "bg-white text-primary-600 hover:bg-primary-100",
        assigns.class
      ])

    ~H"""
    <.link :if={@navigate} navigate={@navigate} class={@classes} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-5 w-5" />{render_slot(@inner_block)}
    </.link>
    <button :if={!@navigate} class={@classes} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-5 w-5" />{render_slot(@inner_block)}
    </button>
    """
  end
end
