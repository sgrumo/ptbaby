defmodule AverzianoWeb.Router do
  use AverzianoWeb, :router
  use AshAuthentication.Phoenix.Router

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
    plug :load_from_session
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

  # Sign-in (magic link) and sign-out
  scope "/", AverzianoWeb do
    pipe_through :browser

    get "/", AuthController, :home
    auth_routes(AuthController, Averziano.Accounts.User, path: "/auth")
    delete "/sign-out", AuthController, :sign_out

    live_session :sign_in, layout: {AverzianoWeb.Layouts, :client} do
      live "/sign-in", Auth.SignInLive
      live "/sign-in/:token", Auth.MagicLinkLive
    end
  end

  # Client app (browser + LiveView, mobile)
  scope "/app", AverzianoWeb.Client do
    pipe_through :browser

    ash_authentication_live_session :client,
      on_mount: [AverzianoWeb.Live.AuthHook],
      layout: {AverzianoWeb.Layouts, :client} do
      live "/", ProgramLive
      live "/sessions/:session_id", SessionLive
      live "/sessions/:session_id/exercises/:exercise_id", WorkoutLive
      live "/sessions/:session_id/exercises/:exercise_id/info", ExerciseLive
      live "/sessions/:session_id/done", SessionDoneLive
    end
  end

  # Coach console (browser + LiveView, desktop)
  scope "/admin", AverzianoWeb.Admin do
    pipe_through :browser

    ash_authentication_live_session :admin,
      on_mount: [AverzianoWeb.Live.AuthHook, AverzianoWeb.Live.CoachHook],
      layout: {AverzianoWeb.Layouts, :admin} do
      live "/", ClientsLive, :index
      live "/clients/new", ClientsLive, :invite
      live "/clients/:client_id", ClientLive, :show
      live "/clients/:client_id/edit", ClientLive, :edit
      live "/programs", ProgramsLive
      live "/programs/:id/edit", PlanEditorLive, :program
      live "/templates", TemplatesLive
      live "/templates/:id/edit", PlanEditorLive, :template
    end
  end

  # Development only: sign in without email, and read sent emails.
  if Application.compile_env(:averziano, :dev_routes) do
    scope "/dev", AverzianoWeb do
      pipe_through :browser

      get "/sign-in/:user_id", DevSessionController, :create
    end

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
