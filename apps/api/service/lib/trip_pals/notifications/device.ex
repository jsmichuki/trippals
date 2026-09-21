defmodule TripPals.Notifications.Device do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "devices" do
    field :platform, :string
    field :token_digest, :string
    field :token_ciphertext, :binary
    field :token_last_four, :string
    field :status, :string, default: "active"
    field :last_seen_at, :utc_datetime_usec
    field :invalidated_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(device, attributes) do
    device
    |> cast(attributes, [
      :platform,
      :token_digest,
      :token_ciphertext,
      :token_last_four,
      :status,
      :last_seen_at,
      :invalidated_at
    ])
    |> validate_required([:platform, :token_digest, :token_ciphertext, :token_last_four, :status])
    |> validate_inclusion(:platform, ~w(ios android))
    |> validate_inclusion(:status, ~w(active invalidated))
    |> validate_length(:token_digest, is: 64)
    |> validate_length(:token_last_four, is: 4)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:platform, :token_digest])
  end
end
