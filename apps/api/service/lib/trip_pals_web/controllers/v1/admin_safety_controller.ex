defmodule TripPalsWeb.V1.AdminSafetyController do
  use TripPalsWeb, :controller

  alias TripPals.TrustSafety
  alias TripPalsWeb.API.Response

  def case_queue(conn, params) do
    case TrustSafety.staff_case_queue(conn.assigns.current_actor.id, params) do
      {:ok, cases} ->
        Response.ok(conn, %{cases: cases})

      {:error, :forbidden} ->
        Response.error(conn, :forbidden, "You do not have permission for this action", 403)
    end
  end

  def assign_case(conn, %{"case_id" => case_id, "reason" => reason}) do
    respond(conn, TrustSafety.assign_case(conn.assigns.current_actor.id, case_id, reason))
  end

  def impose_restriction(conn, %{"user_id" => user_id} = params) do
    respond(conn, TrustSafety.impose_restriction(conn.assigns.current_actor.id, user_id, params))
  end

  def review_appeal(conn, %{"appeal_id" => appeal_id, "decision" => decision, "reason" => reason}) do
    respond(
      conn,
      TrustSafety.review_appeal(conn.assigns.current_actor.id, appeal_id, decision, reason)
    )
  end

  defp respond(conn, {:ok, data}), do: Response.ok(conn, data)

  defp respond(conn, {:error, :forbidden}),
    do: Response.error(conn, :forbidden, "You do not have permission for this action", 403)

  defp respond(conn, {:error, :not_found}),
    do: Response.error(conn, :not_found, "The requested resource was not found", 404)

  defp respond(conn, {:error, :reason_required}),
    do: Response.error(conn, :reason_required, "A reason is required", 422)

  defp respond(conn, {:error, _}),
    do: Response.error(conn, :moderation_action_failed, "The action could not be completed", 422)
end
