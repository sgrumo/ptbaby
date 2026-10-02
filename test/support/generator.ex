defmodule Averziano.Generator do
  @moduledoc """
  Test data generators built on `Ash.Generator`.

  Use `generate/1` and `generate_many/2` (imported with this module) to turn a
  generator into persisted records:

      user = generate(user(name: "Ada"))
      users = generate_many(user(), 3)

  Generators go through the resource's real actions with authorization
  disabled, so validations and defaults still apply.
  """

  use Ash.Generator

  alias Averziano.Accounts.User

  @spec user(keyword()) :: StreamData.t(Ash.Changeset.t())
  def user(opts \\ []) do
    changeset_generator(User, :register,
      defaults: [
        email: sequence(:user_email, &"user#{&1}@example.com"),
        name: "Test User"
      ],
      overrides: opts,
      authorize?: false
    )
  end
end
