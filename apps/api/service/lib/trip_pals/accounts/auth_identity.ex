defmodule TripPals.Accounts.AuthIdentity do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "auth_identities" do
    field :provider, :string
    field :provider_subject, :string
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(auth_identity, attributes) do
    auth_identity
    |> cast(attributes, [:provider, :provider_subject])
    |> validate_required([:provider, :provider_subject])
    |> validate_length(:provider, min: 1, max: 100)
    |> validate_length(:provider_subject, min: 1, max: 1_024)
    |> unique_constraint([:provider, :provider_subject])
  end
end
