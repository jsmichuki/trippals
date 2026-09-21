defmodule TripPalsWeb.SensitiveDataTest do
  use ExUnit.Case, async: true

  test "filters credentials and WebAuthn assertions from Phoenix log payloads" do
    filtered =
      Phoenix.Logger.filter_values(%{
        "access_token" => "access-secret",
        "refresh_token" => "refresh-secret",
        "identity_token" => "provider-secret",
        "authorization" => "Bearer access-secret",
        "assertion" => "assertion-secret",
        "attestation_object" => "attestation-secret",
        "authenticator_data" => "auth-data-secret",
        "signature" => "signature-secret",
        "client_data_json" => "client-data-secret",
        "biometric_outcome" => "biometric-secret",
        "nested" => %{"refresh_token" => "nested-secret"},
        "safe" => "request-value"
      })

    assert filtered["safe"] == "request-value"
    assert filtered["nested"]["refresh_token"] == "[FILTERED]"

    for key <- [
          "access_token",
          "refresh_token",
          "identity_token",
          "authorization",
          "assertion",
          "attestation_object",
          "authenticator_data",
          "signature",
          "client_data_json",
          "biometric_outcome"
        ] do
      assert filtered[key] == "[FILTERED]"
    end
  end
end
