# Controlled-launch gate

Invitation matching is fail-closed. Ordinary discovery, hosting, activity-link
sharing, and explicit Join remain available while matching is disabled.

`TRIPPALS_INVITATION_MATCHING_CITY_IDS` is a comma-separated list of reviewed
city UUIDs and is read only by staging/production release configuration. It
defaults to an empty list. A city may be added only after its privacy review,
abuse controls, moderator coverage, and concierge-pilot rollout criteria have
been recorded. Removing a city UUID immediately prevents both candidate reads
and direct invitation sends; it never enrolls a recipient or changes existing
activities.

Before enabling a city, the release operator must record the city ID, approver,
moderator on-call coverage, pilot evidence, effective time, and rollback owner
in the launch change record. Do not put user data, tokens, invitations, or
availability details in that record.

## Verification gate

Run the full server launch suite against PostgreSQL before each controlled
launch and after every gate change:

```sh
make test-api
cd apps/api/service && mix precommit
```

The acceptance coverage is in `test/trip_pals/launch_gate_acceptance_test.exs`,
`test/trip_pals_web/launch_gate_api_test.exs`, and
`test/trip_pals_web/channels/launch_gate_channel_test.exs`. It supplements the
focused domain, PostgreSQL, authentication/WebAuthn, serialization, rate-limit,
and safety test suites.

| Launch assertion | Automated evidence |
| --- | --- |
| Transitions, permissions, blocks, consent, invitation and deletion decisions | `activity_lifecycle_test`, `invitations_test`, `trust_safety_test`, and `accounts_test` |
| Final seat, capacity, idempotency, rollback, indexes and plans | `participation_test`, `platform_test`, and `database_constraints_test` |
| Guest-safe API responses, city-local dates, profile/auth/version/error behavior | `discovery_controller_test`, `activity_lifecycle_controller_test`, `auth_controller_test`, `api_conventions_test`, and `launch_gate_api_test` |
| Channel authorization, persistence, retry, cursor recovery and revocation | `conversation_channel_test` and `launch_gate_channel_test` |
| Core discovery, invite, chat, lifecycle and safety journeys | `launch_gate_acceptance_test` and `launch_gate_api_test` |
| Token/passkey verification, candidate bypass attempts, rate limiting and sensitive-data scrubbing | `accounts_test`, `webauthn_test`, `identity_token_test`, `invitations_test`, `api_plugs_test`, and `sensitive_data_test` |

Complete the documented operational restore rehearsal in
[`runbooks/backup-restore.md`](runbooks/backup-restore.md) in an isolated
environment. Record only the backup identifier, timing, validation result, and
remediation ticket; restored user content must not be retained in the report.
