defmodule AverzianoWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import AverzianoWeb.ChannelCase

      @endpoint AverzianoWeb.Endpoint
    end
  end

  setup tags do
    Averziano.DataCase.setup_sandbox(tags)
    :ok
  end
end
