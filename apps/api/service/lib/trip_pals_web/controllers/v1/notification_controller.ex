defmodule TripPalsWeb.V1.NotificationController do
  use TripPalsWeb, :controller

  alias TripPals.Notifications
  alias TripPalsWeb.API.Response

  def index(conn, params) do
    case Notifications.list_notifications(actor_id(conn), params) do
      {:ok, page} ->
        Response.ok(conn, page)

      {:error, {:validation_failed, fields}} ->
        Response.error(conn, :validation_failed, "Validation failed", 422, fields)
    end
  end

  def preferences(conn, _params),
    do:
      Response.ok(
        conn,
        Notifications.preference_view(Notifications.get_preferences(actor_id(conn)))
      )

  def update_preferences(conn, params) do
    case Notifications.update_preferences(
           actor_id(conn),
           params,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, preference} -> Response.ok(conn, preference)
      error -> notification_error(conn, error)
    end
  end

  def mark_read(conn, %{"id" => notification_id} = params) do
    case Notifications.mark_read(
           actor_id(conn),
           notification_id,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, notification} ->
        Response.ok(conn, notification)

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested notification was not found", 404)

      error ->
        notification_error(conn, error)
    end
  end

  defp actor_id(conn), do: conn.assigns.current_actor.id

  defp request_hash(params) do
    params
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp notification_error(conn, {:error, :idempotency_key_reused}),
    do:
      Response.error(
        conn,
        :idempotency_key_reused,
        "This idempotency key was used for another request",
        409
      )

  defp notification_error(conn, {:error, :idempotency_in_progress}),
    do:
      Response.error(conn, :idempotency_in_progress, "This request is still being processed", 409)

  defp notification_error(conn, {:error, :idempotency_required}),
    do: Response.error(conn, :idempotency_required, "An idempotency key is required", 400)

  defp notification_error(conn, {:error, _reason}),
    do: Response.error(conn, :validation_failed, "Validation failed", 422)
end
