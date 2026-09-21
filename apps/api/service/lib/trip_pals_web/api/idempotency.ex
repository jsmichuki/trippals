defmodule TripPalsWeb.API.Idempotency do
  @moduledoc false

  import Plug.Conn
  alias TripPalsWeb.API.Response

  def init(options), do: options

  def call(conn, _options) do
    case get_req_header(conn, "idempotency-key") do
      [key] when byte_size(key) in 1..255 ->
        assign(conn, :idempotency_key, key)

      _ ->
        conn
        |> Response.error(:idempotency_key_required, "Idempotency-Key is required", 400)
        |> halt()
    end
  end
end
