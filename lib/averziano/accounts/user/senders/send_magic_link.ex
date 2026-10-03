defmodule Averziano.Accounts.User.Senders.SendMagicLink do
  @moduledoc """
  Emails a magic link. The link opens a confirmation page whose button signs
  in, so email scanners that prefetch links can't spend the token.
  """

  use AshAuthentication.Sender
  use AverzianoWeb, :verified_routes

  alias Averziano.Accounts.Emails
  alias Averziano.Mailer

  @impl true
  def send(user_or_email, token, _opts) do
    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    {:ok, _} =
      email |> to_string() |> Emails.magic_link(url(~p"/sign-in/#{token}")) |> Mailer.deliver()

    :ok
  end
end
