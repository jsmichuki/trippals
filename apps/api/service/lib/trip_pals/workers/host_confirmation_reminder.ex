defmodule TripPals.Workers.HostConfirmationReminder do
  use Oban.Worker, queue: :lifecycle, max_attempts: 5, unique: [period: 600]

  @impl Oban.Worker
  def perform(_job), do: TripPals.Notifications.Lifecycle.host_confirmation_reminders()
end
