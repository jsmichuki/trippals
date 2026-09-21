# TripPals MVP Backend / API Delivery Checklist

This is the implementation checklist for the Phoenix modular monolith described
in `docs/TripPals_Architecture_Plan.md` and
`docs/TripPals_MVP_Plan_and_User_Flows-v2.md`. It is deliberately feature-led:
complete a deliverable only when its API, domain rules, persistence,
authorization, and focused tests are complete.

## Scope and completion rules

- [ ] Keep one Phoenix API/Channels release and PostgreSQL as the authoritative
  store; do not introduce microservices, a separate broker/search cluster,
  client database access, a general people directory, or direct messages.
- [ ] Use a `TripPals.*` context per domain. Controllers, Channels, LiveView,
  and Oban workers must remain thin adapters over explicit context functions.
- [ ] Publish public HTTP routes under `/v1`; use JSON `snake_case`, opaque
  UUID/UUIDv7 public IDs, RFC 3339 UTC timestamps, and the event IANA timezone.
- [x] Define a consistent response envelope and error shape with a stable error
  code, safe human message, field errors where applicable, correlation ID, and
  current entity/version data where a conflict needs it.
- [ ] Require `Idempotency-Key` on every state-changing request. Persist actor,
  operation scope, request hash, status/body, and expiry; reject same-key,
  different-payload replays with `409`.
- [ ] Require `If-Match` or `expected_version` on mutable activity commands;
  return `409 version_conflict` with the current permitted activity projection.
- [ ] Use cursor pagination for activities, plans, invitations, messages,
  notifications, reports, and audits. Do not use offset pagination for changing
  collections or chat history.
- [ ] Shape responses independently for guests, members, hosts, moderators, and
  administrators. UI visibility is never authorization.
- [x] Maintain an OpenAPI contract under `contracts/openapi/` and add contract
  tests before considering an endpoint delivered.
- [ ] Apply targeted rate limits by account, IP, device, and target for auth,
  publishing, joining, invitations, chat, reports, and uploads.

## Deliverable 0 — Platform foundation and API conventions

**Outcome:** A secure, versioned JSON API can run, migrate, test, and expose
health/readiness without committing credentials.

- [x] Keep runtime credentials in environment/secret-manager configuration;
  never commit tokens, credentials, WebAuthn assertions, refresh tokens, or
  production data.
- [x] Configure `TripPals.Repo`, Phoenix endpoint, JSON rendering, request IDs,
  secure headers, request-size limits, CORS policy, and structured logging.
- [x] Add `/up` health and a readiness check that verifies required local
  dependencies without leaking configuration or credentials.
- [x] Add API router pipelines for public, authenticated member, host,
  moderator, administrator, and browser-admin requests.
- [x] Implement common authentication, current-actor, authorization, idempotency,
  optimistic-concurrency, rate-limit, and correlation-ID plugs/helpers.
- [x] Add a fallback/error controller that maps domain errors consistently and
  never exposes stack traces or protected resources.
- [x] Add API documentation generation/validation and a versioning/deprecation
  policy before expanding `/v1`.
- [x] Add release configuration, migration execution, configuration validation,
  and a production-safe health-check path.
- [x] Verify: direct host run, `mix test`, formatter, configuration validation,
  and a no-secret/no-sensitive-payload logging check.

## Deliverable 1 — Database, migrations, and shared domain primitives

**Outcome:** PostgreSQL provides a safe, evolvable source of truth for every
domain that follows.

- [x] Configure Ecto migrations for PostgreSQL and use additive,
  expand/contract-safe changes; never edit an applied migration.
- [x] Use UUID primary/public IDs for product records; do not expose sequential
  database IDs in URLs, JSON, logs, analytics, or push payloads.
- [x] Standardize UTC `timestamptz` timestamps, public ID serialization,
  lifecycle enums/checks, audit timestamps, and soft/deletion-state handling.
- [x] Create `idempotency_keys` with unique `(actor_id, operation_scope, key)`,
  request hash, stored response, expiry, and cleanup index.
- [x] Create `outbox_events` with immutable event ID, status, payload, retry
  metadata, `available_at`, and `(status, available_at, inserted_at)` index.
- [x] Add a transaction helper built on `Ecto.Multi` for domain transition,
  idempotency-result, audit, membership, and outbox work in one commit.
