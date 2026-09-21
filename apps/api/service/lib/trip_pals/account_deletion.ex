defmodule TripPals.AccountDeletion do
  @moduledoc """
  Durable, server-authoritative account deletion workflow.

  Deletion is deliberately a state transition rather than a database `DELETE`:
  immutable safety and audit history can remain under the documented retention
  policy while all authentication, discoverability, RSVP, and chat access are
  revoked in the same transaction.
  """

  import Ecto.Query

  alias TripPals.AccountDeletion.Deletion
  alias TripPals.AccountDeletion.RetentionRecord
  alias TripPals.Accounts
  alias TripPals.Accounts.AuthIdentity
  alias TripPals.Accounts.PasskeyCredential
  alias TripPals.Accounts.Profile
  alias TripPals.Accounts.RefreshToken
  alias TripPals.Accounts.Session
  alias TripPals.Accounts.User
  alias TripPals.Accounts.WebAuthnChallenge
  alias TripPals.Activities.Activity
  alias TripPals.Conversations.ConversationMembership
  alias TripPals.Invitations.Availability
  alias TripPals.Invitations.Invitation
  alias TripPals.Invitations.InvitationSetting
  alias TripPals.Notifications.Device
  alias TripPals.Participation.ParticipationHistory
  alias TripPals.Participation.Record
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo
  alias TripPals.Safety.AuditEntry
  alias TripPals.Safety.ModerationCase
  alias TripPals.Safety.Report
  alias TripPals.Workers.DeletionWorkflow

  @policy_version "privacy-retention-v1"
  @safety_retention_days 2_555

  def request(user_id, session_id) do
    with %Session{user_id: ^user_id} = session <- Repo.get(Session, session_id),
         true <- Accounts.recently_authenticated?(session) do
      Repo.transaction(fn -> request_locked(user_id) end)
      |> maybe_enqueue()
    else
      _ -> {:error, :recent_auth_required}
    end
  end

  # Called by the durable worker. It is intentionally safe to retry after a
  # successful immediate access revocation.
  def run(user_id) do
    Repo.transaction(fn ->
      case locked_deletion(user_id) do
        nil -> Repo.rollback(:not_found)
        %Deletion{status: "completed"} = deletion -> deletion
        %Deletion{} = deletion -> complete_locked(deletion)
      end
    end)
  end

  def get(user_id) do
    case Repo.get_by(Deletion, user_id: user_id) do
      nil -> {:error, :not_found}
      deletion -> {:ok, view(deletion)}
    end
  end

  def view(%Deletion{} = deletion) do
    %{
      status: deletion.status,
      requested_at: deletion.requested_at,
      access_revoked_at: deletion.access_revoked_at,
      completed_at: deletion.completed_at,
      retention_review_at: deletion.retention_review_at,
      message:
        "Account access is revoked immediately; legally required safety and audit records are retained only for their documented review period."
    }
  end

  defp request_locked(user_id) do
    now = DateTime.utc_now()

    case locked_deletion(user_id) do
      %Deletion{} = deletion ->
        request_view(deletion)

      nil ->
        with %User{} = user <- locked_user(user_id),
             {:ok, deletion} <- insert_deletion(user.id, now),
             :ok <- revoke_access_locked(user, deletion, now) do
          Repo.get!(Deletion, deletion.id) |> request_view()
        else
          nil -> Repo.rollback(:not_found)
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp maybe_enqueue({:ok, result}) do
    case Oban.insert(DeletionWorkflow.new(%{"user_id" => result_user_id(result)})) do
      {:ok, _job} -> {:ok, result}
      # Access has already been revoked atomically. The cron/operations path can
      # safely retry final retention processing without restoring access.
      {:error, _reason} -> {:ok, result}
    end
  end

  defp maybe_enqueue({:error, _reason} = error), do: error

  defp result_user_id(%{user_id: user_id}), do: user_id

  defp request_view(%Deletion{} = deletion) do
    deletion
    |> view()
    |> Map.put(:user_id, deletion.user_id)
  end

  defp locked_user(user_id) do
    Repo.one(from(user in User, where: user.id == ^user_id, lock: "FOR UPDATE"))
  end

  defp locked_deletion(user_id) do
    Repo.one(from(deletion in Deletion, where: deletion.user_id == ^user_id, lock: "FOR UPDATE"))
  end

  defp insert_deletion(user_id, now) do
    %Deletion{user_id: user_id}
    |> Deletion.changeset(%{
      status: "requested",
      policy_version: @policy_version,
      requested_at: now
    })
    |> Repo.insert()
  end

  defp revoke_access_locked(user, deletion, now) do
    with :ok <- revoke_sessions_and_tokens(user.id, now),
         :ok <- invalidate_devices(user.id, now),
         :ok <- remove_authentication_material(user.id),
         :ok <- disable_discoverability_and_availability(user.id, now),
         :ok <- revoke_pending_invitations(user.id, now),
         :ok <- release_future_participations(user.id, now),
         :ok <- cancel_future_hosted_activities(user.id, now),
         :ok <- revoke_chat_access(user.id, now),
         :ok <- retain_and_deidentify_safety_material(user.id, deletion, now),
         :ok <- mark_user_deleted(user, now),
         :ok <- record_deletion_audit(user.id, deletion, now),
         :ok <- mark_access_revoked(deletion, now),
         :ok <- outbox(deletion.id, now) do
      :ok
    end
  end

  defp revoke_sessions_and_tokens(user_id, now) do
    session_ids = from(session in Session, where: session.user_id == ^user_id, select: session.id)

    from(token in RefreshToken, where: token.session_id in subquery(session_ids))
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    from(session in Session, where: session.user_id == ^user_id and is_nil(session.revoked_at))
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    :ok
  end

  defp invalidate_devices(user_id, now) do
    from(device in Device, where: device.user_id == ^user_id and device.status == "active")
    |> Repo.update_all(set: [status: "invalidated", invalidated_at: now, updated_at: now])

    :ok
  end

  defp remove_authentication_material(user_id) do
    from(identity in AuthIdentity, where: identity.user_id == ^user_id) |> Repo.delete_all()

    from(credential in PasskeyCredential, where: credential.user_id == ^user_id)
    |> Repo.delete_all()

    from(challenge in WebAuthnChallenge, where: challenge.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  defp disable_discoverability_and_availability(user_id, now) do
    from(profile in Profile, where: profile.user_id == ^user_id)
    |> Repo.update_all(
      set: [
        display_name: "Deleted member",
        invitation_discoverable: false,
        profile_completed_at: nil,
        updated_at: now
      ]
    )

    from(setting in InvitationSetting, where: setting.user_id == ^user_id)
    |> Repo.update_all(set: [enabled: false, revoked_at: now, updated_at: now])

    from(availability in Availability, where: availability.user_id == ^user_id)
    |> Repo.update_all(set: [visible: false, revoked_at: now, updated_at: now])

    :ok
  end

  defp revoke_pending_invitations(user_id, now) do
    from(invitation in Invitation,
      where:
        invitation.status == "pending" and
          (invitation.recipient_id == ^user_id or invitation.host_id == ^user_id)
    )
    |> Repo.update_all(set: [status: "revoked", responded_at: now, updated_at: now])

    :ok
  end

  defp release_future_participations(user_id, now) do
    future_participation_ids =
      from(participation in Record,
        join: activity in Activity,
        on: activity.id == participation.activity_id,
        where:
          participation.user_id == ^user_id and participation.status in ["going", "interested"] and
            activity.start_at > ^now,
        select: participation.activity_id
      )
      |> Repo.all()
      |> Enum.uniq()

    Enum.reduce_while(future_participation_ids, :ok, fn activity_id, :ok ->
      case release_locked_participation(activity_id, user_id, now) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp release_locked_participation(activity_id, user_id, now) do
    with %Activity{} = activity <-
           Repo.one(
             from(activity in Activity, where: activity.id == ^activity_id, lock: "FOR UPDATE")
           ),
         %Record{} = participation <-
           Repo.one(
             from(participation in Record,
               where:
                 participation.activity_id == ^activity_id and participation.user_id == ^user_id,
               lock: "FOR UPDATE"
             )
           ) do
      prior_status = participation.status

      with {:ok, updated} <-
             participation
             |> Ecto.Changeset.change(status: "left", left_at: now, updated_at: now)
             |> Repo.update(),
           :ok <- decrement_going_count(activity, prior_status),
           {:ok, _history} <-
             %ParticipationHistory{
               participation_id: updated.id,
               activity_id: activity.id,
               user_id: user_id
             }
             |> ParticipationHistory.changeset(%{
               from_status: prior_status,
               to_status: "left",
               reason: "account_deletion"
             })
             |> Repo.insert() do
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp decrement_going_count(_activity, status) when status != "going", do: :ok

  defp decrement_going_count(activity, "going") do
    case Repo.update_all(
           from(locked in Activity, where: locked.id == ^activity.id and locked.going_count > 0),
           inc: [going_count: -1]
         ) do
      {1, _} -> :ok
      _ -> {:error, :seat_release_failed}
    end
  end

  defp cancel_future_hosted_activities(user_id, now) do
    from(activity in Activity,
      where:
        activity.host_id == ^user_id and activity.start_at > ^now and
          activity.status in ["draft", "published", "host_confirmed", "pending_review"]
    )
    |> Repo.update_all(
      set: [
        status: "canceled",
        cancellation_reason: "Host account unavailable",
        concluded_at: now,
        updated_at: now
      ],
      inc: [version: 1]
    )

    :ok
  end

  defp revoke_chat_access(user_id, now) do
    from(membership in ConversationMembership,
      where: membership.user_id == ^user_id and membership.status == "active"
    )
    |> Repo.update_all(set: [status: "revoked", revoked_at: now, updated_at: now])

    :ok
  end

  defp retain_and_deidentify_safety_material(user_id, deletion, now) do
    retention_until = DateTime.add(now, @safety_retention_days * 86_400, :second)

    reports =
      Repo.all(from(report in Report, where: report.reporter_id == ^user_id, select: report.id))

    case insert_retention_records(deletion.id, "safety", "report", reports, retention_until, now) do
      :ok ->
        from(report in Report, where: report.id in ^reports)
        |> Repo.update_all(set: [reporter_id: nil, updated_at: now])

        case_ids =
          from(moderation_case in ModerationCase,
            where: moderation_case.report_id in ^reports,
            select: moderation_case.id
          )
          |> Repo.all()

        insert_retention_records(
          deletion.id,
          "case",
          "moderation_case",
          case_ids,
          retention_until,
          now
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_deletion_audit(user_id, deletion, now) do
    with {:ok, audit} <-
           %AuditEntry{actor_id: user_id, subject_id: user_id}
           |> AuditEntry.changeset(%{
             action: "account_deletion_requested",
             scope: "privacy",
             reason: "account deletion requested",
             metadata: %{policy_version: @policy_version}
           })
           |> Repo.insert(),
         :ok <-
           insert_retention_records(
             deletion.id,
             "audit",
             "audit_log",
             [audit.id],
             DateTime.add(now, @safety_retention_days * 86_400, :second),
             now
           ) do
      :ok
    end
  end

  defp insert_retention_records(_deletion_id, _category, _type, [], _until, _now), do: :ok

  defp insert_retention_records(deletion_id, category, record_type, ids, retention_until, now) do
    rows =
      Enum.map(ids, fn record_id ->
        %{
          id: Ecto.UUID.generate(),
          account_deletion_id: deletion_id,
          category: category,
          record_type: record_type,
          record_id: record_id,
          retention_until: retention_until,
          deidentified_at: now,
          inserted_at: now
        }
      end)

    {_, nil} =
      Repo.insert_all(RetentionRecord, rows,
        on_conflict: :nothing,
        conflict_target: [:account_deletion_id, :record_type, :record_id]
      )

    :ok
  rescue
    _error -> {:error, :retention_record_failed}
  end

  defp mark_user_deleted(user, now) do
    user
    |> User.changeset(%{status: "deleted"})
    |> Ecto.Changeset.change(restricted_at: now, updated_at: now)
    |> Repo.update()
    |> case do
      {:ok, _user} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_access_revoked(deletion, now) do
    deletion
    |> Deletion.changeset(%{status: "access_revoked", access_revoked_at: now})
    |> Repo.update()
    |> case do
      {:ok, _deletion} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp outbox(deletion_id, now) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(%{
      topic: "privacy",
      event_type: "account.deletion_access_revoked",
      aggregate_type: "account_deletion",
      aggregate_id: deletion_id,
      payload: %{account_deletion_id: deletion_id},
      available_at: now
    })
    |> Repo.insert()
    |> case do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_locked(deletion) do
    now = DateTime.utc_now()
    review_at = DateTime.add(now, @safety_retention_days * 86_400, :second)

    deletion
    |> Deletion.changeset(%{
      status: "completed",
      completed_at: now,
      retention_review_at: review_at
    })
    |> Repo.update!()
  end
end
