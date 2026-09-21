defmodule TripPalsWeb.ActivityChannel do
  use TripPalsWeb, :channel

  alias TripPals.Conversations

  @impl true
  def join("activity:" <> activity_id, _params, socket) do
    case Conversations.authorize_activity(activity_id, socket.assigns.actor_id) do
      {:ok, _conversation} ->
        Phoenix.PubSub.subscribe(TripPals.PubSub, "activity:#{activity_id}")
        {:ok, %{activity_id: activity_id}, assign(socket, :activity_id, activity_id)}

      {:error, _reason} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  # Activity updates are server-produced projection events. Clients cannot use
  # a Channel command to mutate activity state.
  @impl true
  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "unsupported"}}, socket}

  @impl true
  def handle_info({:activity_event, event, projection}, socket) do
    case Conversations.authorize_activity(socket.assigns.activity_id, socket.assigns.actor_id) do
      {:ok, _conversation} ->
        push(socket, event, projection)
        {:noreply, socket}

      {:error, _reason} ->
        {:stop, :normal, socket}
    end
  end
end