- [x] Add database constraints for every uniqueness, capacity, status, foreign
  key, and time invariant; application validation is not sufficient.
- [x] Add migration tests against PostgreSQL, including rollback safety where
  appropriate and query-plan/index checks for critical queries.
- [x] Document the local PostgreSQL 14 workflow separately from production's
  managed PostgreSQL posture (TLS, backups/PITR, least-privilege credentials).

## Deliverable 2 — Identity, sessions, and profile completion

**Outcome:** A user can authenticate with a verified supported method, receive
a revocable TripPals session, and complete the minimum profile without account
merges based on email.

### Persistence and contexts

- [x] Add `users`, `auth_identities`, `passkey_credentials`,
  `webauthn_challenges`, `sessions`, `refresh_tokens`, `profiles`, and
  `community_rule_acceptances` schemas/migrations.
- [x] Enforce unique `(provider, provider_subject)` and unique binary passkey
  credential ID. Never identify or merge accounts by email alone.
- [x] Store only passkey public-key material and metadata; never store biometric
  data, private keys, raw credential assertions, or provider access tokens.
- [x] Add account status/restriction and profile-completion state; default
  invitation discoverability to off.
- [x] Hash refresh tokens, bind them to a session/device, rotate on use, detect
  reuse, and revoke the affected session family.
- [x] Define recent-authentication/step-up checks for credential management,
  account deletion, login-method changes, and sensitive staff actions.

### API and authorization

- [x] Implement `POST /v1/auth/google/complete` with server-side authorization
  code/ID-token validation: issuer, audience, signature/JWKS, expiry, nonce,
  and stable provider `sub`.
- [x] Implement `POST /v1/auth/apple/complete` with server-side JWT/code,
  issuer, audience, signature/JWKS, expiry, nonce, and stable `sub` validation.
- [x] Implement passkey registration and authentication option/completion routes:
  `POST /v1/auth/passkeys/register/options`,
  `POST /v1/auth/passkeys/register/complete`,
  `POST /v1/auth/passkeys/authenticate/options`, and
  `POST /v1/auth/passkeys/authenticate/complete`.
- [x] Verify WebAuthn challenge single-use/expiry, RP ID/origin, authenticator
  data, user-presence/user-verification flags, signature, and counter semantics
  on the server.
- [x] Implement `POST /v1/auth/refresh`, `POST /v1/auth/logout`, and
  `DELETE /v1/auth/session` with session-specific revocation and safe generic
  responses for account-recovery cases.
- [x] Implement `GET/PATCH /v1/me`, profile-completion validation, and adult
  eligibility/rules acceptance; return only the caller's permitted profile data.
- [x] Implement authenticated provider/passkey linking and unlinking. Require
  successful authentication to both accounts for linking and prevent removal of
  the final usable method.
- [x] Implement `DELETE /v1/me/passkeys/:credential_id` with recent-auth checks
  and a user-visible credential label.
- [x] Preserve but revalidate a client-supplied return intent after login; it
  must never reserve a seat or replay a stale Join automatically.

### Verification

- [x] Test Google/Apple invalid issuer, audience, signature, expiry, nonce, and
  subject handling; test no email-based auto-linking.
- [x] Test WebAuthn challenge replay, origin/RP mismatch, invalid signatures,
  missing user verification, credential revocation, and recovery rules.
- [x] Test access-token expiry, refresh rotation/reuse detection, revocation,
  profile-completion gating, and recent-auth checks.
- [x] Scrub credentials, tokens, assertions, and biometric outcomes from logs,
  analytics, errors, and push payloads.

## Deliverable 3 — Cities, guest discovery, and activity ideas

**Outcome:** Guests can browse honest, city-scoped scheduled activities and
clearly separate non-joinable ideas without GPS or signup.

### Persistence and query behavior

- [x] Add `cities` with opaque ID, name, country, IANA timezone, launch status,
  and one-city-at-launch/multi-city-ready data model.
- [x] Add `activity_ideas` with template title/category/description and enabled
  state only; prohibit host, attendance, scheduled time, and chat fields.
- [x] Add `browse_preferences` only for selected city/filter state; never join
  it to invitation-candidate matching or treat it as consented availability.
