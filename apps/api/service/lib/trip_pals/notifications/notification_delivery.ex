defmodule TripPals.Notifications.NotificationDelivery do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_deliveries" do
    field :channel, :string
    field :status, :string, default: "pending"
    field :provider_message_id, :string
    field :attempt_count, :integer, default: 0
    field :last_error_code, :string
    field :delivered_at, :utc_datetime_usec
    field :available_at, :utc_datetime_usec
    belongs_to :notification, TripPals.Notifications.Notification
    belongs_to :device, TripPals.Notifications.Device
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attributes) do
    delivery
    |> cast(attributes, [
      :channel,
      :status,
      :provider_message_id,
      :attempt_count,
      :last_error_code,
      :delivered_at,
      :available_at
    ])
    |> validate_required([:channel, :status, :available_at])
    |> validate_inclusion(:channel, ~w(push in_app))
    |> validate_inclusion(:status, ~w(pending processing delivered failed invalidated))
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:notification_id)
    |> foreign_key_constraint(:device_id)
    |> unique_constraint([:notification_id, :device_id, :channel])
  end
end
