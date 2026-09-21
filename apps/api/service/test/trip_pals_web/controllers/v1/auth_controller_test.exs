defmodule TripPalsWeb.V1.AuthControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.AccessToken
  alias TripPals.Accounts

  setup do
    {:ok, user} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(user.id, "device-1")
    {:ok, refresh_token, _stored} = Accounts.issue_refresh_token(session)
    %{user: user, session: session, refresh_token: refresh_token}
  end

  test "refreshes a session only with an idempotency key", %{
    conn: conn,
    refresh_token: refresh_token
  } do
    conn =
      conn
      |> put_req_header("idempotency-key", "refresh-1")
      |> post(~p"/v1/auth/refresh", %{refresh_token: refresh_token})

    assert %{"data" => %{"access_token" => access_token, "refresh_token" => replacement}} =
             json_response(conn, 200)

    assert is_binary(access_token) and is_binary(replacement)
  end

  test "returns and updates only the current member profile", %{conn: conn, session: session} do
    token = AccessToken.issue(session)
    conn = conn |> put_req_header("authorization", "Bearer #{token}") |> get(~p"/v1/me")

    assert %{
             "data" => %{
               "id" => _id,
               "invitation_discoverable" => false,
               "profile_completed" => false
             }
           } =
             json_response(conn, 200)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "profile-1")
      |> patch(~p"/v1/me", %{
        display_name: "Amina",
        adult_confirmation: true,
        community_rule_version: "v1"
      })

    assert %{"data" => %{"display_name" => "Amina", "profile_completed" => true}} =
             json_response(conn, 200)
  end

  test "revokes the current session", %{conn: conn, session: session} do
    token = AccessToken.issue(session)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "logout-1")
      |> delete(~p"/v1/auth/session")

    assert response(conn, 204) == ""

    revoked_token_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/v1/me")

    assert %{"error" => %{"code" => "authentication_required"}} =
             json_response(revoked_token_conn, 401)
  end

  test "rejects an expired access token", %{conn: conn, session: session} do
    expired =
      Phoenix.Token.sign(
        TripPalsWeb.Endpoint,
        "access-token-v1",
        %{session_id: session.id, user_id: session.user_id},
        signed_at: System.system_time(:second) - 901
      )

    conn = conn |> put_req_header("authorization", "Bearer #{expired}") |> get(~p"/v1/me")

    assert %{"error" => %{"code" => "authentication_required"}} = json_response(conn, 401)
  end
end
