defmodule TripPalsWeb.API.CorrelationId do
  @moduledoc false

  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    correlation_id =
      conn
      |> get_req_header("x-request-id")
      |> List.first()
      |> Kernel.||(response_request_id(conn))
      |> Kernel.||(request_id(conn))

    Logger.metadata(correlation_id: correlation_id)

    conn
    |> assign(:correlation_id, correlation_id)
    |> put_resp_header("x-correlation-id", correlation_id)
  end

  defp request_id(_conn), do: Ecto.UUID.generate()

  defp response_request_id(conn), do: conn |> get_resp_header("x-request-id") |> List.first()
end
