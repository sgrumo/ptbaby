import Config

config :averziano, Averziano.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "averziano_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :averziano, AverzianoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "EVEX4cfEOFNvRIZ20m+9b+NWkfb6vzDcAUukWY1TS6LEwuWcTLCDfu4wqcn1hZLs",
  server: false

config :averziano, token_verifier: Averziano.Auth.TokenMock

config :ash,
  disable_async?: true,
  policies: [show_policy_breakdowns?: true]

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix,
  sort_verified_routes_query_params: true
