defmodule TripPalsWeb.V1.ActivityController do
  use TripPalsWeb, :controller

  alias TripPals.Activities
  alias TripPalsWeb.API.Response

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
    case Activities.get_public_activity(activity_id) do
      {:ok, activity} ->
        Response.ok(conn, activity)

      {:error, :activity_unavailable} ->
        Response.error(conn, :activity_unavailable, "This activity is no longer available", 410)

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested activity was not found", 404)
    end
  end
end
