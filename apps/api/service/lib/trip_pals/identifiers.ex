defmodule TripPals.Identifiers do
  @moduledoc false

  def public_id!(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "public IDs must be UUID strings"
    end
  end
end
