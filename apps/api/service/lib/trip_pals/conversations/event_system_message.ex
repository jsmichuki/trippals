defmodule TripPals.Conversations.EventSystemMessage do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_system_messages" do
    field :event_type, :string
    field :sequence, :integer
    field :payload, :map, default: %{}
    belongs_to :conversation, TripPals.Conversations.Conversation
    belongs_to :actor, TripPals.Accounts.User
    belongs_to :message, TripPals.Conversations.Message
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attributes) do
    event
    |> cast(attributes, [:event_type, :sequence, :payload, :message_id])
    |> validate_required([:event_type, :sequence, :payload])
    |> validate_length(:event_type, min: 1, max: 100)
    |> validate_number(:sequence, greater_than: 0)
    |> check_constraint(:sequence, name: :event_system_messages_sequence_check)
    |> unique_constraint([:conversation_id, :sequence])
  end
end
