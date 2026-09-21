defmodule TripPals.Platform.OutboxEvent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @statuses ~w(pending processing dispatched discarded)

  schema "outbox_events" do
    field :topic, :string
    field :event_type, :string
    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :attempt_count, :integer, default: 0
    field :last_error_code, :string
    field :available_at, :utc_datetime_usec
    field :dispatched_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(outbox_event, attributes) do
    outbox_event
    |> cast(attributes, [
      :topic,
      :event_type,
      :aggregate_type,
      :aggregate_id,
      :payload,
      :status,
      :attempt_count,
      :last_error_code,
      :available_at,
      :dispatched_at
    ])
    |> validate_required([:topic, :event_type, :aggregate_type, :aggregate_id, :available_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
  end
end
