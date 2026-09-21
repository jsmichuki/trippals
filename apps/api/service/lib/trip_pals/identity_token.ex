defmodule TripPals.IdentityToken do
  @moduledoc false

  @providers %{
    "google" => {"https://accounts.google.com", "https://www.googleapis.com/oauth2/v3/certs"},
    "apple" => {"https://appleid.apple.com", "https://appleid.apple.com/auth/keys"}
  }

  def verify(provider, token, nonce) when provider in ["google", "apple"] and is_binary(token) do
    {issuer, jwks_url} = Map.fetch!(@providers, provider)

    config =
      Application.fetch_env!(:trip_pals, :integrations)
      |> Keyword.fetch!(String.to_existing_atom("#{provider}_oauth"))

    with {:ok, %{status: 200, body: %{"keys" => keys}}} <- jwks_fetcher().(jwks_url),
         jwks <- Enum.map(keys, &JOSE.JWK.from_map/1),
         {:ok, jwt} <- verify_signature(jwks, token),
         %{"iss" => ^issuer, "sub" => subject, "exp" => expiry, "nonce" => ^nonce} = claims <-
           jwt.fields,
         true <- is_binary(subject) and byte_size(subject) > 0,
         true <- expiry > System.system_time(:second),
         true <- audience_valid?(claims["aud"], Keyword.fetch!(config, :audience)) do
      {:ok, subject}
    else
      _ -> {:error, :invalid_identity_token}
    end
  rescue
    _exception -> {:error, :invalid_identity_token}
  end

  defp audience_valid?(audience, expected) when is_binary(audience), do: audience == expected
  defp audience_valid?(audience, expected) when is_list(audience), do: expected in audience
  defp audience_valid?(_, _), do: false

  defp verify_signature(jwks, token) do
    Enum.find_value(jwks, {:error, :invalid_signature}, fn jwk ->
      case JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
        {true, jwt, _jws} -> {:ok, jwt}
        _ -> nil
      end
    end)
  end

  defp jwks_fetcher do
    Application.get_env(:trip_pals, :jwks_fetcher, &Req.get/1)
  end
end
