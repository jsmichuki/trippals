defmodule TripPals.Accounts.Session do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :family_id, Ecto.UUID
    field :device_id, :string
    field :recently_authenticated_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    has_many :refresh_tokens, TripPals.Accounts.RefreshToken
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attributes) do
    session
    |> cast(attributes, [:family_id, :device_id, :recently_authenticated_at, :revoked_at])
    |> validate_required([:family_id, :recently_authenticated_at])
  end
end
