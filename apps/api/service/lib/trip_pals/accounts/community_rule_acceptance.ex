defmodule TripPals.Accounts.CommunityRuleAcceptance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_rule_acceptances" do
    field :rule_version, :string
    field :accepted_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(acceptance, attributes) do
    acceptance
    |> cast(attributes, [:rule_version, :accepted_at])
    |> validate_required([:rule_version, :accepted_at])
    |> unique_constraint([:user_id, :rule_version])
  end
end
