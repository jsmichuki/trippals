defmodule TripPals.WebAuthnTest do
  use TripPals.DataCase, async: true

  alias TripPals.WebAuthn
  alias TripPals.Accounts
  alias TripPals.Accounts.PasskeyCredential
  alias TripPals.Repo

  test "persists a hashed, single-use authentication challenge" do
    assert {:ok, options} = WebAuthn.issue("authentication")

    client_data =
      Jason.encode!(%{
        "type" => "webauthn.get",
        "challenge" => options.challenge,
        "origin" => "https://app.example.test"
      })
      |> Base.url_encode64(padding: false)

    assert {:ok, _challenge, _raw_client_data} =
             WebAuthn.consume(options.challenge_id, "authentication", client_data)

    assert {:error, :invalid_webauthn_challenge} =
             WebAuthn.consume(options.challenge_id, "authentication", client_data)
  end

  test "rejects a client data challenge that does not match the persisted hash" do
    assert {:ok, options} = WebAuthn.issue("authentication")

    client_data =
      Jason.encode!(%{
        "challenge" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      })
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_webauthn_challenge} =
             WebAuthn.consume(options.challenge_id, "authentication", client_data)
  end

  test "rejects an expired challenge" do
    assert {:ok, options} = WebAuthn.issue("authentication", nil, nil, 1)
    Process.sleep(1_100)

    assert {:error, :invalid_webauthn_challenge} =
             WebAuthn.consume(
               options.challenge_id,
               "authentication",
               client_data(options, "webauthn.get")
             )
  end

  test "rejects an origin or ceremony mismatch before a challenge is consumed" do
    assert {:ok, options} = WebAuthn.issue("authentication")

    client_data =
      Jason.encode!(%{
        "type" => "webauthn.get",
        "challenge" => options.challenge,
        "origin" => "https://attacker.example.test"
      })
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_webauthn_challenge} =
             WebAuthn.consume(options.challenge_id, "authentication", client_data)

    wrong_ceremony =
      Jason.encode!(%{
        "type" => "webauthn.create",
        "challenge" => options.challenge,
        "origin" => "https://app.example.test"
      })
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_webauthn_challenge} =
             WebAuthn.consume(options.challenge_id, "authentication", wrong_ceremony)
  end

  test "binds a registration challenge to the account that requested it" do
    assert {:ok, owner} = Accounts.create_user()
    assert {:ok, another_user} = Accounts.create_user()
    assert {:ok, options} = WebAuthn.issue("registration", owner.id)

    client_data =
      Jason.encode!(%{
        "type" => "webauthn.create",
        "challenge" => options.challenge,
        "origin" => "https://app.example.test"
      })
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_webauthn_challenge} =
             WebAuthn.consume(options.challenge_id, "registration", client_data, another_user.id)

    assert {:ok, _challenge, _raw_client_data} =
             WebAuthn.consume(options.challenge_id, "registration", client_data, owner.id)
  end

  test "rejects RP mismatch, missing user verification, and invalid signatures" do
    credential_id = <<11, 12, 13>>
    credentials = [{credential_id, cose_key()}]

    assert {:ok, rp_options} = WebAuthn.issue("authentication")
    rp_client_data = client_data(rp_options, "webauthn.get")

    assert {:ok, rp_challenge, rp_raw_client_data} =
             WebAuthn.consume(rp_options.challenge_id, "authentication", rp_client_data)

    assert {:error, %Wax.InvalidClientDataError{reason: :rp_id_mismatch}} =
             Wax.authenticate(
               credential_id,
               authenticator_data("wrong.example.test", 0x05),
               <<0>>,
               rp_raw_client_data,
               rp_challenge,
               credentials
             )

    assert {:ok, uv_options} = WebAuthn.issue("authentication")
    uv_client_data = client_data(uv_options, "webauthn.get")

    assert {:ok, uv_challenge, uv_raw_client_data} =
             WebAuthn.consume(uv_options.challenge_id, "authentication", uv_client_data)

    assert {:error, %Wax.InvalidClientDataError{reason: :user_not_verified}} =
             Wax.authenticate(
               credential_id,
               authenticator_data("example.test", 0x01),
               <<0>>,
               uv_raw_client_data,
               uv_challenge,
               credentials
             )

    assert {:ok, signature_options} = WebAuthn.issue("authentication")
    signature_client_data = client_data(signature_options, "webauthn.get")

    assert {:ok, signature_challenge, signature_raw_client_data} =
             WebAuthn.consume(
               signature_options.challenge_id,
               "authentication",
               signature_client_data
             )

    assert {:error, %Wax.InvalidSignatureError{}} =
             Wax.authenticate(
               credential_id,
               authenticator_data("example.test", 0x05),
               :crypto.strong_rand_bytes(64),
               signature_raw_client_data,
               signature_challenge,
               credentials
             )
  end

  test "rejects a revoked credential before it can authenticate" do
    assert {:ok, user} = Accounts.create_user()
    raw_credential_id = <<21, 22, 23>>

    assert {:ok, _credential} =
             %PasskeyCredential{user_id: user.id}
             |> PasskeyCredential.changeset(%{
               credential_id: raw_credential_id,
               public_key: :erlang.term_to_binary(cose_key()),
               rp_id: "example.test",
               label: "Revoked phone",
               revoked_at: DateTime.utc_now()
             })
             |> Repo.insert()

    assert {:ok, options} = WebAuthn.issue("authentication")

    assert {:error, :invalid_webauthn_assertion} =
             WebAuthn.verify_authentication(
               options.challenge_id,
               Base.url_encode64(raw_credential_id, padding: false),
               Base.url_encode64(authenticator_data("example.test", 0x05), padding: false),
               Base.url_encode64(<<0>>, padding: false),
               client_data(options, "webauthn.get")
             )
  end

  test "accepts a valid assertion once and rejects a non-increasing signature counter" do
    assert {:ok, user} = Accounts.create_user()
    user_id = user.id
    credential_id = <<31, 32, 33>>
    signing_key = JOSE.JWK.generate_key({:rsa, 512})

    assert {:ok, _credential} =
             %PasskeyCredential{user_id: user.id}
             |> PasskeyCredential.changeset(%{
               credential_id: credential_id,
               public_key: :erlang.term_to_binary(public_cose_key(signing_key)),
               rp_id: "example.test",
               label: "Counter phone"
             })
             |> Repo.insert()

    assert {:ok, first_options} = WebAuthn.issue("authentication")
    first_client_data = client_data(first_options, "webauthn.get")
    first_authenticator_data = authenticator_data("example.test", 0x05, 1)

    assert {:ok, ^user_id} =
             WebAuthn.verify_authentication(
               first_options.challenge_id,
               Base.url_encode64(credential_id, padding: false),
               Base.url_encode64(first_authenticator_data, padding: false),
               Base.url_encode64(
                 signature(signing_key, first_authenticator_data, first_client_data),
                 padding: false
               ),
               first_client_data
             )

    assert {:ok, second_options} = WebAuthn.issue("authentication")
    second_client_data = client_data(second_options, "webauthn.get")
    repeated_authenticator_data = authenticator_data("example.test", 0x05, 1)

    assert {:error, :invalid_webauthn_assertion} =
             WebAuthn.verify_authentication(
               second_options.challenge_id,
               Base.url_encode64(credential_id, padding: false),
               Base.url_encode64(repeated_authenticator_data, padding: false),
               Base.url_encode64(
                 signature(signing_key, repeated_authenticator_data, second_client_data),
                 padding: false
               ),
               second_client_data
             )
  end

  defp client_data(options, type) do
    Jason.encode!(%{
      "type" => type,
      "challenge" => options.challenge,
      "origin" => "https://app.example.test"
    })
    |> Base.url_encode64(padding: false)
  end

  defp authenticator_data(rp_id, flags, sign_count \\ 0) do
    :crypto.hash(:sha256, rp_id) <> <<flags>> <> <<sign_count::unsigned-big-integer-size(32)>>
  end

  defp cose_key do
    %{1 => 3, 3 => -257, -1 => :crypto.strong_rand_bytes(64), -2 => <<1, 0, 1>>}
  end

  defp public_cose_key(signing_key) do
    {_metadata, public_key} = signing_key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    %{
      1 => 3,
      3 => -257,
      -1 => Base.url_decode64!(public_key["n"], padding: false),
      -2 => Base.url_decode64!(public_key["e"], padding: false)
    }
  end

  defp signature(signing_key, authenticator_data, encoded_client_data) do
    {:ok, raw_client_data} = Base.url_decode64(encoded_client_data, padding: false)
    {_metadata, private_key} = JOSE.JWK.to_key(signing_key)

    :public_key.sign(
      authenticator_data <> :crypto.hash(:sha256, raw_client_data),
      :sha256,
      private_key
    )
  end
end
