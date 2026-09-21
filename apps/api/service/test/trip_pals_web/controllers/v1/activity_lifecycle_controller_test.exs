defmodule TripPalsWeb.V1.ActivityLifecycleControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Cities.City
  alias TripPals.Repo

  setup do
    {:ok, host} = Accounts.create_user()
    {:ok, _profile} = complete_profile(host)
    {:ok, host_session} = Accounts.create_session(host.id, "host-device")
    {:ok, other_user} = Accounts.create_user()
    {:ok, other_session} = Accounts.create_session(other_user.id, "other-device")

    city =
      %City{}
      |> City.changeset(%{
        name: "Nairobi #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
      |> Repo.insert!()

    %{
      host: host,
      host_token: AccessToken.issue(host_session),
      other_token: AccessToken.issue(other_session),
      city: city
    }
  end

  test "requires a member and idempotency key to create and publish a host-owned activity", %{
    conn: conn,
    host_token: host_token,
    city: city
  } do
    unauthenticated = post(conn, ~p"/v1/activities", activity_attributes(city))

    assert %{"error" => %{"code" => "authentication_required"}} =
             json_response(unauthenticated, 401)

    missing_key =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> post(~p"/v1/activities", activity_attributes(city))

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(missing_key, 400)

    created =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "create-activity")
      |> post(~p"/v1/activities", activity_attributes(city))

    assert %{"data" => %{"id" => activity_id, "status" => "draft", "version" => 1}} =
             json_response(created, 201)

    published =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "publish-activity")
      |> post(~p"/v1/activities/#{activity_id}/publish", %{})

    assert %{"data" => %{"status" => "published", "going_count" => 1}} =
             json_response(published, 200)

    repeated_publish =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "publish-activity-repeat")
      |> post(~p"/v1/activities/#{activity_id}/publish", %{})

    assert %{"data" => %{"status" => "published"}} = json_response(repeated_publish, 200)
  end

  test "enforces host ownership and If-Match versions for activity edits", %{
    host_token: host_token,
    other_token: other_token,
    city: city
  } do
    created =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "create-for-edit")
      |> post(~p"/v1/activities", activity_attributes(city))

    activity_id = json_response(created, 201)["data"]["id"]

    forbidden =
      build_conn()
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> put_req_header("idempotency-key", "other-edit")
      |> put_req_header("if-match", "1")
      |> patch(~p"/v1/activities/#{activity_id}", %{title: "Not allowed"})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(forbidden, 403)

    missing_version =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "missing-version")
      |> patch(~p"/v1/activities/#{activity_id}", %{title: "Requires version"})

    assert %{"error" => %{"code" => "if_match_required"}} = json_response(missing_version, 400)

    stale =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "stale-version")
      |> put_req_header("if-match", "0")
      |> patch(~p"/v1/activities/#{activity_id}", %{title: "Stale"})

    assert %{"error" => %{"code" => "version_conflict", "current" => %{"version" => 1}}} =
             json_response(stale, 409)
  end

  test "shapes public, member, and host activity detail independently", %{
    host_token: host_token,
    other_token: other_token,
    city: city
  } do
    created =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "create-projection")
      |> post(~p"/v1/activities", activity_attributes(city))

    activity_id = json_response(created, 201)["data"]["id"]

    _published =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "publish-projection")
      |> post(~p"/v1/activities/#{activity_id}/publish", %{})

    guest = build_conn() |> get(~p"/v1/activities/#{activity_id}") |> json_response(200)

    member =
      build_conn()
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> get(~p"/v1/activities/#{activity_id}")
      |> json_response(200)

    host =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> get(~p"/v1/activities/#{activity_id}")
      |> json_response(200)

    assert guest["data"]["viewer_role"] == "guest"
    refute Map.has_key?(guest["data"], "participant_meeting_details")
    assert member["data"]["viewer_role"] == "member"
    assert member["data"]["membership_state"] == "not_going"
    refute Map.has_key?(member["data"], "participant_meeting_details")
    assert host["data"]["participant_meeting_details"] == "Private entrance"
  end

  defp complete_profile(user) do
    Accounts.update_me(user.id, %{
      "display_name" => "Eligible host",
      "adult_confirmation" => true,
      "community_rule_version" => "v1"
    })
  end

  defp activity_attributes(city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    %{
      city_id: city.id,
      title: "Gallery walk",
      category: "culture",
      description: "An inclusive public activity",
      start_at: DateTime.to_iso8601(start_at),
      end_at: DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
      iana_timezone: city.iana_timezone,
      public_area: "City centre",
      participant_meeting_details: "Private entrance",
      cost_amount: "10.00",
      currency: "KES",
      capacity_total: 6
    }
  end
end
