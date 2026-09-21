defmodule TripPals.Invitations.Invitation do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses ~w(pending joined declined expired revoked unavailable needs_review)

  schema "invitations" do
    field :status, :string, default: "pending"
    field :sent_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :responded_at, :utc_datetime_usec
    field :event_version_seen, :integer
    field :unavailable_reason, :string
    belongs_to :activity, TripPals.Activities.Activity
    belongs_to :host, TripPals.Accounts.User
    belongs_to :recipient, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invitation, attributes) do
    invitation
    |> cast(attributes, [
      :activity_id,
      :host_id,
      :recipient_id,
      :status,
      :sent_at,
      :expires_at,
      :responded_at,
      :event_version_seen,
      :unavailable_reason
    ])
    |> validate_required([
      :activity_id,
      :host_id,
      :recipient_id,
      :status,
      :sent_at,
      :expires_at,
      :event_version_seen
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:event_version_seen, greater_than: 0)
    |> validate_expiry()
    |> unique_constraint([:activity_id, :recipient_id])
  end

  defp validate_expiry(changeset) do
    with %DateTime{} = sent_at <- get_field(changeset, :sent_at),
         %DateTime{} = expires_at <- get_field(changeset, :expires_at),
         :gt <- DateTime.compare(expires_at, sent_at) do
      changeset
    else
      :lt -> add_error(changeset, :expires_at, "must be after sent_at")
      :eq -> add_error(changeset, :expires_at, "must be after sent_at")
      _ -> changeset
    end
  end
end
