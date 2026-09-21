defmodule TripPals.Cities.City do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "cities" do
    field :name, :string
    field :country, :string
    field :iana_timezone, :string
    field :launch_status, :string, default: "coming_soon"
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(city, attributes) do
    city
    |> cast(attributes, [:name, :country, :iana_timezone, :launch_status])
    |> validate_required([:name, :country, :iana_timezone, :launch_status])
    |> validate_inclusion(:launch_status, ~w(supported coming_soon unavailable))
    |> validate_format(:iana_timezone, ~r{^[A-Za-z_]+/[A-Za-z_]+(?:/[A-Za-z_]+)*$})
    |> unique_constraint([:name, :country])
  end
end
