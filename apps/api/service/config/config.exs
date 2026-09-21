# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :trip_pals,
  ecto_repos: [TripPals.Repo],
  generators: [timestamp_type: :utc_datetime],
  api: [
    max_body_bytes: 1_000_000,
    cors_origins: []
  ],
  integrations: [
    google_oauth: [client_id: nil, audience: nil],
    apple_oauth: [client_id: nil, audience: nil],
    webauthn: [rp_id: nil, origins: []],
    push: [provider: nil],
    object_storage: [provider: nil],
    analytics: [provider: nil]
  ],
  feature_flags: [invitation_matching_city_ids: []]

config :trip_pals, Oban,
  repo: TripPals.Repo,
  queues: [notifications: 10, lifecycle: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86_400},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/1 * * * *", TripPals.Workers.OutboxDispatch},
       {"*/15 * * * *", TripPals.Workers.HostConfirmationReminder},
       {"0 * * * *", TripPals.Workers.AttendanceReminder},
       {"*/15 * * * *", TripPals.Workers.ActivityLifecycleSweep},
       {"*/15 * * * *", TripPals.Workers.InvitationLifecycleSweep},
       {"0 * * * *", TripPals.Workers.ConversationRetentionSweep},
       {"0 * * * *", TripPals.Workers.MediaCleanup}
     ]}
  ]

# Configure the endpoint
config :trip_pals, TripPalsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TripPalsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TripPals.PubSub,
  live_view: [signing_salt: "A3tt5L0L"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :correlation_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Phoenix request telemetry is the only request logger in this release. Keep
# credential-bearing fields out of it even if a controller accidentally logs
# its params in the future. Analytics and push integrations receive no request
# payloads in the API process.
config :phoenix, :filter_parameters, [
  "access_token",
  "refresh_token",
  "identity_token",
  "authorization",
  "assertion",
  "attestation",
  "authenticator_data",
  "signature",
  "client_data_json",
  "biometric",
  "upload_token",
  "content_base64",
  "x-media-access-token"
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
