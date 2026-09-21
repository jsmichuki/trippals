defmodule TripPals.Invitations.HostInvitationRateWindow do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "host_invitation_rate_windows" do
    field :window_started_at, :utc_datetime_usec
    field :successful_sends, :integer, default: 0
    belongs_to :host, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(window, attributes) do
    window
    |> cast(attributes, [:host_id, :window_started_at, :successful_sends])
    |> validate_required([:host_id, :window_started_at, :successful_sends])
    |> validate_number(:successful_sends, greater_than_or_equal_to: 0)
    |> unique_constraint([:host_id, :window_started_at])
  end
end
