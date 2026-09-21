defmodule TripPalsWeb.V1.ActivityController do
  use TripPalsWeb, :controller

  alias TripPals.Activities
  alias TripPalsWeb.API.Response

  def create(conn, params) do
    case Activities.create_draft(conn.assigns.current_actor.id, params) do
      {:ok, activity} -> Response.ok(conn, Activities.host_activity_view(activity), 201)
      error -> activity_error(conn, error)
    end
  end

  def update(conn, %{"id" => activity_id} = params) do
    case Activities.update_activity(
           activity_id,
           conn.assigns.current_actor.id,
           conn.assigns.expected_version,
           params
         ) do
      {:ok, activity} -> Response.ok(conn, Activities.host_activity_view(activity))
      error -> activity_error(conn, error)
    end
  end

  def publish(conn, %{"id" => activity_id}), do: command(conn, activity_id, &Activities.publish/2)
  def confirm(conn, %{"id" => activity_id}), do: command(conn, activity_id, &Activities.confirm/2)
  def start(conn, %{"id" => activity_id}), do: command(conn, activity_id, &Activities.start/2)

  def finish(conn, %{"id" => activity_id} = params) do
    case Activities.finish(
           activity_id,
           conn.assigns.current_actor.id,
           params["occurred"],
           params["reason"]
         ) do
      {:ok, activity} -> Response.ok(conn, Activities.host_activity_view(activity))
      error -> activity_error(conn, error)
    end
  end

  def cancel(conn, %{"id" => activity_id, "reason" => reason}) do
    case Activities.cancel(activity_id, conn.assigns.current_actor.id, reason) do
      {:ok, activity} -> Response.ok(conn, Activities.host_activity_view(activity))
      error -> activity_error(conn, error)
    end
  end

  def cancel(conn, _params),
    do: activity_error(conn, {:error, {:validation_failed, %{reason: ["is required"]}}})

  def index(conn, params) do
    case Activities.list_public_activities(params) do
      {:ok, result} ->
        Response.ok(conn, result)

      {:error, :city_not_found} ->
        Response.error(conn, :not_found, "The requested city was not found", 404)

      {:error, :city_unavailable} ->
        Response.error(conn, :city_unavailable, "This city is not available", 422)

      {:error, {:validation_failed, fields}} ->
        Response.error(conn, :validation_failed, "Validation failed", 422, fields)
    end
  end

  def show(conn, %{"id" => activity_id}) do
    case Activities.get_activity_for_view(
           activity_id,
           conn.assigns[:current_actor] && conn.assigns.current_actor.id
         ) do
      {:ok, activity} ->
        Response.ok(conn, activity)

      {:error, :activity_unavailable} ->
        Response.error(conn, :activity_unavailable, "This activity is no longer available", 410)

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested activity was not found", 404)
    end
  end

  defp command(conn, activity_id, command) do
    case command.(activity_id, conn.assigns.current_actor.id) do
      {:ok, activity} -> Response.ok(conn, Activities.host_activity_view(activity))
      error -> activity_error(conn, error)
    end
  end

  defp activity_error(conn, {:error, :not_found}),
    do: Response.error(conn, :not_found, "The requested activity was not found", 404)

  defp activity_error(conn, {:error, :forbidden}),
    do: Response.error(conn, :forbidden, "You do not have permission for this action", 403)

  defp activity_error(conn, {:error, :host_ineligible}),
    do: Response.error(conn, :host_ineligible, "Your profile is not eligible to host", 403)

  defp activity_error(conn, {:error, :city_not_found}),
    do: Response.error(conn, :not_found, "The requested city was not found", 404)

  defp activity_error(conn, {:error, :city_unavailable}),
    do: Response.error(conn, :city_unavailable, "This city is not available", 422)

  defp activity_error(conn, {:error, :activity_idea_not_found}),
    do: Response.error(conn, :not_found, "The requested activity idea was not found", 404)

  defp activity_error(conn, {:error, :invalid_transition}),
    do:
      Response.error(conn, :invalid_transition, "This activity cannot make that transition", 422)

  defp activity_error(conn, {:error, :activity_not_started}),
    do: Response.error(conn, :activity_not_started, "This activity has not started", 422)

  defp activity_error(conn, {:error, {:validation_failed, fields}}),
    do: Response.error(conn, :validation_failed, "Validation failed", 422, fields)

  defp activity_error(conn, {:error, {:conflict, current}}),
    do: Response.error(conn, :version_conflict, "The resource has changed", 409, nil, current)

  defp activity_error(conn, {:error, _reason}),
    do: Response.error(conn, :validation_failed, "Validation failed", 422)
end
