import Config

config :averziano, Averziano.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "averziano_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :averziano, AverzianoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kkSsaLR2kZRrxV2xp0d7HHWxF/3Zk+ex0LtCGCSGu1LG8JWf+9rdajnx3Xm/kLZP",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:averziano, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:averziano, ~w(--watch)]}
  ]

config :averziano, dev_routes: true

config :ash, policies: [show_policy_breakdowns?: true]

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
