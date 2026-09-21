defmodule TripPalsWeb.ConversationChannelTest do
  use TripPals.DataCase, async: false

  import Phoenix.ChannelTest

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Conversations.Conversation
  alias TripPals.Participation
  alias TripPals.Repo
  alias TripPalsWeb.{ConversationChannel, UserSocket}

  @endpoint TripPalsWeb.Endpoint

  test "authenticated Going members can join and send; Interested members cannot join" do
    {:ok, host} = host()
    {:ok, interested} = Accounts.create_user()
    {:ok, going} = Accounts.create_user()
    city = city()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.interest(activity.id, interested.id)
    assert {:ok, _} = Participation.join(activity.id, going.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    {:ok, interested_session} = Accounts.create_session(interested.id, "interested-device")

    {:ok, interested_socket} =
      connect(UserSocket, %{"token" => AccessToken.issue(interested_session)})

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(
               interested_socket,
               ConversationChannel,
               "conversation:#{conversation.id}"
             )

    {:ok, going_session} = Accounts.create_session(going.id, "going-device")
    {:ok, going_socket} = connect(UserSocket, %{"token" => AccessToken.issue(going_session)})

    assert {:ok, %{pinned_logistics: %{activity_id: activity_id}}, channel_socket} =
             subscribe_and_join(
               going_socket,
               ConversationChannel,
               "conversation:#{conversation.id}"
             )

    assert activity_id == activity.id

    ref =
      push(channel_socket, "message:create", %{
        "client_message_id" => Ecto.UUID.generate(),
        "body" => "Channel delivery"
      })

    assert_reply ref, :ok, %{message: %{sequence: 1, body: "Channel delivery"}}
    assert_push "message_created", %{sequence: 1, body: "Channel delivery"}
  end

  defp host do
    with {:ok, host} <- Accounts.create_user(),
         {:ok, _profile} <-
           Accounts.update_me(host.id, %{
             "display_name" => "Channel host",
             "adult_confirmation" => true,
             "community_rule_version" => "v1"
           }) do
      {:ok, host}
    end
  end

  defp city do
    %City{}
    |> City.changeset(%{
      name: "Nairobi #{System.unique_integer([:positive])}",
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
        "title" => "Channel walk",
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
