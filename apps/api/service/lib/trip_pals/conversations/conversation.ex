defmodule TripPals.Conversations.Conversation do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :status, :string, default: "active"
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :host, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attributes) do
    conversation
    |> cast(attributes, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["active", "read_only", "archived", "frozen"])
    |> unique_constraint(:activity_id)
  end
end
