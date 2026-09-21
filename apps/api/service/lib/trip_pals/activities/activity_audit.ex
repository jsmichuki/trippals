defmodule TripPals.Activities.ActivityAudit do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activity_audits" do
    field :event_type, :string
    field :reason, :string
    field :details, :map, default: %{}
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :actor, TripPals.Accounts.User
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(audit, attributes) do
    audit
    |> cast(attributes, [:event_type, :reason, :details])
    |> validate_required([:event_type, :details])
    |> validate_length(:event_type, min: 1, max: 100)
  end
end
