defmodule AverzianoWeb.Live.AuthHook do
  @moduledoc """
  Session-based LiveView auth. Assigns `:current_user_id` and an Ash `:actor`
  so LiveViews can pass `actor: socket.assigns.actor` to domain calls.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    case session do
      %{"current_user_id" => user_id} when is_binary(user_id) ->
        {:cont,
         socket
         |> assign(:current_user_id, user_id)
         |> assign(:actor, %{"sub" => user_id})}

      _ ->
        {:halt, redirect(socket, to: "/")}
    end
  end
end
