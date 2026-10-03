defmodule Averziano.Accounts.Changes.FullName do
  @moduledoc "Sets `name` from the `first_name` and `last_name` arguments."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    name =
      [:first_name, :last_name]
      |> Enum.map(&(changeset |> Ash.Changeset.get_argument(&1) |> to_string() |> String.trim()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    Ash.Changeset.force_change_attribute(changeset, :name, name)
  end
end
