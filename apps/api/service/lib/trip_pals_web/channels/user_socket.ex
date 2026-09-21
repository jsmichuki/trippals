defmodule TripPalsWeb.UserSocket do
  use Phoenix.Socket

  alias TripPals.AccessToken

  channel "activity:*", TripPalsWeb.ActivityChannel
  channel "conversation:*", TripPalsWeb.ConversationChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case AccessToken.verify(token) do
      {:ok, actor} -> {:ok, assign(socket, :actor_id, actor.id)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.actor_id}"
end
