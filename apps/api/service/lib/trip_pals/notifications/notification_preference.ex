defmodule TripPals.Notifications.NotificationPreference do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_preferences" do
    field :essential_enabled, :boolean, default: true
    field :nonessential_enabled, :boolean, default: true
    field :push_enabled, :boolean, default: true
    field :muted_activity_ids, {:array, Ecto.UUID}, default: []
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, attributes) do
    preference
    |> cast(attributes, [
      :essential_enabled,
      :nonessential_enabled,
      :push_enabled,
      :muted_activity_ids
    ])
    |> validate_required([
      :essential_enabled,
      :nonessential_enabled,
      :push_enabled,
      :muted_activity_ids
    ])
  end
end
