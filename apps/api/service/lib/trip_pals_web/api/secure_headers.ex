defmodule TripPalsWeb.API.SecureHeaders do
  @moduledoc false

  import Plug.Conn

  @headers [
    {"x-content-type-options", "nosniff"},
    {"x-frame-options", "DENY"},
    {"referrer-policy", "no-referrer"},
    {"permissions-policy", "geolocation=(), microphone=(), camera=()"},
    {"cache-control", "no-store"}
  ]

  def init(options), do: options

  def call(conn, _options) do
    Enum.reduce(@headers, conn, fn {key, value}, acc -> put_resp_header(acc, key, value) end)
  end
end
