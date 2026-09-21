defmodule TripPalsWeb.V1.ProviderAuthController do
  use TripPalsWeb, :controller

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.IdentityToken
  alias TripPals.ReturnIntent
  alias TripPalsWeb.API.Response

  def complete(
        conn,
        %{"provider" => provider, "identity_token" => token, "nonce" => nonce} = params
      )
      when provider in ["google", "apple"] do
    with {:ok, subject} <- IdentityToken.verify(provider, token, nonce),
         {:ok, user} <-
           Accounts.resolve_verified_identity(
             provider,
             subject,
             conn.assigns[:current_actor] && conn.assigns.current_actor.id
           ),
         {:ok, session} <-
           Accounts.create_session(user.id, get_req_header(conn, "x-device-id") |> List.first()),
         {:ok, refresh_token, _} <- Accounts.issue_refresh_token(session) do
      Response.ok(conn, %{
        access_token: AccessToken.issue(session),
        refresh_token: refresh_token,
        profile_completion_required: not Accounts.profile_complete?(user),
        return_intent: ReturnIntent.validate(params["return_intent"])
      })
    else
      _ -> Response.error(conn, :invalid_identity_token, "Unable to verify this identity", 401)
    end
  end

  def complete(conn, _params),
    do: Response.error(conn, :validation_failed, "Validation failed", 422)
end
