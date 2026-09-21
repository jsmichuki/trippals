defmodule TripPals.ObservabilityTest do
  use TripPals.DataCase, async: true

  import ExUnit.CaptureLog

  alias TripPals.Analytics
  alias TripPals.Observability
  alias TripPals.Observability.Sanitizer
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo

  test "telemetry metadata is allow-listed and never emits request payload values" do
    handler_id = {__MODULE__, make_ref()}
    :telemetry.attach(handler_id, [:trip_pals, :observability, :rsvp], &forward_event/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok =
             Observability.emit("rsvp", %{duration: 20, ignored: "ignored"}, %{
               correlation_id: "correlation-123",
               outcome: "conflict",
               chat_body: "never log this",
               authorization: "Bearer private-token",
               payload: %{"private_meeting_details" => "never emit"}
             })

    assert_receive {:observability_event, %{count: 1, duration: 20}, metadata}
    assert metadata["correlation_id"] == "correlation-123"
    assert metadata["outcome"] == "conflict"
    assert metadata["event"] == "rsvp"
    refute Map.has_key?(metadata, "chat_body")
    refute Map.has_key?(metadata, "authorization")
    refute Map.has_key?(metadata, "payload")
  end

  test "error contexts recursively redact sensitive fields" do
    scrubbed =
      Sanitizer.error_context(%{
        "refresh_token" => "refresh-secret",
        "email" => "member@example.test",
        "chat" => %{"body" => "private words"},
        "location" => %{"latitude" => 1.0, "longitude" => 2.0},
        "safe" => %{"reason" => "capacity_full"}
      })

    assert scrubbed["refresh_token"] == "[REDACTED]"
    assert scrubbed["email"] == "[REDACTED]"
    assert scrubbed["chat"] == "[REDACTED]"
    assert scrubbed["location"] == "[REDACTED]"
    assert scrubbed["safe"]["reason"] == "capacity_full"
  end

  test "error reporting logs only scrubbed error context" do
    log =
      capture_log(fn ->
        assert :ok =
                 Observability.report_error(:provider_failure, %{
                   "authorization" => "Bearer provider-secret",
                   "chat_body" => "private message"
                 })
      end)

    assert log =~ "[REDACTED]"
    refute log =~ "provider-secret"
    refute log =~ "private message"
  end

  test "analytics writes an allow-listed server event through the durable outbox" do
    aggregate_id = Ecto.UUID.generate()

    assert {:ok, event} =
             Analytics.enqueue("join_succeeded", "activity", aggregate_id, %{
               "city_id" => Ecto.UUID.generate(),
               "category" => "coffee",
               "capacity_bucket" => "2_4"
             })

    persisted = Repo.get!(OutboxEvent, event.id)
    assert persisted.topic == "analytics"
    assert persisted.event_type == "analytics.join_succeeded"

    assert persisted.payload == %{
             "event" => "join_succeeded",
             "city_id" => event.payload["city_id"],
             "category" => "coffee",
             "capacity_bucket" => "2_4"
           }
  end

  test "analytics rejects private content, contact data, and unreviewed events" do
    activity_id = Ecto.UUID.generate()

    assert {:error, :analytics_payload_not_allowed} =
             Analytics.enqueue("join_succeeded", "activity", activity_id, %{
               "chat_body" => "private words"
             })

    assert {:error, :analytics_payload_not_allowed} =
             Analytics.enqueue("join_succeeded", "activity", activity_id, %{
               "category" => "member@example.test"
             })

    assert {:error, :analytics_event_not_allowed} =
             Analytics.enqueue("chat_message_sent", "activity", activity_id, %{})

    assert Repo.all(OutboxEvent) == []
  end

  defp forward_event(_event, measurements, metadata, test_process) do
    send(test_process, {:observability_event, measurements, metadata})
  end
end
