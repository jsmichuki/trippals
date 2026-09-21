defmodule TripPals.Safety.Block do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "blocks" do
    belongs_to :blocker, TripPals.Accounts.User
    belongs_to :blocked, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(block, attributes) do
    block
    |> cast(attributes, [])
    |> validate_change(:blocked_id, fn :blocked_id, blocked_id ->
      if blocked_id == block.blocker_id, do: [blocked_id: "cannot be the blocker"], else: []
    end)
    |> unique_constraint([:blocker_id, :blocked_id])
    |> check_constraint(:blocked_id, name: :blocks_distinct_users_check)
  end
end
