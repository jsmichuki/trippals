defmodule TripPals.Repo.Migrations.AddNotificationDeliveryRecords do
  use Ecto.Migration

  def up do
    Oban.Migrations.up()

    create table(:notification_preferences, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :essential_enabled, :boolean, null: false, default: true
      add :nonessential_enabled, :boolean, null: false, default: true
      add :push_enabled, :boolean, null: false, default: true
      add :muted_activity_ids, {:array, :uuid}, null: false, default: []
      timestamps(type: :timestamptz)
    end

    create unique_index(:notification_preferences, [:user_id])

    create table(:devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :platform, :text, null: false
      add :token_digest, :text, null: false
      add :token_ciphertext, :binary, null: false
      add :token_last_four, :text, null: false
      add :status, :text, null: false, default: "active"
      add :last_seen_at, :timestamptz
      add :invalidated_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:devices, [:platform, :token_digest])
    create index(:devices, [:user_id, :status, :updated_at])

    create table(:notifications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :event_type, :text, null: false
      add :essential, :boolean, null: false, default: false
      add :activity_id, references(:activities, type: :uuid, on_delete: :nilify_all)
      add :invitation_id, :uuid
      add :conversation_id, :uuid
      add :deep_link, :text, null: false
      add :dedupe_key, :text
      add :payload, :map, null: false, default: %{}
      add :read_at, :timestamptz
      add :dismissed_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create index(:notifications, [:user_id, :inserted_at, :id])
    create index(:notifications, [:activity_id, :user_id])
    create unique_index(:notifications, [:user_id, :dedupe_key])

    create table(:notification_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :notification_id, references(:notifications, type: :uuid, on_delete: :delete_all),
        null: false

      add :device_id, references(:devices, type: :uuid, on_delete: :nilify_all)
      add :channel, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :provider_message_id, :text
      add :attempt_count, :integer, null: false, default: 0
      add :last_error_code, :text
      add :delivered_at, :timestamptz
      add :available_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:notification_deliveries, [:notification_id, :device_id, :channel],
             name: :notification_deliveries_notification_device_channel_index
           )

    create index(:notification_deliveries, [:status, :available_at, :inserted_at])
    create constraint(:devices, :devices_platform_check, check: "platform IN ('ios', 'android')")

    create constraint(:devices, :devices_status_check,
             check: "status IN ('active', 'invalidated')"
           )

    create constraint(:notification_deliveries, :notification_deliveries_channel_check,
             check: "channel IN ('push', 'in_app')"
           )

    create constraint(:notification_deliveries, :notification_deliveries_status_check,
             check: "status IN ('pending', 'processing', 'delivered', 'failed', 'invalidated')"
           )

    create constraint(:notification_deliveries, :notification_deliveries_attempt_count_check,
             check: "attempt_count >= 0"
           )
  end

  def down do
    drop table(:notification_deliveries)
    drop table(:notifications)
    drop table(:devices)
    drop table(:notification_preferences)
    Oban.Migrations.down()
  end
end
