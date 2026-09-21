defmodule TripPalsWeb.V1.MediaControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.AccessToken
  alias TripPals.Accounts

  test "the scoped upload APIs require member auth/idempotency and never expose a public object URL",
       %{conn: conn} do
    {:ok, user} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(user.id, "media-device")
    token = AccessToken.issue(session)
    content = <<0xFF, 0xD8, 0xFF, 1, 2, 3, 4, 5>>

    unauthenticated = post(conn, ~p"/v1/media/avatar/upload-intents", %{})

    assert %{"error" => %{"code" => "authentication_required"}} =
             json_response(unauthenticated, 401)

    missing_key =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/v1/media/avatar/upload-intents", %{
        "content_type" => "image/jpeg",
        "byte_size" => byte_size(content)
      })

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(missing_key, 400)

    intent =
      build_conn()
      |> authenticated(token, "avatar-intent")
      |> post(~p"/v1/media/avatar/upload-intents", %{
        "content_type" => "image/jpeg",
        "byte_size" => byte_size(content)
      })

    assert %{"data" => %{"media_id" => media_id, "upload_token" => upload_token}} =
             json_response(intent, 201)

    upload =
      build_conn()
      |> authenticated(token, "avatar-upload")
      |> put_req_header("x-upload-token", upload_token)
      |> post(~p"/v1/media/#{media_id}/upload", %{"content_base64" => Base.encode64(content)})

    assert %{"data" => %{"status" => "uploaded"}} = json_response(upload, 200)

    confirmed =
      build_conn()
      |> authenticated(token, "avatar-confirm")
      |> put_req_header("x-upload-token", upload_token)
      |> post(~p"/v1/media/#{media_id}/confirm", %{})

    assert %{"data" => confirmation} = json_response(confirmed, 200)
    refute Map.has_key?(confirmation, "url")
    refute Map.has_key?(confirmation, "object_key")

    access =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/v1/media/#{media_id}/access")

    assert %{"data" => %{"access_token" => access_token}} = json_response(access, 200)

    content_response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-media-access-token", access_token)
      |> get(~p"/v1/media/#{media_id}/content")

    assert content_response.status == 200
    assert content_response.resp_body == content
    assert ["private, no-store"] = get_resp_header(content_response, "cache-control")
  end

  defp authenticated(conn, token, key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("idempotency-key", key)
  end
end
