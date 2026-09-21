defmodule TripPals.Accounts.RefreshToken do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "refresh_tokens" do
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :replaced_by_id, Ecto.UUID
    belongs_to :session, TripPals.Accounts.Session
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(token, attributes) do
    token
    |> cast(attributes, [:token_hash, :expires_at, :used_at, :revoked_at, :replaced_by_id])
    |> validate_required([:token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
