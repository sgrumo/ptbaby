[
  import_deps: [:ash, :ash_postgres, :ash_phoenix, :ecto, :ecto_sql, :phoenix, :phoenix_live_view],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]