- [x] Build local-date-to-UTC-bound calculation from the city's IANA timezone.
  Do not add fixed 24-hour intervals across DST transitions.
- [x] Index active public activities by city/status/start time and add the
  PostgreSQL search/index capability required for one-city discovery.

### API and response privacy

- [x] Implement `GET /v1/cities` with supported versus unavailable/coming-soon
  status; do not manufacture activity inventory for unsupported cities.
- [x] Implement `GET /v1/activities` with `city_id`, inclusive
  `start_local_date`/`end_local_date`, category/capacity filters, cursor, and
  guest-safe response projection.
- [x] Validate local date ranges (`start <= end`, defined horizon, appropriate
  past-date behavior) using event-city time rather than device time.
- [x] Implement `GET /v1/activities/:id` with guest/member/host-safe detail
  serializers. Guest output excludes roster, private directions, chat data,
  invitation data, and exact availability.
- [x] Implement `GET /v1/activity-ideas` as a distinct typed collection; do not
  return Join, host, Going-count, or scheduled-event fields on ideas.
- [x] Return truthful empty/terminal activity states rather than stale actionable
  CTAs. Keep joined activities accessible outside current discovery filters via
  later Plans/Chats endpoints.

### Verification

- [x] Test guest browsing with no account/GPS, unsupported city, no activity
  results, date reset, direct activity link, and only guest-safe fields.
- [x] Test local-date boundaries across DST, cross-midnight events, and device
  timezone changes.
- [x] Test that activity ideas cannot be joined, hosted, counted, or confused
  with scheduled activities.

## Deliverable 4 — Activity drafts, publication, revisions, and lifecycle

**Outcome:** Eligible members can create a complete real activity, and hosts can
move it through truthful, auditable lifecycle states.

### Persistence and invariants

- [x] Add `activities`, `activity_host_assignments`, `activity_revisions`, and
  `activity_change_acknowledgements` schemas/migrations.
- [x] Store UTC `start_at`/`end_at`, city IANA timezone, public area, separately
  protected participant meeting detail, cost/currency/description, lifecycle
  state, confirmation deadline, host confirmation/start/conclusion timestamps,
  cancellation reason, and integer version.
- [x] Enforce `end_at > start_at`, `capacity_total BETWEEN 2 AND 10`, valid city
  timezone, and a host seat that is counted exactly once.
- [x] Model only permitted transitions: Draft → Published → Host Confirmed → In
  Progress → Completed Host Reported; explicit cancellation/expiry/outcome
  unknown/review transitions; terminal states are idempotent and audited.
- [x] Define material-change classification for date/time, city/venue, important
  price, capacity, and activity character; retain a versioned diff.
- [x] Create one host-owned conversation and corresponding outbox/audit records
  in the same transaction as successful publication.

### API

- [x] Implement `POST /v1/activities` for a draft created from scratch or from
  an idea template. An idea may prefill editable fields only.
- [x] Validate public venue/area, required logistics, local time/DST validity,
  cost including unavoidable fees, capacity, policy restrictions, and eligible
  host state before publication.
- [x] Implement `PATCH /v1/activities/:id` with ownership/policy authorization,
  `If-Match`/version checks, material-change determination, revision/audit/outbox
  records, and the appropriate participant/invitation reconciliation.
- [x] Implement `POST /v1/activities/:id/publish`, `/confirm`, `/start`,
  `/finish`, and `/cancel`; require idempotency and state-guard checks.
- [x] Require a safe cancellation/conclusion reason and distinguish `Completed —
  host reported`, canceled/not held, and `Outcome unknown`; never infer a
  completed event from elapsed time.
- [x] Reject shrinking capacity below occupied seats; do not silently remove
  members as a side effect of an edit.
- [x] Hide draft/pending-review/restricted/terminal activities from public
  discovery and prevent them from accepting joins or new invitations.
- [x] Publish public/member/host serializers that make host confirmation,
  Going, interest, invitation, and attendance-related facts distinct.

### Verification

- [x] Test valid/invalid transition tables, host-only commands, idempotent
  publish/cancel/finish, stale edits, review/cancel handling, and audit records.
- [x] Test private meeting details and roster fields never appear in guest,
  shared-link, log, analytics, or notification response paths.
- [x] Test material edits propagate the same version/state to activity detail,
  Plans, invitations, pinned chat data, and notifications.

