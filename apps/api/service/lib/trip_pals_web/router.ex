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
      get "/me/plans", ParticipationController, :plans
      get "/conversations/:id/messages", ConversationController, :messages
      get "/me/invitation-settings", InvitationController, :settings
      get "/me/availabilities", InvitationController, :availabilities
      get "/me/invitations", InvitationController, :inbox
      get "/invitations/:id", InvitationController, :show
      get "/activities/:id/invitation-candidates", InvitationController, :candidates
      get "/me/restrictions", SafetyController, :restrictions
      get "/notifications", NotificationController, :index
      get "/me/notification-preferences", NotificationController, :preferences
      get "/media/:id/access", MediaController, :access
      get "/media/:id/content", MediaController, :content
    end

    scope "/" do
      pipe_through [:member, :state_changing]

      post "/activities", ActivityController, :create
      post "/activities/:id/publish", ActivityController, :publish
      post "/activities/:id/confirm", ActivityController, :confirm
      post "/activities/:id/start", ActivityController, :start
      post "/activities/:id/finish", ActivityController, :finish
      post "/activities/:id/cancel", ActivityController, :cancel
      post "/activities/:id/interest", ParticipationController, :interest
      post "/activities/:id/join", ParticipationController, :join
      post "/activities/:id/leave", ParticipationController, :leave
      post "/activities/:id/reconfirm", ParticipationController, :reconfirm
      post "/activities/:id/attendance", ParticipationController, :attendance
      post "/conversations/:id/messages", ConversationController, :create_message
      patch "/me/invitation-settings", InvitationController, :update_settings
      post "/me/availabilities", InvitationController, :create_availability
      patch "/me/availabilities/:id", InvitationController, :update_availability
      delete "/me/availabilities/:id", InvitationController, :delete_availability
      post "/activities/:id/invitations", InvitationController, :send
      post "/invitations/:id/decline", InvitationController, :decline
      post "/reports", SafetyController, :create_report
      post "/blocks/:user_id", SafetyController, :block
      delete "/blocks/:user_id", SafetyController, :unblock
      post "/appeals", SafetyController, :create_appeal
      patch "/me/notification-preferences", NotificationController, :update_preferences
      post "/devices", DeviceController, :create
      delete "/devices/:id", DeviceController, :delete
      patch "/notifications/:id/read", NotificationController, :mark_read
      post "/media/avatar/upload-intents", MediaController, :avatar_intent
      post "/reports/:report_id/evidence/upload-intents", MediaController, :report_evidence_intent
      post "/media/:id/upload", MediaController, :upload
      post "/media/:id/confirm", MediaController, :confirm
      delete "/auth/session", AuthController, :delete_session
      patch "/me", MeController, :update
      delete "/me/passkeys/:credential_id", MeController, :delete_passkey
      delete "/me", AccountDeletionController, :request
      delete "/me/identities/:provider", IdentityController, :unlink
      post "/auth/passkeys/register/options", PasskeyController, :register_options
      post "/auth/passkeys/register/complete", PasskeyController, :register_complete
    end

    scope "/" do
      pipe_through [:member, :state_changing, :activity_mutation]

      patch "/activities/:id", ActivityController, :update
    end

    scope "/admin" do
      pipe_through [:moderator]

      get "/moderation/cases", AdminSafetyController, :case_queue
    end

    scope "/admin" do
      pipe_through [:moderator, :state_changing]

      post "/moderation/cases/:case_id/assign", AdminSafetyController, :assign_case
      post "/moderation/restrictions/:user_id", AdminSafetyController, :impose_restriction
      post "/moderation/appeals/:appeal_id/review", AdminSafetyController, :review_appeal
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
