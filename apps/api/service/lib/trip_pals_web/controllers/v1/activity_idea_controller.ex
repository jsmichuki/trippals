defmodule TripPalsWeb.V1.ActivityIdeaController do
  use TripPalsWeb, :controller

  alias TripPals.Activities
  alias TripPalsWeb.API.Response

  def index(conn, _params),
    do: Response.ok(conn, %{activity_ideas: Activities.list_activity_ideas()})
end
