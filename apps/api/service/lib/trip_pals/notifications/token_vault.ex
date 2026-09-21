defmodule TripPals.Notifications.TokenVault do
  @moduledoc false

  @aad "trip_pals:push_token:v1"

  def encrypt!(token) when is_binary(token) do
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, token, @aad, true)
    <<iv::binary, tag::binary, ciphertext::binary>>
  end

  def decrypt!(<<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> plaintext
      :error -> raise "push token ciphertext could not be decrypted"
    end
  end

  defp key do
    case Application.get_env(:trip_pals, :push_token_encryption_key) do
      key when is_binary(key) and byte_size(key) == 32 -> key
      _ -> raise "push token encryption key is not configured"
    end
  end
end
