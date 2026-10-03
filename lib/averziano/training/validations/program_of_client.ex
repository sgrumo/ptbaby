defmodule Averziano.Training.Validations.ProgramOfClient do
  @moduledoc "A note can only refer to a program of the same client."

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias Averziano.Training.Program

  @impl true
  def validate(changeset, _opts, _context) do
    program_id = Ash.Changeset.get_attribute(changeset, :program_id)
    client_id = Ash.Changeset.get_attribute(changeset, :client_id)

    if is_nil(program_id) or program_of?(program_id, client_id) do
      :ok
    else
      {:error,
       InvalidAttribute.exception(
         field: :program_id,
         message: "il programma non è di questo cliente"
       )}
    end
  end

  defp program_of?(program_id, client_id) do
    match?(
      {:ok, %Program{client_id: ^client_id}},
      Ash.get(Program, program_id, authorize?: false, error?: false)
    )
  end
end
