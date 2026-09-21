defmodule TripPals.Safety.Block do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "blocks" do
    field :reason_code, :string
    field :source, :string, default: "member"
    belongs_to :blocker, TripPals.Accounts.User
    belongs_to :blocked, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(block, attributes) do
    block
    |> cast(attributes, [:reason_code, :source])
    |> validate_inclusion(:source, ~w(member staff))
    |> validate_change(:reason_code, fn :reason_code, value ->
      if String.length(value) <= 80, do: [], else: [reason_code: "is too long"]
    end)
    |> unique_constraint([:blocker_id, :blocked_id])
    |> check_constraint(:blocked_id, name: :blocks_distinct_users_check)
  end
end
