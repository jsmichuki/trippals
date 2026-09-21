import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/trip_pals start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :trip_pals, TripPalsWeb.Endpoint, server: true
end

config :trip_pals, TripPalsWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() in [:prod, :staging] do
  push_token_encryption_key =
    System.get_env("PUSH_TOKEN_ENCRYPTION_KEY") ||
      raise "environment variable PUSH_TOKEN_ENCRYPTION_KEY is missing"

  if byte_size(push_token_encryption_key) != 32 do
    raise "PUSH_TOKEN_ENCRYPTION_KEY must be exactly 32 bytes"
  end

  config :trip_pals, :push_token_encryption_key, push_token_encryption_key

  max_body_bytes =
    case System.get_env("API_MAX_BODY_BYTES") do
      nil ->
        1_000_000

      value ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> raise "environment variable API_MAX_BODY_BYTES must be a positive integer"
        end
    end

  cors_origins =
    System.get_env("CORS_ORIGINS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  config :trip_pals, :api,
    max_body_bytes: max_body_bytes,
    cors_origins: cors_origins

  config :trip_pals, :integrations,
    google_oauth: [
      client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
      audience: System.get_env("GOOGLE_OAUTH_AUDIENCE")
    ],
    apple_oauth: [
      client_id: System.get_env("APPLE_OAUTH_CLIENT_ID"),
      audience: System.get_env("APPLE_OAUTH_AUDIENCE")
    ],
    webauthn: [
      rp_id: System.get_env("WEBAUTHN_RP_ID"),
      origins:
        System.get_env("WEBAUTHN_ORIGINS", "")
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    ],
    push: [provider: System.get_env("PUSH_PROVIDER")],
    object_storage: [provider: System.get_env("OBJECT_STORAGE_PROVIDER")],
    analytics: [provider: System.get_env("ANALYTICS_PROVIDER")]
end

if config_env() in [:prod, :staging] do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :trip_pals, TripPals.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :trip_pals, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :trip_pals, TripPalsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :trip_pals, TripPalsWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :trip_pals, TripPalsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
