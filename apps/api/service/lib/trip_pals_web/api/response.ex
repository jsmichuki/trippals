defmodule TripPalsWeb.API.Response do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @type error_code :: atom() | String.t()

  def ok(conn, data, status \\ 200) do
    conn
    |> put_status(status)
    |> json(%{data: data, meta: metadata(conn)})
  end

  def error(conn, code, message, status, field_errors \\ nil, current \\ nil) do
    error = %{code: to_string(code), message: message}
    error = if field_errors in [nil, %{}], do: error, else: Map.put(error, :fields, field_errors)
    error = if is_nil(current), do: error, else: Map.put(error, :current, current)

    conn
    |> put_status(status)
    |> json(%{error: error, meta: metadata(conn)})
  end

  def metadata(conn) do
    %{correlation_id: conn.assigns[:correlation_id] || request_id(conn)}
  end

  defp request_id(conn) do
    conn
    |> get_resp_header("x-request-id")
    |> List.first()
  end
end
