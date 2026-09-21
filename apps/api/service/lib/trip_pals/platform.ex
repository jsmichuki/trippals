defmodule TripPals.Platform do
  @moduledoc """
  Shared durable primitives for domain commands. Contexts use these functions
  inside their `Ecto.Multi` transactions; no HTTP adapter owns product state.
  """

  import Ecto.Query

  alias TripPals.Platform.IdempotencyKey
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo

  @idempotency_ttl_seconds 86_400

  def claim_idempotency(actor_id, operation_scope, key, request_hash, options \\ []) do
    expires_at = Keyword.get_lazy(options, :expires_at, &default_expiry/0)

    attributes = %{
      actor_id: actor_id,
      operation_scope: operation_scope,
      key: key,
      request_hash: request_hash,
      expires_at: expires_at
    }

    case Repo.insert(IdempotencyKey.claim_changeset(%IdempotencyKey{}, attributes)) do
      {:ok, idempotency_key} ->
        {:ok, :new, idempotency_key}

      {:error, changeset} ->
        resolve_claim_conflict(changeset, actor_id, operation_scope, key, request_hash)
    end
  end

  def record_idempotency_response(%IdempotencyKey{} = idempotency_key, status, body) do
    idempotency_key
    |> IdempotencyKey.response_changeset(status, body)
    |> Repo.update()
  end

  def enqueue_outbox_event(attributes) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(Map.put_new_lazy(attributes, :available_at, &DateTime.utc_now/0))
    |> Repo.insert()
  end

  def pending_outbox_events(limit) when is_integer(limit) and limit > 0 do
    now = DateTime.utc_now()

    from(event in OutboxEvent,
      where: event.status == "pending" and event.available_at <= ^now,
      order_by: [asc: event.available_at, asc: event.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp resolve_claim_conflict(changeset, actor_id, operation_scope, key, request_hash) do
    if unique_claim_conflict?(changeset) do
      existing =
        Repo.get_by!(IdempotencyKey,
          actor_id: actor_id,
          operation_scope: operation_scope,
          key: key
        )

      case existing.request_hash do
        ^request_hash when is_integer(existing.response_status) -> {:ok, :replay, existing}
        ^request_hash -> {:ok, :in_progress, existing}
        _ -> {:error, :idempotency_key_reused}
      end
    else
      {:error, changeset}
    end
  end

  defp unique_claim_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {:actor_id, {_message, options}} -> options[:constraint] == :unique
      _ -> false
    end)
  end

  defp default_expiry, do: DateTime.add(DateTime.utc_now(), @idempotency_ttl_seconds, :second)
end
