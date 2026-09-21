defmodule TripPals.TestSupport.TransientPushGateway do
  @behaviour TripPals.Notifications.PushGateway

  @impl true
  def deliver(_token, _payload), do: {:error, :provider_unavailable}
end
