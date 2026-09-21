defmodule TripPalsWeb.V1.ParticipationController do
  use TripPalsWeb, :controller

  alias TripPals.Participation
  alias TripPalsWeb.API.Response

  def interest(conn, %{"id" => activity_id} = params),
    do: command(conn, activity_id, params, &Participation.interest/4)

  def join(conn, %{"id" => activity_id} = params),
    do: command(conn, activity_id, params, &Participation.join/4)

  def leave(conn, %{"id" => activity_id} = params),
    do: command(conn, activity_id, params, &Participation.leave/4)

  def reconfirm(conn, %{"id" => activity_id, "answer" => "yes"} = params) do
    case Participation.reconfirm(
           activity_id,
           conn.assigns.current_actor.id,
           true,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, result} -> Response.ok(conn, result)
      error -> participation_error(conn, error)
    end
  end

  def reconfirm(conn, _params),
    do: Response.error(conn, :invalid_reconfirmation, "Choose yes or leave the activity", 422)

  def attendance(conn, %{"id" => activity_id, "attendance" => attendance} = params) do
    case Participation.attendance(
           activity_id,
           conn.assigns.current_actor.id,
           attendance,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, result} -> Response.ok(conn, result)
      error -> participation_error(conn, error)
    end
  end

  def attendance(conn, _params),
    do: Response.error(conn, :invalid_attendance, "Attendance is required", 422)

  def plans(conn, params) do
    case Participation.list_plans(conn.assigns.current_actor.id, params) do
      {:ok, plans} ->
        Response.ok(conn, plans)

      {:error, {:validation_failed, fields}} ->
        Response.error(conn, :validation_failed, "Validation failed", 422, fields)
    end
  end

  defp command(conn, activity_id, params, command) do
    case command.(
           activity_id,
           conn.assigns.current_actor.id,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, result} -> Response.ok(conn, result)
      error -> participation_error(conn, error)
    end
  end

  defp request_hash(params) do
    params
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp participation_error(conn, {:error, :not_found}),
    do: Response.error(conn, :not_found, "The requested activity was not found", 404)

  defp participation_error(conn, {:error, :account_restricted}),
    do: Response.error(conn, :participation_unavailable, "Participation is not available", 403)

  defp participation_error(conn, {:error, :block_conflict}),
    do: Response.error(conn, :participation_unavailable, "Participation is not available", 403)

  defp participation_error(conn, {:error, :capacity_full}),
    do: Response.error(conn, :capacity_full, "This activity is full", 409)

  defp participation_error(conn, {:error, :idempotency_key_reused}),
    do:
      Response.error(
        conn,
        :idempotency_key_reused,
        "This idempotency key was used for another request",
        409
      )

  defp participation_error(conn, {:error, :idempotency_in_progress}),
    do:
      Response.error(conn, :idempotency_in_progress, "This request is still being processed", 409)

  defp participation_error(conn, {:error, :activity_not_joinable}),
    do: Response.error(conn, :participation_unavailable, "Participation is not available", 422)

  defp participation_error(conn, {:error, :host_already_going}),
    do: Response.error(conn, :host_already_going, "Hosts already occupy their activity seat", 422)

  defp participation_error(conn, {:error, :not_going}),
    do: Response.error(conn, :not_going, "You are not currently going to this activity", 422)

  defp participation_error(conn, {:error, :attendance_not_available}),
    do:
      Response.error(
        conn,
        :attendance_not_available,
        "Attendance reporting is not available",
        422
      )

  defp participation_error(conn, {:error, code}) when is_atom(code),
    do: Response.error(conn, code, "The request could not be completed", 422)
end
