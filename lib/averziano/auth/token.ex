defmodule Averziano.Auth.Token do
  @moduledoc false

  use Joken.Config

  @spec verify_token(String.t()) :: {:ok, map()} | {:error, :unauthorized}
  def verify_token(token) do
    case verify_and_validate(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, _reason} -> {:error, :unauthorized}
    end
  end
end
