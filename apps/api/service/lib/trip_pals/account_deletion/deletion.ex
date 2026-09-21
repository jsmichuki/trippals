defmodule TripPals.AccountDeletion.Deletion do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_deletions" do
    field :status, :string, default: "requested"
    field :policy_version, :string
    field :requested_at, :utc_datetime_usec
    field :access_revoked_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :retention_review_at, :utc_datetime_usec
    field :failure_code, :string
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(deletion, attributes) do
    deletion
    |> cast(attributes, [
      :status,
      :policy_version,
      :requested_at,
      :access_revoked_at,
      :completed_at,
      :retention_review_at,
      :failure_code
    ])
    |> validate_required([:status, :policy_version, :requested_at])
    |> validate_inclusion(:status, ~w(requested access_revoked completed retention_hold))
    |> unique_constraint(:user_id)
  end
end
