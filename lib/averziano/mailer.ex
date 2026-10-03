defmodule Averziano.Mailer do
  @moduledoc "Sends email: Brevo in production, the local mailbox in dev (`/dev/mailbox`)."

  use Swoosh.Mailer, otp_app: :averziano
end
