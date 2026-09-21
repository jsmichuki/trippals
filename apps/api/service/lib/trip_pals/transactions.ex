defmodule TripPals.Transactions do
  @moduledoc """
  Domain transactions compose state changes, outbox writes, and idempotency
  response storage through `Ecto.Multi` and commit them atomically.
  """

  alias Ecto.Multi
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo

  def transact(%Multi{} = multi), do: Repo.transaction(multi)

  def append_outbox_event(%Multi{} = multi, name, attributes) do
    Multi.insert(multi, name, OutboxEvent.changeset(%OutboxEvent{}, attributes))
  end
end
