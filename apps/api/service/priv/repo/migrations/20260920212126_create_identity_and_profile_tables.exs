defmodule TripPals.Repo.Migrations.CreateIdentityAndProfileTables do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :status, :string, null: false, default: "active"
      add :restricted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:users, :users_status_check,
             check:
               "status IN ('active', 'restricted', 'suspended', 'pending_deletion', 'deleted')"
           )

    create table(:sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :family_id, :uuid, null: false
      add :device_id, :string
      add :recently_authenticated_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:sessions, [:user_id, :family_id])

    create table(:auth_identities, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_subject, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_identities, [:provider, :provider_subject])
    create index(:auth_identities, [:user_id])

    create table(:passkey_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :rp_id, :string, null: false
      add :transports, {:array, :string}, null: false, default: []
      add :backup_eligible, :boolean, null: false, default: false
      add :backup_state, :boolean, null: false, default: false
      add :aaguid, :binary
      add :label, :string, null: false
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:passkey_credentials, [:credential_id])
    create index(:passkey_credentials, [:user_id])

    create table(:webauthn_challenges, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :session_id, references(:sessions, type: :uuid, on_delete: :delete_all)
      add :challenge_hash, :binary, null: false
      add :ceremony, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webauthn_challenges, [:challenge_hash])
    create index(:webauthn_challenges, [:expires_at])

    create table(:refresh_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:sessions, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :replaced_by_id, :uuid
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:refresh_tokens, [:token_hash])
    create index(:refresh_tokens, [:session_id, :expires_at])

    create table(:profiles, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :display_name, :string
      add :profile_completed_at, :utc_datetime_usec
      add :adult_eligible_at, :utc_datetime_usec
      add :invitation_discoverable, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:profiles, [:user_id])

    create table(:community_rule_acceptances, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :rule_version, :string, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:community_rule_acceptances, [:user_id, :rule_version])
  end
end
