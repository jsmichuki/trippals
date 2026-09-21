defmodule TripPals.Repo.Migrations.AddParticipationBlockGuard do
  use Ecto.Migration

  def change do
    # The full block-management API arrives with Deliverable 9. The pair table
    # is introduced now because Join must enforce a durable block decision.
    create table(:blocks, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :blocker_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :blocked_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:blocks, [:blocker_id, :blocked_id])
    create constraint(:blocks, :blocks_distinct_users_check, check: "blocker_id <> blocked_id")
  end
end
