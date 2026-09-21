defmodule TripPalsWeb.V1.AccountDeletionController do
  use TripPalsWeb, :controller

  alias TripPals.AccountDeletion
  alias TripPalsWeb.API.Response

  # The router intentionally owns the authenticated/state-changing pipeline.
  # Integrate this action at DELETE /v1/me (or a dedicated deletion resource)
  # only behind :member and :state_changing.
  def request(conn, _params) do
    actor = conn.assigns.current_actor

    case AccountDeletion.request(actor.id, actor.session_id) do
      {:ok, deletion} ->
        Response.ok(conn, Map.delete(deletion, :user_id), 202)

      {:error, :recent_auth_required} ->
        Response.error(conn, :recent_auth_required, "Recent authentication is required", 403)

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested resource was not found", 404)

      {:error, _reason} ->
        Response.error(
          conn,
          :account_deletion_unavailable,
          "The account deletion request could not be completed",
          422
        )
    end
  end

  def show(conn, _params) do
    case AccountDeletion.get(conn.assigns.current_actor.id) do
      {:ok, deletion} ->
        Response.ok(conn, deletion)

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested resource was not found", 404)
    end
  end
end
