defmodule TripPals.Conversations.Conversation do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :status, :string, default: "active"
    field :grace_ends_at, :utc_datetime_usec
    field :next_message_sequence, :integer, default: 0
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :host, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attributes) do
    conversation
    |> cast(attributes, [:status, :grace_ends_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, [
      "active",
      "bounded_grace",
      "read_only",
      "archived",
      "safety_freeze",
      "frozen"
    ])
    |> unique_constraint(:activity_id)
  end
end
