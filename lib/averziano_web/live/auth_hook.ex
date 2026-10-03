defmodule AverzianoWeb.Live.AuthHook do
  @moduledoc """
  Requires a signed-in user in a LiveView. AshAuthentication's live session
  has already loaded `:current_user` from the session token; this assigns
  `:current_user_id` and the Ash `:actor` (the same claims shape as the API)
  so LiveViews pass `actor: socket.assigns.actor` to domain calls.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Averziano.Accounts.User

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      %User{id: user_id} ->
        {:cont,
         socket
         |> assign(:current_user_id, user_id)
         |> assign(:actor, %{"sub" => user_id})}

      nil ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end
end
