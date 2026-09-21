defmodule TripPals.Participation.Record do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "participations" do
    field :status, :string, default: "interested"
    field :reconfirmed_at, :utc_datetime_usec
    field :attendance, :string
    field :left_at, :utc_datetime_usec
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs),
    do:
      record
      |> cast(attrs, [:status, :reconfirmed_at, :attendance, :left_at])
      |> validate_inclusion(:status, ["interested", "going", "left"])
      |> validate_inclusion(:attendance, ["attended", "not_attended", "prefer_not_to_say"])
      |> unique_constraint([:activity_id, :user_id])
end
