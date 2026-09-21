defmodule TripPalsWeb.ConversationChannel do
  use TripPalsWeb, :channel

  alias TripPals.Conversations

  @impl true
  def join("conversation:" <> conversation_id, _params, socket) do
    case Conversations.pinned_logistics(conversation_id, socket.assigns.actor_id) do
      {:ok, pinned_logistics} ->
        Phoenix.PubSub.subscribe(TripPals.PubSub, "conversation:#{conversation_id}")

        {:ok, %{conversation_id: conversation_id, pinned_logistics: pinned_logistics},
         assign(socket, :conversation_id, conversation_id)}

      {:error, _reason} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("message:create", payload, socket) do
    client_message_id = payload["client_message_id"]
    body = payload["body"]

    request_hash =
      %{client_message_id: client_message_id, body: body}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    idempotency_key = "channel:#{client_message_id || "missing"}"

    case Conversations.send_message(
           socket.assigns.conversation_id,
           socket.assigns.actor_id,
           payload,
           idempotency_key,
           request_hash
         ) do
      {:ok, message} -> {:reply, {:ok, %{message: message}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: safe_reason(reason)}}, socket}
    end
  end

  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "unsupported"}}, socket}

  @impl true
  def handle_info({:conversation_event, event, payload}, socket) do
    # Membership can be revoked after a successful join. Re-check before
    # forwarding every durable event so an old Channel process is never an
    # authorization grant.
    case Conversations.authorize(socket.assigns.conversation_id, socket.assigns.actor_id, :read) do
      {:ok, _conversation} ->
        push(socket, event, payload)
        {:noreply, socket}

      {:error, _reason} ->
        {:stop, :normal, socket}
    end
  end

  defp safe_reason(:conversation_read_only), do: "read_only"
  defp safe_reason(:conversation_unavailable), do: "unauthorized"
  defp safe_reason(_reason), do: "message_rejected"
end
