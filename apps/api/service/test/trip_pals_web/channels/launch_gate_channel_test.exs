defmodule TripPalsWeb.LaunchGateChannelTest do
  @moduledoc """
  Channel acceptance checks for durable delivery, retry, cursor recovery, and
  membership revocation during the controlled launch.
  """

  use TripPals.DataCase, async: false

  import Phoenix.ChannelTest

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Conversations
  alias TripPals.Conversations.Conversation
  alias TripPals.Participation
  alias TripPals.Repo
  alias TripPalsWeb.{ConversationChannel, UserSocket}

  @endpoint TripPalsWeb.Endpoint

  test "a Going member gets durable messages once, recovers by cursor, and loses access on leave" do
    {:ok, host} = completed_user("Channel launch host")
    {:ok, member} = Accounts.create_user()
    city = city()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    {:ok, session} = Accounts.create_session(member.id, "channel-launch-device")

    {:ok, socket} =
      connect(UserSocket, %{"token" => AccessToken.issue(session)})

    {:ok, _reply, channel_socket} =
      subscribe_and_join(socket, ConversationChannel, "conversation:#{conversation.id}")

    payload = %{
      "client_message_id" => Ecto.UUID.generate(),
      "body" => "Persist before broadcast"
    }

    first = push(channel_socket, "message:create", payload)

    assert_reply first, :ok, %{
      message: %{id: message_id, sequence: 1, body: "Persist before broadcast"}
    }

    assert_push "message_created", %{id: ^message_id, sequence: 1}

    retry = push(channel_socket, "message:create", payload)
    # The replay is read from the JSONB idempotency response, so its keys are
    # strings even though the first in-memory response uses atom keys.
    assert_reply retry, :ok, %{message: %{"id" => ^message_id, "sequence" => 1}}

    assert {:ok, %{messages: [%{id: ^message_id, sequence: 1}], next_cursor: cursor}} =
             Conversations.list_messages(conversation.id, member.id, %{"limit" => "1"})

    assert is_binary(cursor) or is_nil(cursor)

    assert {:ok, _} = Participation.leave(activity.id, member.id)

    rejected =
      push(channel_socket, "message:create", %{
        "client_message_id" => Ecto.UUID.generate(),
        "body" => "This must be rejected after leave"
      })

    assert_reply rejected, :error, %{reason: "unauthorized"}

    assert {:error, :conversation_unavailable} =
             Conversations.list_messages(conversation.id, member.id)
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

  defp city do
    %City{}
    |> City.changeset(%{
      name: "Channel launch #{System.unique_integer([:positive])}",
      country: "Kenya",
      iana_timezone: "Africa/Nairobi",
      launch_status: "supported"
    })
    |> Repo.insert!()
  end

  defp published_activity(host, city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(host.id, %{
        "city_id" => city.id,
        "title" => "Channel launch activity",
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
