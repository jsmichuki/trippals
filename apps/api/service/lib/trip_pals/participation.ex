defmodule TripPals.Participation do
  @moduledoc """
  Server-authoritative RSVP and plan state. Seat-changing transitions lock the
  activity row, so the host's published seat plus Going participations can
  never exceed the activity capacity.
  """

  import Ecto.Query

  alias TripPals.Accounts.User
  alias TripPals.Activities.Activity
  alias TripPals.Conversations.Conversation
  alias TripPals.Conversations.ConversationMembership
  alias TripPals.Participation.ParticipationHistory
  alias TripPals.Participation.Record
  alias TripPals.Platform
  alias TripPals.Repo
  alias TripPals.Safety.Block

  @joinable ~w(published host_confirmed)
  @terminal ~w(completed canceled expired outcome_unknown restricted pending_review draft)
  @default_page_size 20
  @max_page_size 50

  # Two-argument commands are for trusted jobs/context tests. HTTP uses the
  # idempotent variants below, which store and replay the safe response body.
  def interest(activity_id, user_id),
    do: transaction(fn -> interest_locked(activity_id, user_id) end)

  def join(activity_id, user_id), do: transaction(fn -> join_locked(activity_id, user_id) end)
  def leave(activity_id, user_id), do: transaction(fn -> leave_locked(activity_id, user_id) end)

  def reconfirm(activity_id, user_id, true),
    do: transaction(fn -> reconfirm_locked(activity_id, user_id) end)

  def reconfirm(activity_id, user_id, false), do: leave(activity_id, user_id)
  def reconfirm(_activity_id, _user_id, _answer), do: {:error, :invalid_reconfirmation}

  def attendance(activity_id, user_id, attendance)
      when attendance in ["attended", "not_attended", "prefer_not_to_say"],
      do: transaction(fn -> attendance_locked(activity_id, user_id, attendance) end)

  def attendance(_activity_id, _user_id, _attendance), do: {:error, :invalid_attendance}

  def interest(activity_id, user_id, key, request_hash),
    do: idempotent("interest", activity_id, user_id, key, request_hash, &interest_locked/2)

  def join(activity_id, user_id, key, request_hash),
    do: idempotent("join", activity_id, user_id, key, request_hash, &join_locked/2)

  def leave(activity_id, user_id, key, request_hash),
    do: idempotent("leave", activity_id, user_id, key, request_hash, &leave_locked/2)

  def reconfirm(activity_id, user_id, answer, key, request_hash) when answer in [true, false] do
    command = if answer, do: &reconfirm_locked/2, else: &leave_locked/2
    idempotent("reconfirm", activity_id, user_id, key, request_hash, command)
  end

  def reconfirm(_activity_id, _user_id, _answer, _key, _request_hash),
    do: {:error, :invalid_reconfirmation}

  def attendance(activity_id, user_id, attendance, key, request_hash)
      when attendance in ["attended", "not_attended", "prefer_not_to_say"] do
    idempotent("attendance", activity_id, user_id, key, request_hash, fn id, actor_id ->
      attendance_locked(id, actor_id, attendance)
    end)
  end

  def attendance(_activity_id, _user_id, _attendance, _key, _request_hash),
    do: {:error, :invalid_attendance}

  def list_plans(user_id, params \\ %{}) do
    with {:ok, limit} <- plan_limit(params["limit"]),
         {:ok, cursor} <- decode_cursor(params["cursor"]) do
      now = DateTime.utc_now()

      participation_plans =
        from(participation in Record,
          join: activity in Activity,
          on: activity.id == participation.activity_id,
          where: participation.user_id == ^user_id,
          select: {participation, activity}
        )
        |> Repo.all()
        |> Enum.map(fn {participation, activity} -> plan(activity, participation, false, now) end)

      hosting_plans =
        from(activity in Activity, where: activity.host_id == ^user_id)
        |> Repo.all()
        |> Enum.map(&plan(&1, nil, true, now))

      plans =
        (participation_plans ++ hosting_plans)
        |> Enum.uniq_by(& &1.activity_id)
        |> Enum.sort_by(
          fn plan -> {DateTime.to_unix(plan.updated_at, :microsecond), plan.activity_id} end,
          :desc
        )
        |> after_cursor(cursor)

      {page, remaining} = Enum.split(plans, limit)

      {:ok,
       %{
         plans: Enum.map(page, &Map.delete(&1, :updated_at)),
         next_cursor: next_cursor(page, remaining),
         views: %{
           going: Enum.count(plans, &(&1.kind == "going")),
           interested: Enum.count(plans, &(&1.kind == "interested")),
           hosting: Enum.count(plans, &(&1.kind == "hosting")),
           invitations: 0,
           past: Enum.count(plans, &(&1.kind == "past")),
           terminal: Enum.count(plans, &(&1.kind == "terminal"))
         }
       }}
    end
  end

  def participation_view(%Record{} = participation) do
    %{
      activity_id: participation.activity_id,
      participation_id: participation.id,
      status: participation.status,
      reconfirmed_at: participation.reconfirmed_at,
      attendance: participation.attendance,
      left_at: participation.left_at
    }
  end

  defp idempotent(operation, activity_id, user_id, key, request_hash, command) do
    Repo.transaction(fn ->
      scope = "activity:#{activity_id}:#{operation}"

      case Platform.claim_idempotency(user_id, scope, key, request_hash) do
        {:ok, :replay, claim} ->
          claim.response_body

        {:ok, :in_progress, _claim} ->
          Repo.rollback(:idempotency_in_progress)

        {:ok, :new, claim} ->
          with {:ok, participation} <- command.(activity_id, user_id),
               response = participation_view(participation),
               {:ok, _claim} <- Platform.record_idempotency_response(claim, 200, response) do
            response
          else
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp transaction(command) do
    Repo.transaction(fn ->
      case command.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp interest_locked(activity_id, user_id) do
    with {:ok, activity} <- locked_activity(activity_id),
         :ok <- active_account?(user_id),
         :ok <- not_host?(activity, user_id),
         :ok <- no_block_conflict?(activity, user_id),
         :ok <- joinable?(activity) do
      case Repo.get_by(Record, activity_id: activity_id, user_id: user_id) do
        %Record{status: "going"} = record -> {:ok, record}
        %Record{status: "interested"} = record -> {:ok, record}
        record -> transition_interest(activity, user_id, record)
      end
    end
  end

  defp join_locked(activity_id, user_id) do
    with {:ok, activity} <- locked_activity(activity_id),
         :ok <- active_account?(user_id),
         :ok <- not_host?(activity, user_id),
         :ok <- no_block_conflict?(activity, user_id),
         :ok <- joinable?(activity) do
      case Repo.get_by(Record, activity_id: activity_id, user_id: user_id) do
        %Record{status: "going"} = record ->
          # A retry without a stored idempotency response remains harmless.
          {:ok, record}

        record ->
          with :ok <- capacity_available?(activity),
               {:ok, participation} <- set_status(activity, user_id, record, "going"),
               :ok <- increment_going_count(activity),
               :ok <- set_membership(activity.id, user_id, "active"),
               :ok <- history_and_outbox(participation, record && record.status, "going", nil) do
            {:ok, participation}
          end
      end
    end
  end

  defp leave_locked(activity_id, user_id) do
    with {:ok, activity} <- locked_activity(activity_id),
         :ok <- active_account?(user_id),
         :ok <- not_host?(activity, user_id),
         %Record{} = record <- Repo.get_by(Record, activity_id: activity_id, user_id: user_id) do
      case record do
        %Record{status: "left"} ->
          {:ok, record}

        _ ->
          with :ok <- leave_permitted?(activity, record),
               {:ok, participation} <- set_status(activity, user_id, record, "left"),
               :ok <- decrement_going_count(activity, record),
               :ok <- set_membership(activity.id, user_id, "revoked"),
               :ok <- history_and_outbox(participation, record.status, "left", "left") do
            {:ok, participation}
          end
      end
    else
      nil -> {:error, :not_going}
    end
  end

  defp reconfirm_locked(activity_id, user_id) do
    with {:ok, activity} <- locked_activity(activity_id),
         :ok <- joinable?(activity),
         %Record{status: "going"} = record <-
           Repo.get_by(Record, activity_id: activity_id, user_id: user_id),
         {:ok, updated} <-
           Repo.update(Ecto.Changeset.change(record, reconfirmed_at: DateTime.utc_now())),
         :ok <- history_and_outbox(updated, "going", "going", "reconfirmed") do
      {:ok, updated}
    else
      nil -> {:error, :not_going}
      %Record{} -> {:error, :not_going}
    end
  end

  defp attendance_locked(activity_id, user_id, attendance) do
    with {:ok, activity} <- locked_activity(activity_id),
         :ok <- attendance_permitted?(activity),
         %Record{status: "going"} = record <-
           Repo.get_by(Record, activity_id: activity_id, user_id: user_id),
         {:ok, updated} <- Repo.update(Ecto.Changeset.change(record, attendance: attendance)),
         :ok <- history_and_outbox(updated, "going", "going", "attendance_reported") do
      {:ok, updated}
    else
      nil -> {:error, :not_going}
      %Record{} -> {:error, :not_going}
    end
  end

  defp transition_interest(activity, user_id, record) do
    with {:ok, participation} <- set_status(activity, user_id, record, "interested"),
         :ok <- history_and_outbox(participation, record && record.status, "interested", nil) do
      {:ok, participation}
    end
  end

  defp locked_activity(activity_id) do
    case Repo.one(
           from activity in Activity, where: activity.id == ^activity_id, lock: "FOR UPDATE"
         ) do
      nil -> {:error, :not_found}
      activity -> {:ok, activity}
    end
  end

  defp active_account?(user_id) do
    case Repo.get(User, user_id) do
      %User{status: "active"} -> :ok
      %User{} -> {:error, :account_restricted}
      nil -> {:error, :not_found}
    end
  end

  defp not_host?(%Activity{host_id: user_id}, user_id), do: {:error, :host_already_going}
  defp not_host?(_activity, _user_id), do: :ok

  defp no_block_conflict?(activity, user_id) do
    participant_ids =
      [
        activity.host_id
        | Repo.all(
            from participation in Record,
              where:
                participation.activity_id == ^activity.id and participation.status == "going",
              select: participation.user_id
          )
      ]

    blocked? =
      Repo.exists?(
        from block in Block,
          where:
            (block.blocker_id == ^user_id and block.blocked_id in ^participant_ids) or
              (block.blocked_id == ^user_id and block.blocker_id in ^participant_ids)
      )

    if blocked?, do: {:error, :block_conflict}, else: :ok
  end

  defp joinable?(%Activity{status: status, start_at: start_at}) when status in @joinable do
    if DateTime.compare(start_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :activity_not_joinable}
  end

  defp joinable?(_activity), do: {:error, :activity_not_joinable}
  defp leave_permitted?(%Activity{status: status}, _record) when status not in @terminal, do: :ok
  defp leave_permitted?(_activity, _record), do: {:error, :activity_not_joinable}

  defp attendance_permitted?(%Activity{status: status})
       when status in ["in_progress", "completed"], do: :ok

  defp attendance_permitted?(_activity), do: {:error, :attendance_not_available}

  defp capacity_available?(%Activity{going_count: count, capacity_total: total})
       when count < total, do: :ok

  defp capacity_available?(_activity), do: {:error, :capacity_full}

  defp set_status(activity, user_id, nil, status) do
    %Record{activity_id: activity.id, user_id: user_id}
    |> Record.changeset(status_attributes(status))
    |> Repo.insert()
  end

  defp set_status(_activity, _user_id, %Record{status: status} = record, status),
    do: {:ok, record}

  defp set_status(_activity, _user_id, record, status) do
    record |> Record.changeset(status_attributes(status)) |> Repo.update()
  end

  defp status_attributes("going"), do: %{status: "going", left_at: nil}
  defp status_attributes("left"), do: %{status: "left", left_at: DateTime.utc_now()}
  defp status_attributes("interested"), do: %{status: "interested", left_at: nil}

  defp increment_going_count(activity) do
    case Repo.update_all(
           from(item in Activity,
             where: item.id == ^activity.id and item.going_count < item.capacity_total
           ),
           inc: [going_count: 1]
         ) do
      {1, _} -> :ok
      _ -> {:error, :capacity_full}
    end
  end

  defp decrement_going_count(_activity, %Record{status: status}) when status != "going", do: :ok

  defp decrement_going_count(activity, %Record{status: "going"}) do
    case Repo.update_all(
           from(item in Activity, where: item.id == ^activity.id and item.going_count > 1),
           inc: [going_count: -1]
         ) do
      {1, _} -> :ok
      _ -> {:error, :seat_count_invariant}
    end
  end

  defp set_membership(activity_id, user_id, status) do
    case Repo.get_by(Conversation, activity_id: activity_id) do
      nil ->
        {:error, :conversation_missing}

      conversation ->
        now = DateTime.utc_now()
        revoked_at = if status == "revoked", do: now, else: nil

        membership =
          ConversationMembership.changeset(
            %ConversationMembership{conversation_id: conversation.id, user_id: user_id},
            %{status: status, revoked_at: revoked_at}
          )

        case Repo.insert(
               membership,
               on_conflict: [set: [status: status, revoked_at: revoked_at, updated_at: now]],
               conflict_target: [:conversation_id, :user_id]
             ) do
          {:ok, _membership} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp history_and_outbox(participation, from_status, to_status, reason) do
    history =
      ParticipationHistory.changeset(
        %ParticipationHistory{
          participation_id: participation.id,
          activity_id: participation.activity_id,
          user_id: participation.user_id
        },
        %{from_status: from_status, to_status: to_status, reason: reason}
      )

    with {:ok, _history} <- Repo.insert(history),
         {:ok, _event} <-
           Platform.enqueue_outbox_event(%{
             topic: "participations",
             event_type: "participation.#{to_status}",
             aggregate_type: "activity",
             aggregate_id: participation.activity_id,
             payload: %{user_id: participation.user_id, status: to_status, reason: reason},
             available_at: DateTime.utc_now()
           }) do
      :ok
    end
  end

  defp plan(activity, participation, host?, now) do
    %{
      activity_id: activity.id,
      title: activity.title,
      activity_status: activity.status,
      participation_status: participation && participation.status,
      kind: plan_kind(activity, participation, host?, now),
      start_at: activity.start_at,
      iana_timezone: activity.iana_timezone,
      explanatory_state: explanatory_state(activity),
      updated_at: max_updated_at(activity, participation)
    }
  end

  defp plan_kind(%Activity{status: status}, _participation, _host?, _now)
       when status in ["canceled", "expired", "outcome_unknown", "restricted"], do: "terminal"

  defp plan_kind(%Activity{status: "completed"}, _participation, _host?, _now), do: "past"

  defp plan_kind(%Activity{start_at: start_at}, _participation, _host?, now) when start_at <= now,
    do: "past"

  defp plan_kind(_activity, _participation, true, _now), do: "hosting"
  defp plan_kind(_activity, %Record{status: "going"}, false, _now), do: "going"
  defp plan_kind(_activity, %Record{status: "interested"}, false, _now), do: "interested"
  defp plan_kind(_activity, _participation, _host?, _now), do: "past"

  defp explanatory_state(%Activity{status: "canceled"}), do: "canceled"
  defp explanatory_state(%Activity{status: "expired"}), do: "expired"
  defp explanatory_state(%Activity{status: "outcome_unknown"}), do: "outcome_unknown"
  defp explanatory_state(%Activity{status: "completed"}), do: "completed"
  defp explanatory_state(_activity), do: "scheduled"

  defp max_updated_at(activity, nil), do: activity.updated_at

  defp max_updated_at(activity, participation),
    do:
      if(participation.updated_at > activity.updated_at,
        do: participation.updated_at,
        else: activity.updated_at
      )

  defp plan_limit(nil), do: {:ok, @default_page_size}

  defp plan_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit >= 1 and limit <= @max_page_size -> {:ok, limit}
      _ -> {:error, {:validation_failed, %{limit: ["is invalid"]}}}
    end
  end

  defp plan_limit(_value), do: {:error, {:validation_failed, %{limit: ["is invalid"]}}}

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [timestamp, id] <- String.split(decoded, "|", parts: 2),
         {microseconds, ""} <- Integer.parse(timestamp) do
      {:ok, {microseconds, id}}
    else
      _ -> {:error, {:validation_failed, %{cursor: ["is invalid"]}}}
    end
  end

  defp decode_cursor(_cursor), do: {:error, {:validation_failed, %{cursor: ["is invalid"]}}}

  defp after_cursor(plans, nil), do: plans

  defp after_cursor(plans, {microseconds, id}) do
    Enum.filter(plans, fn plan ->
      {updated_at, activity_id} =
        {DateTime.to_unix(plan.updated_at, :microsecond), plan.activity_id}

      updated_at < microseconds or (updated_at == microseconds and activity_id < id)
    end)
  end

  defp next_cursor([], _remaining), do: nil
  defp next_cursor(_page, []), do: nil

  defp next_cursor(page, _remaining) do
    last = List.last(page)

    Base.url_encode64("#{DateTime.to_unix(last.updated_at, :microsecond)}|#{last.activity_id}",
      padding: false
    )
  end
end
