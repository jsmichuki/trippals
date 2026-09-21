defmodule TripPals.Workers.DeletionWorkflow do
  use Oban.Worker,
    queue: :lifecycle,
    max_attempts: 10,
    unique: [fields: [:args], keys: [:user_id], period: 86_400]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}),
    do: TripPals.Notifications.Lifecycle.run_deletion(user_id)

  def perform(_job), do: {:discard, :invalid_deletion_job}
end
