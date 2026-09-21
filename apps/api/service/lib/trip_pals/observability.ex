defmodule TripPals.Observability do
  @moduledoc """
  Privacy-safe operational telemetry and error-reporting boundary.

  Callers provide only stable outcome codes and aggregate counts. Request
  payloads, identifiers, user-provided text, and provider payloads are never
  accepted as telemetry metadata.
  """

  require Logger

  alias TripPals.Observability.Sanitizer

  @events %{
    "http" => :http,
    "channel" => :channel,
    "job" => :job,
    "rsvp" => :rsvp,
    "chat_delivery" => :chat_delivery,
    "push" => :push,
    "lifecycle" => :lifecycle,
    "rate_limit" => :rate_limit
  }

  @spec emit(String.t() | atom(), map(), map()) :: :ok | {:error, :unknown_event}
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    event = to_string(event)

    case Map.fetch(@events, event) do
      {:ok, event_atom} ->
        safe_measurements = measurements(measurements)
        safe_metadata = Sanitizer.telemetry_metadata(metadata) |> Map.put("event", event)

        :telemetry.execute(
          [:trip_pals, :observability, event_atom],
          safe_measurements,
          safe_metadata
        )

        Logger.info("operational_event " <> Jason.encode!(safe_metadata))

        :ok

      :error ->
        {:error, :unknown_event}
    end
  end

  @spec report_error(String.t() | atom(), term(), map()) :: :ok
  def report_error(error_code, context, metadata \\ %{}) do
    safe_context = Sanitizer.error_context(context)
    safe_metadata = Sanitizer.telemetry_metadata(metadata)

    Logger.error(
      "application_error " <>
        Jason.encode!(%{
          "error_code" => to_string(error_code),
          "context" => safe_context,
          "metadata" => safe_metadata
        })
    )

    :ok
  end

  @spec scrub_error_context(term()) :: term()
  def scrub_error_context(context), do: Sanitizer.error_context(context)

  defp measurements(measurements) when is_map(measurements) do
    measurements
    |> Map.take([:duration, "duration", :count, "count"])
    |> Enum.reduce(%{}, fn
      {key, value}, safe when is_integer(value) or is_float(value) ->
        Map.put(safe, normalize_measurement_key(key), value)

      _, safe ->
        safe
    end)
    |> Map.put_new(:count, 1)
  end

  defp measurements(_measurements), do: %{count: 1}

  defp normalize_measurement_key(key) when key in [:duration, "duration"], do: :duration
  defp normalize_measurement_key(_key), do: :count
end
