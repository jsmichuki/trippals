defmodule TripPals.Analytics do
  @moduledoc """
  Server-owned, privacy-reviewed analytics events stored in the transactional
  outbox. This context accepts only aggregate, allow-listed dimensions.

  It deliberately has no generic "track arbitrary payload" function: that
  would make it possible for chat, meeting, identity, or report content to
  reach an analytics vendor later.
  """

  alias TripPals.Platform

  @event_dimensions %{
    "join_succeeded" => ~w(city_id category capacity_bucket),
    "host_confirmed" => ~w(city_id category capacity_bucket),
    "lifecycle_transitioned" => ~w(city_id from_status to_status category),
    "invitation_state_changed" => ~w(city_id state source),
    "candidate_metrics_aggregated" => ~w(city_id bucket count)
  }

  @spec enqueue(String.t() | atom(), String.t(), Ecto.UUID.t(), map()) ::
          {:ok, TripPals.Platform.OutboxEvent.t()} | {:error, atom() | Ecto.Changeset.t()}
  def enqueue(event_name, aggregate_type, aggregate_id, dimensions \\ %{})

  def enqueue(event_name, aggregate_type, aggregate_id, dimensions)
      when is_binary(aggregate_type) and is_binary(aggregate_id) and is_map(dimensions) do
    event_name = to_string(event_name)

    with {:ok, allowed_dimensions} <- allowed_dimensions(event_name),
         {:ok, payload} <- payload(dimensions, allowed_dimensions) do
      Platform.enqueue_outbox_event(%{
        topic: "analytics",
        event_type: "analytics." <> event_name,
        aggregate_type: aggregate_type,
        aggregate_id: aggregate_id,
        payload: Map.put(payload, "event", event_name)
      })
    end
  end

  def enqueue(_event_name, _aggregate_type, _aggregate_id, _dimensions),
    do: {:error, :invalid_analytics_event}

  @spec allowed_event?(String.t() | atom()) :: boolean()
  def allowed_event?(event_name), do: Map.has_key?(@event_dimensions, to_string(event_name))

  defp allowed_dimensions(event_name) do
    case Map.fetch(@event_dimensions, event_name) do
      {:ok, dimensions} -> {:ok, dimensions}
      :error -> {:error, :analytics_event_not_allowed}
    end
  end

  defp payload(dimensions, allowed_dimensions) do
    normalized =
      Enum.reduce(dimensions, %{}, fn {key, value}, accumulator ->
        Map.put(accumulator, to_string(key), value)
      end)

    rejected? = Enum.any?(Map.keys(normalized), &(&1 not in allowed_dimensions))

    if rejected? do
      {:error, :analytics_payload_not_allowed}
    else
      normalized
      |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, payload} ->
        case scalar_dimension(value) do
          {:ok, safe_value} -> {:cont, {:ok, Map.put(payload, key, safe_value)}}
          :error -> {:halt, {:error, :analytics_payload_not_allowed}}
        end
      end)
    end
  end

  defp scalar_dimension(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp scalar_dimension(value) when is_binary(value) do
    if byte_size(value) <= 80 and not String.contains?(value, ["@", "Bearer "]) do
      {:ok, value}
    else
      :error
    end
  end

  defp scalar_dimension(_value), do: :error
end
