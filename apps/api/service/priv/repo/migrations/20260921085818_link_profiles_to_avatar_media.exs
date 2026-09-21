defmodule TripPals.Repo.Migrations.LinkProfilesToAvatarMedia do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :avatar_media_id, references(:media_objects, type: :uuid, on_delete: :nilify_all)
    end

    create unique_index(:profiles, [:avatar_media_id], where: "avatar_media_id IS NOT NULL")
  end
end
