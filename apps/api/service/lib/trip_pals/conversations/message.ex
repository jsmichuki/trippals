defmodule TripPals.Conversations.Message do
  use Ecto.Schema

  import Ecto.Changeset

  @max_body_length 2_000

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :client_message_id, :binary_id
    field :sequence, :integer
    field :body, :string
    field :moderation_state, :string, default: "visible"
    field :moderated_at, :utc_datetime_usec
    field :report_reference_id, :binary_id
    belongs_to :conversation, TripPals.Conversations.Conversation
    belongs_to :sender, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attributes) do
    message
    |> cast(attributes, [:client_message_id, :sequence, :body])
    |> validate_required([:client_message_id, :sequence, :body])
    |> validate_number(:sequence, greater_than: 0)
    |> validate_body()
    |> unique_constraint([:conversation_id, :sender_id, :client_message_id])
    |> unique_constraint([:conversation_id, :sequence])
    |> check_constraint(:sequence, name: :messages_sequence_check)
  end

  def moderation_changeset(message, attributes) do
    message
    |> cast(attributes, [:moderation_state, :moderated_at, :report_reference_id])
    |> validate_inclusion(:moderation_state, ["visible", "hidden", "removed"])
    |> check_constraint(:moderation_state, name: :messages_moderation_state_check)
  end

  defp validate_body(changeset) do
    validate_change(changeset, :body, fn :body, body ->
      cond do
        not String.valid?(body) ->
          [body: "must be valid UTF-8 text"]

        String.trim(body) == "" ->
          [body: "cannot be blank"]

        String.length(body) > @max_body_length ->
          [body: "must be at most #{@max_body_length} characters"]

        String.contains?(body, <<0>>) ->
          [body: "contains unsupported content"]

        true ->
          []
      end
    end)
  end
end
