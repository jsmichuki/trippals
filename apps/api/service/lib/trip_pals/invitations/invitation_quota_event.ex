defmodule TripPals.Invitations.InvitationQuotaEvent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invitation_quota_events" do
    field :sent_at, :utc_datetime_usec
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :recipient, TripPals.Accounts.User
    belongs_to :invitation, TripPals.Invitations.Invitation
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attributes) do
    event
    |> cast(attributes, [:activity_id, :recipient_id, :invitation_id, :sent_at])
    |> validate_required([:activity_id, :recipient_id, :invitation_id, :sent_at])
    |> unique_constraint([:activity_id, :recipient_id])
  end
end