## Deliverable 5 — Participation, capacity-safe Join/Leave, and My Plans

**Outcome:** Members can express interest, join, leave, reconfirm, and report
attendance without overbooking or falsely treating an RSVP as attendance.

### Persistence and transaction rules

- [ ] Add `participations` and `participation_history` with unique
  `(activity_id, user_id)`, explicit status, reconfirmation, attendance report,
  and audit/history timestamps.
- [ ] Use one transaction with an activity-row lock (or equivalent advisory
  lock) for Join: idempotency lookup, lifecycle/block/restriction checks,
  existing participation, remaining capacity, Going upsert, conversation
  membership, history, outbox, and stored idempotency response.
- [ ] Enforce `one host seat + current Going non-host participants <= capacity`.
  Interested and pending invitations never consume a seat.
- [ ] On Leave, atomically change participation, remove future chat access,
  create history/outbox records, and free the seat. Define any permitted
  historical transcript access separately.
- [ ] Keep host-confirmed status, Going, reconfirmation, and attendance report
  as separate records/counters.

### API

- [ ] Implement `POST /v1/activities/:id/interest`, `/join`, `/leave`,
  `/reconfirm`, and `/attendance` with member authorization and idempotency.
- [ ] Return a current successful result for an already-Going member rather than
  allocating another seat; reject invalid terminal/full/cutoff states safely.
- [ ] Make reconfirmation opt-in (`yes` or a leave flow for cannot attend); do
  not infer nonattendance or silently remove a nonresponding member.
- [ ] Implement `GET /v1/me/plans` with cursor pagination and clearly typed
  Going, Interested, Hosting, Invitations, Past, and Canceled/terminal views.
- [ ] Preserve stable activity IDs across city/filter changes and return an
  explanatory state rather than routing an expired/canceled plan to discovery.

### Verification

- [ ] Run concurrent final-seat Join tests and prove exactly one request wins.
- [ ] Test host + Going never exceeds 10, repeat Join/Leave idempotency,
  transaction rollback, rejoin eligibility, and chat-membership coupling.
- [ ] Test block/restriction/start-cutoff/full/terminal decisions and no leakage
  of private data in unsuccessful Join responses.

## Deliverable 6 — Conversations, durable messages, and Phoenix Channels

**Outcome:** Every published activity has a durable, access-controlled group
conversation for its host and Going members only.

### Persistence and lifecycle

- [ ] Add `conversations`, `conversation_memberships`, `messages`,
  `event_system_messages`, and message moderation/report references.
- [ ] Enforce exactly one conversation per activity and unique
  `(conversation_id, sender_id, client_message_id)` for retry-safe messages.
- [ ] Add deterministic activity-local/server message sequence and index message
  history by `(conversation_id, created_at DESC, id DESC)` or equivalent cursor.
- [ ] Derive pinned logistics from canonical Activity fields; do not make a chat
  message the authoritative plan record.
- [ ] Implement conversation states: active, bounded grace, read-only, archived,
  and safety freeze. Revoke access when Going membership ends.

### HTTP and Channel API

- [ ] Implement `GET /v1/conversations/:id/messages` with member/host-only
  authorization, cursor resume, deterministic order, and safe system-message
  representation.
- [ ] Implement `POST /v1/conversations/:id/messages` as the HTTP fallback with
  body length/content validation, rate limiting, `client_message_id`, persistence
  before broadcast, and retry-safe response.
- [ ] Configure authenticated sockets and authorize every Channel join.
- [ ] Implement `activity:{activity_id}` for permitted, projection-safe activity
  revision/lifecycle updates and `conversation:{conversation_id}` for authorized
  chat/membership events.
- [ ] Re-check membership on history read, send, socket connect/join, reconnect,
  and revocation; guests, Interested, pending-invited, left, removed, and
  restricted nonmembers cannot read or write.
- [ ] Broadcast only after a message/system event has committed. Acknowledge
  sends only after persistence and return a cursor/sequence for recovery.
- [ ] Treat Phoenix Presence as an ephemeral UI hint only; it must never signal
  attendance or decide membership.

### Verification

- [ ] Test persisted-before-broadcast, duplicate client-message retry, ordering,
  cursor resume, offline/reconnect behavior, and membership revocation during
  composition.
