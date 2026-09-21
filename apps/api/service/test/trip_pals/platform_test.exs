defmodule TripPals.PlatformTest do
  use TripPals.DataCase, async: true

  alias Ecto.Multi
  alias TripPals.Platform
  alias TripPals.Transactions

  @request_hash String.duplicate("a", 64)

  test "persists idempotency claims, replays identical requests, and rejects key reuse" do
    actor_id = Ecto.UUID.generate()

    assert {:ok, :new, claim} =
             Platform.claim_idempotency(actor_id, "activity:join", "key-1", @request_hash)

    assert {:ok, claim} =
             Platform.record_idempotency_response(claim, 201, %{data: %{activity_id: "opaque"}})

    assert {:ok, :replay, replay} =
             Platform.claim_idempotency(actor_id, "activity:join", "key-1", @request_hash)

    assert replay.id == claim.id
    assert replay.response_status == 201

    assert {:error, :idempotency_key_reused} =
             Platform.claim_idempotency(
               actor_id,
               "activity:join",
               "key-1",
               String.duplicate("b", 64)
             )
  end

  test "commits an outbox event with its domain transaction" do
    aggregate_id = Ecto.UUID.generate()

    multi =
      Multi.new()
      |> Transactions.append_outbox_event(:outbox, %{
        topic: "activity",
        event_type: "activity.published",
        aggregate_type: "activity",
        aggregate_id: aggregate_id,
        payload: %{activity_id: aggregate_id},
        available_at: DateTime.utc_now()
      })

    assert {:ok, %{outbox: event}} = Transactions.transact(multi)
    assert [pending] = Platform.pending_outbox_events(10)
    assert pending.id == event.id
  end

  test "rolls an outbox event back with its surrounding transaction" do
    aggregate_id = Ecto.UUID.generate()

    multi =
      Multi.new()
      |> Transactions.append_outbox_event(:outbox, %{
        topic: "activity",
        event_type: "activity.published",
        aggregate_type: "activity",
        aggregate_id: aggregate_id,
        available_at: DateTime.utc_now()
      })
      |> Multi.run(:fail, fn _repo, _changes -> {:error, :force_rollback} end)

    assert {:error, :fail, :force_rollback, _changes} = Transactions.transact(multi)
    assert Platform.pending_outbox_events(10) == []
  end
end
