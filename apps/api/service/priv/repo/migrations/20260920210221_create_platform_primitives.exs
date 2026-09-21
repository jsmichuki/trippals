defmodule TripPals.Repo.Migrations.CreatePlatformPrimitives do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto", ""

    create table(:idempotency_keys, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :actor_id, :uuid, null: false
      add :operation_scope, :string, null: false
      add :key, :string, null: false
      add :request_hash, :string, null: false
      add :response_status, :integer
      add :response_body, :map
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:idempotency_keys, [:actor_id, :operation_scope, :key],
             name: :idempotency_keys_actor_scope_key_index
           )

    create index(:idempotency_keys, [:expires_at])

    create table(:outbox_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :topic, :string, null: false
      add :event_type, :string, null: false
      add :aggregate_type, :string, null: false
      add :aggregate_id, :uuid, null: false
      add :payload, :map, null: false, default: fragment("'{}'::jsonb")
      add :status, :string, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :last_error_code, :string
      add :available_at, :utc_datetime_usec, null: false
      add :dispatched_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:outbox_events, :outbox_events_status_check,
             check: "status IN ('pending', 'processing', 'dispatched', 'discarded')"
           )

    create index(:outbox_events, [:status, :available_at, :inserted_at])
  end
end
