defmodule TripPals.WebAuthn do
  @moduledoc false

  import Ecto.Query

  alias TripPals.Accounts.PasskeyCredential
  alias TripPals.Accounts.WebAuthnChallenge
  alias TripPals.Repo

  @timeout_seconds 120

  def issue(ceremony, user_id \\ nil, session_id \\ nil, timeout_seconds \\ @timeout_seconds)
      when ceremony in ["registration", "authentication"] and is_integer(timeout_seconds) and
             timeout_seconds > 0 do
    challenge = wax_challenge(ceremony)
    now = DateTime.utc_now()

    attributes = %{
      user_id: user_id,
      session_id: session_id,
      challenge_hash: :crypto.hash(:sha256, challenge.bytes),
      ceremony: ceremony,
      expires_at: DateTime.add(now, timeout_seconds, :second)
    }

    case Repo.insert(struct(WebAuthnChallenge, attributes)) do
      {:ok, record} ->
        {:ok,
         %{
           challenge_id: record.id,
           challenge: Base.url_encode64(challenge.bytes, padding: false),
           rp_id: challenge.rp_id,
           user_verification: "required",
           timeout_ms: timeout_seconds * 1_000
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def consume(challenge_id, ceremony, client_data_json, expected_user_id \\ nil) do
    with {:ok, client_data} <- Base.url_decode64(client_data_json, padding: false),
         %{"challenge" => encoded_challenge, "origin" => origin, "type" => type} <-
           Jason.decode!(client_data),
         true <- type == client_data_type(ceremony),
         true <- origin in configured_origins(),
         {:ok, bytes} <- Base.url_decode64(encoded_challenge, padding: false),
         1 <- consume_record(challenge_id, ceremony, bytes, expected_user_id) do
      {:ok, wax_challenge(ceremony, bytes), client_data}
    else
      _ -> {:error, :invalid_webauthn_challenge}
    end
  rescue
    Jason.DecodeError -> {:error, :invalid_webauthn_challenge}
  end

  def verify_authentication(
        challenge_id,
        credential_id,
        authenticator_data,
        signature,
        client_data_json
      ) do
    with {:ok, raw_credential_id} <- decode(credential_id),
         %PasskeyCredential{} = credential <-
           Repo.one(
             from(passkey in PasskeyCredential,
               where: passkey.credential_id == ^raw_credential_id and is_nil(passkey.revoked_at)
             )
           ),
         {:ok, challenge, raw_client_data} <-
           consume(challenge_id, "authentication", client_data_json),
         {:ok, raw_authenticator_data} <- decode(authenticator_data),
         {:ok, raw_signature} <- decode(signature),
         cose_key <- :erlang.binary_to_term(credential.public_key, [:safe]),
         {:ok, auth_data} <-
           Wax.authenticate(
             raw_credential_id,
             raw_authenticator_data,
             raw_signature,
             raw_client_data,
             challenge,
             [{raw_credential_id, cose_key}]
           ),
         :ok <- advance_counter(credential, auth_data.sign_count) do
      {:ok, credential.user_id}
    else
      _ -> {:error, :invalid_webauthn_assertion}
    end
  end

  def register(challenge_id, attestation_object, client_data_json, user_id, label) do
    with {:ok, challenge, raw_client_data} <-
           consume(challenge_id, "registration", client_data_json, user_id),
         {:ok, raw_attestation} <- decode(attestation_object),
         {:ok, {auth_data, _attestation}} <-
           Wax.register(raw_attestation, raw_client_data, challenge),
         credential_data <- auth_data.attested_credential_data,
         {:ok, _credential} <-
           %PasskeyCredential{user_id: user_id}
           |> PasskeyCredential.changeset(%{
             credential_id: credential_data.credential_id,
             public_key: :erlang.term_to_binary(credential_data.credential_public_key),
             sign_count: auth_data.sign_count,
             rp_id: challenge.rp_id,
             backup_eligible: auth_data.flag_backup_eligible,
             backup_state: auth_data.flag_credential_backed_up,
             aaguid: credential_data.aaguid,
             label: label
           })
           |> Repo.insert() do
      :ok
    else
      _ -> {:error, :invalid_webauthn_registration}
    end
  end

  defp consume_record(id, ceremony, bytes, expected_user_id) do
    now = DateTime.utc_now()

    query =
      from(challenge in WebAuthnChallenge,
        where: challenge.id == ^id and challenge.ceremony == ^ceremony,
        where: is_nil(challenge.consumed_at) and challenge.expires_at > ^now,
        where: challenge.challenge_hash == ^:crypto.hash(:sha256, bytes)
      )

    query =
      if is_nil(expected_user_id),
        do: query,
        else: from(challenge in query, where: challenge.user_id == ^expected_user_id)

    query
    |> Repo.update_all(set: [consumed_at: now, updated_at: now])
    |> elem(0)
  end

  defp advance_counter(credential, next_count)
       when credential.sign_count > 0 and next_count <= credential.sign_count,
       do: {:error, :counter_regression}

  defp advance_counter(credential, next_count) do
    credential
    |> Ecto.Changeset.change(sign_count: next_count, last_used_at: DateTime.utc_now())
    |> Repo.update()
    |> case do
      {:ok, _credential} -> :ok
      {:error, _changeset} -> {:error, :counter_update_failed}
    end
  end

  defp wax_challenge(ceremony, bytes \\ nil) do
    config = Application.fetch_env!(:trip_pals, :integrations) |> Keyword.fetch!(:webauthn)

    options = [
      origin: Keyword.fetch!(config, :origins),
      rp_id: Keyword.fetch!(config, :rp_id),
      user_verification: "required",
      timeout: @timeout_seconds
    ]

    options = if bytes, do: Keyword.put(options, :bytes, bytes), else: options

    if ceremony == "registration",
      do: Wax.new_registration_challenge(options),
      else: Wax.new_authentication_challenge(options)
  end

  defp decode(value), do: Base.url_decode64(value, padding: false)

  defp client_data_type("registration"), do: "webauthn.create"
  defp client_data_type("authentication"), do: "webauthn.get"

  defp configured_origins do
    Application.fetch_env!(:trip_pals, :integrations)
    |> Keyword.fetch!(:webauthn)
    |> Keyword.fetch!(:origins)
  end
end
