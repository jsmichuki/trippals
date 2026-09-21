defmodule TripPals.Notifications.PushGateway.Noop do
  @moduledoc false

  @behaviour TripPals.Notifications.PushGateway

  @impl true
  def deliver(_token, _payload), do: {:ok, "local-noop"}
end
