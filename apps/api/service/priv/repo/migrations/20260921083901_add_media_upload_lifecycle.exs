defmodule TripPals.Repo.Migrations.AddMediaUploadLifecycle do
  use Ecto.Migration

  def change do
    # The preceding placeholder migration was released without D10's schema.
    # Keep it immutable and introduce the media lifecycle as an additive change.
    create table(:media_objects, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :object_key, :string, null: false
      add :owner_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :report_id, references(:reports, type: :uuid, on_delete: :restrict)
      add :scope, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :content_sha256, :binary
      add :validation_status, :string, null: false, default: "pending"
      add :scan_status, :string, null: false, default: "pending"
      add :status, :string, null: false, default: "intent"
      add :expires_at, :utc_datetime_usec, null: false
      add :confirmed_at, :utc_datetime_usec
      add :available_at, :utc_datetime_usec
      add :retention_until, :utc_datetime_usec
      add :delete_after, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec
      add :deletion_reason, :string
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_objects, [:object_key])
    create index(:media_objects, [:owner_id, :scope, :status])
    create index(:media_objects, [:report_id, :status])
    create index(:media_objects, [:status, :expires_at])
    create index(:media_objects, [:status, :delete_after])

    create constraint(:media_objects, :media_objects_scope_check,
             check: "scope IN ('avatar', 'report_evidence')"
           )

    create constraint(:media_objects, :media_objects_status_check,
             check:
               "status IN ('intent', 'uploaded', 'available', 'rejected', 'expired', 'deleted')"
           )

    create constraint(:media_objects, :media_objects_validation_status_check,
             check: "validation_status IN ('pending', 'validated', 'rejected')"
           )

    create constraint(:media_objects, :media_objects_scan_status_check,
             check: "scan_status IN ('pending', 'clean', 'failed')"
           )

    create constraint(:media_objects, :media_objects_byte_size_check, check: "byte_size > 0")

    create constraint(:media_objects, :media_objects_scope_reference_check,
             check:
               "(scope = 'avatar' AND owner_id IS NOT NULL AND report_id IS NULL) OR (scope = 'report_evidence' AND owner_id IS NOT NULL AND report_id IS NOT NULL)"
           )
  end
end
