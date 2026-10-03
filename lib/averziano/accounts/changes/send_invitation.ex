defmodule Averziano.Accounts.Changes.SendInvitation do
  @moduledoc """
  After a client is invited, emails them a link to the sign-in page. If the
  email can't be sent the invitation is rolled back, so the coach knows.
  """

  use Ash.Resource.Change
  use AverzianoWeb, :verified_routes

  alias Averziano.Accounts.{Emails, User}
  alias Averziano.Mailer

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, client ->
      coach_name = coach_name(context.actor)

      email =
        Emails.invitation(to_string(client.email), client.name, coach_name, url(~p"/sign-in"))

      case Mailer.deliver(email) do
        {:ok, _} ->
          {:ok, client}

        {:error, _reason} ->
          {:error,
           Ash.Error.Changes.InvalidAttribute.exception(
             field: :email,
             message: "impossibile inviare l'invito a questo indirizzo"
           )}
      end
    end)
  end

  defp coach_name(%{"sub" => coach_id}) do
    case Ash.get(User, coach_id, authorize?: false, error?: false) do
      {:ok, %User{name: name}} -> name
      _ -> "Il tuo coach"
    end
  end

  defp coach_name(_actor), do: "Il tuo coach"
end
