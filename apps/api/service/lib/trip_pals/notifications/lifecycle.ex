defmodule TripPals.Notifications.Lifecycle do
  @moduledoc false

  import Ecto.Query

  alias TripPals.Activities.Activity
  alias TripPals.Conversations.Conversation
  alias TripPals.Invitations.Invitation
  alias TripPals.Notifications.Device
  alias TripPals.Participation.Record
  alias TripPals.Repo

  @terminal_activity_states ~w(canceled expired completed outcome_unknown restricted)

  # The business policy intentionally notifies a host when confirmation is due;
  # it never silently concludes an activity or treats a missed deadline as
  # attendance. All comparisons are UTC instants persisted from city-local
  # policy cutoffs, avoiding a fixed-duration/DST calculation in the worker.
  def host_confirmation_reminders(now \\ DateTime.utc_now()) do
    from(activity in Activity,
      where:
        activity.status == "published" and not is_nil(activity.confirmation_deadline_at) and
          activity.confirmation_deadline_at <= ^now,
      select: activity
    )
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn activity, :ok ->
      attributes = %{
        user_id: activity.host_id,
        event_type: "activity.host_confirmation_due",
        essential: true,
        activity_id: activity.id,
        deep_link: "/activities/#{activity.id}",
        dedupe_key: "host_confirmation_due:#{activity.id}",
        payload: %{activity_id: activity.id, event_type: "activity.host_confirmation_due"}
      }

      case TripPals.Notifications.notify(attributes) do
        {:ok, _notification} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def attendance_reminders(now \\ DateTime.utc_now()) do
    from(participation in Record,
      join: activity in Activity,
      on: activity.id == participation.activity_id,
      where:
        participation.status == "going" and is_nil(participation.attendance) and
          activity.end_at <= ^now and activity.status in ["completed", "outcome_unknown"],
      select: {participation, activity}
    )
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn {participation, activity}, :ok ->
      attributes = %{
        user_id: participation.user_id,
        event_type: "activity.attendance_reminder",
        essential: false,
        activity_id: activity.id,
        deep_link: "/activities/#{activity.id}/attendance",
        dedupe_key: "attendance_reminder:#{activity.id}:#{participation.user_id}",
        payload: %{activity_id: activity.id, event_type: "activity.attendance_reminder"}
      }

      case TripPals.Notifications.notify(attributes) do
        {:ok, _notification} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def sweep_activity_lifecycle(now \\ DateTime.utc_now()) do
    # A passed end time is not completion. It creates an explanatory host task
    # so the host records an explicit outcome through the canonical context.
    from(activity in Activity,
      where:
        activity.end_at <= ^now and
          activity.status in ["published", "host_confirmed", "in_progress"],
      select: activity
    )
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn activity, :ok ->
      case TripPals.Notifications.notify(%{
             user_id: activity.host_id,
             event_type: "activity.outcome_required",
             essential: true,
             activity_id: activity.id,
             deep_link: "/activities/#{activity.id}",
             dedupe_key: "activity_outcome_required:#{activity.id}",
             payload: %{activity_id: activity.id, event_type: "activity.outcome_required"}
           }) do
        {:ok, _notification} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def sweep_invitations(now \\ DateTime.utc_now()) do
    from(invitation in Invitation,
      where: invitation.status == "pending" and invitation.expires_at <= ^now,
      select: invitation
    )
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn invitation, :ok ->
      result =
        Repo.transaction(fn ->
          locked =
            from(record in Invitation, where: record.id == ^invitation.id, lock: "FOR UPDATE")
            |> Repo.one()

          case locked do
            %Invitation{status: "pending", expires_at: expires_at} when expires_at <= now ->
              with {:ok, updated} <-
                     locked
                     |> Ecto.Changeset.change(status: "expired", responded_at: now)
                     |> Repo.update(),
                   {:ok, _notification} <-
                     TripPals.Notifications.insert_notification(%{
                       user_id: updated.recipient_id,
                       event_type: "invitation.expired",
                       essential: true,
                       activity_id: updated.activity_id,
                       invitation_id: updated.id,
                       deep_link: "/invitations/#{updated.id}",
                       dedupe_key: "invitation_expired:#{updated.id}",
                       payload: %{invitation_id: updated.id, activity_id: updated.activity_id}
                     }) do
                :ok
              else
                {:error, reason} -> Repo.rollback(reason)
              end

            _ ->
              :ok
          end
        end)

      case result do
        {:ok, :ok} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def sweep_conversation_retention do
    now = DateTime.utc_now()

    from(conversation in Conversation,
      join: activity in Activity,
      on: activity.id == conversation.activity_id,
      where:
        conversation.status in ["active", "bounded_grace"] and
          activity.status in @terminal_activity_states
    )
    |> Repo.update_all(set: [status: "read_only", updated_at: now])

    :ok
  end

  def cleanup_media do
    if Code.ensure_loaded?(TripPals.Media) and function_exported?(TripPals.Media, :cleanup, 0) do
      apply(TripPals.Media, :cleanup, [])
    else
      :ok
    end
  end

  def run_deletion(user_id) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      from(device in Device, where: device.user_id == ^user_id and device.status == "active")
      |> Repo.update_all(set: [status: "invalidated", invalidated_at: now, updated_at: now])

      if Code.ensure_loaded?(TripPals.Deletion) and function_exported?(TripPals.Deletion, :run, 1) do
        apply(TripPals.Deletion, :run, [user_id])
      else
        :ok
      end
    end)
  end
end
