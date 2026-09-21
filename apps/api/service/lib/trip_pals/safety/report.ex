defmodule TripPals.Safety.Report do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @target_types ~w(activity message account)
  @reason_codes ~w(harassment unwanted_sexual_contact scam_spam misleading_commercial_activity abuse immediate_safety_concern other)

  schema "reports" do
    field :target_type, :string
    field :target_id, Ecto.UUID
    field :reason_code, :string
    field :evidence_reference, :string
    field :context, :map, default: %{}
    field :urgency, :string, default: "standard"
    field :status, :string, default: "submitted"
    belongs_to :reporter, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(report, attributes) do
    report
    |> cast(attributes, [
      :target_type,
      :target_id,
      :reason_code,
      :evidence_reference,
      :context,
      :urgency
    ])
    |> validate_required([:target_type, :target_id, :reason_code])
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:reason_code, @reason_codes)
    |> validate_inclusion(:urgency, ~w(standard urgent))
    |> validate_length(:evidence_reference, max: 512)
    |> validate_context()
    |> check_constraint(:target_type, name: :reports_target_type_check)
    |> check_constraint(:reason_code, name: :reports_reason_code_check)
  end

  defp validate_context(changeset) do
    validate_change(changeset, :context, fn :context, value ->
      if is_map(value) and map_size(value) <= 12, do: [], else: [context: "is invalid"]
    end)
  end
end
