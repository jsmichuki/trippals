defmodule TripPals.Workers.PushDelivery do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 8,
    unique: [fields: [:args], keys: [:delivery_id], period: 86_400]

  import Ecto.Query

  alias TripPals.Notifications.Device
  alias TripPals.Notifications.Notification
  alias TripPals.Notifications.NotificationDelivery
  alias TripPals.Notifications.PushGateway
  alias TripPals.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    case claim(delivery_id) do
      {:ok, :already_finished} ->
        :ok

      {:ok, %{delivery: delivery, device: device, notification: notification}} ->
        deliver(delivery, device, notification)

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def perform(_job), do: {:discard, :invalid_delivery_job}

  defp claim(delivery_id) do
    Repo.transaction(fn ->
      record =
        from(delivery in NotificationDelivery,
          join: device in Device,
          on: device.id == delivery.device_id,
          join: notification in Notification,
          on: notification.id == delivery.notification_id,
          where: delivery.id == ^delivery_id,
          lock: "FOR UPDATE",
          select: {delivery, device, notification}
        )
        |> Repo.one()

      case record do
        nil ->
          Repo.rollback(:not_found)

        {%NotificationDelivery{status: status}, _device, _notification}
        when status in ["delivered", "invalidated"] ->
          :already_finished

        {%NotificationDelivery{} = delivery, device, notification} ->
          case delivery
               |> Ecto.Changeset.change(
                 status: "processing",
                 attempt_count: delivery.attempt_count + 1,
                 updated_at: DateTime.utc_now()
               )
               |> Repo.update() do
            {:ok, claimed} -> %{delivery: claimed, device: device, notification: notification}
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  defp deliver(delivery, device, notification) do
    case PushGateway.deliver(device, notification) do
      {:ok, provider_message_id} ->
        delivery
        |> Ecto.Changeset.change(
          status: "delivered",
          delivered_at: DateTime.utc_now(),
          provider_message_id: provider_message_id,
          last_error_code: nil
        )
        |> Repo.update()
        |> case do
          {:ok, _delivery} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :invalid_token} ->
        invalidate_token(delivery, device)

      {:error, reason} ->
        _ =
          delivery
          |> Ecto.Changeset.change(
            status: "pending",
            last_error_code: normalize_error(reason),
            available_at: DateTime.add(DateTime.utc_now(), 30, :second)
          )
          |> Repo.update()

        {:error, reason}
    end
  end

  defp invalidate_token(delivery, device) do
    now = DateTime.utc_now()

    case Repo.transaction(fn ->
           with {1, _} <-
                  from(record in Device, where: record.id == ^device.id)
                  |> Repo.update_all(
                    set: [status: "invalidated", invalidated_at: now, updated_at: now]
                  ),
                {1, _} <-
                  from(record in NotificationDelivery, where: record.id == ^delivery.id)
                  |> Repo.update_all(
                    set: [
                      status: "invalidated",
                      last_error_code: "invalid_token",
                      updated_at: now
                    ]
                  ) do
             :ok
           else
             _ -> Repo.rollback(:not_found)
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_error(reason) when is_binary(reason), do: String.slice(reason, 0, 120)
  defp normalize_error(_reason), do: "push_failed"
end
