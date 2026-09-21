defmodule TripPals.IdentityTokenTest do
  use ExUnit.Case, async: false

  alias TripPals.IdentityToken

  setup do
    previous_integrations = Application.get_env(:trip_pals, :integrations)
    previous_fetcher = Application.get_env(:trip_pals, :jwks_fetcher)
    # A short-lived in-memory test key keeps the suite independent of provider
    # infrastructure; it is never used outside this process.
    jwk = JOSE.JWK.generate_key({:rsa, 512})
    {_meta, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    Application.put_env(:trip_pals, :integrations,
      google_oauth: [audience: "trip-pals-google"],
      apple_oauth: [audience: "trip-pals-apple"],
      webauthn: [rp_id: "example.test", origins: ["https://app.example.test"]]
    )

    Application.put_env(:trip_pals, :jwks_fetcher, fn _url ->
      {:ok, %{status: 200, body: %{"keys" => [public_jwk]}}}
    end)

    on_exit(fn ->
      Application.put_env(:trip_pals, :integrations, previous_integrations)

      if previous_fetcher,
        do: Application.put_env(:trip_pals, :jwks_fetcher, previous_fetcher),
        else: Application.delete_env(:trip_pals, :jwks_fetcher)
    end)

    %{jwk: jwk}
  end

  test "rejects invalid issuer, audience, expiry, nonce, and subject for Google and Apple", %{
    jwk: jwk
  } do
    for {provider, issuer, audience} <- [
          {"google", "https://accounts.google.com", "trip-pals-google"},
          {"apple", "https://appleid.apple.com", "trip-pals-apple"}
        ] do
      valid = %{
        "iss" => issuer,
        "aud" => audience,
        "exp" => System.system_time(:second) + 60,
        "nonce" => "nonce",
        "sub" => "subject"
      }

      assert {:ok, "subject"} = IdentityToken.verify(provider, sign(jwk, valid), "nonce")

      for {claim, value} <- [
            {"iss", "bad"},
            {"aud", "bad"},
            {"exp", 0},
            {"nonce", "bad"},
            {"sub", nil}
          ] do
        claims = Map.put(valid, claim, value)

        assert {:error, :invalid_identity_token} =
                 IdentityToken.verify(provider, sign(jwk, claims), "nonce")
      end
    end
  end

  test "rejects a JWT with an invalid signature or format", %{jwk: jwk} do
    claims = %{
      "iss" => "https://accounts.google.com",
      "aud" => "trip-pals-google",
      "exp" => System.system_time(:second) + 60,
      "nonce" => "nonce",
      "sub" => "subject"
    }

    signed = sign(jwk, claims)
    [header, payload, signature] = String.split(signed, ".")
    replacement = if String.starts_with?(signature, "A"), do: "B", else: "A"
    tampered_signature = replacement <> binary_part(signature, 1, byte_size(signature) - 1)
    tampered = Enum.join([header, payload, tampered_signature], ".")

    assert {:error, :invalid_identity_token} = IdentityToken.verify("google", tampered, "nonce")
    assert {:error, :invalid_identity_token} = IdentityToken.verify("apple", "not-a-jwt", "nonce")
  end

  defp sign(jwk, claims) do
    jwk
    |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end
end
