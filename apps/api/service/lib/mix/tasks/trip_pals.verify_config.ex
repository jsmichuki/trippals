defmodule Mix.Tasks.TripPals.VerifyConfig do
  @shortdoc "Validates safe TripPals API configuration"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadconfig")

    api_config = Application.fetch_env!(:trip_pals, :api)
    max_body_bytes = Keyword.fetch!(api_config, :max_body_bytes)
    cors_origins = Keyword.fetch!(api_config, :cors_origins)

    unless is_integer(max_body_bytes) and max_body_bytes > 0 do
      Mix.raise(":api max_body_bytes must be a positive integer")
    end

    unless is_list(cors_origins) and Enum.all?(cors_origins, &valid_origin?/1) do
      Mix.raise(":api cors_origins must be a list of http(s) origins without paths")
    end

    Mix.shell().info("TripPals API configuration is valid")
  end

  defp valid_origin?(origin) when is_binary(origin) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host, path: path, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and path in [nil, ""] ->
        true

      _ ->
        false
    end
  end

  defp valid_origin?(_origin), do: false
end
