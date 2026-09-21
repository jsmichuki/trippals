defmodule TripPals.OpenAPIContractTest do
  use ExUnit.Case, async: true

  @contract_path Path.expand("../../../../../contracts/openapi/trippals-v1.json", __DIR__)

  test "the published contract is valid JSON and defines the API envelope" do
    contract = @contract_path |> File.read!() |> Jason.decode!()

    assert contract["openapi"] == "3.1.0"
    assert Map.has_key?(contract["paths"], "/v1/hello")
    assert Map.has_key?(contract["paths"], "/v1/cities")
    assert Map.has_key?(contract["paths"], "/v1/activities")
    assert Map.has_key?(contract["paths"], "/v1/activities/{id}")
    assert Map.has_key?(contract["paths"], "/v1/activity-ideas")
    assert get_in(contract, ["components", "schemas", "Success", "required"]) == ["data", "meta"]
    assert get_in(contract, ["components", "schemas", "Error", "required"]) == ["error", "meta"]
  end
end
