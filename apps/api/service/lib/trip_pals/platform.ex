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

    # `on_conflict: :nothing` avoids putting an enclosing domain transaction
    # into PostgreSQL's aborted state. That matters because a Join must look up
    # and replay an existing claim while retaining its activity-row lock.
    case Repo.insert(IdempotencyKey.claim_changeset(%IdempotencyKey{}, attributes),
           on_conflict: :nothing,
           conflict_target: [:actor_id, :operation_scope, :key]
         ) do
      {:ok, attempted} ->
        existing =
          Repo.get_by!(IdempotencyKey,
            actor_id: actor_id,
            operation_scope: operation_scope,
            key: key
          )

        if existing.id == attempted.id do
          {:ok, :new, existing}
        else
          resolve_existing_claim(existing, request_hash)
        end

      {:error, changeset} ->
        {:error, changeset}
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

  defp resolve_existing_claim(existing, request_hash) do
    case existing.request_hash do
      ^request_hash when is_integer(existing.response_status) -> {:ok, :replay, existing}
      ^request_hash -> {:ok, :in_progress, existing}
      _ -> {:error, :idempotency_key_reused}
    end
  end

  defp default_expiry, do: DateTime.add(DateTime.utc_now(), @idempotency_ttl_seconds, :second)
end
