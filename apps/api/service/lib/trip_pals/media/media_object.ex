defmodule TripPals.Media.MediaObject do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  @scopes ~w(avatar report_evidence)
  @statuses ~w(intent uploaded available rejected expired deleted)
  @validation_statuses ~w(pending validated rejected)
  @scan_statuses ~w(pending clean failed)

  schema "media_objects" do
    field :object_key, :string
    field :scope, :string
    field :content_type, :string
    field :byte_size, :integer
    field :content_sha256, :binary
    field :validation_status, :string, default: "pending"
    field :scan_status, :string, default: "pending"
    field :status, :string, default: "intent"
    field :expires_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :available_at, :utc_datetime_usec
    field :retention_until, :utc_datetime_usec
    field :delete_after, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    field :deletion_reason, :string
    field :metadata, :map, default: %{}
    belongs_to :owner, TripPals.Accounts.User
    belongs_to :report, TripPals.Safety.Report
    timestamps(type: :utc_datetime_usec)
  end

  def intent_changeset(media, attributes) do
    media
    |> cast(attributes, [
      :id,
      :object_key,
      :scope,
      :content_type,
      :byte_size,
      :expires_at,
      :metadata
    ])
    |> validate_required([:id, :object_key, :scope, :content_type, :byte_size, :expires_at])
    |> validate_inclusion(:scope, @scopes)
    |> validate_number(:byte_size, greater_than: 0)
    |> validate_length(:object_key, min: 12, max: 255)
    |> validate_metadata()
    |> unique_constraint(:object_key)
    |> check_constraint(:scope, name: :media_objects_scope_check)
    |> check_constraint(:byte_size, name: :media_objects_byte_size_check)
    |> check_constraint(:scope, name: :media_objects_scope_reference_check)
  end

  def lifecycle_changeset(media, attributes) do
    media
    |> cast(attributes, [
      :content_sha256,
      :validation_status,
      :scan_status,
      :status,
      :confirmed_at,
      :available_at,
      :retention_until,
      :delete_after,
      :deleted_at,
      :deletion_reason
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:validation_status, @validation_statuses)
    |> validate_inclusion(:scan_status, @scan_statuses)
    |> check_constraint(:status, name: :media_objects_status_check)
    |> check_constraint(:validation_status, name: :media_objects_validation_status_check)
    |> check_constraint(:scan_status, name: :media_objects_scan_status_check)
  end

  defp validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      if is_map(metadata) and map_size(metadata) <= 8,
        do: [],
        else: [metadata: "is invalid"]
    end)
  end
end
