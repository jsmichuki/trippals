defmodule TripPals.Safety.ModerationCaseEvent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moderation_case_events" do
    field :event_type, :string
    field :reason, :string
    field :details, :map, default: %{}
    belongs_to :moderation_case, TripPals.Safety.ModerationCase, foreign_key: :case_id
    belongs_to :actor, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attributes) do
    event
    |> cast(attributes, [:event_type, :reason, :details])
    |> validate_required([:event_type, :reason])
    |> validate_length(:event_type, min: 2, max: 80)
    |> validate_length(:reason, min: 3, max: 1_000)
  end
end
