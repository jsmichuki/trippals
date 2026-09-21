defmodule TripPalsWeb.API.OptimisticConcurrency do
  @moduledoc false

  import Plug.Conn
  alias TripPalsWeb.API.Response

  def init(options), do: options

  def call(conn, _options) do
    case get_req_header(conn, "if-match") do
      [version] -> assign(conn, :expected_version, String.trim(version, "\""))
      _ -> conn |> Response.error(:if_match_required, "If-Match is required", 400) |> halt()
    end
  end
end
