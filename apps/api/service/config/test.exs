import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :trip_pals, TripPals.Repo,
  url: System.fetch_env!("TEST_DATABASE_URL"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :trip_pals, TripPalsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("t", 64),
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :trip_pals, :api,
  max_body_bytes: 1_024,
  cors_origins: ["https://app.example.test"]

config :trip_pals, :integrations,
  webauthn: [rp_id: "example.test", origins: ["https://app.example.test"]]

config :trip_pals, :push_token_encryption_key, String.duplicate("t", 32)

config :trip_pals, Oban, testing: :manual

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
