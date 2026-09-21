defmodule TripPals.Activities.ActivityChangeAcknowledgement do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activity_change_acknowledgements" do
    field :acknowledged_at, :utc_datetime_usec
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :revision, TripPals.Activities.ActivityRevision
    belongs_to :user, TripPals.Accounts.User
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(acknowledgement, attributes) do
    acknowledgement
    |> cast(attributes, [:acknowledged_at])
    |> validate_required([:acknowledged_at])
    |> unique_constraint([:revision_id, :user_id])
  end
end
