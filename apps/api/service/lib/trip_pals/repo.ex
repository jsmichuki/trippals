defmodule TripPals.Repo do
  use Ecto.Repo,
    otp_app: :trip_pals,
    adapter: Ecto.Adapters.Postgres
end
