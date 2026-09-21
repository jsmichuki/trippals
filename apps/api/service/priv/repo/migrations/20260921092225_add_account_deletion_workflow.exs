defmodule TripPals.Repo.Migrations.AddAccountDeletionWorkflow do
  use Ecto.Migration

  # Reserved by the delivery plan and already applied in shared development
  # databases. Keep it immutable; the additive schema follows in the next
  # migration.
  def change do
    :ok
  end
end
