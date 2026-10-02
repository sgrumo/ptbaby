defmodule Averziano.Repo do
  use AshPostgres.Repo, otp_app: :averziano

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions", "citext"]
  end

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  # Single-tenant application. Return the tenant list here if you enable
  # schema-based multitenancy on a resource.
  @impl true
  def all_tenants, do: []
end
