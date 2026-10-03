defmodule AverzianoWeb.Auth.SignInLive do
  @moduledoc """
  Sign-in page: asks for an email and sends a magic link to it. The answer is
  the same whether or not the address belongs to a user, so the page can't
  be used to find out who is registered.
  """

  use AverzianoWeb, :live_view

  alias AshAuthentication.{Info, Strategy}
  alias Averziano.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Accedi", sent_to: nil, form: to_form(%{"email" => ""}))}
  end

  @impl true
  def handle_event("request", %{"email" => email}, socket) do
    email = String.trim(email)

    # Unknown addresses succeed silently; only delivery problems surface.
    case User |> Info.strategy!(:magic_link) |> Strategy.action(:request, %{"email" => email}) do
      :ok ->
        {:noreply, assign(socket, :sent_to, email)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Non è stato possibile inviare il link. Riprova.")}
    end
  end

  def handle_event("again", _params, socket), do: {:noreply, assign(socket, :sent_to, nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 flex-col justify-center gap-8 px-6 py-12">
      <div class="flex flex-col gap-2">
        <span class="font-display text-[22px] font-semibold text-primary-600">Work Baby</span>
        <h1 class="font-display text-[28px] font-semibold leading-[34px]">Accedi</h1>
      </div>

      <div :if={@sent_to} id="link-sent" class="flex flex-col gap-4">
        <p class="text-[15px] leading-[22px]">
          Se <b>{@sent_to}</b>
          è registrato, ti abbiamo inviato un link per accedere. Controlla la posta: vale 10 minuti.
        </p>
        <button
          type="button"
          phx-click="again"
          class="self-start text-sm font-medium text-primary-600"
        >
          Usa un altro indirizzo
        </button>
      </div>

      <.form
        :if={!@sent_to}
        for={@form}
        id="sign-in-form"
        phx-submit="request"
        class="flex flex-col gap-4"
      >
        <div class="flex flex-col gap-1.5">
          <label for="sign-in-email" class="text-sm font-medium">Email</label>
          <.input
            field={@form[:email]}
            id="sign-in-email"
            type="email"
            required
            autocomplete="email"
            placeholder="nome@esempio.it"
            class="block h-12 w-full rounded-xl border border-neutral-200 px-4 text-[15px] focus:border-primary-500 focus:ring-0"
          />
        </div>
        <button
          type="submit"
          phx-disable-with="Invio…"
          class="flex h-12 items-center justify-center rounded-pill bg-primary-600 text-base font-semibold text-white hover:bg-primary-700"
        >
          Inviami il link
        </button>
        <p class="text-[13px] text-neutral-500">
          Non serve una password: ti mandiamo un link per entrare.
        </p>
      </.form>
    </div>
    """
  end
end
