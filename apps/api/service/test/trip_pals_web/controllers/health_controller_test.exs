defmodule TripPalsWeb.HealthControllerTest do
  use TripPalsWeb.ConnCase, async: true

  test "GET /up returns the health response", %{conn: conn} do
    conn = get(conn, ~p"/up")

    assert %{"data" => %{"status" => "ok"}} = json_response(conn, 200)
  end

  test "GET /ready verifies the database dependency", %{conn: conn} do
    conn = get(conn, ~p"/ready")

    assert %{"data" => %{"status" => "ready"}} = json_response(conn, 200)
  end
end
