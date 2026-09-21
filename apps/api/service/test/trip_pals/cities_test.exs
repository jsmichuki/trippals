defmodule TripPals.CitiesTest do
  use TripPals.DataCase, async: true

  alias TripPals.Activities
  alias TripPals.Activities.Activity
  alias TripPals.Activities.ActivityIdea
  alias TripPals.Cities
  alias TripPals.Cities.City
  alias TripPals.Repo

  test "converts event-city calendar dates to UTC boundaries across DST" do
    assert {:ok, {spring_start, spring_end}} =
             Cities.local_date_bounds("America/New_York", ~D[2027-03-14])

    assert DateTime.diff(spring_end, spring_start, :hour) == 23

    assert {:ok, {fall_start, fall_end}} =
             Cities.local_date_bounds("America/New_York", ~D[2027-11-07])

    assert DateTime.diff(fall_end, fall_start, :hour) == 25
  end

  test "filters by an activity start date in the city timezone, not a device timezone" do
    city = create_city!("America/New_York")
    date = Date.add(Date.utc_today(), 10)
    assert {:ok, {starts_at, _ends_at}} = Cities.local_date_bounds(city.iana_timezone, date)

    create_activity!(city, starts_at, DateTime.add(starts_at, 3 * 60 * 60, :second))

    previous_date = Date.add(date, -1)

    assert {:ok, {previous_starts_at, _}} =
             Cities.local_date_bounds(city.iana_timezone, previous_date)

    create_activity!(
      city,
      DateTime.add(previous_starts_at, 23 * 60 * 60, :second),
      DateTime.add(previous_starts_at, 27 * 60 * 60, :second),
      "Cross-midnight"
    )

    params = %{
      "city_id" => city.id,
      "start_local_date" => Date.to_iso8601(date),
      "end_local_date" => Date.to_iso8601(date)
    }

    assert {:ok, %{activities: [%{title: "Scheduled"}]}} =
             Activities.list_public_activities(params)
  end

  test "keeps activity ideas distinct from scheduled activities" do
    assert {:ok, activity_idea} =
             %ActivityIdea{}
             |> ActivityIdea.changeset(%{
               title: "Coffee walk",
               category: "social",
               description: "A future template"
             })
             |> Repo.insert()

    activity_idea_id = activity_idea.id

    assert [%{id: ^activity_idea_id, kind: "activity_idea"} = idea] =
             Activities.list_activity_ideas()

    refute Map.has_key?(idea, :start_at)
    refute Map.has_key?(idea, :host_id)
    refute Map.has_key?(idea, :going_count)
    refute Map.has_key?(idea, :join)
    refute :host_id in ActivityIdea.__schema__(:fields)
    refute :start_at in ActivityIdea.__schema__(:fields)
  end

  test "uses an opaque cursor with category, capacity, and PostgreSQL search filters" do
    city = create_city!("America/New_York")
    date = Date.add(Date.utc_today(), 10)
    assert {:ok, {starts_at, _}} = Cities.local_date_bounds(city.iana_timezone, date)

    first =
      create_activity!(city, starts_at, DateTime.add(starts_at, 60 * 60, :second), "Gallery walk")

    second =
      create_activity!(
        city,
        DateTime.add(starts_at, 60, :second),
        DateTime.add(starts_at, 2 * 60 * 60, :second),
        "Gallery talk"
      )

    params = %{
      "city_id" => city.id,
      "start_local_date" => Date.to_iso8601(date),
      "end_local_date" => Date.to_iso8601(date),
      "category" => "social",
      "min_capacity" => "2",
      "max_capacity" => "10",
      "q" => "gallery",
      "limit" => "1"
    }

    first_id = first.id
    second_id = second.id

    assert {:ok, %{activities: [%{id: ^first_id}], next_cursor: cursor}} =
             Activities.list_public_activities(params)

    assert is_binary(cursor)

    assert {:ok, %{activities: [%{id: ^second_id}], next_cursor: nil}} =
             Activities.list_public_activities(Map.put(params, "cursor", cursor))
  end

  defp create_city!(timezone) do
    %City{}
    |> City.changeset(%{
      name: "Nairobi #{System.unique_integer([:positive])}",
      country: "Kenya",
      iana_timezone: timezone,
      launch_status: "supported"
    })
    |> Repo.insert!()
  end

  defp create_activity!(city, start_at, end_at, title \\ "Scheduled") do
    %Activity{city_id: city.id}
    |> Activity.discovery_changeset(%{
      title: title,
      category: "social",
      description: "Guest-safe description",
      start_at: start_at,
      end_at: end_at,
      iana_timezone: city.iana_timezone,
      public_area: "Central district",
      capacity_total: 6,
      going_count: 1,
      status: "published",
      participant_meeting_details: "Private gate code"
    })
    |> Repo.insert!()
  end
end
