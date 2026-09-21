defmodule TripPals.LaunchGateAcceptanceTest do
  @moduledoc """
  Cross-context acceptance checks for the controlled, one-city launch gate.

  These deliberately use the public contexts rather than controller internals:
  they make sure a real activity cannot turn an invitation, a chat membership,
  or a safety operation into an authorization bypass.
  """

  use TripPals.DataCase, async: false

  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Activities.ActivityIdea
  alias TripPals.Cities.City
  alias TripPals.Conversations
  alias TripPals.Conversations.Conversation
  alias TripPals.Invitations
  alias TripPals.Participation
  alias TripPals.Repo
  alias TripPals.TrustSafety

  setup do
    {:ok, host} = completed_user("Launch host")
    {:ok, member} = completed_user("Launch member")
    {:ok, moderator} = Accounts.create_user()

    city =
      %City{}
      |> City.changeset(%{
        name: "Launch city #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
      |> Repo.insert!()

    previous_flags = Application.get_env(:trip_pals, :feature_flags, [])
    Application.put_env(:trip_pals, :feature_flags, previous_flags)
    on_exit(fn -> Application.put_env(:trip_pals, :feature_flags, previous_flags) end)

    %{host: host, member: member, moderator: moderator, city: city}
  end

  test "invitation matching is default-off and can only be enabled for a reviewed city", %{
    host: host,
    member: member,
    city: city
  } do
    activity = published_activity(host, city)
    enable_availability(member, city)

    assert {:error, :invitation_matching_disabled} =
             Invitations.invitation_candidates(activity.id, host.id)

    assert {:error, :invitation_matching_disabled} =
             Invitations.send_invitations(activity.id, host.id, [member.id])

    Application.put_env(:trip_pals, :feature_flags, invitation_matching_city_ids: [city.id])

    assert {:ok, %{candidates: [%{id: member_id}]}} =
             Invitations.invitation_candidates(activity.id, host.id)

    assert member_id == member.id
  end

  test "idea to published activity to invitation to Join creates no automatic enrollment", %{
    host: host,
    member: member,
    city: city
  } do
    idea =
      %ActivityIdea{}
      |> ActivityIdea.changeset(%{
        title: "Gallery visit",
        category: "culture",
        description: "A small public gallery group"
      })
      |> Repo.insert!()

    {:ok, draft} = Activities.create_draft(host.id, activity_attributes(city, idea.id))
    assert draft.status == "draft"
    assert {:ok, activity} = Activities.publish(draft.id, host.id)
    assert activity.status == "published"

    enable_availability(member, city)

    Application.put_env(:trip_pals, :feature_flags, invitation_matching_city_ids: [city.id])

    assert {:ok, %{outcomes: [%{status: "sent", invitation_id: invitation_id}]}} =
             Invitations.send_invitations(activity.id, host.id, [member.id])

    assert Repo.get!(TripPals.Activities.Activity, activity.id).going_count == 1
    assert {:ok, %{status: "pending"}} = Invitations.get_invitation(member.id, invitation_id)

    assert {:ok, participation} = Participation.join(activity.id, member.id)
    assert participation.status == "going"
    assert Repo.get!(TripPals.Activities.Activity, activity.id).going_count == 2
  end

  test "a departed member loses private conversation access while durable history remains", %{
    host: host,
    member: member,
    city: city
  } do
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    assert {:ok, message} =
             Conversations.send_message(
               conversation.id,
               member.id,
               %{"client_message_id" => Ecto.UUID.generate(), "body" => "Durable message"},
               "launch-message",
               String.duplicate("a", 64)
             )

    assert message.body == "Durable message"
    assert {:ok, _} = Participation.leave(activity.id, member.id)

    assert {:error, :conversation_unavailable} =
             Conversations.list_messages(conversation.id, member.id)

    assert {:ok, %{messages: [%{body: "Durable message"}]}} =
             Conversations.list_messages(conversation.id, host.id)
  end

  test "block, report, moderation restriction, and appeal retain the safety audit path", %{
    host: host,
    member: member,
    moderator: moderator
  } do
    assert {:ok, %{status: "blocked"}} = TrustSafety.block(host.id, member.id)
    assert TrustSafety.block_conflict?(host.id, [member.id])

    assert {:ok, %{case_id: case_id}} =
             TrustSafety.submit_report(host.id, %{
               "target_type" => "account",
               "target_id" => member.id,
               "reason_code" => "harassment"
             })

    grant_moderator!(moderator)

    assert {:ok, %{id: restriction_id, appeal_available: true}} =
             TrustSafety.impose_restriction(moderator.id, member.id, %{
               "kind" => "join_freeze",
               "reason" => "Verified policy violation",
               "notice" => "Joining is temporarily unavailable",
               "case_id" => case_id
             })

    assert {:ok, %{restriction_id: ^restriction_id, status: "submitted"}} =
             TrustSafety.submit_appeal(member.id, restriction_id, %{
               "statement" => "Please review this decision."
             })
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

  defp grant_moderator!(user) do
    alias TripPals.Safety.StaffRoleAssignment

    %StaffRoleAssignment{user_id: user.id}
    |> StaffRoleAssignment.changeset(%{role: "moderator", scope_type: "platform"})
    |> Repo.insert!()
  end

  defp enable_availability(user, city) do
    assert {:ok, _} =
             Invitations.update_settings(user.id, %{
               "enabled" => true,
               "shareable_fields" => %{"display_name" => true}
             })

    assert {:ok, _} =
             Invitations.create_availability(user.id, %{
               "city_id" => city.id,
               "role" => "traveler",
               "start_local_date" => Date.to_iso8601(Date.utc_today()),
               "end_local_date" => Date.to_iso8601(Date.add(Date.utc_today(), 3)),
               "visible" => true,
               "shareable_fields" => %{}
             })
  end

  defp published_activity(host, city) do
    {:ok, draft} = Activities.create_draft(host.id, activity_attributes(city))
    {:ok, activity} = Activities.publish(draft.id, host.id)
    activity
  end

  defp activity_attributes(city, idea_id \\ nil) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    %{
      "idea_id" => idea_id,
      "city_id" => city.id,
      "title" => "Launch activity",
      "category" => "culture",
      "description" => "A public, organized launch activity",
      "start_at" => DateTime.to_iso8601(start_at),
      "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
      "iana_timezone" => city.iana_timezone,
      "public_area" => "City centre",
      "participant_meeting_details" => "Shared only with Going members",
      "cost_amount" => "0.00",
      "currency" => "KES",
      "capacity_total" => 4
    }
  end
end
