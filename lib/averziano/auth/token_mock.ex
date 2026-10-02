defmodule Averziano.Auth.TokenMock do
  @moduledoc false

  @spec verify_token(String.t()) :: {:ok, map()} | {:error, :unauthorized}
  def verify_token("valid_token"), do: {:ok, %{"sub" => "test-user-id"}}
  def verify_token(_token), do: {:error, :unauthorized}
end
