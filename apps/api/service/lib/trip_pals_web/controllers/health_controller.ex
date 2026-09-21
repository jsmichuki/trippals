defmodule TripPalsWeb.HealthController do
  use TripPalsWeb, :controller

  def show(conn, _params) do
    TripPalsWeb.API.Response.ok(conn, %{status: "ok"})
  end
end
