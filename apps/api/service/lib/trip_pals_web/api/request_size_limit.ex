defmodule TripPalsWeb.API.RequestSizeLimit do
  @moduledoc false

  import Plug.Conn

  alias TripPalsWeb.API.Response

  def init(options), do: Keyword.fetch!(options, :max_bytes)

  def call(conn, max_bytes) do
    case get_req_header(conn, "content-length") do
      [value | _] -> enforce(conn, value, max_bytes)
      [] -> conn
    end
  end

  defp enforce(conn, value, max_bytes) do
    case Integer.parse(value) do
      {length, ""} when length > max_bytes ->
        conn
        |> Response.error(:payload_too_large, "Request payload is too large", 413)
        |> halt()

      _ ->
        conn
    end
  end
end
