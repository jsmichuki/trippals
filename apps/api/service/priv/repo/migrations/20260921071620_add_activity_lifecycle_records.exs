defmodule TripPals.Repo.Migrations.AddActivityLifecycleRecords do
  use Ecto.Migration

  def change do
    alter table(:activities) do
      add :confirmation_deadline_at, :timestamptz
      add :started_at, :timestamptz
      add :concluded_at, :timestamptz
      add :cancellation_reason, :text
      add :outcome, :string
      add :version, :integer, null: false, default: 1
      add :published_at, :timestamptz
    end

    create constraint(:activities, :activities_version_check, check: "version > 0")

    create constraint(:activities, :activities_outcome_check,
             check:
               "outcome IS NULL OR outcome IN ('host_reported_completed', 'not_held', 'unknown')"
           )

    create table(:activity_host_assignments, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :role, :string, null: false, default: "primary"
      add :seat_counted, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:activity_host_assignments, [:activity_id, :user_id])

    create unique_index(:activity_host_assignments, [:activity_id],
             where: "role = 'primary'",
             name: :activity_host_assignments_one_primary_host_index
           )

    create constraint(:activity_host_assignments, :activity_host_assignments_role_check,
             check: "role IN ('primary', 'co_host')"
           )

    create table(:activity_revisions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :version, :integer, null: false
      add :material, :boolean, null: false
      add :changes, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:activity_revisions, [:activity_id, :version])

    create table(:activity_change_acknowledgements, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false

      add :revision_id, references(:activity_revisions, type: :uuid, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :acknowledged_at, :timestamptz, null: false
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:activity_change_acknowledgements, [:revision_id, :user_id])

    create table(:activity_audits, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :actor_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :event_type, :string, null: false
      add :reason, :text
      add :details, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:activity_audits, [:activity_id, :inserted_at])

    create table(:conversations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :host_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversations, [:activity_id])

    create constraint(:conversations, :conversations_status_check,
             check: "status IN ('active', 'read_only', 'archived', 'frozen')"
           )
  end
end
