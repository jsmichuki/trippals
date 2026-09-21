defmodule TripPals.Activities.Activity do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activities" do
    field :title, :string
    field :category, :string
    field :description, :string
    field :start_at, :utc_datetime_usec
    field :end_at, :utc_datetime_usec
    field :iana_timezone, :string
    field :public_area, :string
    field :participant_meeting_details, :string
    field :cost_amount, :decimal
    field :currency, :string
    field :capacity_total, :integer
    field :going_count, :integer, default: 0
    field :status, :string, default: "draft"
    field :host_confirmed_at, :utc_datetime_usec
    field :confirmation_deadline_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :concluded_at, :utc_datetime_usec
    field :cancellation_reason, :string
    field :outcome, :string
    field :version, :integer, default: 1
    field :published_at, :utc_datetime_usec
    belongs_to :city, TripPals.Cities.City
    belongs_to :idea, TripPals.Activities.ActivityIdea
    belongs_to :host, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def discovery_changeset(activity, attributes) do
    activity
    |> cast(attributes, [
      :title,
      :category,
      :description,
      :start_at,
      :end_at,
      :iana_timezone,
      :public_area,
      :participant_meeting_details,
      :cost_amount,
      :currency,
      :capacity_total,
      :going_count,
      :status,
      :host_confirmed_at,
      :confirmation_deadline_at,
      :started_at,
      :concluded_at,
      :cancellation_reason,
      :outcome,
      :version,
      :published_at
    ])
    |> validate_required([
      :title,
      :category,
      :description,
      :start_at,
      :end_at,
      :iana_timezone,
      :public_area,
      :capacity_total,
      :status
    ])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:category, min: 1, max: 80)
    |> validate_noncommercial(:title)
    |> validate_noncommercial(:description)
    |> validate_number(:capacity_total, greater_than_or_equal_to: 2, less_than_or_equal_to: 10)
    |> validate_number(:going_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, [
      "draft",
      "published",
      "host_confirmed",
      "in_progress",
      "completed",
      "canceled",
      "expired",
      "outcome_unknown",
      "restricted",
      "pending_review"
    ])
    |> validate_end_after_start()
    |> validate_going_count()
    |> foreign_key_constraint(:city_id)
    |> foreign_key_constraint(:idea_id)
    |> foreign_key_constraint(:host_id)
    |> check_constraint(:end_at, name: :activities_time_order_check)
    |> check_constraint(:capacity_total, name: :activities_capacity_check)
    |> check_constraint(:going_count, name: :activities_going_count_check)
    |> check_constraint(:status, name: :activities_status_check)
    |> check_constraint(:version, name: :activities_version_check)
    |> check_constraint(:outcome, name: :activities_outcome_check)
  end

  defp validate_end_after_start(changeset) do
    start_at = get_field(changeset, :start_at)
    end_at = get_field(changeset, :end_at)

    if start_at && end_at && DateTime.compare(end_at, start_at) != :gt do
      add_error(changeset, :end_at, "must be after start_at")
    else
      changeset
    end
  end

  defp validate_going_count(changeset) do
    capacity_total = get_field(changeset, :capacity_total)
    going_count = get_field(changeset, :going_count)

    if is_integer(capacity_total) and is_integer(going_count) and going_count > capacity_total do
      add_error(changeset, :going_count, "cannot exceed capacity_total")
    else
      changeset
    end
  end

  defp validate_noncommercial(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if Regex.match?(~r{(?:https?://|www\.)}i, value) do
        [{field, "must not include promotional links"}]
      else
        []
      end
    end)
  end
end
