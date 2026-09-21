defmodule TripPals.Repo.Migrations.AddConversationMessages do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :grace_ends_at, :timestamptz
      add :next_message_sequence, :bigint, null: false, default: 0
    end

    drop constraint(:conversations, :conversations_status_check)

    create constraint(:conversations, :conversations_status_check,
             check:
               "status IN ('active', 'bounded_grace', 'read_only', 'archived', 'safety_freeze', 'frozen')"
           )

    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all),
        null: false

      add :sender_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :client_message_id, :uuid, null: false
      add :sequence, :bigint, null: false
      add :body, :text, null: false
      add :moderation_state, :string, null: false, default: "visible"
      add :moderated_at, :timestamptz
      # Report records are introduced by the safety migration. Keeping this a
      # UUID now makes chat migration ordering independent and allows a later
      # expand migration to add the foreign key without rewriting messages.
      add :report_reference_id, :uuid
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:messages, [:conversation_id, :sender_id, :client_message_id])
    create unique_index(:messages, [:conversation_id, :sequence])

    create index(:messages, [:conversation_id, :inserted_at, :id],
             name: :messages_history_cursor_index
           )

    create constraint(:messages, :messages_sequence_check, check: "sequence > 0")

    create constraint(:messages, :messages_moderation_state_check,
             check: "moderation_state IN ('visible', 'hidden', 'removed')"
           )

    create table(:event_system_messages, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all),
        null: false

      add :actor_id, references(:users, type: :uuid, on_delete: :restrict)
      add :message_id, references(:messages, type: :uuid, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :sequence, :bigint, null: false
      add :payload, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_system_messages, [:conversation_id, :sequence])

    create index(:event_system_messages, [:conversation_id, :inserted_at, :id],
             name: :event_system_messages_history_cursor_index
           )

    create constraint(:event_system_messages, :event_system_messages_sequence_check,
             check: "sequence > 0"
           )
  end
end
