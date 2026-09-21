defmodule TripPals.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "users" do
    field :status, :string, default: "active"
    field :restricted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attributes) do
    user
    |> cast(attributes, [:status, :restricted_at])
    |> validate_inclusion(:status, ~w(active restricted suspended pending_deletion deleted))
  end
end
