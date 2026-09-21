defmodule TripPalsWeb.V1.CityController do
  use TripPalsWeb, :controller

  alias TripPals.Cities
  alias TripPalsWeb.API.Response

  def index(conn, _params) do
    cities =
      Cities.list_cities()
      |> Enum.map(fn city ->
        %{
          id: city.id,
          name: city.name,
          country: city.country,
          iana_timezone: city.iana_timezone,
          launch_status: city.launch_status
        }
      end)

    Response.ok(conn, %{cities: cities})
  end
end
