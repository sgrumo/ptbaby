defmodule AverzianoWeb.Live.CoachHook do
  @moduledoc """
  Restricts a live session to the coach. Runs after
  `AverzianoWeb.Live.AuthHook`; anyone else goes to the client app.
  """

  import Phoenix.LiveView

  alias Averziano.Accounts.User

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    case socket.assigns.current_user do
      %User{role: :coach} -> {:cont, socket}
      _ -> {:halt, redirect(socket, to: "/app")}
    end
  end
end
