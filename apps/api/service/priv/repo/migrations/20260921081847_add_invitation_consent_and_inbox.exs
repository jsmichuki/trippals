defmodule TripPals.Repo.Migrations.AddInvitationConsentAndInbox do
  use Ecto.Migration

  def change do
    create table(:invitation_settings, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :enabled, :boolean, null: false, default: false
      add :consented_at, :timestamptz
      add :revoked_at, :timestamptz
      add :shareable_fields, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitation_settings, [:user_id])

    create table(:availabilities, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :uuid, on_delete: :restrict), null: false
      add :role, :string, null: false
      add :start_local_date, :date
      add :end_local_date, :date
      add :time_preferences, :map, null: false, default: fragment("'{}'::jsonb")
      add :shareable_fields, :map, null: false, default: fragment("'{}'::jsonb")
      add :visible, :boolean, null: false, default: false
      add :expires_at, :timestamptz
      add :revoked_at, :timestamptz
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:availabilities, :availabilities_role_check,
             check: "role IN ('traveler', 'resident')"
           )

    create constraint(:availabilities, :availabilities_date_order_check,
             check:
               "end_local_date IS NULL OR start_local_date IS NULL OR end_local_date >= start_local_date"
           )

    create index(:availabilities, [:city_id, :visible, :expires_at])
    create index(:availabilities, [:user_id, :revoked_at])

    create table(:invitations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :host_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :recipient_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "pending"
      add :sent_at, :timestamptz, null: false
      add :expires_at, :timestamptz, null: false
      add :responded_at, :timestamptz
      add :event_version_seen, :integer, null: false
      add :unavailable_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitations, [:activity_id, :recipient_id])
    create index(:invitations, [:recipient_id, :status, :expires_at])
    create index(:invitations, [:activity_id, :status])

    create constraint(:invitations, :invitations_status_check,
             check:
               "status IN ('pending', 'joined', 'declined', 'expired', 'revoked', 'unavailable', 'needs_review')"
           )

    create table(:invitation_quota_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :recipient_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :invitation_id, references(:invitations, type: :uuid, on_delete: :restrict), null: false
      add :sent_at, :timestamptz, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:invitation_quota_events, [:activity_id, :recipient_id])
    create index(:invitation_quota_events, [:activity_id, :sent_at])

    create table(:host_invitation_rate_windows, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :host_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :window_started_at, :timestamptz, null: false
      add :successful_sends, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:host_invitation_rate_windows, [:host_id, :window_started_at])

    create constraint(:host_invitation_rate_windows, :host_invitation_rate_windows_count_check,
             check: "successful_sends >= 0"
           )
  end
end
