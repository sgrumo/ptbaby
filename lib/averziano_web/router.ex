defmodule AverzianoWeb.Router do
  use AverzianoWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AverzianoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug AverzianoWeb.Plugs.Auth
  end

  # Health & Metrics
  forward("/health", AverzianoWeb.Health.Router)

  # Public API
  scope "/api", AverzianoWeb do
    pipe_through :api
  end

  # Authenticated API
  scope "/api", AverzianoWeb do
    pipe_through [:api, :authenticated]

    resources "/users", UserController, except: [:new, :edit]
  end

  # Admin (browser + LiveView)
  scope "/admin", AverzianoWeb do
    pipe_through :browser

    live_session :admin, on_mount: [AverzianoWeb.Live.AuthHook] do
      # Admin LiveViews go here
    end
  end

  # Metrics dashboard (telemetry_ui)
  if Application.compile_env(:averziano, :dev_routes) do
    scope "/dev" do
      pipe_through :browser
    end
  end
end
