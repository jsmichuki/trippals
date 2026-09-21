defmodule TripPals.Repo.Migrations.HardenPlatformConstraints do
  use Ecto.Migration

  def change do
    create constraint(:idempotency_keys, :idempotency_keys_response_pair_check,
             check: "(response_status IS NULL) = (response_body IS NULL)"
           )

    create constraint(:idempotency_keys, :idempotency_keys_expiry_check,
             check: "expires_at > inserted_at"
           )

    create constraint(:outbox_events, :outbox_events_attempt_count_check,
             check: "attempt_count >= 0"
           )

    create constraint(:cities, :cities_iana_timezone_format_check,
             check: "iana_timezone ~ '^[A-Za-z_]+/[A-Za-z_]+(/[A-Za-z_]+)*$'"
           )

    create constraint(:webauthn_challenges, :webauthn_challenges_ceremony_check,
             check: "ceremony IN ('registration', 'authentication')"
           )

    create constraint(:webauthn_challenges, :webauthn_challenges_expiry_check,
             check: "expires_at > inserted_at"
           )

    create constraint(:refresh_tokens, :refresh_tokens_expiry_check,
             check: "expires_at > inserted_at"
           )
  end
end
