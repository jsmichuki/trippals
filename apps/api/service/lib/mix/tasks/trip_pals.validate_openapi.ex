defmodule Mix.Tasks.TripPals.ValidateOpenapi do
  @shortdoc "Validates the checked-in OpenAPI contract"
  use Mix.Task

  @contract Path.expand("../../../../../../contracts/openapi/trippals-v1.json", __DIR__)

  @impl Mix.Task
  def run(_args) do
    contract = @contract |> File.read!() |> Jason.decode!()

    unless contract["openapi"] == "3.1.0" and is_map(contract["paths"]) and
             is_map(contract["components"]) do
      Mix.raise("OpenAPI contract must be a valid 3.1.0 document with paths and components")
    end

    Mix.shell().info("TripPals OpenAPI contract is valid")
  end
end
