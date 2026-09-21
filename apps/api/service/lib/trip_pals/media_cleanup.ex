defmodule TripPals.MediaCleanup do
  @moduledoc "Durable cleanup entry points for expired and unreferenced private media."

  alias TripPals.Media

  def run(now \\ DateTime.utc_now()), do: Media.cleanup(now)
end
