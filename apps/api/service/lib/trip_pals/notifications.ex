defmodule TripPals.Notifications do
  @moduledoc """
  Durable in-app notification state and privacy-preserving push delivery setup.

  Call `insert_notification/1` from an enclosing domain transaction when a
  transition must atomically create both the in-app record and outbox event.
  The only payload persisted or sent to a provider is a stable identifier and
  event context; bodies, directions, tokens, availability, and evidence are
  rejected at this boundary.
  """

  import Ecto.Query

  alias TripPals.Notifications.Device
  alias TripPals.Notifications.Notification
  alias TripPals.Notifications.NotificationDelivery
  alias TripPals.Notifications.NotificationPreference
  alias TripPals.Platform
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo

  @default_page_size 20
  @max_page_size 50
  @payload_keys [
    {"activity_id", :activity_id},
    {"invitation_id", :invitation_id},
    {"conversation_id", :conversation_id},
    {"notification_id", :notification_id},
    {"event_type", :event_type}
  ]

  def get_preferences(user_id) do
    Repo.get_by(NotificationPreference, user_id: user_id) ||
      %NotificationPreference{
        user_id: user_id,
        essential_enabled: true,
        nonessential_enabled: true,
        push_enabled: true,
        muted_activity_ids: []
      }
  end

  def update_preferences(user_id, attributes, idempotency_key, request_hash)
      when is_map(attributes) do
    idempotent(user_id, "notification_preferences", idempotency_key, request_hash, fn ->
      preference = get_preferences(user_id)

      preference
      |> NotificationPreference.changeset(normalize_preferences(preference, attributes))
      |> Repo.insert_or_update()
      |> case do
        {:ok, updated} -> {:ok, preference_view(updated)}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  def register_device(user_id, attributes, idempotency_key, request_hash)
      when is_map(attributes) do
    idempotent(user_id, "devices", idempotency_key, request_hash, fn ->
      with {:ok, platform} <- platform(attributes),
           {:ok, token} <- device_token(attributes) do
        now = DateTime.utc_now()
        digest = token_digest(token)

        device =
          Repo.get_by(Device, platform: platform, token_digest: digest) ||
            %Device{platform: platform, token_digest: digest, user_id: user_id}

        device
        |> Device.changeset(%{
          platform: platform,
          token_digest: digest,
          token_ciphertext: TripPals.Notifications.TokenVault.encrypt!(token),
          token_last_four: String.slice(token, -4, 4),
          status: "active",
          last_seen_at: now,
          invalidated_at: nil
        })
        |> Ecto.Changeset.put_change(:user_id, user_id)
        |> Repo.insert_or_update()
        |> case do
          {:ok, registered} -> {:ok, device_view(registered)}
          {:error, changeset} -> {:error, changeset}
        end
      end
    end)
  end

  def invalidate_device(device_id, user_id) do
    now = DateTime.utc_now()

    from(device in Device, where: device.id == ^device_id and device.user_id == ^user_id)
    |> Repo.update_all(set: [status: "invalidated", invalidated_at: now, updated_at: now])
    |> case do
      {1, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  def invalidate_device_token(platform, token) when is_binary(token) do
    now = DateTime.utc_now()

    from(device in Device,
      where: device.platform == ^platform and device.token_digest == ^token_digest(token)
    )
    |> Repo.update_all(set: [status: "invalidated", invalidated_at: now, updated_at: now])

    :ok
  end

  def list_notifications(user_id, params \\ %{}) do
    with {:ok, limit} <- page_limit(params["limit"]),
         {:ok, cursor} <- decode_cursor(params["cursor"]) do
      query =
        from(notification in Notification,
          where: notification.user_id == ^user_id and is_nil(notification.dismissed_at),
          order_by: [desc: notification.inserted_at, desc: notification.id],
          limit: ^(limit + 1)
        )
        |> after_cursor(cursor)

      {items, remainder} = query |> Repo.all() |> Enum.split(limit)

      {:ok,
       %{
         notifications: Enum.map(items, &notification_view/1),
         next_cursor: next_cursor(items, remainder)
       }}
    end
  end

  def mark_read(user_id, notification_id, idempotency_key, request_hash) do
    idempotent(
      user_id,
      "notification:#{notification_id}:read",
      idempotency_key,
      request_hash,
      fn ->
        mark_read_record(user_id, notification_id)
      end
    )
  end

  defp mark_read_record(user_id, notification_id) do
    now = DateTime.utc_now()

    from(notification in Notification,
      where: notification.id == ^notification_id and notification.user_id == ^user_id
    )
    |> Repo.update_all(set: [read_at: now, updated_at: now])
    |> case do
      {1, _} -> {:ok, %{id: notification_id, read_at: now}}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Inserts the in-app record and its dispatch event without opening a second
  transaction. Use this in an `Ecto.Multi`/`Repo.transaction` transition.
  """
  def insert_notification(attributes) when is_map(attributes) do
    with {:ok, user_id} <- required_uuid(attributes, :user_id),
         {:ok, event_type} <- required_string(attributes, :event_type),
         {:ok, deep_link} <- required_string(attributes, :deep_link),
         {:ok, notification} <-
           %Notification{user_id: user_id}
           |> Notification.changeset(%{
             event_type: event_type,
             essential: Map.get(attributes, :essential, false),
             activity_id: Map.get(attributes, :activity_id),
             invitation_id: Map.get(attributes, :invitation_id),
             conversation_id: Map.get(attributes, :conversation_id),
             deep_link: deep_link,
             dedupe_key: Map.get(attributes, :dedupe_key),
             payload: safe_payload(attributes)
           })
           |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :dedupe_key]) do
      case notification_or_deduped(notification, user_id, Map.get(attributes, :dedupe_key)) do
        {:ok, persisted, true} ->
          outbox_notification(persisted)
          |> case do
            {:ok, _event} -> {:ok, persisted}
            {:error, reason} -> {:error, reason}
          end

        {:ok, persisted, false} ->
          {:ok, persisted}
      end
    end
  end

  def notify(attributes) when is_map(attributes) do
    Repo.transaction(fn ->
      case insert_notification(attributes) do
        {:ok, notification} -> notification
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def prepare_push_deliveries(notification_id) do
    Repo.transaction(fn ->
      notification = Repo.get(Notification, notification_id)

      with %Notification{} = notification <- notification,
           true <- should_deliver_push?(notification),
           devices <- active_devices(notification.user_id),
           :ok <- insert_push_deliveries(notification, devices) do
        %{notification_id: notification.id, deliveries: length(devices)}
      else
        nil -> Repo.rollback(:notification_not_found)
        false -> %{notification_id: notification_id, deliveries: 0}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_delivery(delivery_id), do: Repo.get(NotificationDelivery, delivery_id)

  def pending_push_delivery_ids(notification_id) do
    from(delivery in NotificationDelivery,
      where:
        delivery.notification_id == ^notification_id and delivery.channel == "push" and
          delivery.status == "pending",
      select: delivery.id
    )
    |> Repo.all()
  end

  def notification_view(%Notification{} = notification) do
    %{
      id: notification.id,
      event_type: notification.event_type,
      essential: notification.essential,
      activity_id: notification.activity_id,
      invitation_id: notification.invitation_id,
      conversation_id: notification.conversation_id,
      deep_link: notification.deep_link,
      payload: safe_payload(notification.payload),
      read_at: notification.read_at,
      created_at: notification.inserted_at
    }
  end

  def preference_view(%NotificationPreference{} = preference) do
    %{
      essential_enabled: preference.essential_enabled,
      nonessential_enabled: preference.nonessential_enabled,
      push_enabled: preference.push_enabled,
      muted_activity_ids: preference.muted_activity_ids
    }
  end

  def device_view(%Device{} = device) do
    %{
      id: device.id,
      platform: device.platform,
      status: device.status,
      last_seen_at: device.last_seen_at
    }
  end

  defp idempotent(user_id, scope, idempotency_key, request_hash, fun)
       when is_function(fun, 0) and is_binary(idempotency_key) and is_binary(request_hash) do
    Repo.transaction(fn ->
      case Platform.claim_idempotency(user_id, scope, idempotency_key, request_hash) do
        {:ok, :replay, claim} ->
          {:replay, claim.response_body}

        {:ok, :in_progress, _claim} ->
          Repo.rollback(:idempotency_in_progress)

        {:ok, :new, claim} ->
          case fun.() do
            {:ok, result} ->
              case Platform.record_idempotency_response(claim, 200, result) do
                {:ok, _claim} -> {:persisted, result}
                {:error, reason} -> Repo.rollback(reason)
              end

            {:error, reason} ->
              Repo.rollback(reason)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> normalize_idempotent_result()
  end

  defp idempotent(_user_id, _scope, _idempotency_key, _request_hash, _fun),
    do: {:error, :idempotency_required}

  defp normalize_idempotent_result({:ok, {:persisted, result}}), do: {:ok, result}
  defp normalize_idempotent_result({:ok, {:replay, result}}), do: {:ok, result}
  defp normalize_idempotent_result({:error, reason}), do: {:error, reason}

  defp normalize_preferences(preference, attributes) do
    %{
      essential_enabled: Map.get(attributes, "essential_enabled", preference.essential_enabled),
      nonessential_enabled:
        Map.get(attributes, "nonessential_enabled", preference.nonessential_enabled),
      push_enabled: Map.get(attributes, "push_enabled", preference.push_enabled),
      muted_activity_ids: Map.get(attributes, "muted_activity_ids", preference.muted_activity_ids)
    }
  end

  defp platform(%{"platform" => platform}) when platform in ["ios", "android"],
    do: {:ok, platform}

  defp platform(_attributes), do: {:error, :invalid_device}

  defp device_token(%{"token" => token}) when is_binary(token) and byte_size(token) >= 8,
    do: {:ok, token}

  defp device_token(_attributes), do: {:error, :invalid_device}

  defp token_digest(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  defp required_uuid(attributes, key) do
    case Map.get(attributes, key) do
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, :invalid_notification}
    end
  end

  defp required_string(attributes, key) do
    case Map.get(attributes, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, :invalid_notification}
    end
  end

  defp safe_payload(attributes) when is_map(attributes) do
    payload = Map.get(attributes, :payload, attributes)

    Enum.reduce(@payload_keys, %{}, fn {key, atom_key}, result ->
      value = Map.get(payload, key, Map.get(payload, atom_key))

      if is_binary(value) or is_boolean(value), do: Map.put(result, key, value), else: result
    end)
  end

  defp notification_or_deduped(notification, _user_id, nil), do: {:ok, notification, true}

  defp notification_or_deduped(notification, user_id, dedupe_key) do
    case notification.id do
      nil ->
        case Repo.get_by(Notification, user_id: user_id, dedupe_key: dedupe_key) do
          %Notification{} = existing -> {:ok, existing, false}
          nil -> {:error, :notification_not_found}
        end

      _ ->
        {:ok, notification, true}
    end
  end

  defp outbox_notification(notification) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(%{
      topic: "notification:#{notification.user_id}",
      event_type: "notification.created",
      aggregate_type: "notification",
      aggregate_id: notification.id,
      payload: %{notification_id: notification.id},
      available_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  defp should_deliver_push?(notification) do
    preference = get_preferences(notification.user_id)

    preference.push_enabled and
      (notification.essential or preference.nonessential_enabled) and
      notification.activity_id not in preference.muted_activity_ids
  end

  defp active_devices(user_id) do
    from(device in Device, where: device.user_id == ^user_id and device.status == "active")
    |> Repo.all()
  end

  defp insert_push_deliveries(notification, devices) do
    now = DateTime.utc_now()

    entries =
      Enum.map(devices, fn device ->
        %{
          id: Ecto.UUID.generate(),
          notification_id: notification.id,
          device_id: device.id,
          channel: "push",
          status: "pending",
          available_at: now,
          attempt_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    case entries do
      [] ->
        :ok

      _ ->
        {_, nil} =
          Repo.insert_all(NotificationDelivery, entries,
            on_conflict: :nothing,
            conflict_target: [:notification_id, :device_id, :channel]
          )

        :ok
    end
  end

  defp page_limit(nil), do: {:ok, @default_page_size}

  defp page_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit > 0 and limit <= @max_page_size -> {:ok, limit}
      _ -> {:error, {:validation_failed, %{limit: ["is invalid"]}}}
    end
  end

  defp page_limit(_value), do: {:error, {:validation_failed, %{limit: ["is invalid"]}}}

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         {timestamp, id} when is_binary(timestamp) and is_binary(id) <-
           :erlang.binary_to_term(decoded, [:safe]),
         {:ok, datetime, 0} <- DateTime.from_iso8601(timestamp) do
      {:ok, {datetime, id}}
    else
      _ -> {:error, {:validation_failed, %{cursor: ["is invalid"]}}}
    end
  end

  defp decode_cursor(_cursor), do: {:error, {:validation_failed, %{cursor: ["is invalid"]}}}

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, {inserted_at, id}) do
    where(
      query,
      [notification],
      notification.inserted_at < ^inserted_at or
        (notification.inserted_at == ^inserted_at and notification.id < ^id)
    )
  end

  defp next_cursor([], _remainder), do: nil
  defp next_cursor(_items, []), do: nil

  defp next_cursor(items, _remainder) do
    last = List.last(items)

    {last.inserted_at |> DateTime.to_iso8601(), last.id}
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end
end
