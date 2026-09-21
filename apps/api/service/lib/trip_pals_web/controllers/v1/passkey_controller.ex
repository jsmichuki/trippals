defmodule TripPalsWeb.V1.PasskeyController do
  use TripPalsWeb, :controller

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.WebAuthn
  alias TripPals.ReturnIntent
  alias TripPalsWeb.API.Response

  def register_options(conn, _params) do
    actor = conn.assigns.current_actor

    case WebAuthn.issue("registration", actor.id, actor.session_id) do
      {:ok, options} ->
        Response.ok(conn, options)

      {:error, _reason} ->
        Response.error(conn, :webauthn_unavailable, "Passkey registration is unavailable", 503)
    end
  end

  def authenticate_options(conn, _params) do
    case WebAuthn.issue("authentication") do
      {:ok, options} ->
        Response.ok(conn, options)

      {:error, _reason} ->
        Response.error(conn, :webauthn_unavailable, "Passkey authentication is unavailable", 503)
    end
  end

  def register_complete(
        conn,
        %{
          "challenge_id" => challenge_id,
          "attestation_object" => attestation,
          "client_data_json" => client_data
        } = params
      ) do
    actor = conn.assigns.current_actor

    case WebAuthn.register(
           challenge_id,
           attestation,
           client_data,
           actor.id,
           params["label"] || "Passkey"
         ) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, _reason} ->
        Response.error(
          conn,
          :invalid_webauthn_registration,
          "Unable to register this passkey",
          422
        )
    end
  end

  def register_complete(conn, _params),
    do: Response.error(conn, :validation_failed, "Validation failed", 422)

  def authenticate_complete(conn, params) do
    case WebAuthn.verify_authentication(
           params["challenge_id"],
           params["credential_id"],
           params["authenticator_data"],
           params["signature"],
           params["client_data_json"]
         ) do
      {:ok, user_id} ->
        {:ok, session} =
          Accounts.create_session(user_id, get_req_header(conn, "x-device-id") |> List.first())

        {:ok, refresh_token, _} = Accounts.issue_refresh_token(session)

        Response.ok(conn, %{
          access_token: AccessToken.issue(session),
          refresh_token: refresh_token,
          return_intent: ReturnIntent.validate(params["return_intent"])
        })

      {:error, _reason} ->
        Response.error(
          conn,
          :invalid_webauthn_assertion,
          "Unable to authenticate with this passkey",
          401
        )
    end
  end
end
