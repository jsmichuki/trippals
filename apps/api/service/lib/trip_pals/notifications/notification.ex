defmodule TripPals.Notifications.Notification do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :event_type, :string
    field :essential, :boolean, default: false
    field :invitation_id, Ecto.UUID
    field :conversation_id, Ecto.UUID
    field :deep_link, :string
    field :dedupe_key, :string
    field :payload, :map, default: %{}
    field :read_at, :utc_datetime_usec
    field :dismissed_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    belongs_to :activity, TripPals.Activities.Activity
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(notification, attributes) do
    notification
    |> cast(attributes, [
      :event_type,
      :essential,
      :activity_id,
      :invitation_id,
      :conversation_id,
      :deep_link,
      :dedupe_key,
      :payload,
      :read_at,
      :dismissed_at
    ])
    |> validate_required([:event_type, :essential, :deep_link, :payload])
    |> validate_length(:event_type, min: 3, max: 100)
    |> validate_length(:deep_link, min: 1, max: 500)
    |> validate_length(:dedupe_key, max: 200)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:activity_id)
    |> unique_constraint([:user_id, :dedupe_key])
  end
end
