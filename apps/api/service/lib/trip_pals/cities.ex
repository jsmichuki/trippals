defmodule TripPals.Cities do
  @moduledoc false

  import Ecto.Query

  alias TripPals.Cities.City
  alias TripPals.Repo

  @max_discovery_days 90

  def list_cities do
    from(city in City, order_by: [asc: city.country, asc: city.name])
    |> Repo.all()
  end

  def get_city(city_id) when is_binary(city_id) do
    case Ecto.UUID.cast(city_id) do
      {:ok, _uuid} -> Repo.get(City, city_id)
      :error -> nil
    end
  end

  def get_city(_city_id), do: nil

  def discovery_range(%City{} = city, attributes) do
    with {:ok, start_date, end_date} <- parse_dates(city, attributes),
         :ok <- validate_date_range(city, start_date, end_date),
         {:ok, {starts_at, _}} <- local_date_bounds(city.iana_timezone, start_date),
         {:ok, {_, ends_at}} <- local_date_bounds(city.iana_timezone, end_date) do
      {:ok, %{start_date: start_date, end_date: end_date, starts_at: starts_at, ends_at: ends_at}}
    end
  end

  def local_date_bounds(iana_timezone, %Date{} = local_date) when is_binary(iana_timezone) do
    sql = """
    SELECT
      ($1::date::timestamp AT TIME ZONE $2) AS starts_at,
      (($1::date + 1)::timestamp AT TIME ZONE $2) AS ends_at
    """

    case Repo.query(sql, [local_date, iana_timezone]) do
      {:ok, %{rows: [[starts_at, ends_at]]}} -> {:ok, {starts_at, ends_at}}
      _ -> {:error, {:validation_failed, %{iana_timezone: ["is invalid"]}}}
    end
  end

  defp parse_dates(city, %{"start_local_date" => nil, "end_local_date" => nil}),
    do: default_range(city)

  defp parse_dates(city, attributes) do
    case {attributes["start_local_date"], attributes["end_local_date"]} do
      {nil, nil} ->
        default_range(city)

      {start_date, end_date} when is_binary(start_date) and is_binary(end_date) ->
        with {:ok, parsed_start_date} <- Date.from_iso8601(start_date),
             {:ok, parsed_end_date} <- Date.from_iso8601(end_date) do
          {:ok, parsed_start_date, parsed_end_date}
        else
          _ -> {:error, {:validation_failed, %{local_date: ["must be ISO 8601 dates"]}}}
        end

      _ ->
        {:error,
         {:validation_failed,
          %{local_date: ["start_local_date and end_local_date must be supplied together"]}}}
    end
  end

  defp default_range(city) do
    with {:ok, today} <- local_today(city.iana_timezone) do
      {:ok, today, Date.add(today, 6)}
    end
  end

  defp validate_date_range(city, start_date, end_date) do
    with true <- Date.compare(start_date, end_date) != :gt,
         true <- Date.diff(end_date, start_date) < @max_discovery_days,
         {:ok, today} <- local_today(city.iana_timezone),
         true <- Date.compare(start_date, today) != :lt do
      :ok
    else
      false ->
        {:error,
         {:validation_failed,
          %{local_date: ["must be ordered, within 90 days, and not start in the past"]}}}

      {:error, _reason} = error ->
        error
    end
  end

  defp local_today(iana_timezone) do
    case Repo.query("SELECT (now() AT TIME ZONE $1)::date", [iana_timezone]) do
      {:ok, %{rows: [[today]]}} -> {:ok, today}
      _ -> {:error, {:validation_failed, %{iana_timezone: ["is invalid"]}}}
    end
  end
end
