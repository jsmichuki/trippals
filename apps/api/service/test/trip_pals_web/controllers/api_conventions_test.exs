defmodule TripPalsWeb.APIConventionsTest do
  use TripPalsWeb.ConnCase, async: true

  test "adds a stable envelope, correlation ID, and security headers", %{conn: conn} do
    conn = get(conn, ~p"/v1/hello")

    assert %{
             "data" => %{"message" => "Hello, TripPals!"},
             "meta" => %{"correlation_id" => correlation_id}
           } = json_response(conn, 200)

    assert correlation_id == get_resp_header(conn, "x-correlation-id") |> List.first()
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "preserves a caller correlation ID", %{conn: conn} do
    conn = conn |> put_req_header("x-request-id", "trace-123") |> get(~p"/v1/hello")

    assert %{"meta" => %{"correlation_id" => "trace-123"}} = json_response(conn, 200)
    assert get_resp_header(conn, "x-correlation-id") == ["trace-123"]
  end

  test "handles allowed CORS preflight requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://app.example.test")
      |> options(~p"/v1/hello")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["https://app.example.test"]
  end

  test "rejects untrusted CORS preflight requests with the API error shape", %{conn: conn} do
    conn = conn |> put_req_header("origin", "https://untrusted.example") |> options(~p"/v1/hello")

    assert %{
             "error" => %{"code" => "cors_origin_forbidden"},
             "meta" => %{"correlation_id" => _correlation_id}
           } = json_response(conn, 403)
  end

  test "rejects declared oversized payloads before routing" do
    conn = build_conn() |> put_req_header("content-length", "1025")
    conn = TripPalsWeb.API.RequestSizeLimit.call(conn, 1_024)

    assert %{"error" => %{"code" => "payload_too_large"}} = Jason.decode!(conn.resp_body)
  end

  test "returns an API-shaped not-found response", %{conn: conn} do
    conn = get(conn, "/v1/does-not-exist")

    assert %{
             "error" => %{
               "code" => "not_found",
               "message" => "The requested resource was not found"
             },
             "meta" => %{"correlation_id" => _correlation_id}
           } = json_response(conn, 404)
  end

  test "returns the same API error shape for an unknown mutation", %{conn: conn} do
    conn = post(conn, "/v1/does-not-exist", %{})

    assert %{
             "error" => %{"code" => "not_found"},
             "meta" => %{"correlation_id" => _correlation_id}
           } = json_response(conn, 404)
  end
end
