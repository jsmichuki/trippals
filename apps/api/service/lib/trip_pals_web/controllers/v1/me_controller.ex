defmodule TripPalsWeb.V1.MeController do
  use TripPalsWeb, :controller

  alias TripPals.Accounts
  alias TripPalsWeb.API.Response

  def show(conn, _params) do
    profile = Accounts.get_me(conn.assigns.current_actor.id)
    Response.ok(conn, profile_data(profile))
  end

  def update(conn, params) do
    case Accounts.update_me(conn.assigns.current_actor.id, params) do
      {:ok, profile} -> Response.ok(conn, profile_data(profile))
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete_passkey(conn, %{"credential_id" => credential_id}) do
    actor = conn.assigns.current_actor

    case Accounts.revoke_passkey(actor.id, credential_id, actor.session_id) do
      {:ok, _credential} ->
        send_resp(conn, 204, "")

      {:error, :recent_auth_required} ->
        Response.error(conn, :recent_auth_required, "Recent authentication is required", 403)

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

  defp profile_data(profile) do
    %{
      id: profile.user_id,
      display_name: profile.display_name,
      profile_completed: not is_nil(profile.profile_completed_at),
      invitation_discoverable: profile.invitation_discoverable
    }
  end
end
