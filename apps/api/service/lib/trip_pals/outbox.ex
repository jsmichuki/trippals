defmodule TripPals.Outbox do
  @moduledoc """
  Producer/consumer operations for immutable transactional outbox events.
  """

  import Ecto.Query

  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo
  alias TripPals.Workers.OutboxDispatch

  @retry_seconds 30

  def enqueue_pending(limit \\ 100) when is_integer(limit) and limit > 0 do
    now = DateTime.utc_now()

    from(event in OutboxEvent,
      where: event.status == "pending" and event.available_at <= ^now,
      order_by: [asc: event.available_at, asc: event.inserted_at],
      limit: ^limit,
      select: event.id
    )
    |> Repo.all()
    |> Enum.reduce({:ok, 0}, fn event_id, {:ok, count} ->
      case Oban.insert(OutboxDispatch.new(%{"event_id" => event_id})) do
        {:ok, _job} -> {:ok, count + 1}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def claim(event_id) do
    Repo.transaction(fn ->
      event =
        from(event in OutboxEvent, where: event.id == ^event_id, lock: "FOR UPDATE")
        |> Repo.one()

      case event do
        nil ->
          Repo.rollback(:not_found)

        %OutboxEvent{status: "dispatched"} ->
          {:already_dispatched, event}

        %OutboxEvent{status: "discarded"} ->
          {:discarded, event}

        %OutboxEvent{} = event ->
          case event
               |> Ecto.Changeset.change(
                 status: "processing",
                 attempt_count: event.attempt_count + 1,
                 updated_at: DateTime.utc_now()
               )
               |> Repo.update() do
            {:ok, claimed} -> {:claimed, claimed}
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  def dispatch_succeeded(%OutboxEvent{} = event) do
    event
    |> Ecto.Changeset.change(
      status: "dispatched",
      dispatched_at: DateTime.utc_now(),
      last_error_code: nil
    )
    |> Repo.update()
  end

  def dispatch_failed(%OutboxEvent{} = event, error_code) do
    event
    |> Ecto.Changeset.change(
      status: "pending",
      last_error_code: normalize_error(error_code),
      available_at: DateTime.add(DateTime.utc_now(), @retry_seconds, :second)
    )
    |> Repo.update()
  end

  defp normalize_error(error) when is_atom(error), do: Atom.to_string(error)
  defp normalize_error(error) when is_binary(error), do: String.slice(error, 0, 120)
  defp normalize_error(_error), do: "dispatch_failed"
end
