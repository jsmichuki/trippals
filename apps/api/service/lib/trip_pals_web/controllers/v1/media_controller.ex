defmodule TripPalsWeb.V1.MediaController do
  use TripPalsWeb, :controller

  import Plug.Conn

  alias TripPals.Media
  alias TripPalsWeb.API.Response

  # These actions are wired by the D10 route additions. Scope is set by the
  # route/action rather than trusted from client input.
  def avatar_intent(conn, params) do
    create_intent(conn, Map.put(params, "scope", "avatar"))
  end

  def report_evidence_intent(conn, %{"report_id" => report_id} = params) do
    create_intent(
      conn,
      params |> Map.put("scope", "report_evidence") |> Map.put("report_id", report_id)
    )
  end

  def upload(conn, %{"id" => media_id, "content_base64" => encoded} = params) do
    with {:ok, content} <- Base.decode64(encoded),
         {:ok, result} <-
           Media.put_upload(
             conn.assigns.current_actor.id,
             media_id,
             upload_token(conn, params),
             content,
             command_options(conn, %{"media_id" => media_id, "content_sha256" => sha256(content)})
           ) do
      Response.ok(conn, result)
    else
      :error -> media_error(conn, :invalid_upload_content)
      {:error, error} -> media_error(conn, error)
    end
  end

  def confirm(conn, %{"id" => media_id} = params) do
    case Media.confirm_upload(
           conn.assigns.current_actor.id,
           media_id,
           upload_token(conn, params),
           command_options(conn, %{"media_id" => media_id, "command" => "confirm"})
         ) do
      {:ok, result} -> Response.ok(conn, result)
      {:error, error} -> media_error(conn, error)
    end
  end

  def access(conn, %{"id" => media_id}) do
    case Media.signed_access(conn.assigns.current_actor.id, media_id) do
      {:ok, result} -> Response.ok(conn, result)
      {:error, error} -> media_error(conn, error)
    end
  end

  def content(conn, %{"id" => media_id} = params) do
    case Media.read_private(conn.assigns.current_actor.id, media_id, access_token(conn, params)) do
      {:ok, content_type, content} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "private, no-store")
        |> send_resp(200, content)

      {:error, error} ->
        media_error(conn, error)
    end
  end

  defp create_intent(conn, params) do
    case Media.create_upload_intent(
           conn.assigns.current_actor.id,
           params,
           command_options(conn, params)
         ) do
      {:ok, result} -> Response.ok(conn, result, 201)
      {:error, error} -> media_error(conn, error)
    end
  end

  defp upload_token(conn, params),
    do: get_req_header(conn, "x-upload-token") |> List.first() || params["upload_token"]

  defp access_token(conn, params),
    do: get_req_header(conn, "x-media-access-token") |> List.first() || params["access_token"]

  defp command_options(conn, request) do
    encoded = Jason.encode!(request)

    [
      idempotency_key: conn.assigns[:idempotency_key],
      request_hash: :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)
    ]
  end

  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp media_error(conn, :not_found),
    do: Response.error(conn, :not_found, "The requested resource was not found", 404)

  defp media_error(conn, :forbidden),
    do: Response.error(conn, :forbidden, "You do not have permission for this action", 403)

  defp media_error(conn, :upload_intent_expired),
    do: Response.error(conn, :upload_intent_expired, "The upload intent has expired", 410)

  defp media_error(conn, :invalid_upload_capability),
    do: Response.error(conn, :invalid_upload_capability, "The upload capability is invalid", 403)

  defp media_error(conn, error)
       when error in [
              :invalid_upload_size,
              :unsupported_media_type,
              :content_signature_mismatch,
              :malware_detected,
              :invalid_upload_content,
              :upload_missing,
              :upload_not_available,
              :upload_already_confirmed,
              :media_not_available
            ],
       do: Response.error(conn, error, "The media upload could not be completed", 422)

  defp media_error(conn, :idempotency_key_reused),
    do: Response.error(conn, :idempotency_key_reused, "The idempotency key cannot be reused", 409)

  defp media_error(conn, _error),
    do:
      Response.error(conn, :media_request_failed, "The media request could not be completed", 422)
end
