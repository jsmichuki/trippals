defmodule TripPals.AccountDeletion.RetentionRecord do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_retention_records" do
    field :category, :string
    field :record_type, :string
    field :record_id, Ecto.UUID
    field :retention_until, :utc_datetime_usec
    field :deidentified_at, :utc_datetime_usec
    belongs_to :account_deletion, TripPals.AccountDeletion.Deletion
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attributes) do
    record
    |> cast(attributes, [:category, :record_type, :record_id, :retention_until, :deidentified_at])
    |> validate_required([:category, :record_type, :record_id, :retention_until])
    |> validate_inclusion(:category, ~w(safety case audit))
    |> unique_constraint([:account_deletion_id, :record_type, :record_id])
  end
end
