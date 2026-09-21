defmodule TripPals.Workers.ActivityLifecycleSweep do
  use Oban.Worker, queue: :lifecycle, max_attempts: 5, unique: [period: 600]

  @impl Oban.Worker
  def perform(_job), do: TripPals.Notifications.Lifecycle.sweep_activity_lifecycle()
end
