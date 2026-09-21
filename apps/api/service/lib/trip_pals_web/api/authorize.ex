defmodule TripPalsWeb.API.Authorize do
  @moduledoc false

  import Plug.Conn

  alias TripPalsWeb.API.Response

  def init(options), do: options

  def call(conn, :authenticated) do
    if conn.assigns[:current_actor] do
      conn
    else
      conn
      |> Response.error(:authentication_required, "Authentication is required", 401)
      |> halt()
    end
  end

  def call(conn, required_role) do
    actor = conn.assigns[:current_actor]

    if actor && required_role in Map.get(actor, :roles, []) do
      conn
    else
      conn
      |> Response.error(:forbidden, "You do not have permission for this action", 403)
      |> halt()
    end
  end
end
