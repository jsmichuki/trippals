defmodule TripPalsWeb.V1.NotificationControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Notifications

  setup do
    {:ok, user} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(user.id, "notification-api")
    %{user: user, token: AccessToken.issue(session)}
  end

  test "notification reads are owned, paginated, and never expose sensitive payload fields", %{
    user: user,
    token: token
  } do
    assert {:ok, _} =
             Notifications.notify(%{
               user_id: user.id,
               event_type: "activity.canceled",
               essential: true,
               deep_link: "/activities/a-1",
               dedupe_key: "notification-api-1",
               payload: %{
                 activity_id: "a-1",
                 body: "not allowed",
                 private_directions: "not allowed"
               }
             })

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/v1/notifications?limit=1")

    assert %{
             "data" => %{
               "notifications" => [
                 %{"event_type" => "activity.canceled", "payload" => %{"activity_id" => "a-1"}}
               ]
             }
           } = json_response(response, 200)
  end

  test "device and preference updates require authentication and idempotency", %{token: token} do
    unauthenticated =
      post(build_conn(), "/v1/devices", %{"platform" => "ios", "token" => "private-token"})

    assert %{"error" => %{"code" => "authentication_required"}} =
             json_response(unauthenticated, 401)

    missing_key =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/v1/devices", %{"platform" => "ios", "token" => "private-token"})

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(missing_key, 400)

    registered =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "notification-device-1")
      |> post("/v1/devices", %{"platform" => "ios", "token" => "private-token"})

    assert %{"data" => %{"id" => _id, "platform" => "ios"} = device} =
             json_response(registered, 201)

    refute Map.has_key?(device, "token")

    preference =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "notification-preferences-1")
      |> patch("/v1/me/notification-preferences", %{"nonessential_enabled" => false})

    assert %{"data" => %{"nonessential_enabled" => false}} = json_response(preference, 200)
  end
end
