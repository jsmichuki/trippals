defmodule TripPals.Safety.AuditEntry do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_log" do
    field :action, :string
    field :scope, :string
    field :reason, :string
    field :metadata, :map, default: %{}
    belongs_to :actor, TripPals.Accounts.User
    belongs_to :subject, TripPals.Accounts.User
    belongs_to :moderation_case, TripPals.Safety.ModerationCase, foreign_key: :case_id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attributes) do
    entry
    |> cast(attributes, [:action, :scope, :reason, :metadata])
    |> validate_required([:action, :scope, :reason])
    |> validate_length(:action, min: 2, max: 100)
    |> validate_length(:scope, min: 2, max: 100)
    |> validate_length(:reason, min: 3, max: 1_000)
  end
end
