defmodule TripPalsWeb.API.RateLimit do
  @moduledoc """
  Builds a privacy-safe key from actor, IP, device, operation and target.
  Durable policy enforcement is delegated to the RateLimits context.
  """
  import Plug.Conn

  def init(options), do: Keyword.fetch!(options, :operation)

  def call(conn, operation) do
    actor = get_in(conn.assigns, [:current_actor, :id]) || "anonymous"
    device = get_req_header(conn, "x-device-id") |> List.first() || "unknown-device"
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    target = Map.get(conn.path_params || %{}, "id") || conn.request_path
    material = Enum.join([to_string(actor), ip, device, operation, target], ":")
    assign(conn, :rate_limit_key, :crypto.hash(:sha256, material) |> Base.encode16(case: :lower))
  end
end
