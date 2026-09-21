defmodule TripPals.Accounts.WebAuthnChallenge do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webauthn_challenges" do
    field :challenge_hash, :binary
    field :ceremony, :string
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    belongs_to :session, TripPals.Accounts.Session
    timestamps(type: :utc_datetime_usec)
  end
end
