defmodule TripPalsWeb.Router do
  use TripPalsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug TripPalsWeb.API.CorrelationId

    plug TripPalsWeb.API.RequestSizeLimit,
      max_bytes: Application.compile_env(:trip_pals, [:api, :max_body_bytes], 1_000_000)

    plug TripPalsWeb.API.SecureHeaders

    plug TripPalsWeb.API.CORS,
      origins: Application.compile_env(:trip_pals, [:api, :cors_origins], [])

    plug TripPalsWeb.API.CurrentActor
  end

  pipeline :member do
    plug TripPalsWeb.API.Authorize, :authenticated
  end

  pipeline :state_changing do
    plug TripPalsWeb.API.Idempotency
    plug TripPalsWeb.API.RateLimit, operation: "mutation"
  end

  pipeline :activity_mutation do
    plug TripPalsWeb.API.OptimisticConcurrency
  end

  pipeline :host do
    plug TripPalsWeb.API.Authorize, :host
  end

  pipeline :moderator do
    plug TripPalsWeb.API.Authorize, :moderator
  end

  pipeline :administrator do
    plug TripPalsWeb.API.Authorize, :administrator
  end

  pipeline :browser_admin do
    plug :fetch_session
    plug TripPalsWeb.API.CorrelationId
    plug TripPalsWeb.API.SecureHeaders
    plug TripPalsWeb.API.CurrentActor
    plug TripPalsWeb.API.Authorize, :administrator
  end

  scope "/v1", TripPalsWeb.V1, as: :v1 do
    pipe_through :api

    get "/hello", HelloController, :show
    get "/cities", CityController, :index
    get "/activities", ActivityController, :index
    get "/activities/:id", ActivityController, :show
    get "/activity-ideas", ActivityIdeaController, :index

    scope "/" do
      pipe_through [:state_changing]

      post "/auth/refresh", AuthController, :refresh
      post "/auth/logout", AuthController, :logout
      post "/auth/passkeys/authenticate/options", PasskeyController, :authenticate_options
      post "/auth/passkeys/authenticate/complete", PasskeyController, :authenticate_complete
      post "/auth/:provider/complete", ProviderAuthController, :complete
    end

    scope "/" do
      pipe_through [:member]

      get "/me", MeController, :show
    end

    scope "/" do
      pipe_through [:member, :state_changing]

      post "/activities", ActivityController, :create
      post "/activities/:id/publish", ActivityController, :publish
      post "/activities/:id/confirm", ActivityController, :confirm
      post "/activities/:id/start", ActivityController, :start
      post "/activities/:id/finish", ActivityController, :finish
      post "/activities/:id/cancel", ActivityController, :cancel
      delete "/auth/session", AuthController, :delete_session
      patch "/me", MeController, :update
      delete "/me/passkeys/:credential_id", MeController, :delete_passkey
      delete "/me/identities/:provider", IdentityController, :unlink
      post "/auth/passkeys/register/options", PasskeyController, :register_options
      post "/auth/passkeys/register/complete", PasskeyController, :register_complete
    end

    scope "/" do
      pipe_through [:member, :state_changing, :activity_mutation]

      patch "/activities/:id", ActivityController, :update
    end

    options "/*path", PreflightController, :show
    get "/*path", NotFoundController, :show
    post "/*path", NotFoundController, :show
    patch "/*path", NotFoundController, :show
    put "/*path", NotFoundController, :show
    delete "/*path", NotFoundController, :show
  end

  scope "/", TripPalsWeb do
    pipe_through :api

    get "/up", HealthController, :show
    get "/ready", ReadinessController, :show
    options "/*path", PreflightController, :show
    get "/*path", NotFoundController, :show
    post "/*path", NotFoundController, :show
    patch "/*path", NotFoundController, :show
    put "/*path", NotFoundController, :show
    delete "/*path", NotFoundController, :show
  end
end
