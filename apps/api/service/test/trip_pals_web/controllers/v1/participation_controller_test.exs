defmodule TripPalsWeb.V1.ParticipationControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Repo

  setup do
    {:ok, host} = Accounts.create_user()

    {:ok, _profile} =
      Accounts.update_me(host.id, %{
        "display_name" => "Host",
        "adult_confirmation" => true,
        "community_rule_version" => "v1"
      })

    {:ok, member} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(member.id, "member-device")

    city =
      %City{}
      |> City.changeset(%{
        name: "Nairobi #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
      |> Repo.insert!()

    %{host: host, member_token: AccessToken.issue(session), city: city}
  end

  test "requires member auth and idempotency, then replays Join and exposes plans", %{
    conn: conn,
    host: host,
    member_token: member_token,
    city: city
  } do
    activity = published_activity(host, city)

    unauthenticated = post(conn, ~p"/v1/activities/#{activity.id}/join", %{})

    assert %{"error" => %{"code" => "authentication_required"}} =
             json_response(unauthenticated, 401)

    missing_key =
      build_conn()
      |> put_req_header("authorization", "Bearer #{member_token}")
      |> post(~p"/v1/activities/#{activity.id}/join", %{})

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(missing_key, 400)

    joined =
      build_conn()
      |> put_req_header("authorization", "Bearer #{member_token}")
      |> put_req_header("idempotency-key", "join-activity")
      |> post(~p"/v1/activities/#{activity.id}/join", %{})

    assert %{"data" => %{"activity_id" => activity_id, "status" => "going"}} =
             json_response(joined, 200)

    assert activity_id == activity.id
    refute Map.has_key?(json_response(joined, 200)["data"], "participant_meeting_details")

    replay =
      build_conn()
      |> put_req_header("authorization", "Bearer #{member_token}")
      |> put_req_header("idempotency-key", "join-activity")
      |> post(~p"/v1/activities/#{activity.id}/join", %{})

    assert %{"data" => %{"activity_id" => ^activity_id, "status" => "going"}} =
             json_response(replay, 200)

    plans =
      build_conn()
      |> put_req_header("authorization", "Bearer #{member_token}")
      |> get(~p"/v1/me/plans?limit=1")

    assert %{"data" => %{"plans" => [%{"activity_id" => ^activity_id, "kind" => "going"}]}} =
             json_response(plans, 200)
  end

  defp published_activity(host, city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(host.id, %{
        "city_id" => city.id,
        "title" => "Museum walk",
        "category" => "culture",
        "description" => "A public daytime activity",
        "start_at" => DateTime.to_iso8601(start_at),
        "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
        "iana_timezone" => city.iana_timezone,
        "public_area" => "City centre",
        "participant_meeting_details" => "Private entrance",
        "cost_amount" => "10.00",
        "currency" => "KES",
        "capacity_total" => 2
      })

    {:ok, published} = Activities.publish(draft.id, host.id)
    published
  end
end
