defmodule TripPals.Participation.ParticipationHistory do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "participation_history" do
    field :from_status, :string
    field :to_status, :string
    field :reason, :string
    belongs_to :participation, TripPals.Participation.Record
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :user, TripPals.Accounts.User
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(history, attrs),
    do:
      history
      |> cast(attrs, [:from_status, :to_status, :reason])
      |> validate_required([:to_status])
end
