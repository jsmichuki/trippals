defmodule TripPals.Repo.Migrations.AddParticipationsAndConversationMemberships do
  use Ecto.Migration

  def change do
    create table(:participations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "interested"
      add :reconfirmed_at, :timestamptz
      add :attendance, :string
      add :left_at, :timestamptz
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:participations, [:activity_id, :user_id])
    create index(:participations, [:user_id, :status, :updated_at])

    create constraint(:participations, :participations_status_check,
             check: "status IN ('interested', 'going', 'left')"
           )

    create constraint(:participations, :participations_attendance_check,
             check:
               "attendance IS NULL OR attendance IN ('attended', 'not_attended', 'prefer_not_to_say')"
           )

    create table(:participation_history, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :participation_id, references(:participations, type: :uuid, on_delete: :delete_all),
        null: false

      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :from_status, :string
      add :to_status, :string, null: false
      add :reason, :string
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:participation_history, [:activity_id, :inserted_at])

    create table(:conversation_memberships, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :revoked_at, :timestamptz
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversation_memberships, [:conversation_id, :user_id])

    create constraint(:conversation_memberships, :conversation_memberships_status_check,
             check: "status IN ('active', 'revoked')"
           )
  end
end
