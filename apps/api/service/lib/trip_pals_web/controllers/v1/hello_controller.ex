defmodule TripPalsWeb.V1.HelloController do
  use TripPalsWeb, :controller

  def show(conn, _params) do
    TripPalsWeb.API.Response.ok(conn, %{message: "Hello, TripPals!"})
  end
end
