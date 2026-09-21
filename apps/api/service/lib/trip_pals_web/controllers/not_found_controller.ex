defmodule TripPalsWeb.NotFoundController do
  use TripPalsWeb, :controller

  alias TripPalsWeb.API.Response

  def show(conn, _params) do
    Response.error(conn, :not_found, "The requested resource was not found", 404)
  end
end
