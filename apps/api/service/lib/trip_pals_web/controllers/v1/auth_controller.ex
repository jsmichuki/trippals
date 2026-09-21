defmodule TripPalsWeb.V1.AuthController do
  use TripPalsWeb, :controller

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPalsWeb.API.Response

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Accounts.refresh_session(refresh_token) do
      {:ok, session, replacement_refresh_token} ->
        Response.ok(conn, %{
          access_token: AccessToken.issue(session),
          refresh_token: replacement_refresh_token
        })

      {:error, _reason} ->
        Response.error(conn, :invalid_refresh_token, "Unable to refresh this session", 401)
    end
  end

  def refresh(conn, _params),
    do:
      Response.error(conn, :validation_failed, "Validation failed", 422, %{
        refresh_token: ["is required"]
      })

  def logout(conn, _params) do
    if actor = conn.assigns[:current_actor] do
      _ = Accounts.revoke_session(actor.session_id, actor.id)
    end

    send_resp(conn, 204, "")
  end

  def delete_session(conn, _params) do
    actor = conn.assigns.current_actor
    _ = Accounts.revoke_session(actor.session_id, actor.id)
    send_resp(conn, 204, "")
  end
end
