defmodule TripPalsWeb.PreflightController do
  use TripPalsWeb, :controller

  def show(conn, _params), do: send_resp(conn, 204, "")
end
