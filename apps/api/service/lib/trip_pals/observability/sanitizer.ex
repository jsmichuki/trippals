defmodule TripPals.Observability.Sanitizer do
  @moduledoc """
  Prevents request, authentication, private-content, and contact data from
  crossing the observability boundary.

  This is intentionally deny-by-default for structured event metadata. Error
  contexts are recursively scrubbed because they may originate in libraries.
  Neither function serializes arbitrary structs or process state.
  """

  @allowed_metadata ~w(
    correlation_id event operation outcome result status status_code route method
    reason error_code attempt queue worker provider response_class entity_type
    transition conflict_type count limit bucket source transport
  )

  @sensitive_key_fragments ~w(
    token authorization credential password secret assertion attestation authenticator
    signature client_data biometric email chat body message content meeting location
    latitude longitude gps availability travel date itinerary contact phone address
    report evidence upload media
  )

  @spec telemetry_metadata(map()) :: map()
  def telemetry_metadata(metadata) when is_map(metadata) do
    metadata
    |> stringify_keys()
    |> Map.take(@allowed_metadata)
    |> Enum.reduce(%{}, fn {key, value}, sanitized ->
      case safe_scalar(value) do
        {:ok, scalar} -> Map.put(sanitized, key, scalar)
        :error -> sanitized
      end
    end)
  end

  def telemetry_metadata(_metadata), do: %{}

  @spec error_context(term()) :: term()
  def error_context(value), do: scrub(value)

  defp scrub(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp scrub(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp scrub(%Date{} = value), do: Date.to_iso8601(value)

  defp scrub(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, sanitized ->
      key = to_string(key)

      Map.put(
        sanitized,
        key,
        if(sensitive_key?(key), do: "[REDACTED]", else: scrub(nested_value))
      )
    end)
  end

  defp scrub(value) when is_list(value), do: Enum.map(value, &scrub/1)
  defp scrub(value) when is_binary(value), do: String.slice(value, 0, 256)
  defp scrub(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp scrub(_value), do: "[REDACTED]"

  defp stringify_keys(metadata) do
    Enum.reduce(metadata, %{}, fn {key, value}, sanitized ->
      Map.put(sanitized, to_string(key), value)
    end)
  end

  defp safe_scalar(value) when is_binary(value), do: {:ok, String.slice(value, 0, 120)}

  defp safe_scalar(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: {:ok, value}

  defp safe_scalar(nil), do: {:ok, nil}
  defp safe_scalar(_value), do: :error

  defp sensitive_key?(key) do
    normalized = key |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
    Enum.any?(@sensitive_key_fragments, &String.contains?(normalized, &1))
  end
end
