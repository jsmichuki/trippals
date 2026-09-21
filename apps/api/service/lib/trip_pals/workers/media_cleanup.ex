defmodule TripPals.Workers.MediaCleanup do
  use Oban.Worker, queue: :lifecycle, max_attempts: 5, unique: [period: 3_600]

  @impl Oban.Worker
  def perform(_job), do: TripPals.Notifications.Lifecycle.cleanup_media()
end
