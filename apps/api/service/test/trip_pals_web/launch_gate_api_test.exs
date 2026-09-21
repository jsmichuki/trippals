defmodule TripPalsWeb.LaunchGateApiTest do
  @moduledoc """
  Acceptance-level HTTP checks for the launch loop and its public boundaries.
  """

  use TripPalsWeb.ConnCase, async: false

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Repo

  setup do
    {:ok, host} = completed_user("API launch host")
    {:ok, guest_member} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(guest_member.id, "launch-gate-device")

    city =
      %City{}
      |> City.changeset(%{
        name: "API launch city #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Etc/UTC",
        launch_status: "supported"
      })
      |> Repo.insert!()

    previous_flags = Application.get_env(:trip_pals, :feature_flags, [])
    Application.put_env(:trip_pals, :feature_flags, previous_flags)
    on_exit(fn -> Application.put_env(:trip_pals, :feature_flags, previous_flags) end)

    %{host: host, member: guest_member, token: AccessToken.issue(session), city: city}
  end

  test "a GPS-free guest discovery handoff can authenticate, complete a profile, and Join", %{
    host: host,
    member: member,
    token: token,
    city: city
  } do
    activity = published_activity(host, city)

    day = activity.start_at |> DateTime.to_date() |> Date.to_iso8601()

    guest_discovery =
      build_conn()
      |> get("/v1/activities", %{
        "city_id" => city.id,
        "start_local_date" => day,
        "end_local_date" => day
      })

    assert %{"data" => %{"activities" => [%{"id" => activity_id} = guest_activity]}} =
             json_response(guest_discovery, 200)

    assert activity_id == activity.id

    for private_field <- ["participant_meeting_details", "roster", "chat", "host_id"] do
      refute Map.has_key?(guest_activity, private_field)
    end

    profile =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "launch-profile")
      |> patch("/v1/me", %{
        "display_name" => "API launch member",
        "adult_confirmation" => true,
        "community_rule_version" => "v1"
      })

    assert %{"data" => %{"profile_completed" => true}} = json_response(profile, 200)

    join =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "launch-join")
      |> post("/v1/activities/#{activity.id}/join", %{})

    assert %{"data" => %{"activity_id" => ^activity_id, "status" => "going"}} =
             json_response(join, 200)

    assert member.id != host.id
  end

  test "the API cannot bypass a disabled city invitation-matching gate", %{
    host: host,
    token: _member_token,
    city: city
  } do
    activity = published_activity(host, city)
    {:ok, host_session} = Accounts.create_session(host.id, "host-launch-gate")
    host_token = AccessToken.issue(host_session)

    candidates =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> get("/v1/activities/#{activity.id}/invitation-candidates")

    assert %{
             "error" => %{"code" => "invitation_matching_disabled"},
             "meta" => %{"correlation_id" => _}
           } =
             json_response(candidates, 422)

    direct_send =
      build_conn()
      |> put_req_header("authorization", "Bearer #{host_token}")
      |> put_req_header("idempotency-key", "disabled-direct-send")
      |> post("/v1/activities/#{activity.id}/invitations", %{
        "recipient_ids" => [Ecto.UUID.generate()]
      })

    assert %{
             "error" => %{"code" => "invitation_matching_disabled"},
             "meta" => %{"correlation_id" => _}
           } =
             json_response(direct_send, 422)
  end

  defp completed_user(display_name) do
    with {:ok, user} <- Accounts.create_user(),
         {:ok, _profile} <-
           Accounts.update_me(user.id, %{
             "display_name" => display_name,
             "adult_confirmation" => true,
             "community_rule_version" => "v1"
           }) do
      {:ok, user}
    end
  end

  defp published_activity(host, city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(host.id, %{
        "city_id" => city.id,
        "title" => "API launch activity",
        "category" => "culture",
        "description" => "A public launch activity",
        "start_at" => DateTime.to_iso8601(start_at),
        "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
        "iana_timezone" => city.iana_timezone,
        "public_area" => "City centre",
        "participant_meeting_details" => "Private entrance",
        "cost_amount" => "0.00",
        "currency" => "KES",
        "capacity_total" => 3
      })

    {:ok, activity} = Activities.publish(draft.id, host.id)
    activity
  end
end
