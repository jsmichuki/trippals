defmodule TripPals.Activities.ActivityRevision do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activity_revisions" do
    field :version, :integer
    field :material, :boolean
    field :changes, :map, default: %{}
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :author, TripPals.Accounts.User
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(revision, attributes) do
    revision
    |> cast(attributes, [:version, :material, :changes])
    |> validate_required([:version, :material, :changes])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:activity_id, :version])
  end
end
