defmodule TripPals.Notifications.PushGateway do
  @moduledoc false

  alias TripPals.Notifications.TokenVault

  @callback deliver(String.t(), map()) :: {:ok, String.t() | nil} | {:error, atom()}

  def deliver(device, notification) do
    gateway =
      Application.get_env(:trip_pals, :push_gateway, TripPals.Notifications.PushGateway.Noop)

    # Decryption occurs only at the outbound-adapter boundary. Neither the
    # worker arguments nor the notification payload contain a device token.
    gateway.deliver(TokenVault.decrypt!(device.token_ciphertext), minimal_payload(notification))
  end

  defp minimal_payload(notification) do
    %{
      notification_id: notification.id,
      event_type: notification.event_type,
      activity_id: notification.activity_id,
      invitation_id: notification.invitation_id,
      conversation_id: notification.conversation_id,
      deep_link: notification.deep_link
    }
  end
end
