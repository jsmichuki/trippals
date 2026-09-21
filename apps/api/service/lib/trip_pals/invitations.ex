defmodule TripPals.Invitations do
  @moduledoc """
  Explicit invitation consent and activity-scoped candidate selection.

  Candidate queries never consult browsing data and only return fields selected
  by a recipient. Sending is serialized by the activity row lock, so quota
  events, invitations, and notification outbox records commit together.
  """

  import Ecto.Query

  alias TripPals.Accounts.Profile
  alias TripPals.Accounts.User
  alias TripPals.Activities.Activity
  alias TripPals.Invitations.Availability
  alias TripPals.Invitations.HostInvitationRateWindow
  alias TripPals.Invitations.Invitation
  alias TripPals.Invitations.InvitationQuotaEvent
  alias TripPals.Invitations.InvitationSetting
  alias TripPals.Participation.Record
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo
  alias TripPals.Safety.Block

  @activity_quota 15
  @host_rate_limit 30
  @host_rate_window_seconds 3_600
  @invitation_ttl_seconds 7 * 24 * 3_600
  @candidate_limit 50
  @open_statuses ~w(published host_confirmed)
  @terminal_statuses ~w(canceled expired completed outcome_unknown restricted pending_review)

  def get_settings(user_id) do
    Repo.get_by(InvitationSetting, user_id: user_id) ||
      %InvitationSetting{user_id: user_id, enabled: false, shareable_fields: %{}}
  end

  def update_settings(user_id, attributes) when is_map(attributes) do
    now = DateTime.utc_now()
    current = get_settings(user_id)
    enabled = Map.get(attributes, "enabled", current.enabled)

    setting_attributes = %{
      enabled: enabled,
      shareable_fields: Map.get(attributes, "shareable_fields", current.shareable_fields),
      consented_at: if(enabled, do: current.consented_at || now, else: current.consented_at),
      revoked_at: if(enabled, do: nil, else: now)
    }

    Repo.transaction(fn ->
      with {:ok, setting} <-
             current |> InvitationSetting.changeset(setting_attributes) |> Repo.insert_or_update(),
           :ok <- maybe_revoke_availabilities(user_id, enabled, now) do
        setting
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def list_availabilities(user_id) do
    from(availability in Availability,
      where: availability.user_id == ^user_id and is_nil(availability.revoked_at),
      order_by: [desc: availability.updated_at]
    )
    |> Repo.all()
  end

  def create_availability(user_id, attributes) do
    with :ok <- consent_enabled?(user_id) do
      %Availability{user_id: user_id}
      |> Availability.changeset(normalize_availability_attributes(attributes))
      |> Repo.insert()
    end
  end

  def update_availability(user_id, availability_id, attributes) do
    with :ok <- consent_enabled?(user_id),
         %Availability{} = availability <-
           Repo.get_by(Availability, id: availability_id, user_id: user_id),
         true <- is_nil(availability.revoked_at) do
      availability
      |> Availability.changeset(normalize_availability_attributes(attributes))
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def revoke_availability(user_id, availability_id) do
    from(availability in Availability,
      where:
        availability.id == ^availability_id and availability.user_id == ^user_id and
          is_nil(availability.revoked_at)
    )
    |> Repo.update_all(
      set: [visible: false, revoked_at: DateTime.utc_now(), updated_at: DateTime.utc_now()]
    )
    |> case do
      {1, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  def invitation_candidates(activity_id, host_id, params \\ %{}) do
    with {:ok, activity} <- eligible_host_activity(activity_id, host_id),
         :ok <- invitation_matching_enabled?(activity.city_id),
         :ok <- seats_remaining?(activity),
         {:ok, limit} <- candidate_limit(params["limit"]) do
      now = DateTime.utc_now()
      {start_date, end_date} = activity_dates(activity)

      from(availability in Availability,
        as: :availability,
        join: setting in InvitationSetting,
        on: setting.user_id == availability.user_id,
        join: profile in Profile,
        on: profile.user_id == availability.user_id,
        join: user in User,
        on: user.id == availability.user_id,
        where: availability.city_id == ^activity.city_id,
        where: availability.visible and is_nil(availability.revoked_at),
        where: setting.enabled and is_nil(setting.revoked_at),
        where: user.status == "active",
        where: availability.user_id != ^host_id,
        where: is_nil(availability.expires_at) or availability.expires_at > ^now,
        where:
          is_nil(availability.start_local_date) or availability.start_local_date <= ^end_date,
        where: is_nil(availability.end_local_date) or availability.end_local_date >= ^start_date,
        where:
          not exists(
            from(participation in Record,
              where:
                participation.activity_id == ^activity.id and
                  participation.user_id == parent_as(:availability).user_id and
                  participation.status in ["going", "interested"]
            )
          ),
        where:
          not exists(
            from(invitation in Invitation,
              where:
                invitation.activity_id == ^activity.id and
                  invitation.recipient_id == parent_as(:availability).user_id
            )
          ),
        where:
          not exists(
            from(block in Block,
              where:
                (block.blocker_id == ^host_id and
                   block.blocked_id == parent_as(:availability).user_id) or
                  (block.blocked_id == ^host_id and
                     block.blocker_id == parent_as(:availability).user_id)
            )
          ),
        order_by: [asc: availability.id],
        limit: ^limit,
        select: {availability, setting, profile}
      )
      |> Repo.all()
      |> Enum.map(&candidate_card/1)
      |> then(&{:ok, %{candidates: &1}})
    end
  end

  # Matching stays disabled unless a city has been explicitly enabled after
  # its privacy, abuse, moderation, and concierge-pilot launch review.
  defp invitation_matching_enabled?(city_id) do
    enabled_city_ids =
      Application.get_env(:trip_pals, :feature_flags, [])
      |> Keyword.get(:invitation_matching_city_ids, [])

    if city_id in enabled_city_ids, do: :ok, else: {:error, :invitation_matching_disabled}
  end

  def send_invitations(activity_id, host_id, recipient_ids) when is_list(recipient_ids) do
    recipient_ids =
      recipient_ids |> Enum.filter(&is_binary/1) |> Enum.uniq() |> Enum.take(@activity_quota)

    if recipient_ids == [] do
      {:error, :invalid_recipients}
    else
      Repo.transaction(fn ->
        with {:ok, activity} <- locked_host_activity(activity_id, host_id),
             :ok <- invitation_matching_enabled?(activity.city_id),
             :ok <- seats_remaining?(activity),
             :ok <- host_rate_available?(host_id, length(recipient_ids)),
             {:ok, outcomes} <- send_locked(activity, host_id, recipient_ids) do
          %{outcomes: outcomes}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def list_invitations(recipient_id, params \\ %{}) do
    now = DateTime.utc_now()
    status = params["status"]

    from(invitation in Invitation,
      join: activity in Activity,
      on: activity.id == invitation.activity_id,
      where: invitation.recipient_id == ^recipient_id,
      order_by: [desc: invitation.sent_at, desc: invitation.id],
      select: {invitation, activity}
    )
    |> maybe_filter_invitation_status(status)
    |> Repo.all()
    |> Enum.map(&recipient_view(&1, now))
  end

  def get_invitation(recipient_id, invitation_id) do
    case Repo.get_by(Invitation, id: invitation_id, recipient_id: recipient_id) do
      nil ->
        {:error, :not_found}

      invitation ->
        {:ok,
         recipient_view(
           {invitation, Repo.get!(Activity, invitation.activity_id)},
           DateTime.utc_now()
         )}
    end
  end

  def decline(invitation_id, recipient_id) do
    Repo.transaction(fn ->
      invitation =
        from(invitation in Invitation,
          where: invitation.id == ^invitation_id and invitation.recipient_id == ^recipient_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case invitation do
        nil ->
          Repo.rollback(:not_found)

        %Invitation{status: "declined"} = invitation ->
          invitation

        %Invitation{status: "pending"} = invitation ->
          case invitation
               |> Ecto.Changeset.change(status: "declined", responded_at: DateTime.utc_now())
               |> Repo.update() do
            {:ok, declined} -> declined
            {:error, changeset} -> Repo.rollback(changeset)
          end

        _ ->
          Repo.rollback(:invitation_unavailable)
      end
    end)
  end

  # The Participation context owns the final-seat transaction. It should call
  # this after it has locked the activity but before it grants membership; this
  # helper locks the invitation and marks it joined only after the callback
  # returns {:ok, _}. It is intentionally public as the integration seam.
  def with_locked_invitation_join(invitation_id, recipient_id, join_fun)
      when is_function(join_fun, 0) do
    invitation =
      from(invitation in Invitation,
        where: invitation.id == ^invitation_id and invitation.recipient_id == ^recipient_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    with %Invitation{status: "pending"} = invitation <- invitation,
         :ok <- pending_invitation?(invitation),
         {:ok, result} <- join_fun.(),
         {:ok, _} <-
           invitation
           |> Ecto.Changeset.change(status: "joined", responded_at: DateTime.utc_now())
           |> Repo.update() do
      {:ok, result}
    else
      nil -> {:error, :not_found}
      %Invitation{} -> {:error, :invitation_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def reconcile_activity(activity_id) do
    Repo.transaction(fn ->
      activity = Repo.get(Activity, activity_id)
      now = DateTime.utc_now()

      with %Activity{} = activity <- activity do
        from(invitation in Invitation,
          where:
            invitation.activity_id == ^activity.id and invitation.status == "pending" and
              invitation.event_version_seen != ^activity.version
        )
        |> Repo.update_all(
          set: [status: "needs_review", unavailable_reason: "activity_changed", updated_at: now]
        )

        {status, reason} = reconciliation_state(activity, now)

        if status do
          from(invitation in Invitation,
            where: invitation.activity_id == ^activity.id and invitation.status == "pending"
          )
          |> Repo.update_all(set: [status: status, unavailable_reason: reason, updated_at: now])
        end

        :ok
      else
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  defp send_locked(activity, host_id, recipient_ids) do
    now = DateTime.utc_now()

    quota_used =
      Repo.aggregate(
        from(event in InvitationQuotaEvent, where: event.activity_id == ^activity.id),
        :count
      )

    available = max(@activity_quota - quota_used, 0)

    {outcomes, successes} =
      recipient_ids
      |> Enum.reduce({[], []}, fn recipient_id, {outcomes, successes} ->
        if length(successes) >= available or
             not candidate_eligible?(activity, host_id, recipient_id, now) do
          {[%{recipient_id: recipient_id, status: "unavailable"} | outcomes], successes}
        else
          attrs = %{
            activity_id: activity.id,
            host_id: host_id,
            recipient_id: recipient_id,
            status: "pending",
            sent_at: now,
            expires_at: DateTime.add(now, @invitation_ttl_seconds, :second),
            event_version_seen: activity.version
          }

          case Repo.insert(Invitation.changeset(%Invitation{}, attrs)) do
            {:ok, invitation} ->
              {:ok, _event} =
                Repo.insert(
                  InvitationQuotaEvent.changeset(%InvitationQuotaEvent{}, %{
                    activity_id: activity.id,
                    recipient_id: recipient_id,
                    invitation_id: invitation.id,
                    sent_at: now
                  })
                )

              {:ok, _outbox} = invitation_outbox(invitation, now)

              {[
                 %{recipient_id: recipient_id, status: "sent", invitation_id: invitation.id}
                 | outcomes
               ], [recipient_id | successes]}

            {:error, _changeset} ->
              {[%{recipient_id: recipient_id, status: "unavailable"} | outcomes], successes}
          end
        end
      end)

    increment_host_rate(host_id, length(successes), now)
    {:ok, Enum.reverse(outcomes)}
  end

  defp candidate_eligible?(activity, host_id, recipient_id, now) do
    case invitation_candidates_for_ids(activity, host_id, [recipient_id], now) do
      [^recipient_id] -> true
      _ -> false
    end
  end

  defp invitation_candidates_for_ids(activity, host_id, ids, now) do
    {start_date, end_date} = activity_dates(activity)

    from(availability in Availability,
      as: :availability,
      join: setting in InvitationSetting,
      on: setting.user_id == availability.user_id,
      join: user in User,
      on: user.id == availability.user_id,
      where: availability.user_id in ^ids and availability.city_id == ^activity.city_id,
      where: availability.visible and is_nil(availability.revoked_at),
      where: setting.enabled and is_nil(setting.revoked_at) and user.status == "active",
      where: is_nil(availability.expires_at) or availability.expires_at > ^now,
      where: is_nil(availability.start_local_date) or availability.start_local_date <= ^end_date,
      where: is_nil(availability.end_local_date) or availability.end_local_date >= ^start_date,
      where: availability.user_id != ^host_id,
      where:
        not exists(
          from(block in Block,
            where:
              (block.blocker_id == ^host_id and
                 block.blocked_id == parent_as(:availability).user_id) or
                (block.blocked_id == ^host_id and
                   block.blocker_id == parent_as(:availability).user_id)
          )
        ),
      where:
        not exists(
          from(participation in Record,
            where:
              participation.activity_id == ^activity.id and
                participation.user_id == parent_as(:availability).user_id and
                participation.status in ["going", "interested"]
          )
        ),
      where:
        not exists(
          from(invitation in Invitation,
            where:
              invitation.activity_id == ^activity.id and
                invitation.recipient_id == parent_as(:availability).user_id
          )
        ),
      select: availability.user_id
    )
    |> Repo.all()
  end

  defp eligible_host_activity(activity_id, host_id) do
    case Repo.get(Activity, activity_id) do
      %Activity{host_id: ^host_id} = activity when activity.status in @open_statuses ->
        {:ok, activity}

      %Activity{} ->
        {:error, :invitation_unavailable}

      nil ->
        {:error, :not_found}
    end
  end

  defp locked_host_activity(activity_id, host_id) do
    case Repo.one(
           from(activity in Activity, where: activity.id == ^activity_id, lock: "FOR UPDATE")
         ) do
      %Activity{host_id: ^host_id} = activity when activity.status in @open_statuses ->
        {:ok, activity}

      %Activity{} ->
        {:error, :invitation_unavailable}

      nil ->
        {:error, :not_found}
    end
  end

  defp seats_remaining?(%Activity{going_count: going_count, capacity_total: capacity})
       when going_count < capacity, do: :ok

  defp seats_remaining?(_activity), do: {:error, :activity_full}

  defp consent_enabled?(user_id) do
    case Repo.get_by(InvitationSetting, user_id: user_id) do
      %InvitationSetting{enabled: true, revoked_at: nil} -> :ok
      _ -> {:error, :invitation_consent_required}
    end
  end

  defp maybe_revoke_availabilities(_user_id, true, _now), do: :ok

  defp maybe_revoke_availabilities(user_id, false, now) do
    from(availability in Availability,
      where: availability.user_id == ^user_id and is_nil(availability.revoked_at)
    )
    |> Repo.update_all(set: [visible: false, revoked_at: now, updated_at: now])

    :ok
  end

  defp host_rate_available?(host_id, requested) do
    now = DateTime.utc_now()

    bucket = rate_bucket(now)

    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [host_id])

    used =
      Repo.one(
        from(window in HostInvitationRateWindow,
          where: window.host_id == ^host_id and window.window_started_at == ^bucket,
          select: window.successful_sends
        )
      ) || 0

    if used + requested <= @host_rate_limit, do: :ok, else: {:error, :host_rate_limited}
  end

  defp increment_host_rate(_host_id, 0, _now), do: :ok

  defp increment_host_rate(host_id, count, now) do
    bucket = rate_bucket(now)

    Repo.insert_all(
      HostInvitationRateWindow,
      [
        %{
          host_id: host_id,
          window_started_at: bucket,
          successful_sends: count,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [inc: [successful_sends: count], set: [updated_at: now]],
      conflict_target: [:host_id, :window_started_at]
    )

    :ok
  end

  defp invitation_outbox(invitation, now) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(%{
      topic: "invitation:#{invitation.recipient_id}",
      event_type: "invitation.sent",
      aggregate_type: "invitation",
      aggregate_id: invitation.id,
      payload: %{invitation_id: invitation.id},
      available_at: now
    })
    |> Repo.insert()
  end

  defp candidate_card({availability, setting, profile}) do
    fields = Map.merge(setting.shareable_fields || %{}, availability.shareable_fields || %{})

    %{id: availability.user_id, availability: availability.role}
    |> maybe_share("display_name", fields, profile.display_name)
  end

  defp maybe_share(card, field, fields, value) do
    if Map.get(fields, field) == true and is_binary(value),
      do: Map.put(card, String.to_atom(field), value),
      else: card
  end

  defp recipient_view({invitation, activity}, now) do
    status = effective_status(invitation, activity, now)

    %{
      id: invitation.id,
      activity_id: invitation.activity_id,
      status: status,
      sent_at: invitation.sent_at,
      expires_at: invitation.expires_at,
      activity: %{
        id: activity.id,
        title: activity.title,
        start_at: activity.start_at,
        iana_timezone: activity.iana_timezone,
        public_area: activity.public_area
      }
    }
  end

  defp effective_status(%Invitation{status: "pending", expires_at: expires_at}, _activity, now)
       when expires_at <= now, do: "expired"

  defp effective_status(%Invitation{status: "pending"}, %Activity{status: status}, _now)
       when status in @terminal_statuses, do: "unavailable"

  defp effective_status(invitation, _activity, _now), do: invitation.status

  defp pending_invitation?(%Invitation{expires_at: expires_at}),
    do: if(expires_at > DateTime.utc_now(), do: :ok, else: {:error, :invitation_unavailable})

  defp reconciliation_state(activity, now) do
    cond do
      activity.status in @terminal_statuses -> {"unavailable", activity.status}
      activity.going_count >= activity.capacity_total -> {"unavailable", "activity_full"}
      DateTime.compare(activity.start_at, now) != :gt -> {"unavailable", "activity_started"}
      true -> {nil, nil}
    end
  end

  defp activity_dates(activity) do
    # PostgreSQL has the authoritative IANA timezone database in this release;
    # using it also avoids silently treating city-local days as UTC when tzdata
    # is intentionally not configured in the BEAM.
    %{rows: [[start_date, end_date]]} =
      Repo.query!(
        "SELECT ($1::timestamptz AT TIME ZONE $3)::date, ($2::timestamptz AT TIME ZONE $3)::date",
        [activity.start_at, activity.end_at, activity.iana_timezone]
      )

    {start_date, end_date}
  end

  defp rate_bucket(now) do
    now
    |> DateTime.truncate(:microsecond)
    |> DateTime.add(-rem(DateTime.to_unix(now), @host_rate_window_seconds), :second)
  end

  defp maybe_filter_invitation_status(query, nil), do: query

  defp maybe_filter_invitation_status(query, status),
    do: from([invitation, _activity] in query, where: invitation.status == ^status)

  defp candidate_limit(nil), do: {:ok, @candidate_limit}

  defp candidate_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit > 0 and limit <= @candidate_limit -> {:ok, limit}
      _ -> {:error, :invalid_limit}
    end
  end

  defp candidate_limit(_), do: {:error, :invalid_limit}

  defp normalize_availability_attributes(attributes) do
    attributes
    |> Map.take(
      ~w(city_id role start_local_date end_local_date time_preferences shareable_fields visible expires_at)
    )
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, String.to_existing_atom(key), value)
    end)
  end
end
