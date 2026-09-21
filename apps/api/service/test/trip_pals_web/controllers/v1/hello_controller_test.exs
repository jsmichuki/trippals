defmodule TripPalsWeb.V1.HelloControllerTest do
  use TripPalsWeb.ConnCase, async: true

  test "GET /v1/hello returns the setup response", %{conn: conn} do
    conn = get(conn, ~p"/v1/hello")

    assert %{"data" => %{"message" => "Hello, TripPals!"}} = json_response(conn, 200)
  end
end
