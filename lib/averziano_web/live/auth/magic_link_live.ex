defmodule AverzianoWeb.Auth.MagicLinkLive do
  @moduledoc """
  Where a magic link lands. Signing in takes a press of the button (a POST
  to the strategy), so link scanners that open emails can't spend the token.
  """

  use AverzianoWeb, :live_view

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok, assign(socket, page_title: "Accedi", token: token)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 flex-col justify-center gap-8 px-6 py-12">
      <div class="flex flex-col gap-2">
        <span class="font-display text-[22px] font-semibold text-primary-600">Work Baby</span>
        <h1 class="font-display text-[28px] font-semibold leading-[34px]">Ci sei quasi</h1>
        <p class="text-[15px] text-neutral-600">Premi il pulsante per entrare.</p>
      </div>
      <.form for={%{}} id="magic-link-form" action={~p"/auth/user/magic_link"} method="post">
        <input type="hidden" name="token" value={@token} />
        <button
          type="submit"
          class="flex h-12 w-full items-center justify-center rounded-pill bg-primary-600 text-base font-semibold text-white hover:bg-primary-700"
        >
          Accedi
        </button>
      </.form>
    </div>
    """
  end
end
