defmodule TripPals.TestSupport.InvalidPushGateway do
  @behaviour TripPals.Notifications.PushGateway

  @impl true
  def deliver(_token, _payload), do: {:error, :invalid_token}
end
