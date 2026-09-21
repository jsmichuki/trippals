defmodule TripPals.Activities do
  @moduledoc false

  import Ecto.Query

  alias TripPals.Activities.Activity
  alias TripPals.Activities.ActivityAudit
  alias TripPals.Activities.ActivityHostAssignment
  alias TripPals.Activities.ActivityIdea
  alias TripPals.Activities.ActivityRevision
  alias TripPals.Accounts
  alias TripPals.Cities
  alias TripPals.Conversations.Conversation
  alias TripPals.Transactions
  alias TripPals.Repo
  alias Ecto.Multi

  @active_statuses ["published", "host_confirmed"]
  @default_page_size 20
  @max_page_size 50
  @material_fields ~w(start_at end_at city_id public_area cost_amount currency capacity_total category title description)

  def create_draft(actor_id, attributes) do
    with :ok <- eligible_host?(actor_id),
         {:ok, city} <- supported_city(attributes["city_id"]),
         {:ok, idea} <- activity_idea(attributes["idea_id"]) do
      activity_attributes =
        attributes
        |> Map.take(
          ~w(title category description start_at end_at iana_timezone public_area participant_meeting_details cost_amount currency capacity_total confirmation_deadline_at)
        )
        |> apply_idea(idea)
        |> normalize_activity_attributes()

      %Activity{host_id: actor_id, city_id: city.id, idea_id: idea && idea.id}
      |> Activity.discovery_changeset(
        Map.merge(activity_attributes, %{status: "draft", going_count: 0})
      )
      |> validate_city_timezone(city)
      |> Repo.insert()
    end
  end

  def update_activity(activity_id, actor_id, expected_version, attributes) do
    transition_transaction(activity_id, actor_id, fn activity ->
      with :ok <- version_matches?(activity, expected_version),
           {:ok, city} <- supported_city(attributes["city_id"] || activity.city_id),
           changes <- material_changes(activity, attributes),
           changeset <-
             activity
             |> Activity.discovery_changeset(normalize_activity_attributes(attributes))
             |> Ecto.Changeset.put_change(:city_id, city.id)
             |> validate_city_timezone(city),
           {:ok, updated} <-
             Repo.update(Ecto.Changeset.put_change(changeset, :version, activity.version + 1)),
           {:ok, revision} <- insert_revision(updated, actor_id, changes),
           :ok <-
             record_activity_side_effects(
               updated,
               actor_id,
               "activity.updated",
               changes,
               revision.material
             ) do
        {:ok, updated}
      end
    end)
  end

  def publish(activity_id, actor_id), do: transition(activity_id, actor_id, "published", nil)
  def confirm(activity_id, actor_id), do: transition(activity_id, actor_id, "host_confirmed", nil)
  def start(activity_id, actor_id), do: transition(activity_id, actor_id, "in_progress", nil)

  def finish(activity_id, actor_id, occurred, reason),
    do: finish_transition(activity_id, actor_id, occurred, reason)

  def cancel(activity_id, actor_id, reason),
    do: transition(activity_id, actor_id, "canceled", reason)

  def mark_pending_review(activity_id, actor_id),
    do: transition(activity_id, actor_id, "pending_review", nil)

  def approve_review(activity_id, actor_id),
    do: transition(activity_id, actor_id, "published", nil)

  def expire(activity_id, actor_id), do: transition(activity_id, actor_id, "expired", nil)

  def host_activity(activity_id, actor_id) do
    case Repo.get(Activity, activity_id) do
      %Activity{host_id: ^actor_id} = activity -> {:ok, activity}
      %Activity{} -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  def host_activity_view(activity) do
    guest_activity(activity)
    |> Map.merge(%{
      version: activity.version,
      status: activity.status,
      confirmation_deadline_at: activity.confirmation_deadline_at,
      participant_meeting_details: activity.participant_meeting_details,
      cancellation_reason: activity.cancellation_reason,
      outcome: activity.outcome
    })
  end

  def member_activity_view(activity) do
    guest_activity(activity)
    |> Map.merge(%{viewer_role: "member", membership_state: "not_going"})
  end

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
    get_activity_for_view(activity_id, nil)
  end

  def get_activity_for_view(activity_id, actor_id) when is_binary(activity_id) do
    case Ecto.UUID.cast(activity_id) do
      {:ok, _uuid} ->
        case Repo.get(Activity, activity_id) do
          %Activity{status: status} = activity when status in @active_statuses ->
            {:ok, activity_view(activity, actor_id)}

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

  defp activity_view(%Activity{host_id: host_id} = activity, actor_id) when host_id == actor_id,
    do: host_activity_view(activity)

  defp activity_view(activity, nil), do: Map.put(guest_activity(activity), :viewer_role, "guest")
  defp activity_view(activity, _actor_id), do: member_activity_view(activity)

  defp transition(activity_id, actor_id, target_status, reason) do
    transition_transaction(activity_id, actor_id, fn activity ->
      case {activity.status, target_status} do
        {^target_status, ^target_status} ->
          {:ok, activity}

        {"draft", "published"} ->
          publish_activity(activity, actor_id)

        {"draft", "pending_review"} ->
          change_status(activity, actor_id, target_status, nil, nil)

        {"pending_review", "published"} ->
          publish_activity(activity, actor_id)

        {"published", "host_confirmed"} ->
          change_status(activity, actor_id, target_status, nil, nil)

        {"host_confirmed", "in_progress"} ->
          start_activity(activity, actor_id)

        {status, "expired"} when status in ["published", "host_confirmed", "pending_review"] ->
          change_status(activity, actor_id, target_status, nil, "unknown")

        {status, "canceled"}
        when status in ["draft", "published", "host_confirmed", "in_progress", "pending_review"] ->
          change_status(activity, actor_id, target_status, reason, "not_held")

        _ ->
          {:error, :invalid_transition}
      end
    end)
  end

  defp finish_transition(activity_id, actor_id, occurred, reason) when is_boolean(occurred) do
    transition_transaction(activity_id, actor_id, fn activity ->
      cond do
        activity.status == "completed" and occurred ->
          {:ok, activity}

        activity.status == "outcome_unknown" and not occurred ->
          {:ok, activity}

        activity.status != "in_progress" ->
          {:error, :invalid_transition}

        occurred ->
          change_status(activity, actor_id, "completed", nil, "host_reported_completed")

        valid_reason?(reason) ->
          change_status(activity, actor_id, "outcome_unknown", reason, "unknown")

        true ->
          {:error, {:validation_failed, %{reason: ["is required"]}}}
      end
    end)
  end

  defp finish_transition(_activity_id, _actor_id, _occurred, _reason),
    do: {:error, {:validation_failed, %{occurred: ["must be a boolean"]}}}

  defp transition_transaction(activity_id, actor_id, callback) do
    Repo.transaction(fn ->
      activity =
        from(activity in Activity, where: activity.id == ^activity_id, lock: "FOR UPDATE")
        |> Repo.one()

      case activity do
        nil ->
          Repo.rollback(:not_found)

        %Activity{host_id: ^actor_id} ->
          case callback.(activity) do
            {:ok, updated} -> updated
            {:error, reason} -> Repo.rollback(reason)
          end

        _ ->
          Repo.rollback(:forbidden)
      end
    end)
  end

  defp publish_activity(activity, actor_id) do
    case valid_for_publication?(activity, DateTime.utc_now()) do
      :ok -> publish_activity_transaction(activity, actor_id)
      error -> error
    end
  end

  defp publish_activity_transaction(activity, actor_id) do
    now = DateTime.utc_now()

    activity_changeset =
      activity
      |> Ecto.Changeset.change(
        status: "published",
        published_at: now,
        confirmation_deadline_at:
          activity.confirmation_deadline_at || DateTime.add(activity.start_at, -86_400, :second),
        going_count: 1,
        version: activity.version + 1
      )

    multi =
      Multi.new()
      |> Multi.update(:activity, activity_changeset)
      |> Multi.insert(
        :host_assignment,
        ActivityHostAssignment.changeset(
          %ActivityHostAssignment{activity_id: activity.id, user_id: actor_id},
          %{}
        )
      )
      |> Multi.insert(
        :conversation,
        Conversation.changeset(%Conversation{activity_id: activity.id, host_id: actor_id}, %{})
      )
      |> Multi.insert(
        :revision,
        ActivityRevision.changeset(
          %ActivityRevision{activity_id: activity.id, author_id: actor_id},
          %{version: activity.version + 1, material: false, changes: %{}}
        )
      )
      |> append_activity_propagation_events(activity, "activity.published", %{
        version: activity.version + 1
      })
      |> Multi.insert(
        :audit,
        audit_changeset(activity.id, actor_id, "published", nil, %{version: activity.version + 1})
      )

    case Transactions.transact(multi) do
      {:ok, %{activity: updated}} -> {:ok, updated}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp start_activity(activity, actor_id) do
    if DateTime.compare(DateTime.utc_now(), activity.start_at) == :lt do
      {:error, :activity_not_started}
    else
      change_status(activity, actor_id, "in_progress", nil, nil)
    end
  end

  defp change_status(activity, actor_id, status, reason, outcome) do
    now = DateTime.utc_now()

    changes =
      %{status: status, version: activity.version + 1}
      |> maybe_put(:host_confirmed_at, if(status == "host_confirmed", do: now))
      |> maybe_put(:started_at, if(status == "in_progress", do: now))
      |> maybe_put(
        :concluded_at,
        if(status in ["completed", "canceled", "outcome_unknown"], do: now)
      )
      |> maybe_put(:cancellation_reason, if(status == "canceled", do: reason))
      |> maybe_put(:outcome, outcome)

    with true <- status != "canceled" or valid_reason?(reason),
         {:ok, updated} <- activity |> Ecto.Changeset.change(changes) |> Repo.update(),
         {:ok, revision} <-
           insert_revision(
             updated,
             actor_id,
             Map.take(changes, [:status, :outcome, :cancellation_reason])
           ),
         :ok <-
           record_activity_side_effects(
             updated,
             actor_id,
             "activity.#{status}",
             changes,
             revision.material
           ) do
      {:ok, updated}
    else
      false -> {:error, {:validation_failed, %{reason: ["is required"]}}}
      {:error, _reason} = error -> error
    end
  end

  defp insert_revision(activity, actor_id, changes) do
    material = Enum.any?(Map.keys(changes), &(Atom.to_string(&1) in @material_fields))

    %ActivityRevision{activity_id: activity.id, author_id: actor_id}
    |> ActivityRevision.changeset(%{
      version: activity.version,
      material: material,
      changes: stringify_changes(changes)
    })
    |> Repo.insert()
  end

  defp record_activity_side_effects(activity, actor_id, event_type, changes, material) do
    multi =
      Multi.new()
      |> append_activity_propagation_events(activity, event_type, %{
        version: activity.version,
        material: material
      })
      |> Multi.insert(
        :audit,
        audit_changeset(activity.id, actor_id, event_type, nil, stringify_changes(changes))
      )

    case Transactions.transact(multi) do
      {:ok, _changes} -> :ok
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp outbox_attributes(activity, event_type, payload) do
    %{
      topic: "activities",
      event_type: event_type,
      aggregate_type: "activity",
      aggregate_id: activity.id,
      payload: payload,
      available_at: DateTime.utc_now()
    }
  end

  defp append_activity_propagation_events(multi, activity, event_type, payload) do
    for {name, topic} <- [
          {:plans, "plans"},
          {:invitations, "invitations"},
          {:conversation_projection, "conversations"},
          {:notifications, "notifications"}
        ],
        reduce: multi do
      multi ->
        Transactions.append_outbox_event(
          multi,
          name,
          outbox_attributes(activity, event_type, Map.put(payload, :projection, topic))
        )
    end
  end

  defp audit_changeset(activity_id, actor_id, event_type, reason, details) do
    %ActivityAudit{activity_id: activity_id, actor_id: actor_id}
    |> ActivityAudit.changeset(%{event_type: event_type, reason: reason, details: details})
  end

  defp eligible_host?(actor_id) do
    with user when not is_nil(user) <- Repo.get(TripPals.Accounts.User, actor_id),
         true <- user.status == "active",
         true <- Accounts.profile_complete?(user) do
      :ok
    else
      _ -> {:error, :host_ineligible}
    end
  end

  defp supported_city(city_id) do
    case Cities.get_city(city_id) do
      nil -> {:error, :city_not_found}
      %{launch_status: "supported"} = city -> {:ok, city}
      _ -> {:error, :city_unavailable}
    end
  end

  defp activity_idea(nil), do: {:ok, nil}

  defp activity_idea(idea_id) do
    case Repo.get(ActivityIdea, idea_id) do
      %{enabled: true} = idea -> {:ok, idea}
      _ -> {:error, :activity_idea_not_found}
    end
  end

  defp apply_idea(attributes, nil), do: attributes

  defp apply_idea(attributes, idea) do
    attributes
    |> Map.put_new("title", idea.title)
    |> Map.put_new("category", idea.category)
    |> Map.put_new("description", idea.description)
  end

  defp normalize_activity_attributes(attributes) do
    Map.new(attributes, fn {key, value} ->
      atom_key =
        case key do
          "start_at" -> :start_at
          "end_at" -> :end_at
          "confirmation_deadline_at" -> :confirmation_deadline_at
          "cost_amount" -> :cost_amount
          "capacity_total" -> :capacity_total
          "participant_meeting_details" -> :participant_meeting_details
          "public_area" -> :public_area
          "iana_timezone" -> :iana_timezone
          "title" -> :title
          "category" -> :category
          "description" -> :description
          "currency" -> :currency
          "city_id" -> :city_id
          _ -> key
        end

      {atom_key, parse_datetime(value)}
    end)
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> value
    end
  end

  defp parse_datetime(value), do: value

  defp validate_city_timezone(changeset, city) do
    iana_timezone = Ecto.Changeset.get_field(changeset, :iana_timezone)

    if iana_timezone == city.iana_timezone do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :iana_timezone, "must match the city timezone")
    end
  end

  defp version_matches?(activity, expected_version) do
    case parse_version(expected_version) do
      {:ok, version} when version == activity.version -> :ok
      _ -> {:error, {:conflict, host_activity_view(activity)}}
    end
  end

  defp parse_version(version) when is_integer(version), do: {:ok, version}

  defp parse_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_version(_version), do: :error

  defp material_changes(activity, attributes) do
    attributes
    |> normalize_activity_attributes()
    |> Map.take(Enum.map(@material_fields, &String.to_existing_atom/1))
    |> Enum.reduce(%{}, fn {field, value}, changes ->
      if Map.get(activity, field) == value do
        changes
      else
        Map.put(changes, field, %{from: Map.get(activity, field), to: value})
      end
    end)
  end

  defp stringify_changes(changes) do
    Map.new(changes, fn {key, value} -> {to_string(key), value} end)
  end

  defp valid_reason?(reason) when is_binary(reason), do: String.length(String.trim(reason)) >= 3
  defp valid_reason?(_reason), do: false

  defp valid_for_publication?(activity, now) do
    fields =
      %{}
      |> maybe_required(:public_area, activity.public_area)
      |> maybe_required(:cost_amount, activity.cost_amount)
      |> maybe_required(:currency, activity.currency)
      |> maybe_required(:participant_meeting_details, activity.participant_meeting_details)
      |> maybe_future_start(activity.start_at, now)

    if map_size(fields) == 0, do: :ok, else: {:error, {:validation_failed, fields}}
  end

  defp maybe_required(errors, field, value) when is_binary(value) do
    if byte_size(String.trim(value)) > 0,
      do: errors,
      else: Map.put(errors, field, ["is required"])
  end

  defp maybe_required(errors, _field, %Decimal{}), do: errors
  defp maybe_required(errors, field, _value), do: Map.put(errors, field, ["is required"])

  defp maybe_future_start(errors, start_at, now) do
    if DateTime.compare(start_at, now) == :gt,
      do: errors,
      else: Map.put(errors, :start_at, ["must be in the future before publication"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
