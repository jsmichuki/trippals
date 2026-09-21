defmodule TripPals.AccountDeletionTest do
  use TripPals.DataCase, async: false

  alias TripPals.AccountDeletion
  alias TripPals.AccountDeletion.Deletion
  alias TripPals.AccountDeletion.RetentionRecord
  alias TripPals.Accounts
  alias TripPals.Accounts.AuthIdentity
  alias TripPals.Accounts.Profile
  alias TripPals.Accounts.Session
  alias TripPals.Activities
  alias TripPals.Activities.Activity
  alias TripPals.Cities.City
  alias TripPals.Conversations.Conversation
  alias TripPals.Conversations.ConversationMembership
  alias TripPals.Invitations.Availability
  alias TripPals.Invitations.Invitation
  alias TripPals.Invitations.InvitationSetting
  alias TripPals.Notifications.Device
  alias TripPals.Participation
  alias TripPals.Participation.Record
  alias TripPals.Repo
  alias TripPals.Safety.Report

  test "requires a fresh authenticated session to request deletion" do
    {:ok, user} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(user.id)

    session
    |> Ecto.Changeset.change(recently_authenticated_at: DateTime.add(DateTime.utc_now(), -901))
    |> Repo.update!()

    assert {:error, :recent_auth_required} = AccountDeletion.request(user.id, session.id)
    assert Repo.get!(TripPals.Accounts.User, user.id).status == "active"
  end

  test "atomically revokes access, releases future seats, removes consent, and retains only safety material" do
    {:ok, host} = Accounts.create_user()
    complete_profile(host, "Host")
    {:ok, member} = Accounts.create_user()
    complete_profile(member, "Member")
    {:ok, session} = Accounts.create_session(member.id, "member-device")
    {:ok, _identity} = Accounts.link_identity(member.id, "google", "deleted-member-subject")
    city = city()
    activity = published_activity(host, city)
    assert {:ok, %Record{status: "going"}} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)

    Repo.insert!(
      Device.changeset(%Device{user_id: member.id}, %{
        platform: "ios",
        token_digest: String.duplicate("a", 64),
        token_ciphertext: <<1, 2, 3>>,
        token_last_four: "1234",
        last_seen_at: DateTime.utc_now()
      })
    )

    Repo.insert!(
      InvitationSetting.changeset(%InvitationSetting{user_id: member.id}, %{
        enabled: true,
        consented_at: DateTime.utc_now()
      })
    )

    Repo.insert!(
      Availability.changeset(%Availability{user_id: member.id}, %{
        city_id: city.id,
        role: "traveler",
        visible: true
      })
    )

    pending_invitation =
      Repo.insert!(
        Invitation.changeset(
          %Invitation{activity_id: activity.id, host_id: host.id, recipient_id: member.id},
          %{
            status: "pending",
            sent_at: DateTime.utc_now(),
            expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
            event_version_seen: activity.version
          }
        )
      )

    report =
      Repo.insert!(
        Report.changeset(%Report{reporter_id: member.id}, %{
          target_type: "activity",
          target_id: activity.id,
          reason_code: "abuse"
        })
      )

    assert {:ok, %{status: "access_revoked", user_id: user_id}} =
             AccountDeletion.request(member.id, session.id)

    assert user_id == member.id
    assert Repo.get!(TripPals.Accounts.User, member.id).status == "deleted"
    assert %Session{revoked_at: %DateTime{}} = Repo.get!(Session, session.id)

    assert Repo.aggregate(
             from(identity in AuthIdentity, where: identity.user_id == ^member.id),
             :count
           ) == 0

    assert %Device{status: "invalidated", invalidated_at: %DateTime{}} =
             Repo.get_by!(Device, user_id: member.id)

    assert %Profile{display_name: "Deleted member", invitation_discoverable: false} =
             Repo.get_by!(Profile, user_id: member.id)

    assert %InvitationSetting{enabled: false, revoked_at: %DateTime{}} =
             Repo.get_by!(InvitationSetting, user_id: member.id)

    assert %Availability{visible: false, revoked_at: %DateTime{}} =
             Repo.get_by!(Availability, user_id: member.id)

    assert %Invitation{status: "revoked", responded_at: %DateTime{}} =
             Repo.get!(Invitation, pending_invitation.id)

    assert %Record{status: "left", left_at: %DateTime{}} =
             Repo.get_by!(Record, activity_id: activity.id, user_id: member.id)

    assert Repo.get!(Activity, activity.id).going_count == 1

    assert %ConversationMembership{status: "revoked", revoked_at: %DateTime{}} =
             Repo.get_by!(ConversationMembership,
               conversation_id: conversation.id,
               user_id: member.id
             )

    assert %Report{reporter_id: nil} = Repo.get!(Report, report.id)
    assert Repo.aggregate(RetentionRecord, :count) >= 2

    assert %Deletion{status: "access_revoked", access_revoked_at: %DateTime{}} =
             Repo.get_by!(Deletion, user_id: member.id)

    assert {:ok, %Deletion{status: "completed", completed_at: %DateTime{}}} =
             AccountDeletion.run(member.id)
  end

  defp complete_profile(user, name) do
    assert {:ok, _profile} =
             Accounts.update_me(user.id, %{
               "display_name" => name,
               "adult_confirmation" => true,
               "community_rule_version" => "v1"
             })
  end

  defp city do
    Repo.insert!(
      City.changeset(%City{}, %{
        name: "Nairobi #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
    )
  end

  defp published_activity(host, city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(host.id, %{
        "city_id" => city.id,
        "title" => "Deletion test walk",
        "category" => "culture",
        "description" => "A public daytime activity",
        "start_at" => DateTime.to_iso8601(start_at),
        "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 3_600, :second)),
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
