defmodule TripPals.Invitations.InvitationSetting do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invitation_settings" do
    field :enabled, :boolean, default: false
    field :consented_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :shareable_fields, :map, default: %{}
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting, attributes) do
    setting
    |> cast(attributes, [:enabled, :consented_at, :revoked_at, :shareable_fields])
    |> validate_change(:shareable_fields, &valid_shareable_fields/2)
    |> unique_constraint(:user_id)
  end

  defp valid_shareable_fields(:shareable_fields, fields) when is_map(fields), do: []

  defp valid_shareable_fields(:shareable_fields, _fields),
    do: [shareable_fields: "must be an object"]
end