- [ ] Test Channel and HTTP authorization for guest, Interested, invitee, Going,
  left, restricted, host, canceled, and read-only states.
- [ ] Test pinned logistics/event system updates, block masking policy, and no
  chat body/private directions in push payloads or guest views.

## Deliverable 7 — Notifications, outbox, devices, and lifecycle jobs

**Outcome:** Essential plan changes are durable in-app state first and external
delivery is retryable, minimal, and never part of the RSVP success decision.

### Persistence and API

- [ ] Add `notifications`, `notification_deliveries`, `notification_preferences`,
  `devices`, and outbox producer/consumer contexts.
- [ ] Implement `GET /v1/notifications` with cursor pagination and a safe
  read/update mechanism if required by the client contract.
- [ ] Implement `POST /v1/devices` and notification-preference updates with
  authenticated ownership, token lifecycle handling, and idempotency.
- [ ] Ensure notification/push payloads contain only IDs and minimal event
  context—never chat text, private directions, availability, tokens, or report
  evidence.
- [ ] Generate in-app notification plus outbox event transactionally for
  invitation, confirmation, material change, cancellation, revocation, and
  other essential state changes.

### Oban work

- [ ] Add PostgreSQL-backed Oban and unique/idempotent workers; do not add a
  separate queue for the MVP.
- [ ] Implement `OutboxDispatch` with retry, deduplication, delivery state, and
  failure observability.
- [ ] Implement `HostConfirmationReminder`, `AttendanceReminder`, and
  `ActivityLifecycleSweep` using event-city time and explicit policy cutoffs.
- [ ] Implement `InvitationLifecycleSweep` to expire, revoke, make unavailable,
  or mark invitations needs-review without granting a seat.
- [ ] Implement `ConversationRetentionSweep`, `PushDelivery`, `MediaCleanup`,
  and `DeletionWorkflow` with stable IDs, explicit retry policy, and idempotent
  handlers.
- [ ] Ensure worker failure never rolls back a committed Join or claims push
  delivery was successful.

### Verification

- [ ] Test outbox commit/rollback boundaries, worker retry/idempotency, device
  token invalidation, duplicate/out-of-order deep links, and essential versus
  muted nonessential notifications.
- [ ] Test unconfirmed host, cancellation, material changes, read-only chat,
  and revoked access route users to an explanatory status—not a generic home
  screen.

## Deliverable 8 — Invitation consent, candidates, quota, and inbox

**Outcome:** Hosts can invite only consented, eligible people for one published
activity; recipients retain full control and no invitation reserves a seat.

### Consent and persistence

- [ ] Add `availabilities`, invitation-settings fields, `invitations`,
  `invitation_quota_events`, and `host_invitation_rate_windows`.
- [ ] Make discoverability default-off and explicitly revocable. Store city,
  traveler/resident role, optional local dates/time preferences, shareable
  fields, visibility, expiry, and revocation state separately from browsing.
- [ ] Enforce one invitation per `(activity_id, recipient_id)`, invitation
  lifecycle states, decline suppression, per-activity distinct successful-send
  quota (proposed 15), and host rolling limits in PostgreSQL transactions.
- [ ] Do not replenish the per-activity quota after an invitation is withdrawn,
  deleted, or retried.

### API and privacy

- [ ] Implement `GET/PATCH /v1/me/invitation-settings` and
  `POST/PATCH/DELETE /v1/me/availabilities` with explicit consent, previewable
  shared fields, expiry, and immediate opt-out behavior.
- [ ] Implement `GET /v1/activities/:id/invitation-candidates` for the eligible
  host only. Require a published/open activity, remaining seats, city feature
  enabled, and host authority.
- [ ] Filter candidates server-side for active consent, city/date/time overlap,
  host/self/existing participation, prior invite/decline, blocks, restrictions,
  expiry, and rate/frequency rules.
- [ ] Return consent-limited candidate cards only. Never return exact trip dates,
  accommodation, contact details, GPS, raw itinerary, or opted-out/unmatched
  population counts.
- [ ] Implement `POST /v1/activities/:id/invitations` for bounded batches.
  Lock activity/quota, revalidate each candidate at send time, insert only valid
  invitations, increment successful distinct sends, write outbox events, and
  return per-recipient outcomes without exposing failure reasons.
