defmodule TripPals.Repo.Migrations.AddDiscoveryActivities do
  use Ecto.Migration

  def change do
    create table(:activities, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :city_id, references(:cities, type: :uuid, on_delete: :restrict), null: false
      add :idea_id, references(:activity_ideas, type: :uuid, on_delete: :nilify_all)
      add :host_id, references(:users, type: :uuid, on_delete: :restrict)
      add :title, :string, null: false
      add :category, :string, null: false
      add :description, :text, null: false
      add :start_at, :timestamptz, null: false
      add :end_at, :timestamptz, null: false
      add :iana_timezone, :string, null: false
      add :public_area, :string, null: false
      add :participant_meeting_details, :text
      add :cost_amount, :decimal
      add :currency, :string
      add :capacity_total, :integer, null: false
      add :going_count, :integer, null: false, default: 0
      add :status, :string, null: false, default: "draft"
      add :host_confirmed_at, :timestamptz
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:activities, :activities_time_order_check, check: "end_at > start_at")

    create constraint(:activities, :activities_capacity_check,
             check: "capacity_total BETWEEN 2 AND 10"
           )

    create constraint(:activities, :activities_going_count_check,
             check: "going_count BETWEEN 0 AND capacity_total"
           )

    create constraint(:activities, :activities_status_check,
             check:
               "status IN ('draft', 'published', 'host_confirmed', 'in_progress', 'completed', 'canceled', 'expired', 'outcome_unknown', 'restricted', 'pending_review')"
           )

    create index(:activities, [:city_id, :status, :start_at],
             where: "status IN ('published', 'host_confirmed')",
             name: :activities_public_discovery_index
           )

    execute(
      """
      ALTER TABLE activities
      ADD COLUMN search_document tsvector
      GENERATED ALWAYS AS (
        to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(category, '') || ' ' || coalesce(description, ''))
      ) STORED
      """,
      "ALTER TABLE activities DROP COLUMN search_document"
    )

    execute(
      "CREATE INDEX activities_search_document_index ON activities USING GIN (search_document)",
      "DROP INDEX activities_search_document_index"
    )
  end
end
