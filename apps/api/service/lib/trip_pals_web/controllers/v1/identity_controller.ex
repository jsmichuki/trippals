defmodule TripPalsWeb.V1.IdentityController do
  use TripPalsWeb, :controller

  alias TripPals.Accounts
  alias TripPalsWeb.API.Response

  def unlink(conn, %{"provider" => provider}) when provider in ["google", "apple"] do
    case Accounts.unlink_identity(conn.assigns.current_actor.id, provider) do
      {:ok, _identity} ->
        send_resp(conn, 204, "")

      {:error, :final_login_method} ->
        Response.error(
          conn,
          :final_login_method,
          "Add another login method before removing this one",
          422
        )

      {:error, :not_found} ->
        Response.error(conn, :not_found, "The requested resource was not found", 404)
    end
  end

  def unlink(conn, _params),
    do: Response.error(conn, :validation_failed, "Validation failed", 422)
end
