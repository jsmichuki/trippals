defmodule TripPals.Activities.ActivityHostAssignment do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activity_host_assignments" do
    field :role, :string, default: "primary"
    field :seat_counted, :boolean, default: true
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(assignment, attributes) do
    assignment
    |> cast(attributes, [:role, :seat_counted])
    |> validate_required([:role, :seat_counted])
    |> validate_inclusion(:role, ["primary", "co_host"])
    |> unique_constraint([:activity_id, :user_id])
    |> unique_constraint(:activity_id, name: :activity_host_assignments_one_primary_host_index)
  end
end
