defmodule AverzianoWeb.Live.CoachHook do
  @moduledoc """
  Restricts a live session to coaches. Runs after `AverzianoWeb.Live.AuthHook`
  and assigns the coach as `:current_user`; anyone else goes to the client app.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Averziano.Accounts
  alias Averziano.Accounts.User

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    %{current_user_id: user_id, actor: actor} = socket.assigns

    case Accounts.get_user(user_id, actor: actor) do
      {:ok, %User{role: :coach} = coach} -> {:cont, assign(socket, :current_user, coach)}
      _ -> {:halt, redirect(socket, to: "/app")}
    end
  end
end
