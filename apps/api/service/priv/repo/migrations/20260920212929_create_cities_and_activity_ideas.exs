defmodule TripPals.Repo.Migrations.CreateCitiesAndActivityIdeas do
  use Ecto.Migration

  def change do
    create table(:cities, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :country, :string, null: false
      add :iana_timezone, :string, null: false
      add :launch_status, :string, null: false, default: "coming_soon"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:cities, [:name, :country])

    create constraint(:cities, :cities_launch_status_check,
             check: "launch_status IN ('supported', 'coming_soon', 'unavailable')"
           )

    create table(:activity_ideas, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :title, :string, null: false
      add :category, :string, null: false
      add :description, :text, null: false
      add :enabled, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create index(:activity_ideas, [:enabled])

    create table(:browse_preferences, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :city_id, references(:cities, type: :uuid, on_delete: :nilify_all), null: false
      add :start_local_date, :date
      add :end_local_date, :date
      add :filters, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    create index(:browse_preferences, [:user_id, :updated_at])
  end
end
