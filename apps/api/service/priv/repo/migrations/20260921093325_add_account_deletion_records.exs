defmodule TripPals.Repo.Migrations.AddAccountDeletionRecords do
  use Ecto.Migration

  def change do
    create table(:account_deletions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "requested"
      add :policy_version, :string, null: false
      add :requested_at, :timestamptz, null: false
      add :access_revoked_at, :timestamptz
      add :completed_at, :timestamptz
      add :retention_review_at, :timestamptz
      add :failure_code, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_deletions, [:user_id])
    create index(:account_deletions, [:status, :inserted_at])

    create constraint(:account_deletions, :account_deletions_status_check,
             check: "status IN ('requested', 'access_revoked', 'completed', 'retention_hold')"
           )

    create table(:account_retention_records, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :account_deletion_id,
          references(:account_deletions, type: :uuid, on_delete: :delete_all),
          null: false

      add :category, :string, null: false
      add :record_type, :string, null: false
      add :record_id, :uuid, null: false
      add :retention_until, :timestamptz, null: false
      add :deidentified_at, :timestamptz
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:account_retention_records, [
             :account_deletion_id,
             :record_type,
             :record_id
           ])

    create index(:account_retention_records, [:retention_until])

    create constraint(:account_retention_records, :account_retention_records_category_check,
             check: "category IN ('safety', 'case', 'audit')"
           )
  end
end
