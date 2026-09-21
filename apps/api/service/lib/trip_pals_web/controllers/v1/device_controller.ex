defmodule TripPalsWeb.V1.DeviceController do
  use TripPalsWeb, :controller

  alias TripPals.Notifications
  alias TripPalsWeb.API.Response

  def create(conn, params) do
    case Notifications.register_device(
           actor_id(conn),
           params,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, device} ->
        Response.ok(conn, device, 201)

      {:error, :invalid_device} ->
        Response.error(conn, :invalid_device, "The device registration is invalid", 422)

      {:error, :idempotency_key_reused} ->
        Response.error(
          conn,
          :idempotency_key_reused,
          "This idempotency key was used for another request",
          409
        )

      {:error, :idempotency_in_progress} ->
        Response.error(
          conn,
          :idempotency_in_progress,
          "This request is still being processed",
          409
        )

      {:error, :idempotency_required} ->
        Response.error(conn, :idempotency_required, "An idempotency key is required", 400)

      {:error, _reason} ->
        Response.error(
          conn,
          :device_registration_failed,
          "The device could not be registered",
          422
        )
    end
  end

  def delete(conn, %{"id" => device_id}) do
    case Notifications.invalidate_device(device_id, actor_id(conn)) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested device was not found", 404)
    end
  end

  defp actor_id(conn), do: conn.assigns.current_actor.id

  defp request_hash(params) do
    params
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
