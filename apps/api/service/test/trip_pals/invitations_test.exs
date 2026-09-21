defmodule TripPals.InvitationsTest do
  use TripPals.DataCase, async: false

  import Ecto.Query

  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Invitations
  alias TripPals.Invitations.Availability
  alias TripPals.Invitations.Invitation
  alias TripPals.Invitations.InvitationQuotaEvent
  alias TripPals.Repo
  alias TripPals.Safety.Block

  setup do
    {:ok, host} = completed_user("Host")
    {:ok, recipient} = completed_user("Recipient")
    {:ok, other} = completed_user("Other")

    city =
      %City{}
      |> City.changeset(%{
        name: "Invite city #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
      |> Repo.insert!()

    %{host: host, recipient: recipient, other: other, city: city}
  end

  test "discoverability is explicit and opt-out immediately revokes availability", %{
    recipient: recipient,
    city: city
  } do
    assert {:error, :invitation_consent_required} =
             Invitations.create_availability(recipient.id, availability_attrs(city))

    assert {:ok, setting} =
             Invitations.update_settings(recipient.id, %{
               "enabled" => true,
               "shareable_fields" => %{"display_name" => true}
             })

    assert setting.enabled

    assert {:ok, availability} =
             Invitations.create_availability(recipient.id, availability_attrs(city))

    assert availability.visible

    assert {:ok, opted_out} = Invitations.update_settings(recipient.id, %{"enabled" => false})
    refute opted_out.enabled

    assert %Availability{visible: false, revoked_at: %DateTime{}} =
             Repo.get(Availability, availability.id)

    assert [] = Invitations.list_availabilities(recipient.id)
  end

  test "candidate cards expose only consented fields and exclude block pairs", %{
    host: host,
    recipient: recipient,
    city: city
  } do
    activity = published_activity(host, city, 3)
    enable_and_add_availability(recipient, city, %{"display_name" => true})

    assert {:ok,
            %{
              candidates: [
                %{id: recipient_id, availability: "traveler", display_name: "Recipient"}
              ]
            }} =
             Invitations.invitation_candidates(activity.id, host.id)

    assert recipient_id == recipient.id

    Repo.insert!(%Block{blocker_id: host.id, blocked_id: recipient.id})
    assert {:ok, %{candidates: []}} = Invitations.invitation_candidates(activity.id, host.id)
  end

  test "send uses immutable distinct quota events, suppresses retries, and decline does not reserve a seat",
       %{host: host, recipient: recipient, city: city} do
    activity = published_activity(host, city, 2)
    enable_and_add_availability(recipient, city, %{})

    assert {:ok, %{outcomes: [%{status: "sent", invitation_id: invitation_id}]}} =
             Invitations.send_invitations(activity.id, host.id, [recipient.id])

    assert Repo.aggregate(InvitationQuotaEvent, :count) == 1
    assert Repo.get!(TripPals.Activities.Activity, activity.id).going_count == 1

    assert {:ok, %{outcomes: [%{status: "unavailable"}]}} =
             Invitations.send_invitations(activity.id, host.id, [recipient.id])

    assert {:ok, %Invitation{status: "declined"}} =
             Invitations.decline(invitation_id, recipient.id)

    assert Repo.aggregate(InvitationQuotaEvent, :count) == 1
    assert Repo.get!(TripPals.Activities.Activity, activity.id).going_count == 1
    assert [%{status: "declined"}] = Invitations.list_invitations(recipient.id)
  end

  test "full activities do not expose candidates or create invitations", %{
    host: host,
    recipient: recipient,
    city: city
  } do
    activity = published_activity(host, city, 2)
    enable_and_add_availability(recipient, city, %{})

    Repo.update_all(
      from(activity in TripPals.Activities.Activity, where: activity.id == ^activity.id),
      set: [going_count: 2]
    )

    assert {:error, :activity_full} = Invitations.invitation_candidates(activity.id, host.id)

    assert {:error, :activity_full} =
             Invitations.send_invitations(activity.id, host.id, [recipient.id])

    assert Repo.aggregate(Invitation, :count) == 0
  end

  test "a bounded batch has generic per-recipient outcomes and a material change requires review",
       %{
         host: host,
         recipient: recipient,
         other: other,
         city: city
       } do
    activity = published_activity(host, city, 4)
    enable_and_add_availability(recipient, city, %{})

    assert {:ok, %{outcomes: outcomes}} =
             Invitations.send_invitations(activity.id, host.id, [recipient.id, other.id])

    assert Enum.any?(outcomes, &(&1.recipient_id == recipient.id and &1.status == "sent"))
    assert Enum.any?(outcomes, &(&1.recipient_id == other.id and &1.status == "unavailable"))

    Repo.update_all(
      from(activity_record in TripPals.Activities.Activity,
        where: activity_record.id == ^activity.id
      ),
      inc: [version: 1]
    )

    assert {:ok, :ok} = Invitations.reconcile_activity(activity.id)

    assert %Invitation{status: "needs_review", unavailable_reason: "activity_changed"} =
             Repo.get_by!(Invitation, activity_id: activity.id, recipient_id: recipient.id)
  end

  defp completed_user(name) do
    with {:ok, user} <- Accounts.create_user(),
         {:ok, _profile} <-
           Accounts.update_me(user.id, %{
             "display_name" => name,
             "adult_confirmation" => true,
             "community_rule_version" => "v1"
           }) do
      {:ok, user}
    end
  end

  defp enable_and_add_availability(user, city, shareable_fields) do
    assert {:ok, _} =
             Invitations.update_settings(user.id, %{
               "enabled" => true,
               "shareable_fields" => shareable_fields
             })

    assert {:ok, _} = Invitations.create_availability(user.id, availability_attrs(city))
  end

  defp availability_attrs(city) do
    %{
      "city_id" => city.id,
      "role" => "traveler",
      "start_local_date" => Date.to_iso8601(Date.utc_today()),
      "end_local_date" => Date.to_iso8601(Date.add(Date.utc_today(), 3)),
      "visible" => true,
      "time_preferences" => %{"daytime" => true},
      "shareable_fields" => %{}
    }
  end

  defp published_activity(host, city, capacity) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(host.id, %{
        "city_id" => city.id,
        "title" => "Invitation activity",
        "category" => "culture",
        "description" => "A safe public activity",
        "start_at" => DateTime.to_iso8601(start_at),
        "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
        "iana_timezone" => city.iana_timezone,
        "public_area" => "City centre",
        "participant_meeting_details" => "Provided after RSVP",
        "cost_amount" => "0.00",
        "currency" => "KES",
        "capacity_total" => capacity
      })

    {:ok, activity} = Activities.publish(draft.id, host.id)
    activity
  end
end
