defmodule TripPals.Accounts.Profile do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "profiles" do
    field :display_name, :string
    field :profile_completed_at, :utc_datetime_usec
    field :adult_eligible_at, :utc_datetime_usec
    field :invitation_discoverable, :boolean, default: false
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(profile, attributes) do
    profile
    |> cast(attributes, [
      :display_name,
      :profile_completed_at,
      :adult_eligible_at,
      :invitation_discoverable
    ])
    |> validate_length(:display_name, min: 1, max: 80)
    |> unique_constraint(:user_id)
  end
end