- [ ] Implement `GET /v1/me/invitations`, `GET /v1/invitations/:id`, and
  `POST /v1/invitations/:id/decline` with recipient-only access and truthful
  pending/joined/declined/expired/revoked/unavailable/needs-review states.
- [ ] Make invitation Join call the standard activity Join transaction; lock the
  invitation within it and mark it joined only after participation succeeds.
- [ ] Reconcile pending invitations on full, start cutoff, cancellation,
  restriction, expiry, and material edit. Never give a pending invitee chat or
  roster access.

### Verification

- [ ] Test browsing filters never create availability, opt-out prevents the next
  candidate/send query, and no candidate data leak via pagination or errors.
- [ ] Test quota/rate concurrency, partial batch failures, duplicate retries,
  decline suppression, block pairs, event full, and material-reschedule review.
- [ ] Test invitation open/decline never reserves a seat or grants conversation
  access; invitation Join competes atomically for the final seat.

## Deliverable 9 — Reports, blocks, restrictions, appeals, and staff audit

**Outcome:** Safety actions are actionable, least-privilege, reasoned, and
immutable while protecting reporters.

### Persistence and policy

- [ ] Add `blocks`, `reports`, `moderation_cases`, `moderation_case_events`,
  `account_restrictions`, `appeals`, and immutable `audit_log` tables.
- [ ] Enforce unique `(blocker_id, blocked_id)` and `blocker_id <> blocked_id`.
- [ ] Define target types (activity, message, account), allowed reason codes,
  report evidence references, staff scopes, restriction effects, notice policy,
  appeal process, and urgent-safety escalation path.
- [ ] Require a staff reason and immutable audit entry for every moderation or
  administrative action; protect reporter identity from the subject.
- [ ] Apply blocks before Join, candidate selection/sending, conversation access,
  and profile resolution. Explain that an in-app block cannot guarantee physical
  separation at a shared event.

### API and administration

- [ ] Implement `POST /v1/reports` with safe contextual reference and no
  unnecessary sensitive data collection.
- [ ] Implement `POST /v1/blocks/:user_id` and `DELETE /v1/blocks/:user_id`
  with idempotent semantics and all downstream policy effects.
- [ ] Implement `GET /v1/me/restrictions` and `POST /v1/appeals` with the
  affected user's appropriate notice, scope, duration/review status, and appeal
  path.
- [ ] Build protected `/admin/*` LiveView or staff JSON adapters with separate
  staff roles, stronger authentication, scoped queries, case work queues,
  action reasons, and audit history.
- [ ] Make moderation actions reconcile affected activities, invitations,
  conversations, notifications, and access explicitly rather than silently
  deleting visible state.

### Verification

- [ ] Test reporter privacy, immutable audit events, explicit action reasons,
  scoped staff access, appeal visibility, block enforcement, and restricted-user
  behavior across API and Channel paths.
- [ ] Test message removal/restriction, safety chat freeze, event review/cancel,
  and participant notices without leaking report details.

## Deliverable 10 — Media and protected uploads

**Outcome:** Avatar and report-evidence uploads use short-lived, scoped access
without permanent public object URLs or unvalidated content.

- [ ] Add `media_objects` with object key, owner/scope, metadata, expiration,
  validation/scan status, and deletion lifecycle.
- [ ] Implement upload-intent and upload-confirm APIs for avatars and report
  evidence with authenticated, least-privilege scopes and idempotency.
- [ ] Validate size, MIME type, content signature, and malware-scan status before
  making an avatar available; apply stricter controls to report evidence.
- [ ] Store object keys rather than permanent public URLs; use private,
  short-lived signed access only after server authorization.
- [ ] Include failed/expired/unreferenced uploads in `MediaCleanup` and account
  deletion retention policy.
- [ ] Test cross-user access denial, content/type/size failures, expired upload
  intents, scan failures, deletion cleanup, and absence of evidence URLs in
  public responses/logs/analytics.

## Deliverable 11 — Account deletion, retention, and privacy operations

**Outcome:** Account deletion is a durable workflow that revokes access quickly
and retains only approved safety/legal material.

- [ ] Define the data inventory, legal basis/consent record, retention schedule,
  deletion exceptions, backup/restore process, and launch-country privacy review.
