defmodule TripPals.Workers.OutboxDispatch do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 8,
    unique: [fields: [:args], keys: [:event_id], period: 86_400]

  alias TripPals.Notifications
  alias TripPals.Outbox
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Workers.PushDelivery

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    case Outbox.enqueue_pending() do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    case Outbox.claim(event_id) do
      {:ok, {:already_dispatched, _event}} -> :ok
      {:ok, {:discarded, _event}} -> :ok
      {:ok, {:claimed, event}} -> dispatch(event)
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(_job), do: {:discard, :invalid_outbox_job}

  defp dispatch(%OutboxEvent{event_type: "notification.created"} = event) do
    notification_id =
      Map.get(event.payload, "notification_id") || Map.get(event.payload, :notification_id)

    with {:ok, _result} <- Notifications.prepare_push_deliveries(notification_id),
         :ok <- enqueue_push_deliveries(notification_id),
         {:ok, _event} <- Outbox.dispatch_succeeded(event) do
      :ok
    else
      {:error, reason} -> retry(event, reason)
    end
  end

  # Non-notification topics are durable integration events. Marking them as
  # dispatched only means this consumer accepted them; they never make RSVP
  # success contingent on a push provider.
  defp dispatch(event) do
    case Outbox.dispatch_succeeded(event) do
      {:ok, _event} -> :ok
      {:error, reason} -> retry(event, reason)
    end
  end

  defp enqueue_push_deliveries(notification_id) do
    notification_id
    |> Notifications.pending_push_delivery_ids()
    |> Enum.reduce_while(:ok, fn delivery_id, :ok ->
      case Oban.insert(PushDelivery.new(%{"delivery_id" => delivery_id})) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp retry(event, reason) do
    _ = Outbox.dispatch_failed(event, reason)
    {:error, reason}
  end
end
