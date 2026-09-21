defmodule TripPals.ReturnIntent do
  @moduledoc false

  def validate(nil), do: nil

  def validate("/v1/activities/" <> activity_id) do
    case Ecto.UUID.cast(activity_id) do
      {:ok, _uuid} -> "/v1/activities/" <> activity_id
      :error -> nil
    end
  end

  def validate(_intent), do: nil
end