- [ ] Implement authenticated, recent-auth account deletion initiation with a
  clear status and no misleading promise of instant full erasure.
- [ ] In the deletion transaction/workflow revoke sessions/devices, disable
  discoverability and availability, revoke pending invitations, remove the user
  from future activities, release seats, and revoke future chat access.
- [ ] De-identify retained references where permitted while retaining the minimum
  safety, report, case, and audit material required by approved policy.
- [ ] Test session/device invalidation, future-seat release, candidate removal,
  pending-invitation revocation, chat access removal, and retention exceptions.

## Deliverable 12 — Observability, analytics, and operational hardening

**Outcome:** The API can be operated, debugged, and scaled without exposing
sensitive user content or relying on unverified client state.

- [ ] Emit structured logs and metrics for correlation ID, HTTP/Channel latency,
  database timing, job retries, RSVP conflicts, chat delivery outcomes,
  push-provider responses, and lifecycle counts.
- [ ] Configure error reporting with payload scrubbing. Exclude credentials,
  bearer/refresh tokens, passkey data, biometrics, chat bodies, private meeting
  details, exact location, availability, report evidence, and raw email.
- [ ] Emit server-owned funnel events through the outbox where possible:
  `join_succeeded`, `host_confirmed`, lifecycle transitions, invitation state,
  and aggregated candidate metrics.
- [ ] Prohibit analytics payloads containing chat bodies, precise meeting details,
  exact travel dates, contact details, GPS, report evidence, or auth material.
- [ ] Add rate-limit telemetry and abuse-monitoring for auth, publishing,
  joining, candidate pagination, invitations, messaging, reports, and uploads.
- [ ] Add database monitoring, backup/PITR, periodic restore verification, and
  health/readiness alerting for production.
- [ ] Add threat modeling, dependency scanning/patching, secure transport,
  secret rotation runbooks, and production access reviews.

## Deliverable 13 — End-to-end API acceptance and launch gate

**Outcome:** The server proves the MVP's core loop and safety boundaries before
the controlled one-city launch.

- [ ] Add domain unit tests for valid/invalid transitions, permissions, blocks,
  availability consent, invitation lifecycle, conversation lifecycle, and
  deletion-policy decisions.
- [ ] Add PostgreSQL integration tests for final-seat concurrency, capacity,
  idempotency collisions/replays, quota/rate transactions, rollback, indexes,
  and query plans.
- [ ] Add API contract tests for guest-safe serialization, date/DST filtering,
  profile completion, optimistic concurrency, authentication validation,
  invitation privacy, and status/error formats.
- [ ] Add Channel tests for join authorization, persistence-before-broadcast,
  duplicate retry, reconnect cursor, and immediate access revocation.
- [ ] Add end-to-end flows: guest discovery → authenticate → profile → Join;
  idea → draft → publish → invite → Join; confirm → chat → conclude; material
  edit/cancel → reconciliation; report/block → moderation/appeal.
- [ ] Run security/operations tests for token reuse/revocation, WebAuthn checks,
  candidate scraping/bypass attempts, rate limits, secret/log scrubbing, and
  backup restore.
- [ ] Verify no GPS requirement for browsing, no overbooking, no invitation
  auto-enrollment, no unauthorized chat/private-detail access, truthful
  lifecycle labels, durable chat, and auditable safety operations.
- [ ] Keep invitation matching behind a city feature flag until privacy, abuse,
  moderation staffing, and concierge-pilot rollout criteria are met.

## Decisions that must be resolved before the dependent deliverable ships

- [ ] Define host-confirmation deadline, late-join cutoff, invitation expiry,
  material-change acknowledgment/reconfirmation rule, chat grace/read-only
  period, message edit/deletion policy, and activity outcome rules.
- [ ] Confirm invitation consent wording, candidate-card fields, availability
  expiry, per-activity quota, host rate limits, and per-city feature-flag rules.
- [ ] Select managed PostgreSQL, object storage, push, error reporting,
  analytics, and hosting vendors after privacy/data-residency review.
- [ ] Register environment-specific Google/Apple credentials, WebAuthn RP IDs,
  Android Digital Asset Links, Apple Associated Domains, APNs, and FCM.
- [ ] Complete adult-pilot, launch-jurisdiction privacy/legal, incident-response,
  moderator operating procedure, and retention reviews before broad release.
