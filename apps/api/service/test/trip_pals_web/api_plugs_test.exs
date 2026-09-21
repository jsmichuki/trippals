defmodule TripPalsWeb.APIPlugsTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPalsWeb.API.Idempotency
  alias TripPalsWeb.API.OptimisticConcurrency
  alias TripPalsWeb.API.RateLimit

  test "requires and assigns a bounded idempotency key" do
    conn = build_conn()
    assert %{halted: true, status: 400} = Idempotency.call(conn, [])

    conn = build_conn() |> put_req_header("idempotency-key", "join-123")
    assert %{assigns: %{idempotency_key: "join-123"}} = Idempotency.call(conn, [])
  end

  test "never reflects a supplied idempotency key in an error response" do
    secret = "sensitive-idempotency-key"
    conn = build_conn() |> put_req_header("idempotency-key", String.duplicate(secret, 20))
    conn = Idempotency.call(conn, [])

    refute conn.resp_body =~ secret
  end

  test "requires If-Match and extracts the expected activity version" do
    assert %{halted: true, status: 400} = OptimisticConcurrency.call(build_conn(), [])

    conn = build_conn() |> put_req_header("if-match", "\"12\"")
    assert %{assigns: %{expected_version: "12"}} = OptimisticConcurrency.call(conn, [])
  end

  test "builds a hashed rate-limit key from account, IP, device, and target" do
    conn =
      build_conn()
      |> put_req_header("x-device-id", "device-123")
      |> Plug.Conn.assign(:current_actor, %{id: "actor-123"})
      |> RateLimit.call("join")

    assert String.match?(conn.assigns.rate_limit_key, ~r/\A[0-9a-f]{64}\z/)
  end
end
