defmodule TripPalsWeb.V1.ConversationController do
  use TripPalsWeb, :controller

  alias Ecto.Changeset
  alias TripPals.Conversations
  alias TripPalsWeb.API.Response

  def messages(conn, %{"id" => conversation_id} = params) do
    case Conversations.list_messages(conversation_id, conn.assigns.current_actor.id, params) do
      {:ok, page} -> Response.ok(conn, page)
      error -> conversation_error(conn, error)
    end
  end

  def create_message(conn, %{"id" => conversation_id} = params) do
    case Conversations.send_message(
           conversation_id,
           conn.assigns.current_actor.id,
           params,
           conn.assigns.idempotency_key,
           request_hash(params)
         ) do
      {:ok, message} -> Response.ok(conn, message, 201)
      error -> conversation_error(conn, error)
    end
  end

  defp request_hash(params) do
    params
    |> Map.take(["body", "client_message_id"])
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp conversation_error(conn, {:error, %Changeset{} = changeset}) do
    Response.error(conn, :validation_failed, "Validation failed", 422, field_errors(changeset))
  end

  defp conversation_error(conn, {:error, {:validation_failed, fields}}),
    do: Response.error(conn, :validation_failed, "Validation failed", 422, fields)

  defp conversation_error(conn, {:error, :conversation_not_found}),
    do: Response.error(conn, :not_found, "The requested conversation was not found", 404)

  defp conversation_error(conn, {:error, :conversation_unavailable}),
    do:
      Response.error(conn, :conversation_unavailable, "Conversation access is not available", 403)

  defp conversation_error(conn, {:error, :conversation_read_only}),
    do: Response.error(conn, :conversation_read_only, "This conversation is read-only", 409)

  defp conversation_error(conn, {:error, :client_message_id_reused}),
    do: Response.error(conn, :client_message_id_reused, "Message retry data does not match", 409)

  defp conversation_error(conn, {:error, :idempotency_key_reused}),
    do:
      Response.error(
        conn,
        :idempotency_key_reused,
        "This idempotency key was used for another request",
        409
      )

  defp conversation_error(conn, {:error, :idempotency_in_progress}),
    do:
      Response.error(conn, :idempotency_in_progress, "This request is still being processed", 409)

  defp conversation_error(conn, {:error, :idempotency_required}),
    do: Response.error(conn, :idempotency_required, "An idempotency key is required", 400)

  defp conversation_error(conn, {:error, _reason}),
    do: Response.error(conn, :message_unavailable, "The message could not be sent", 422)

  defp field_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
