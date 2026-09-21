defmodule TripPals.Conversations.ConversationMembership do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversation_memberships" do
    field :status, :string, default: "active"
    field :revoked_at, :utc_datetime_usec
    belongs_to :conversation, TripPals.Conversations.Conversation
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attributes) do
    membership
    |> cast(attributes, [:status, :revoked_at])
    |> validate_inclusion(:status, ["active", "revoked"])
    |> unique_constraint([:conversation_id, :user_id])
  end
end
