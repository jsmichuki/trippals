defmodule TripPals.Activities do
  @moduledoc false

  import Ecto.Query

  alias TripPals.Activities.Activity
  alias TripPals.Activities.ActivityIdea
  alias TripPals.Cities
  alias TripPals.Repo

  @active_statuses ["published", "host_confirmed"]
  @default_page_size 20
  @max_page_size 50

  def list_public_activities(attributes) do
    with %{} = city <- Cities.get_city(attributes["city_id"]),
         :ok <- supported_city?(city),
         {:ok, range} <- Cities.discovery_range(city, attributes),
         {:ok, filters} <- parse_filters(attributes),
         {:ok, cursor} <- decode_cursor(attributes["cursor"]) do
      query =
        from(activity in Activity,
          where: activity.city_id == ^city.id and activity.status in ^@active_statuses,
          where: activity.start_at >= ^range.starts_at and activity.start_at < ^range.ends_at,
          order_by: [asc: activity.start_at, asc: activity.id]
        )
        |> apply_filters(filters)
        |> apply_cursor(cursor)

      activities = Repo.all(from(activity in query, limit: ^(filters.limit + 1)))
      {page, remaining} = Enum.split(activities, filters.limit)

      {:ok,
       %{
         activities: Enum.map(page, &guest_activity/1),
         next_cursor: next_cursor(page, remaining),
         range: %{start_local_date: range.start_date, end_local_date: range.end_date}
       }}
    else
      nil -> {:error, :city_not_found}
      {:error, _reason} = error -> error
    end
  end

  def get_public_activity(activity_id) when is_binary(activity_id) do
    case Ecto.UUID.cast(activity_id) do
      {:ok, _uuid} ->
        case Repo.get(Activity, activity_id) do
          %Activity{status: status} = activity when status in @active_statuses ->
            {:ok, guest_activity(activity)}

          %Activity{} ->
            {:error, :activity_unavailable}

          nil ->
            {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  def list_activity_ideas do
    from(activity_idea in ActivityIdea,
      where: activity_idea.enabled,
      order_by: [asc: activity_idea.category, asc: activity_idea.title]
    )
    |> Repo.all()
    |> Enum.map(fn activity_idea ->
      %{
        id: activity_idea.id,
        title: activity_idea.title,
        category: activity_idea.category,
        description: activity_idea.description,
        kind: "activity_idea"
      }
    end)
  end

  def guest_activity(activity) do
    %{
      id: activity.id,
      title: activity.title,
      category: activity.category,
      description: activity.description,
      kind: "scheduled_activity",
      start_at: activity.start_at,
      end_at: activity.end_at,
      iana_timezone: activity.iana_timezone,
      public_area: activity.public_area,
      cost_amount: activity.cost_amount,
      currency: activity.currency,
      capacity_total: activity.capacity_total,
      going_count: activity.going_count,
      seats_remaining: activity.capacity_total - activity.going_count,
      host_confirmed: not is_nil(activity.host_confirmed_at)
    }
  end

  defp supported_city?(%{launch_status: "supported"}), do: :ok
  defp supported_city?(_city), do: {:error, :city_unavailable}

  defp parse_filters(attributes) do
    with {:ok, limit} <- parse_limit(attributes["limit"]),
         {:ok, minimum_capacity} <- parse_capacity(attributes["min_capacity"]),
         {:ok, maximum_capacity} <- parse_capacity(attributes["max_capacity"]),
         true <-
           is_nil(minimum_capacity) or is_nil(maximum_capacity) or
             minimum_capacity <= maximum_capacity do
      {:ok,
       %{
         category: blank_to_nil(attributes["category"]),
         query: blank_to_nil(attributes["q"]),
         minimum_capacity: minimum_capacity,
         maximum_capacity: maximum_capacity,
         limit: limit
       }}
    else
      false -> {:error, {:validation_failed, %{capacity: ["minimum cannot exceed maximum"]}}}
      {:error, _reason} = error -> error
    end
  end

  defp parse_limit(nil), do: {:ok, @default_page_size}
  defp parse_limit(value), do: parse_integer(value, :limit, 1, @max_page_size)
  defp parse_capacity(nil), do: {:ok, nil}
  defp parse_capacity(value), do: parse_integer(value, :capacity, 2, 10)

  defp parse_integer(value, field, minimum, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= minimum and parsed <= maximum -> {:ok, parsed}
      _ -> {:error, {:validation_failed, %{field => ["is invalid"]}}}
    end
  end

  defp parse_integer(_value, field, _minimum, _maximum),
    do: {:error, {:validation_failed, %{field => ["is invalid"]}}}

  defp apply_filters(query, filters) do
    query
    |> maybe_filter_category(filters.category)
    |> maybe_filter_minimum_capacity(filters.minimum_capacity)
    |> maybe_filter_maximum_capacity(filters.maximum_capacity)
    |> maybe_filter_search(filters.query)
  end

  defp maybe_filter_category(query, nil), do: query

  defp maybe_filter_category(query, category),
    do: from(activity in query, where: activity.category == ^category)

  defp maybe_filter_minimum_capacity(query, nil), do: query

  defp maybe_filter_minimum_capacity(query, capacity),
    do: from(activity in query, where: activity.capacity_total >= ^capacity)

  defp maybe_filter_maximum_capacity(query, nil), do: query

  defp maybe_filter_maximum_capacity(query, capacity),
    do: from(activity in query, where: activity.capacity_total <= ^capacity)

  defp maybe_filter_search(query, nil), do: query

  defp maybe_filter_search(query, search_query),
    do:
      from(activity in query,
        where: fragment("search_document @@ plainto_tsquery('simple', ?)", ^search_query)
      )

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, %{start_at: start_at, id: id}) do
    from(activity in query,
      where:
        activity.start_at > ^start_at or (activity.start_at == ^start_at and activity.id > ^id)
    )
  end

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, encoded} <- Base.url_decode64(cursor, padding: false),
         %{"start_at" => start_at, "id" => id} <- Jason.decode!(encoded),
         {:ok, parsed_start_at, _offset} <- DateTime.from_iso8601(start_at),
         {:ok, _uuid} <- Ecto.UUID.cast(id) do
      {:ok, %{start_at: parsed_start_at, id: id}}
    else
      _ -> {:error, {:validation_failed, %{cursor: ["is invalid"]}}}
    end
  rescue
    Jason.DecodeError -> {:error, {:validation_failed, %{cursor: ["is invalid"]}}}
  end

  defp decode_cursor(_cursor), do: {:error, {:validation_failed, %{cursor: ["is invalid"]}}}

  defp next_cursor(_page, []), do: nil

  defp next_cursor(page, _remaining) do
    last = List.last(page)

    %{start_at: last.start_at, id: last.id}
    |> Map.update!(:start_at, &DateTime.to_iso8601/1)
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil
end
