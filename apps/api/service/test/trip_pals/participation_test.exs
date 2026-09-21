defmodule TripPals.ParticipationTest do
  use TripPals.DataCase, async: false

  alias TripPals.Accounts
  alias TripPals.Accounts.User
  alias TripPals.Activities
  alias TripPals.Activities.Activity
  alias TripPals.Cities.City
  alias TripPals.Conversations.Conversation
  alias TripPals.Conversations.ConversationMembership
  alias TripPals.Participation
  alias TripPals.Participation.ParticipationHistory
  alias TripPals.Participation.Record
  alias TripPals.Repo
  alias TripPals.Safety.Block

  @hash String.duplicate("a", 64)

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

  test "interest consumes no seat; join, leave, and rejoin atomically couple chat access", %{
    host: host,
    city: city
  } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city, 2)

    assert {:ok, %Record{status: "interested"}} = Participation.interest(activity.id, member.id)
    assert Repo.get!(Activity, activity.id).going_count == 1

    assert {:ok, %Record{status: "going"}} = Participation.join(activity.id, member.id)
    assert Repo.get!(Activity, activity.id).going_count == 2

    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    assert %ConversationMembership{status: "active", revoked_at: nil} =
             Repo.get_by!(ConversationMembership,
               conversation_id: conversation.id,
               user_id: member.id
             )

    assert {:ok, %Record{status: "left"}} = Participation.leave(activity.id, member.id)
    assert Repo.get!(Activity, activity.id).going_count == 1

    assert %ConversationMembership{status: "revoked", revoked_at: %DateTime{}} =
             Repo.get_by!(ConversationMembership,
               conversation_id: conversation.id,
               user_id: member.id
             )

    assert {:ok, %Record{status: "going"}} = Participation.join(activity.id, member.id)
    assert Repo.get!(Activity, activity.id).going_count == 2
    assert Repo.aggregate(ParticipationHistory, :count) == 4
  end

  test "replays an idempotent Join without allocating another seat or emitting new history", %{
    host: host,
    city: city
  } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city, 2)

    assert {:ok, first} = Participation.join(activity.id, member.id, "join-1", @hash)
    assert first.status == "going"
    assert {:ok, replay} = Participation.join(activity.id, member.id, "join-1", @hash)
    assert replay["status"] == "going"
    assert Repo.get!(Activity, activity.id).going_count == 2
    assert Repo.aggregate(ParticipationHistory, :count) == 1

    assert {:error, :idempotency_key_reused} =
             Participation.join(activity.id, member.id, "join-1", String.duplicate("b", 64))
  end

  test "two final-seat attempts yield exactly one Going participation", %{host: host, city: city} do
    {:ok, first_member} = Accounts.create_user()
    {:ok, second_member} = Accounts.create_user()
    activity = published_activity(host, city, 2)

    results =
      [first_member, second_member]
      |> Task.async_stream(
        fn member -> Participation.join(activity.id, member.id) end,
        timeout: :infinity,
        ordered: false,
        max_concurrency: 2
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, %Record{status: "going"}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :capacity_full}, &1)) == 1
    assert Repo.get!(Activity, activity.id).going_count == 2
    assert Repo.aggregate(Record, :count) == 1
  end

  test "one host plus nine Going participants is the maximum permitted capacity", %{
    host: host,
    city: city
  } do
    activity = published_activity(host, city, 10)

    members =
      for _ <- 1..10 do
        {:ok, member} = Accounts.create_user()
        member
      end

    Enum.each(Enum.take(members, 9), fn member ->
      assert {:ok, %Record{status: "going"}} = Participation.join(activity.id, member.id)
    end)

    assert Repo.get!(Activity, activity.id).going_count == 10
    assert {:error, :capacity_full} = Participation.join(activity.id, List.last(members).id)
    assert Repo.get!(Activity, activity.id).going_count == 10
  end

  test "a failed chat-membership write rolls back the participation and seat", %{
    host: host,
    city: city
  } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city, 2)
    Repo.delete!(Repo.get_by!(Conversation, activity_id: activity.id))

    assert {:error, :conversation_missing} = Participation.join(activity.id, member.id)
    assert Repo.get!(Activity, activity.id).going_count == 1
    assert Repo.get_by(Record, activity_id: activity.id, user_id: member.id) == nil
    assert Repo.aggregate(ParticipationHistory, :count) == 0
  end

  test "safe policy decisions reject full, terminal, restricted, and post-start joins", %{
    host: host,
    city: city
  } do
    {:ok, member} = Accounts.create_user()
    {:ok, other_member} = Accounts.create_user()
    activity = published_activity(host, city, 2)

    assert {:ok, _} = Participation.join(activity.id, member.id)
    assert {:error, :capacity_full} = Participation.join(activity.id, other_member.id)
    assert Repo.get!(Activity, activity.id).participant_meeting_details == "Private entrance"

    assert {:ok, _} = Activities.cancel(activity.id, host.id, "Weather")
    assert {:error, :activity_not_joinable} = Participation.join(activity.id, other_member.id)

    another = published_activity(host, city, 3)

    restricted =
      Repo.get!(User, other_member.id)
      |> User.changeset(%{status: "restricted"})
      |> Repo.update!()

    assert restricted.status == "restricted"
    assert {:error, :account_restricted} = Participation.join(another.id, other_member.id)

    {:ok, active_member} = Accounts.create_user()

    past =
      Repo.get!(Activity, another.id)
      |> Ecto.Changeset.change(start_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

    assert {:error, :activity_not_joinable} = Participation.join(past.id, active_member.id)

    {:ok, blocked_member} = Accounts.create_user()
    Repo.insert!(%Block{blocker_id: host.id, blocked_id: blocked_member.id})
    open_activity = published_activity(host, city, 3)
    assert {:error, :block_conflict} = Participation.join(open_activity.id, blocked_member.id)
  end

  test "plans retain stable activity IDs and separate terminal and interest states", %{
    host: host,
    city: city
  } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city, 3)

    assert {:ok, _} = Participation.interest(activity.id, member.id)
    assert {:ok, plans} = Participation.list_plans(member.id, %{"limit" => "1"})

    assert [%{activity_id: activity_id, kind: "interested", explanatory_state: "scheduled"}] =
             plans.plans

    assert activity_id == activity.id
    assert plans.views.invitations == 0

    assert {:ok, _} = Activities.cancel(activity.id, host.id, "Weather")
    assert {:ok, terminal_plans} = Participation.list_plans(member.id)

    assert [%{activity_id: ^activity_id, kind: "terminal", explanatory_state: "canceled"}] =
             terminal_plans.plans
  end

  defp published_activity(host, city, capacity) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    attributes = %{
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
      "capacity_total" => capacity
    }

    {:ok, draft} = Activities.create_draft(host.id, attributes)
    {:ok, published} = Activities.publish(draft.id, host.id)
    published
  end
end
