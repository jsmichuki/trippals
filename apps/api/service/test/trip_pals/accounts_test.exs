defmodule TripPals.AccountsTest do
  use TripPals.DataCase, async: true

  alias TripPals.Accounts
  alias TripPals.Accounts.PasskeyCredential
  alias TripPals.Accounts.Profile
  alias TripPals.Accounts.Session
  alias TripPals.Repo

  test "creates an account with discoverability disabled and never links by email" do
    assert {:ok, user} = Accounts.create_user()
    profile = Repo.get_by!(Profile, user_id: user.id)

    refute profile.invitation_discoverable
    assert {:ok, _identity} = Accounts.link_identity(user.id, "google", "google-subject-1")

    assert {:error, changeset} = Accounts.link_identity(user.id, "google", "google-subject-1")
    assert %{provider: ["has already been taken"]} = errors_on(changeset)
  end

  test "uses only the verified provider subject and never auto-links matching email-like data" do
    assert {:ok, google_user} =
             Accounts.resolve_verified_identity("google", "person@example.test")

    assert {:ok, apple_user} =
             Accounts.resolve_verified_identity("apple", "person@example.test")

    assert google_user.id != apple_user.id

    assert {:ok, same_google_user} =
             Accounts.resolve_verified_identity("google", "person@example.test")

    assert same_google_user.id == google_user.id
  end

  test "enforces globally unique binary passkey credential IDs" do
    assert {:ok, first_user} = Accounts.create_user()
    assert {:ok, second_user} = Accounts.create_user()

    attributes = %{
      credential_id: <<1, 2, 3>>,
      public_key: <<4, 5>>,
      rp_id: "example.test",
      label: "Phone"
    }

    assert {:ok, _credential} =
             %PasskeyCredential{user_id: first_user.id}
             |> PasskeyCredential.changeset(attributes)
             |> Repo.insert()

    assert {:error, changeset} =
             %PasskeyCredential{user_id: second_user.id}
             |> PasskeyCredential.changeset(attributes)
             |> Repo.insert()

    assert %{credential_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "recent-authentication checks reject revoked and stale sessions" do
    assert {:ok, user} = Accounts.create_user()
    assert {:ok, session} = Accounts.create_session(user.id, "device-1")

    assert Accounts.recently_authenticated?(session)

    refute Accounts.recently_authenticated?(
             session,
             DateTime.add(session.recently_authenticated_at, 901, :second)
           )

    refute Accounts.recently_authenticated?(%{session | revoked_at: DateTime.utc_now()})
  end

  test "rotates refresh tokens and revokes the session family on reuse" do
    assert {:ok, user} = Accounts.create_user()
    assert {:ok, session} = Accounts.create_session(user.id, "device-1")
    assert {:ok, raw_token, _token} = Accounts.issue_refresh_token(session)

    assert {:ok, {replacement_raw_token, _replacement}} = Accounts.rotate_refresh_token(raw_token)
    assert is_binary(replacement_raw_token)
    assert {:error, :refresh_token_reuse} = Accounts.rotate_refresh_token(raw_token)

    assert %Session{revoked_at: revoked_at} = Repo.get!(Session, session.id)
    assert not is_nil(revoked_at)
  end

  test "recovery rules preserve a usable login method and require recent authentication" do
    assert {:ok, user} = Accounts.create_user()
    assert {:ok, _identity} = Accounts.link_identity(user.id, "google", "subject")
    assert {:error, :final_login_method} = Accounts.unlink_identity(user.id, "google")

    assert {:ok, session} = Accounts.create_session(user.id, "device-1")

    assert {:ok, credential} =
             %PasskeyCredential{user_id: user.id}
             |> PasskeyCredential.changeset(%{
               credential_id: <<7, 8, 9>>,
               public_key: <<1, 2, 3>>,
               rp_id: "example.test",
               label: "Phone"
             })
             |> Repo.insert()

    stale_session =
      session
      |> Ecto.Changeset.change(
        recently_authenticated_at: DateTime.add(DateTime.utc_now(), -901, :second)
      )
      |> Repo.update!()

    assert {:error, :recent_auth_required} =
             Accounts.revoke_passkey(user.id, credential.id, stale_session.id)

    fresh_session =
      stale_session
      |> Ecto.Changeset.change(recently_authenticated_at: DateTime.utc_now())
      |> Repo.update!()

    assert {:ok, revoked_credential} =
             Accounts.revoke_passkey(user.id, credential.id, fresh_session.id)

    assert not is_nil(revoked_credential.revoked_at)
  end
end
