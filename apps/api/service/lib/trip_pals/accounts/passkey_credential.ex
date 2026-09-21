defmodule TripPals.Accounts.PasskeyCredential do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "passkey_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :rp_id, :string
    field :transports, {:array, :string}, default: []
    field :backup_eligible, :boolean, default: false
    field :backup_state, :boolean, default: false
    field :aaguid, :binary
    field :label, :string
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(credential, attributes) do
    credential
    |> cast(attributes, [
      :credential_id,
      :public_key,
      :sign_count,
      :rp_id,
      :transports,
      :backup_eligible,
      :backup_state,
      :aaguid,
      :label,
      :last_used_at,
      :revoked_at
    ])
    |> validate_required([:credential_id, :public_key, :rp_id, :label])
    |> validate_number(:sign_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:credential_id)
  end
end
