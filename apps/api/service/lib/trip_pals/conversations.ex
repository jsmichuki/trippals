defmodule TripPals.Conversations do
  @moduledoc """
  Durable, activity-scoped group conversation operations.

  The context is the authorization boundary for both HTTP and Channel adapters:
  no adapter may use Presence, a client claim, or a previous join as proof that
  a member can read or write. Every operation reads current membership again.
  """

  import Ecto.Query

  alias TripPals.Accounts.User
  alias TripPals.Activities.Activity
  alias TripPals.Conversations.Conversation
  alias TripPals.Conversations.ConversationMembership
  alias TripPals.Conversations.EventSystemMessage
  alias TripPals.Conversations.Message
  alias TripPals.Platform
  alias TripPals.Repo
  alias TripPals.Safety.Block

  @default_page_size 50
  @max_page_size 100
  @readable_states ~w(active bounded_grace read_only safety_freeze frozen)
  @writable_states ~w(active bounded_grace)
  @writable_activity_states ~w(published host_confirmed in_progress)

  def list_messages(conversation_id, actor_id, params \\ %{}) do
    with {:ok, limit} <- page_limit(params["limit"]),
         {:ok, after_sequence} <- decode_cursor(params["cursor"]),
         {:ok, conversation} <- authorize(conversation_id, actor_id, :read) do
      items = history_page(conversation.id, after_sequence, limit + 1)
      {page, remainder} = Enum.split(items, limit)

      {:ok,
       %{
         messages: Enum.map(page, &history_view/1),
         next_cursor: next_cursor(page, remainder)
       }}
    end
  end

  def send_message(conversation_id, actor_id, attributes, idempotency_key, request_hash)
      when is_binary(idempotency_key) and is_binary(request_hash) do
    with {:ok, client_message_id} <- client_message_id(attributes),
         {:ok, body} <- message_body(attributes) do
      result =
        Repo.transaction(fn ->
          scope = "conversation:#{conversation_id}:message"

          case Platform.claim_idempotency(actor_id, scope, idempotency_key, request_hash) do
            {:ok, :replay, claim} ->
              {:replay, claim.response_body}

            {:ok, :in_progress, _claim} ->
              Repo.rollback(:idempotency_in_progress)

            {:ok, :new, claim} ->
              if allow_send?(actor_id, conversation_id) do
                case persist_message(conversation_id, actor_id, client_message_id, body) do
                  {:ok, message, duplicate?} ->
                    response = message_view(message)

                    with {:ok, _claim} <-
                           Platform.record_idempotency_response(claim, 201, response) do
                      {:persisted, response, not duplicate?}
                    else
                      {:error, reason} -> Repo.rollback(reason)
                    end

                  {:error, reason} ->
                    Repo.rollback(reason)
                end
              else
                Repo.rollback(:message_rate_limited)
              end

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)

      after_message_transaction(result, conversation_id)
    end
  end

  def send_message(_conversation_id, _actor_id, _attributes, _idempotency_key, _request_hash),
    do: {:error, :idempotency_required}

  # System messages are server-authored durable state transitions. The payload
  # deliberately accepts only safe, projection-level values; message bodies and
  # protected meeting details cannot be injected into an event system message.
  def record_system_event(conversation_id, actor_id, event_type, payload \\ %{})
      when is_binary(event_type) and is_map(payload) do
    result =
      Repo.transaction(fn ->
        with {:ok, conversation} <- authorize(conversation_id, actor_id, :read),
             {:ok, sequence} <- next_sequence(conversation),
             {:ok, event} <-
               %EventSystemMessage{conversation_id: conversation.id, actor_id: actor_id}
               |> EventSystemMessage.changeset(%{
                 event_type: event_type,
                 sequence: sequence,
                 payload: safe_system_payload(payload)
               })
               |> Repo.insert() do
          {:persisted, system_event_view(event)}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {:persisted, event}} ->
        broadcast_conversation(conversation_id, "system_event", event)
        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def authorize(conversation_id, actor_id, intent) when intent in [:read, :write] do
    with %User{status: "active"} <- Repo.get(User, actor_id),
         {conversation, activity, membership} <- conversation_record(conversation_id, actor_id),
         true <- active_member?(conversation, membership, actor_id),
         true <- not blocked_with_current_members?(conversation, actor_id),
         :ok <- permitted_state?(conversation, activity, intent) do
      {:ok, conversation}
    else
      nil -> {:error, :conversation_not_found}
      %User{} -> {:error, :conversation_unavailable}
      false -> {:error, :conversation_unavailable}
      :error -> {:error, :conversation_not_found}
      {:error, _reason} = error -> error
    end
  end

  def authorize_activity(activity_id, actor_id) do
    case Repo.get_by(Conversation, activity_id: activity_id) do
      %Conversation{} = conversation -> authorize(conversation.id, actor_id, :read)
      nil -> {:error, :conversation_not_found}
    end
  end

  def pinned_logistics(conversation_id, actor_id) do
    with {:ok, %Conversation{activity_id: activity_id}} <-
           authorize(conversation_id, actor_id, :read),
         %Activity{} = activity <- Repo.get(Activity, activity_id) do
      {:ok,
       %{
         activity_id: activity.id,
         version: activity.version,
         start_at: activity.start_at,
         end_at: activity.end_at,
         iana_timezone: activity.iana_timezone,
         public_area: activity.public_area,
         participant_meeting_details: activity.participant_meeting_details,
         activity_status: activity.status
       }}
    else
      nil -> {:error, :conversation_not_found}
      {:error, _reason} = error -> error
    end
  end

  # Lifecycle adapters call this after the canonical Activity transaction has
  # committed. The allow-list excludes message bodies, private logistics, and
  # participant facts from the activity topic.
  def broadcast_activity_projection(activity_id, projection) when is_map(projection) do
    safe_projection =
      projection
      |> Map.take([
        :activity_id,
        :version,
        :status,
        :host_confirmed,
        "activity_id",
        "version",
        "status",
        "host_confirmed"
      ])
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), safe_payload_value(value)} end)

    Phoenix.PubSub.broadcast(
      TripPals.PubSub,
      "activity:#{activity_id}",
      {:activity_event, "activity_updated", safe_projection}
    )
  end

  def message_view(%Message{} = message) do
    %{
      id: message.id,
      kind: "message",
      sequence: message.sequence,
      client_message_id: message.client_message_id,
      sender_id: message.sender_id,
      body: message_body_for_view(message),
      created_at: message.inserted_at
    }
  end

  defp persist_message(conversation_id, actor_id, client_message_id, body) do
    with {:ok, conversation} <- locked_conversation(conversation_id),
         {:ok, _conversation} <- authorize_locked(conversation, actor_id, :write) do
      case Repo.get_by(Message,
             conversation_id: conversation.id,
             sender_id: actor_id,
             client_message_id: client_message_id
           ) do
        %Message{body: ^body} = message ->
          {:ok, message, true}

        %Message{} ->
          {:error, :client_message_id_reused}

        nil ->
          with {:ok, sequence} <- next_sequence(conversation),
               {:ok, message} <-
                 %Message{conversation_id: conversation.id, sender_id: actor_id}
                 |> Message.changeset(%{
                   client_message_id: client_message_id,
                   sequence: sequence,
                   body: body
                 })
                 |> Repo.insert() do
            {:ok, message, false}
          end
      end
    end
  end

  defp after_message_transaction({:ok, {:persisted, response, true}}, conversation_id) do
    broadcast_conversation(conversation_id, "message_created", response)
    {:ok, response}
  end

  defp after_message_transaction({:ok, {:persisted, response, false}}, _conversation_id),
    do: {:ok, response}

  defp after_message_transaction({:ok, {:replay, response}}, _conversation_id),
    do: {:ok, response}

  defp after_message_transaction({:error, reason}, _conversation_id), do: {:error, reason}

  defp history_page(conversation_id, after_sequence, limit) do
    messages =
      from(message in Message,
        where: message.conversation_id == ^conversation_id and message.sequence > ^after_sequence,
        order_by: [asc: message.sequence],
        limit: ^limit,
        select: {:message, message}
      )

    system_events =
      from(event in EventSystemMessage,
        where: event.conversation_id == ^conversation_id and event.sequence > ^after_sequence,
        order_by: [asc: event.sequence],
        limit: ^limit,
        select: {:system, event}
      )

    (Repo.all(messages) ++ Repo.all(system_events))
    |> Enum.sort_by(fn {_kind, item} -> item.sequence end)
    |> Enum.take(limit)
  end

  defp history_view({:message, message}), do: message_view(message)
  defp history_view({:system, event}), do: system_event_view(event)

  defp system_event_view(%EventSystemMessage{} = event) do
    %{
      id: event.id,
      kind: "system",
      sequence: event.sequence,
      event_type: event.event_type,
      payload: event.payload,
      created_at: event.inserted_at
    }
  end

  defp conversation_record(conversation_id, actor_id) do
    Repo.one(
      from(conversation in Conversation,
        join: activity in Activity,
        on: activity.id == conversation.activity_id,
        left_join: membership in ConversationMembership,
        on:
          membership.conversation_id == conversation.id and membership.user_id == ^actor_id and
            membership.status == "active",
        where: conversation.id == ^conversation_id,
        select: {conversation, activity, membership}
      )
    )
  end

  defp locked_conversation(conversation_id) do
    case Repo.one(
           from(conversation in Conversation,
             where: conversation.id == ^conversation_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Conversation{} = conversation -> {:ok, conversation}
      nil -> {:error, :conversation_not_found}
    end
  end

  defp authorize_locked(conversation, actor_id, intent) do
    with %User{status: "active"} <- Repo.get(User, actor_id),
         %Activity{} = activity <- Repo.get(Activity, conversation.activity_id),
         membership <-
           Repo.get_by(ConversationMembership,
             conversation_id: conversation.id,
             user_id: actor_id,
             status: "active"
           ),
         true <- active_member?(conversation, membership, actor_id),
         true <- not blocked_with_current_members?(conversation, actor_id),
         :ok <- permitted_state?(conversation, activity, intent) do
      {:ok, conversation}
    else
      nil -> {:error, :conversation_unavailable}
      %User{} -> {:error, :conversation_unavailable}
      false -> {:error, :conversation_unavailable}
      {:error, _reason} = error -> error
    end
  end

  defp active_member?(%Conversation{host_id: host_id}, _membership, actor_id)
       when host_id == actor_id,
       do: true

  defp active_member?(_conversation, %ConversationMembership{status: "active"}, _actor_id),
    do: true

  defp active_member?(_conversation, _membership, _actor_id), do: false

  defp blocked_with_current_members?(conversation, actor_id) do
    member_ids =
      from(membership in ConversationMembership,
        where: membership.conversation_id == ^conversation.id and membership.status == "active",
        select: membership.user_id
      )
      |> Repo.all()
      |> Enum.uniq()

    participant_ids = Enum.uniq([conversation.host_id | member_ids])

    Repo.exists?(
      from(block in Block,
        where:
          (block.blocker_id == ^actor_id and block.blocked_id in ^participant_ids) or
            (block.blocked_id == ^actor_id and block.blocker_id in ^participant_ids)
      )
    )
  end

  defp permitted_state?(%Conversation{status: status}, _activity, :read)
       when status in @readable_states,
       do: :ok

  defp permitted_state?(%Conversation{status: status}, %Activity{status: activity_status}, :write)
       when status in @writable_states and activity_status in @writable_activity_states,
       do: :ok

  defp permitted_state?(_conversation, _activity, _intent), do: {:error, :conversation_read_only}

  defp next_sequence(%Conversation{} = conversation) do
    sequence = conversation.next_message_sequence + 1

    case Repo.update_all(
           from(item in Conversation,
             where:
               item.id == ^conversation.id and
                 item.next_message_sequence == ^conversation.next_message_sequence
           ),
           set: [next_message_sequence: sequence]
         ) do
      {1, _} -> {:ok, sequence}
      _ -> {:error, :conversation_sequence_conflict}
    end
  end

  defp client_message_id(%{"client_message_id" => value}) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, {:validation_failed, %{client_message_id: ["is invalid"]}}}
    end
  end

  defp client_message_id(_),
    do: {:error, {:validation_failed, %{client_message_id: ["is required"]}}}

  defp message_body(%{"body" => body}) when is_binary(body) do
    case Message.changeset(%Message{}, %{
           client_message_id: Ecto.UUID.generate(),
           sequence: 1,
           body: body
         }) do
      %{valid?: true} -> {:ok, body}
      changeset -> {:error, changeset}
    end
  end

  defp message_body(_), do: {:error, {:validation_failed, %{body: ["is required"]}}}

  defp page_limit(nil), do: {:ok, @default_page_size}

  defp page_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit >= 1 and limit <= @max_page_size -> {:ok, limit}
      _ -> {:error, {:validation_failed, %{limit: ["is invalid"]}}}
    end
  end

  defp page_limit(_), do: {:error, {:validation_failed, %{limit: ["is invalid"]}}}

  defp decode_cursor(nil), do: {:ok, 0}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, encoded} <- Base.url_decode64(cursor, padding: false),
         {sequence, ""} <- Integer.parse(encoded),
         true <- sequence >= 0 do
      {:ok, sequence}
    else
      _ -> {:error, {:validation_failed, %{cursor: ["is invalid"]}}}
    end
  end

  defp decode_cursor(_), do: {:error, {:validation_failed, %{cursor: ["is invalid"]}}}

  defp next_cursor([], _remainder), do: nil
  defp next_cursor(_page, []), do: nil

  defp next_cursor(page, _remainder) do
    page
    |> List.last()
    |> then(fn {_kind, item} -> Integer.to_string(item.sequence) end)
    |> Base.url_encode64(padding: false)
  end

  defp message_body_for_view(%Message{moderation_state: "visible", body: body}), do: body
  defp message_body_for_view(_message), do: nil

  defp safe_system_payload(payload) do
    payload
    |> Map.take([
      :activity_id,
      :version,
      :status,
      :reason_code,
      :member_count,
      "activity_id",
      "version",
      "status",
      "reason_code",
      "member_count"
    ])
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), safe_payload_value(value)} end)
  end

  defp safe_payload_value(value) when is_binary(value) and byte_size(value) <= 120, do: value
  defp safe_payload_value(value) when is_integer(value) or is_boolean(value), do: value
  defp safe_payload_value(_value), do: nil

  defp broadcast_conversation(conversation_id, event, payload) do
    Phoenix.PubSub.broadcast(
      TripPals.PubSub,
      "conversation:#{conversation_id}",
      {:conversation_event, event, payload}
    )
  end

  defp allow_send?(actor_id, conversation_id) do
    table = message_rate_table()
    minute = System.system_time(:second) |> div(60)
    key = {actor_id, conversation_id, minute}
    count = :ets.update_counter(table, key, {2, 1}, {key, 0})
    count <= 30
  end

  defp message_rate_table do
    case :ets.whereis(:trip_pals_conversation_message_rate_limits) do
      :undefined ->
        try do
          :ets.new(:trip_pals_conversation_message_rate_limits, [:named_table, :public, :set])
        rescue
          ArgumentError -> :trip_pals_conversation_message_rate_limits
        end

      table ->
        table
    end
  end
end
