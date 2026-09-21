defmodule TripPals.Invitations.Availability do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "availabilities" do
    field :role, :string
    field :start_local_date, :date
    field :end_local_date, :date
    field :time_preferences, :map, default: %{}
    field :shareable_fields, :map, default: %{}
    field :visible, :boolean, default: false
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    belongs_to :city, TripPals.Cities.City
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(availability, attributes) do
    availability
    |> cast(attributes, [
      :city_id,
      :role,
      :start_local_date,
      :end_local_date,
      :time_preferences,
      :shareable_fields,
      :visible,
      :expires_at,
      :revoked_at
    ])
    |> validate_required([:city_id, :role])
    |> validate_inclusion(:role, ["traveler", "resident"])
    |> validate_date_order()
    |> validate_map(:time_preferences)
    |> validate_map(:shareable_fields)
    |> foreign_key_constraint(:city_id)
  end

  defp validate_date_order(changeset) do
    case {get_field(changeset, :start_local_date), get_field(changeset, :end_local_date)} do
      {%Date{} = start_date, %Date{} = end_date} when end_date < start_date ->
        add_error(changeset, :end_local_date, "must not be before start_local_date")

      _ ->
        changeset
    end
  end

  defp validate_map(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_map(value), do: [], else: [{field, "must be an object"}]
    end)
  end
end
