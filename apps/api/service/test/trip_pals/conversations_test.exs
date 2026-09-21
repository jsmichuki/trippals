defmodule TripPals.ConversationsTest do
  use TripPals.DataCase, async: false

  alias TripPals.Accounts
  alias TripPals.Accounts.User
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Conversations
  alias TripPals.Conversations.Conversation
  alias TripPals.Conversations.Message
  alias TripPals.Participation
  alias TripPals.Repo
  alias TripPals.Safety.Block

  @hash String.duplicate("a", 64)

  setup do
    {:ok, host} = Accounts.create_user()

    {:ok, _profile} =
      Accounts.update_me(host.id, %{
        "display_name" => "Conversation host",
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

  test "persists a message before broadcasting and retries a client message safely", %{
    host: host,
    city: city
  } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)
    Phoenix.PubSub.subscribe(TripPals.PubSub, "conversation:#{conversation.id}")

    client_message_id = Ecto.UUID.generate()

    assert {:ok, created} =
             Conversations.send_message(
               conversation.id,
               member.id,
               %{"client_message_id" => client_message_id, "body" => "See you there"},
               "message-a",
               @hash
             )

    assert_receive {:conversation_event, "message_created", broadcast}
    assert broadcast.id == created.id
    assert %Message{id: message_id, sequence: 1} = Repo.get!(Message, created.id)
    assert message_id == created.id

    # A transport retry with a new HTTP idempotency key still cannot create a
    # second message because the client identifier is durable and unique.
    assert {:ok, replay} =
             Conversations.send_message(
               conversation.id,
               member.id,
               %{"client_message_id" => client_message_id, "body" => "See you there"},
               "message-b",
               String.duplicate("b", 64)
             )

    assert replay.id == created.id
    assert Repo.aggregate(Message, :count) == 1
    refute_receive {:conversation_event, "message_created", _}
  end

  test "history is sequence ordered, resumable, and system messages do not carry private logistics",
       %{
         host: host,
         city: city
       } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    assert {:ok, first} = send(conversation, member, "first", "one")

    assert {:ok, system_event} =
             Conversations.record_system_event(conversation.id, host.id, "activity.updated", %{
               activity_id: activity.id,
               version: 2,
               participant_meeting_details: "must never be published"
             })

    assert system_event.payload == %{"activity_id" => activity.id, "version" => 2}
    assert {:ok, second} = send(conversation, member, "second", "two")

    assert {:ok, first_page} =
             Conversations.list_messages(conversation.id, member.id, %{"limit" => "2"})

    assert Enum.map(first_page.messages, & &1.sequence) == [first.sequence, system_event.sequence]
    assert [%{kind: "message"}, %{kind: "system", payload: payload}] = first_page.messages
    refute Map.has_key?(payload, "participant_meeting_details")

    assert {:ok, second_page} =
             Conversations.list_messages(conversation.id, member.id, %{
               "cursor" => first_page.next_cursor
             })

    assert [%{id: second_id, sequence: 3}] = second_page.messages
    assert second_id == second.id
  end

  test "membership, account, block, lifecycle, and conversation state are rechecked for each send",
       %{
         host: host,
         city: city
       } do
    {:ok, member} = Accounts.create_user()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    assert {:ok, _} = send(conversation, member, "before leave", "before-leave")
    assert {:ok, _} = Participation.leave(activity.id, member.id)

    assert {:error, :conversation_unavailable} =
             send(conversation, member, "while composing", "after-leave")

    assert {:ok, _} = Participation.join(activity.id, member.id)
    Repo.insert!(%Block{blocker_id: host.id, blocked_id: member.id})

    assert {:error, :conversation_unavailable} =
             Conversations.list_messages(conversation.id, member.id)

    Repo.delete_all(Block)

    Repo.get!(User, member.id)
    |> User.changeset(%{status: "restricted"})
    |> Repo.update!()

    assert {:error, :conversation_unavailable} =
             send(conversation, member, "restricted", "restricted")

    Repo.get!(User, member.id)
    |> User.changeset(%{status: "active"})
    |> Repo.update!()

    assert {:ok, _} = Activities.cancel(activity.id, host.id, "Weather")

    assert {:error, :conversation_read_only} =
             send(conversation, member, "after cancel", "canceled")
  end

  test "only host and Going members can use canonical pinned logistics", %{host: host, city: city} do
    {:ok, interested} = Accounts.create_user()
    {:ok, going} = Accounts.create_user()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.interest(activity.id, interested.id)
    assert {:ok, _} = Participation.join(activity.id, going.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    assert {:error, :conversation_unavailable} =
             Conversations.pinned_logistics(conversation.id, interested.id)

    assert {:ok, pinned} = Conversations.pinned_logistics(conversation.id, going.id)
    assert pinned.participant_meeting_details == "Private entrance"
    assert pinned.activity_id == activity.id
    assert {:ok, host_pinned} = Conversations.pinned_logistics(conversation.id, host.id)
    assert host_pinned.version == activity.version
  end

  defp send(conversation, user, body, key) do
    Conversations.send_message(
      conversation.id,
      user.id,
      %{"client_message_id" => Ecto.UUID.generate(), "body" => body},
      key,
      :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
    )
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
        "capacity_total" => 4
      })

    {:ok, activity} = Activities.publish(draft.id, host.id)
    activity
  end
end
