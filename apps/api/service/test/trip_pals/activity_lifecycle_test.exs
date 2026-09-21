defmodule TripPals.ActivityLifecycleTest do
  use TripPals.DataCase, async: true

  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Activities.ActivityAudit
  alias TripPals.Activities.ActivityHostAssignment
  alias TripPals.Activities.ActivityIdea
  alias TripPals.Activities.ActivityRevision
  alias TripPals.Cities.City
  alias TripPals.Conversations.Conversation
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo

  setup do
    {:ok, host} = Accounts.create_user()

    {:ok, _profile} =
      Accounts.update_me(host.id, %{
        "display_name" => "Host",
        "adult_confirmation" => true,
        "community_rule_version" => "v1"
      })

    city =
      %City{}
      |> City.changeset(%{
        name: "Nairobi #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
      |> Repo.insert!()

    %{host: host, city: city}
  end

  test "publishes a complete draft with host, conversation, revision, audit, and outbox", %{
    host: host,
    city: city
  } do
    assert {:ok, draft} = Activities.create_draft(host.id, activity_attributes(city))
    assert draft.status == "draft"

    assert {:ok, published} = Activities.publish(draft.id, host.id)
    assert published.status == "published"
    assert published.going_count == 1

    assert %Conversation{activity_id: activity_id, host_id: host_id} =
             Repo.get_by!(Conversation, activity_id: published.id)

    assert activity_id == published.id
    assert host_id == host.id

    assert %ActivityHostAssignment{seat_counted: true, role: "primary"} =
             Repo.get_by!(ActivityHostAssignment, activity_id: published.id, user_id: host.id)

    assert Repo.aggregate(ActivityRevision, :count) == 1
    assert Repo.aggregate(ActivityAudit, :count) == 1
  end

  test "models pending review, approval, expiry, and cancellation as explicit audited states", %{
    host: host,
    city: city
  } do
    {:ok, draft} = Activities.create_draft(host.id, activity_attributes(city))
    assert {:ok, reviewing} = Activities.mark_pending_review(draft.id, host.id)
    assert reviewing.status == "pending_review"
    assert {:ok, published} = Activities.approve_review(reviewing.id, host.id)
    assert published.status == "published"
    assert {:ok, expired} = Activities.expire(published.id, host.id)
    assert expired.status == "expired"

    {:ok, another_draft} = Activities.create_draft(host.id, activity_attributes(city))
    assert {:ok, reviewing_again} = Activities.mark_pending_review(another_draft.id, host.id)
    assert {:ok, canceled} = Activities.cancel(reviewing_again.id, host.id, "Safety review")
    assert canceled.status == "canceled"
  end

  test "uses an activity idea only as editable draft prefill", %{host: host, city: city} do
    idea =
      %ActivityIdea{}
      |> ActivityIdea.changeset(%{
        title: "Idea title",
        category: "social",
        description: "Idea description"
      })
      |> Repo.insert!()

    attributes =
      activity_attributes(city)
      |> Map.drop(["title", "category", "description"])
      |> Map.put("idea_id", idea.id)

    assert {:ok, draft} = Activities.create_draft(host.id, attributes)
    assert draft.idea_id == idea.id
    assert draft.title == idea.title
    assert draft.category == idea.category
    assert draft.description == idea.description
  end

  test "blocks publication without safe logistics, disclosed cost, or future timing", %{
    host: host,
    city: city
  } do
    incomplete = Map.delete(activity_attributes(city), "cost_amount")
    assert {:ok, draft} = Activities.create_draft(host.id, incomplete)

    assert {:error, {:validation_failed, %{cost_amount: ["is required"]}}} =
             Activities.publish(draft.id, host.id)

    past_attributes = activity_attributes(city, DateTime.add(DateTime.utc_now(), -60, :second))
    assert {:ok, past_draft} = Activities.create_draft(host.id, past_attributes)

    assert {:error,
            {:validation_failed, %{start_at: ["must be in the future before publication"]}}} =
             Activities.publish(past_draft.id, host.id)

    assert {:error, changeset} =
             Activities.create_draft(
               host.id,
               Map.put(activity_attributes(city), "description", "https://example.test")
             )

    assert %{description: ["must not include promotional links"]} = errors_on(changeset)
  end

  test "enforces host authorization, transitions, terminal idempotency, and safe outcomes", %{
    host: host,
    city: city
  } do
    {:ok, another_user} = Accounts.create_user()

    assert {:ok, draft} = Activities.create_draft(host.id, activity_attributes(city))

    assert {:error, :forbidden} = Activities.publish(draft.id, another_user.id)
    assert {:ok, published} = Activities.publish(draft.id, host.id)
    assert {:error, :invalid_transition} = Activities.start(published.id, host.id)
    assert {:ok, confirmed} = Activities.confirm(published.id, host.id)

    started_at =
      confirmed
      |> Ecto.Changeset.change(start_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

    assert {:ok, started} = Activities.start(started_at.id, host.id)
    assert {:ok, completed} = Activities.finish(started.id, host.id, true, nil)
    assert completed.outcome == "host_reported_completed"
    assert {:ok, ^completed} = Activities.finish(completed.id, host.id, true, nil)
    assert {:error, :invalid_transition} = Activities.cancel(completed.id, host.id, "Too late")
  end

  test "uses versions and material revisions for host edits without shrinking below occupied seats",
       %{host: host, city: city} do
    {:ok, draft} = Activities.create_draft(host.id, activity_attributes(city))
    {:ok, published} = Activities.publish(draft.id, host.id)

    assert {:error, {:conflict, current}} =
             Activities.update_activity(published.id, host.id, published.version - 1, %{
               "title" => "Changed"
             })

    assert current.version == published.version

    assert {:error, _changeset} =
             Activities.update_activity(published.id, host.id, published.version, %{
               "capacity_total" => 0
             })

    assert {:ok, updated} =
             Activities.update_activity(published.id, host.id, published.version, %{
               "public_area" => "Westlands"
             })

    assert updated.version == published.version + 1

    assert Repo.get_by!(ActivityRevision, activity_id: updated.id, version: updated.version).material

    events =
      Repo.all(
        Ecto.Query.where(
          OutboxEvent,
          [event],
          event.aggregate_id == ^updated.id and event.event_type == "activity.updated"
        )
      )

    assert MapSet.new(Enum.map(events, & &1.payload["projection"])) ==
             MapSet.new(["plans", "invitations", "conversations", "notifications"])

    assert Enum.all?(events, fn event ->
             event.payload["version"] == updated.version and
               not Map.has_key?(event.payload, "participant_meeting_details")
           end)
  end

  defp activity_attributes(city, start_at \\ DateTime.add(DateTime.utc_now(), 86_400, :second)) do
    %{
      "city_id" => city.id,
      "title" => "Museum walk",
      "category" => "culture",
      "description" => "A public daytime activity",
      "start_at" => DateTime.to_iso8601(start_at),
      "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 2 * 60 * 60, :second)),
      "iana_timezone" => city.iana_timezone,
      "public_area" => "City centre",
      "participant_meeting_details" => "Private entrance",
      "cost_amount" => "10.00",
      "currency" => "KES",
      "capacity_total" => 6
    }
  end
end
