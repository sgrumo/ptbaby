defmodule Averziano.Training.Validations.Unset do
  @moduledoc """
  Fails when `attribute` is already set on the stored record, e.g. a session
  that is already completed. Unlike `attribute_equals(attr, nil)`, the atomic
  form uses `is_nil/1`, so it also holds against the stored row, not only the
  in-memory record.

      validate {Unset, attribute: :completed_at, message: "già completata"}
  """

  use Ash.Resource.Validation

  import Ash.Expr

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]) and is_binary(opts[:message]),
      do: {:ok, opts},
      else: {:error, "expected `attribute` (atom) and `message` (string)"}
  end

  @impl true
  def validate(changeset, opts, _context) do
    case Ash.Changeset.get_data(changeset, opts[:attribute]) do
      nil ->
        :ok

      _value ->
        {:error, InvalidAttribute.exception(field: opts[:attribute], message: opts[:message])}
    end
  end

  @impl true
  def atomic(_changeset, opts, _context) do
    attribute = opts[:attribute]

    {:atomic, [attribute], expr(not is_nil(^atomic_ref(attribute))),
     expr(error(^InvalidAttribute, %{field: ^attribute, message: ^opts[:message]}))}
  end
end
