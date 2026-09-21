defmodule TripPals.Safety.StaffRoleAssignment do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "staff_role_assignments" do
    field :role, :string
    field :scope_type, :string, default: "platform"
    field :scope_id, Ecto.UUID
    field :revoked_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    belongs_to :granted_by, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(assignment, attributes) do
    assignment
    |> cast(attributes, [:role, :scope_type, :scope_id, :revoked_at])
    |> validate_required([:role, :scope_type])
    |> validate_inclusion(:role, ~w(moderator administrator))
    |> validate_inclusion(:scope_type, ~w(platform city))
  end
end
