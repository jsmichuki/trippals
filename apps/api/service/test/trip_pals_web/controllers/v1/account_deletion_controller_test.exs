defmodule TripPalsWeb.V1.AccountDeletionControllerTest do
  use TripPalsWeb.ConnCase, async: false

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Accounts.Session
  alias TripPals.Repo

  test "requires authentication and accepts a recent-auth deletion request", %{conn: conn} do
    unauthorized = delete(conn, ~p"/v1/me")
    assert %{"error" => %{"code" => "authentication_required"}} = json_response(unauthorized, 401)

    {:ok, user} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(user.id)

    accepted =
      build_conn()
      |> put_req_header("authorization", "Bearer #{AccessToken.issue(session)}")
      |> put_req_header("idempotency-key", "delete-account-1")
      |> delete(~p"/v1/me")

    assert %{
             "data" => %{
               "status" => "access_revoked",
               "message" => message
             }
           } = json_response(accepted, 202)

    assert message =~ "access is revoked immediately"
    assert %Session{revoked_at: %DateTime{}} = Repo.get!(Session, session.id)
  end
end
