defmodule TripPalsWeb.API.CORS do
  @moduledoc false

  import Plug.Conn

  alias TripPalsWeb.API.Response

  @methods "GET, POST, PATCH, PUT, DELETE, OPTIONS"
  @headers "authorization, content-type, idempotency-key, if-match, x-device-id, x-request-id"

  def init(options), do: Keyword.fetch!(options, :origins)

  def call(conn, origins) do
    case get_req_header(conn, "origin") do
      [origin | _] -> handle_origin(conn, origin, origins)
      _ -> conn
    end
  end

  defp handle_origin(conn, origin, origins) do
    cond do
      origin in origins ->
        allow(conn, origin)

      conn.method == "OPTIONS" ->
        conn |> Response.error(:cors_origin_forbidden, "Origin is not permitted", 403) |> halt()

      true ->
        conn
    end
  end

  defp allow(conn, origin) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", @methods)
      |> put_resp_header("access-control-allow-headers", @headers)
      |> merge_resp_headers([{"vary", "origin"}])

    if conn.method == "OPTIONS" do
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end
end
