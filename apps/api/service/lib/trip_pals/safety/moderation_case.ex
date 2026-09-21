defmodule TripPals.Safety.ModerationCase do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moderation_cases" do
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :status, :string, default: "open"
    field :resolution, :string
    field :resolved_at, :utc_datetime_usec
    belongs_to :report, TripPals.Safety.Report
    belongs_to :assigned_staff, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(moderation_case, attributes) do
    moderation_case
    |> cast(attributes, [
      :target_type,
      :target_id,
      :status,
      :assigned_staff_id,
      :resolution,
      :resolved_at
    ])
    |> validate_required([:target_type, :target_id, :status])
    |> validate_inclusion(:target_type, ~w(activity message account))
    |> validate_inclusion(:status, ~w(open investigating actioned closed))
    |> foreign_key_constraint(:report_id)
  end
end
