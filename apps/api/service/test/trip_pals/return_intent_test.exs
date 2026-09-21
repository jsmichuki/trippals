defmodule TripPals.ReturnIntentTest do
  use ExUnit.Case, async: true

  alias TripPals.ReturnIntent

  test "preserves only an opaque activity-detail return intent" do
    activity_id = Ecto.UUID.generate()
    intent = "/v1/activities/#{activity_id}"

    assert ReturnIntent.validate(intent) == intent
    assert ReturnIntent.validate("/v1/activities/#{activity_id}/join") == nil
    assert ReturnIntent.validate("https://untrusted.example") == nil
  end
end
