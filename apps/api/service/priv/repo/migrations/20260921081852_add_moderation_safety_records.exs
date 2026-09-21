defmodule TripPals.Repo.Migrations.AddModerationSafetyRecords do
  use Ecto.Migration

  def change do
    # The pair table already guards participation. Extend it; never recreate it.
    alter table(:blocks) do
      add :reason_code, :string
      add :source, :string, null: false, default: "member"
    end

    create constraint(:blocks, :blocks_source_check, check: "source IN ('member', 'staff')")

    create table(:staff_role_assignments, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :scope_type, :string, null: false, default: "platform"
      add :scope_id, :uuid
      add :granted_by_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:staff_role_assignments, [:user_id, :role, :scope_type, :scope_id],
             name: :staff_role_assignments_unique_scope
           )

    create index(:staff_role_assignments, [:user_id, :revoked_at])

    create constraint(:staff_role_assignments, :staff_role_assignments_role_check,
             check: "role IN ('moderator', 'administrator')"
           )

    create constraint(:staff_role_assignments, :staff_role_assignments_scope_check,
             check: "scope_type IN ('platform', 'city')"
           )

    create table(:reports, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :reporter_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :target_type, :string, null: false
      add :target_id, :uuid, null: false
      add :reason_code, :string, null: false
      add :evidence_reference, :string
      add :context, :map, null: false, default: %{}
      add :urgency, :string, null: false, default: "standard"
      add :status, :string, null: false, default: "submitted"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:reports, [:target_type, :target_id, :inserted_at])
    create index(:reports, [:reporter_id, :inserted_at])

    create constraint(:reports, :reports_target_type_check,
             check: "target_type IN ('activity', 'message', 'account')"
           )

    create constraint(:reports, :reports_reason_code_check,
             check:
               "reason_code IN ('harassment', 'unwanted_sexual_contact', 'scam_spam', 'misleading_commercial_activity', 'abuse', 'immediate_safety_concern', 'other')"
           )

    create constraint(:reports, :reports_urgency_check,
             check: "urgency IN ('standard', 'urgent')"
           )

    create constraint(:reports, :reports_status_check,
             check: "status IN ('submitted', 'in_review', 'closed')"
           )

    create table(:moderation_cases, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :report_id, references(:reports, type: :uuid, on_delete: :restrict), null: false
      add :target_type, :string, null: false
      add :target_id, :uuid, null: false
      add :status, :string, null: false, default: "open"
      add :assigned_staff_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :resolution, :string
      add :resolved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:moderation_cases, [:report_id])
    create index(:moderation_cases, [:status, :inserted_at])
    create index(:moderation_cases, [:assigned_staff_id, :status])

    create constraint(:moderation_cases, :moderation_cases_target_type_check,
             check: "target_type IN ('activity', 'message', 'account')"
           )

    create constraint(:moderation_cases, :moderation_cases_status_check,
             check: "status IN ('open', 'investigating', 'actioned', 'closed')"
           )

    create table(:moderation_case_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :case_id, references(:moderation_cases, type: :uuid, on_delete: :restrict), null: false
      add :actor_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :reason, :string, null: false
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:moderation_case_events, [:case_id, :inserted_at])

    create table(:account_restrictions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :case_id, references(:moderation_cases, type: :uuid, on_delete: :nilify_all)
      add :imposed_by_id, references(:users, type: :uuid, on_delete: :nilify_all), null: false
      add :kind, :string, null: false
      add :scope, :string, null: false, default: "account"
      add :reason, :string, null: false
      add :notice, :string, null: false
      add :status, :string, null: false, default: "active"
      add :effective_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec
      add :review_at, :utc_datetime_usec
      add :lifted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:account_restrictions, [:user_id, :status, :effective_at])
    create index(:account_restrictions, [:status, :review_at])

    create constraint(:account_restrictions, :account_restrictions_kind_check,
             check:
               "kind IN ('join_freeze', 'chat_freeze', 'activity_review', 'account_suspension')"
           )

    create constraint(:account_restrictions, :account_restrictions_scope_check,
             check: "scope IN ('account', 'activity', 'conversation')"
           )

    create constraint(:account_restrictions, :account_restrictions_status_check,
             check: "status IN ('active', 'lifted', 'under_review')"
           )

    create constraint(:account_restrictions, :account_restrictions_time_check,
             check: "expires_at IS NULL OR expires_at > effective_at"
           )

    create table(:appeals, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :restriction_id, references(:account_restrictions, type: :uuid, on_delete: :restrict),
        null: false

      add :appellant_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :statement, :string, null: false
      add :status, :string, null: false, default: "submitted"
      add :reviewed_by_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :decision_reason, :string
      add :reviewed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:appeals, [:restriction_id, :appellant_id],
             name: :appeals_one_open_per_restriction
           )

    create index(:appeals, [:status, :inserted_at])

    create constraint(:appeals, :appeals_status_check,
             check: "status IN ('submitted', 'in_review', 'upheld', 'overturned')"
           )

    create table(:audit_log, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :actor_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :subject_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :case_id, references(:moderation_cases, type: :uuid, on_delete: :nilify_all)
      add :action, :string, null: false
      add :scope, :string, null: false
      add :reason, :string, null: false
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_log, [:case_id, :inserted_at])
    create index(:audit_log, [:subject_id, :inserted_at])
    create index(:audit_log, [:actor_id, :inserted_at])

    execute(
      "CREATE FUNCTION trip_pals_prevent_safety_history_mutation() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'safety history is immutable'; END; $$ LANGUAGE plpgsql;",
      "DROP FUNCTION trip_pals_prevent_safety_history_mutation()"
    )

    execute(
      "CREATE TRIGGER audit_log_immutable BEFORE UPDATE OR DELETE ON audit_log FOR EACH ROW EXECUTE FUNCTION trip_pals_prevent_safety_history_mutation();",
      "DROP TRIGGER audit_log_immutable ON audit_log"
    )

    execute(
      "CREATE TRIGGER moderation_case_events_immutable BEFORE UPDATE OR DELETE ON moderation_case_events FOR EACH ROW EXECUTE FUNCTION trip_pals_prevent_safety_history_mutation();",
      "DROP TRIGGER moderation_case_events_immutable ON moderation_case_events"
    )
  end
end
