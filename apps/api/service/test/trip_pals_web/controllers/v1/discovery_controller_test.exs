defmodule TripPalsWeb.V1.DiscoveryControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.Activities.Activity
  alias TripPals.Activities.ActivityIdea
  alias TripPals.Cities
  alias TripPals.Cities.City
  alias TripPals.Repo

  setup do
    city = create_city!("supported")
    unavailable_city = create_city!("coming_soon")
    date = Date.add(Date.utc_today(), 10)
    {:ok, {start_at, _end_of_day}} = Cities.local_date_bounds(city.iana_timezone, date)

    activity =
      create_activity!(
        city,
        start_at,
        DateTime.add(start_at, 2 * 60 * 60, :second),
        "Open gallery"
      )

    terminal_activity =
      create_activity!(
        city,
        DateTime.add(start_at, 24 * 60 * 60, :second),
        DateTime.add(start_at, 27 * 60 * 60, :second),
        "Canceled gallery",
        "canceled"
      )

    %{
      city: city,
      unavailable_city: unavailable_city,
      date: date,
      activity: activity,
      terminal_activity: terminal_activity
    }
  end

  test "lets a guest browse supported cities and guest-safe scheduled activities", %{
    conn: conn,
    city: city,
    date: date,
    activity: activity
  } do
    cities_conn = get(conn, ~p"/v1/cities")

    assert %{"data" => %{"cities" => cities}} = json_response(cities_conn, 200)
    assert Enum.any?(cities, &(&1["id"] == city.id and &1["launch_status"] == "supported"))

    activities_conn =
      build_conn()
      |> get(~p"/v1/activities", %{
        "city_id" => city.id,
        "start_local_date" => Date.to_iso8601(date),
        "end_local_date" => Date.to_iso8601(date)
      })

    assert %{
             "data" => %{
               "activities" => [
                 %{
                   "id" => activity_id,
                   "kind" => "scheduled_activity",
                   "iana_timezone" => "America/New_York",
                   "seats_remaining" => 5
                 } = rendered
               ],
               "next_cursor" => nil
             }
           } = json_response(activities_conn, 200)

    assert activity_id == activity.id

    direct_link_conn = build_conn() |> get(~p"/v1/activities/#{activity.id}")

    assert %{"data" => %{"id" => ^activity_id, "kind" => "scheduled_activity"}} =
             json_response(direct_link_conn, 200)

    for forbidden <- [
          "host_id",
          "participant_meeting_details",
          "roster",
          "chat",
          "invitation",
          "exact_availability"
        ] do
      refute Map.has_key?(rendered, forbidden)
    end
  end

  test "returns honest unavailable, empty, invalid-range, and terminal states", %{
    conn: conn,
    city: city,
    unavailable_city: unavailable_city,
    date: date,
    terminal_activity: terminal_activity
  } do
    unavailable_conn =
      get(conn, ~p"/v1/activities", %{
        "city_id" => unavailable_city.id,
        "start_local_date" => Date.to_iso8601(date),
        "end_local_date" => Date.to_iso8601(date)
      })

    assert %{"error" => %{"code" => "city_unavailable"}} = json_response(unavailable_conn, 422)

    empty_conn =
      build_conn()
      |> get(~p"/v1/activities", %{
        "city_id" => city.id,
        "start_local_date" => Date.to_iso8601(Date.add(date, 2)),
        "end_local_date" => Date.to_iso8601(Date.add(date, 2))
      })

    assert %{"data" => %{"activities" => []}} = json_response(empty_conn, 200)

    invalid_range_conn =
      build_conn()
      |> get(~p"/v1/activities", %{
        "city_id" => city.id,
        "start_local_date" => Date.to_iso8601(Date.add(date, 1)),
        "end_local_date" => Date.to_iso8601(date)
      })

    assert %{"error" => %{"code" => "validation_failed"}} = json_response(invalid_range_conn, 422)

    past_range_conn =
      build_conn()
      |> get(~p"/v1/activities", %{
        "city_id" => city.id,
        "start_local_date" => Date.to_iso8601(Date.add(Date.utc_today(), -1)),
        "end_local_date" => Date.to_iso8601(Date.add(Date.utc_today(), -1))
      })

    assert %{"error" => %{"code" => "validation_failed"}} = json_response(past_range_conn, 422)

    horizon_range_conn =
      build_conn()
      |> get(~p"/v1/activities", %{
        "city_id" => city.id,
        "start_local_date" => Date.to_iso8601(date),
        "end_local_date" => Date.to_iso8601(Date.add(date, 90))
      })

    assert %{"error" => %{"code" => "validation_failed"}} = json_response(horizon_range_conn, 422)

    terminal_conn = build_conn() |> get(~p"/v1/activities/#{terminal_activity.id}")
    assert %{"error" => %{"code" => "activity_unavailable"}} = json_response(terminal_conn, 410)
  end

  test "resets to the city-local upcoming range and keeps ideas non-joinable", %{city: city} do
    assert {:ok, %{start_date: start_date, starts_at: starts_at}} =
             Cities.discovery_range(city, %{})

    _activity =
      create_activity!(
        city,
        DateTime.add(starts_at, 60 * 60, :second),
        DateTime.add(starts_at, 3 * 60 * 60, :second),
        "Default-range gallery"
      )

    reset_conn = build_conn() |> get(~p"/v1/activities", %{"city_id" => city.id})

    assert %{
             "data" => %{
               "activities" => activities,
               "range" => %{"start_local_date" => returned_start_date}
             }
           } = json_response(reset_conn, 200)

    assert returned_start_date == Date.to_iso8601(start_date)
    assert Enum.any?(activities, &(&1["title"] == "Default-range gallery"))

    activity_idea =
      %ActivityIdea{}
      |> ActivityIdea.changeset(%{
        title: "Template only",
        category: "art",
        description: "No scheduled event exists"
      })
      |> Repo.insert!()

    ideas_conn = build_conn() |> get(~p"/v1/activity-ideas")

    assert %{
             "data" => %{
               "activity_ideas" => [%{"id" => activity_idea_id, "kind" => "activity_idea"} = idea]
             }
           } = json_response(ideas_conn, 200)

    assert activity_idea_id == activity_idea.id
    refute Map.has_key?(idea, "start_at")
    refute Map.has_key?(idea, "going_count")
    refute Map.has_key?(idea, "host_id")
    refute Map.has_key?(idea, "join")

    join_conn = build_conn() |> post(~p"/v1/activity-ideas/#{activity_idea.id}/join", %{})
    assert %{"error" => %{"code" => "not_found"}} = json_response(join_conn, 404)
  end

  defp create_city!(launch_status) do
    %City{}
    |> City.changeset(%{
      name: "City #{System.unique_integer([:positive])}",
      country: "Kenya",
      iana_timezone: "America/New_York",
      launch_status: launch_status
    })
    |> Repo.insert!()
  end

  defp create_activity!(city, start_at, end_at, title, status \\ "published") do
    %Activity{city_id: city.id}
    |> Activity.discovery_changeset(%{
      title: title,
      category: "art",
      description: "Public gallery visit",
      start_at: start_at,
      end_at: end_at,
      iana_timezone: city.iana_timezone,
      public_area: "Arts district",
      participant_meeting_details: "Private member directions",
      capacity_total: 6,
      going_count: 1,
      status: status
    })
    |> Repo.insert!()
  end
end
