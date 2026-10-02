defmodule AverzianoWeb.Health.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  @checks [
    %PlugCheckup.Check{
      name: "database",
      module: AverzianoWeb.Health.Checks,
      function: :database
    }
  ]

  forward("/",
    to: PlugCheckup,
    init_opts: PlugCheckup.Options.new(checks: @checks, json_encoder: Jason)
  )
end
