# TripPals repository guide

## Product and architecture

- Read `docs/TripPals_Architecture_Plan.md` and the current MVP user-flow document before changing product behavior. The architecture plan is the source of truth when documents conflict; record a deliberate product decision in `docs/adr/` before deviating from it.
- TripPals is a modular monolith: one Phoenix API/Channels release with PostgreSQL as the source of truth, plus a Kotlin Multiplatform mobile client. Do not introduce microservices, a general people directory, direct messages, client database access, or client-authoritative RSVP logic without an approved ADR.
- Keep server-side authorization and response shaping separate for guests, members, hosts, moderators, and administrators. Hiding a field in mobile UI is never access control.

## Layout and ownership

- `apps/api/service/` is the Phoenix application once bootstrapped. Put business rules in explicit `TripPals.*` contexts; controllers, Channels, and workers remain thin adapters.
- `apps/mobile/` contains the KMP workspace. Keep domain/data/network code in `shared`; platform-specific auth, passkey, storage, push, and app-lock adapters belong in `androidApp` or `iosApp`.
- `contracts/openapi/` holds versioned API contracts. Public API routes live under `/v1` and JSON uses `snake_case`.
- `infra/` holds declarative operational configuration only. `docs/adr/` records durable architectural decisions; never edit historical documents under `docs/old/`.

## Backend practices

- Use opaque UUID/UUIDv7 public IDs; never expose sequential database IDs.
- Put validation in Ecto changesets and domain transitions in contexts. Use `Ecto.Multi` and database constraints for multi-record work; do not implement capacity, quotas, idempotency, or authorization checks only in application memory.
- Every state-changing HTTP request needs an `Idempotency-Key`; activity edits additionally use an expected version/`If-Match`. Reused keys with a different payload must conflict.
- A Going RSVP, seat reservation, chat-access change, and outbox record are one transaction. Concurrent final-seat joins must yield exactly one success.
- Persist chat messages before broadcast; authorize every Channel join and revoke access when Going membership ends. Phoenix Presence is UI-only and is never attendance.
- Use PostgreSQL + Oban for durable jobs/outbox work in the MVP. Do not add a separate queue or search cluster without measured need.
- Store timestamps in UTC, include the event IANA timezone in responses, and derive discovery ranges from city-local calendar dates. Never add a fixed 24 hours across DST.

## Security and privacy

- Do not commit secrets, tokens, credentials, private keys, production data, or `.env`. Add only safe examples to `.env.example`.
- Auth credentials, refresh tokens, passkey assertions, biometric results, private meeting details, report evidence, and chat bodies must never enter logs, analytics, push payloads, or error reports.
- Invitation discoverability is opt-in. Candidate queries are activity-scoped and must not expose itineraries, exact availability, contact details, accommodation, GPS, or opted-out population counts.
- Passkeys are verified server-side through WebAuthn; Google/Apple identities are keyed by validated provider subject. Do not merge accounts by email alone.
- Moderation and staff actions require an explicit reason and an immutable audit record.

## Testing and changes

- Add or update focused tests with every behavior change. Exercise context rules, database constraints/transactions, API response privacy, Channel authorization, and relevant mobile repository behavior.
- For migrations: use additive, reversible-safe expand/contract changes; add indexes concurrently where appropriate; never edit an applied migration. Test migrations against PostgreSQL.
- Keep changes small and scoped. Format Elixir with `mix format` and Kotlin with the project formatter once the applications are bootstrapped. Do not hand-edit generated dependency locks unless changing dependencies.
- Before handoff, run the narrowest relevant test suite plus formatting and configuration validation. State clearly when a tool/runtime was unavailable.

## Containers and local development

- Local development uses the Homebrew `postgresql@14` service directly on `127.0.0.1:5432`; do not install or run Docker for this project at this stage. Mobile builds are native/CI concerns and do not get a Dockerfile.
- Copy `.env.example` to `.env` for local-only database URLs. Production/staging credentials come from the deployment secret manager, never from committed configuration.
- Bootstrap the Phoenix source with `make bootstrap-api`, create local databases with `make setup-api`, then run the API directly on this machine with `make up`. Use `make test-api` for the focused API suite.
