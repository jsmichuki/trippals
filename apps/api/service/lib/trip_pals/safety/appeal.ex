defmodule TripPals.Safety.Appeal do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "appeals" do
    field :statement, :string
    field :status, :string, default: "submitted"
    field :decision_reason, :string
    field :reviewed_at, :utc_datetime_usec
    belongs_to :restriction, TripPals.Safety.AccountRestriction
    belongs_to :appellant, TripPals.Accounts.User
    belongs_to :reviewed_by, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(appeal, attributes) do
    appeal
    |> cast(attributes, [:statement, :status, :decision_reason, :reviewed_at])
    |> validate_required([:statement])
    |> validate_length(:statement, min: 3, max: 4_000)
    |> validate_inclusion(:status, ~w(submitted in_review upheld overturned))
    |> unique_constraint([:restriction_id, :appellant_id],
      name: :appeals_one_open_per_restriction
    )
  end
end
