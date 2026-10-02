defmodule Averziano.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AverzianoWeb.Telemetry,
        Averziano.Repo,
        telemetry_ui_child(),
        {DNSCluster, query: Application.get_env(:averziano, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Averziano.PubSub},
        {Registry, keys: :unique, name: Averziano.Registry},
        {DynamicSupervisor, name: Averziano.DynamicSupervisor, strategy: :one_for_one},
        AverzianoWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Averziano.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AverzianoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp telemetry_ui_child do
    if Application.get_env(:averziano, :telemetry_ui_enabled, false) do
      {TelemetryUI, telemetry_ui_config()}
    end
  end

  defp telemetry_ui_config do
    [
      metrics: AverzianoWeb.Telemetry.metrics(),
      theme: %{title: "Averziano Metrics"},
      backend: %TelemetryUI.Backend.EctoPostgres{repo: Averziano.Repo}
    ]
  end
end
