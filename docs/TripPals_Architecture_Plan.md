# TripPals MVP Architecture Plan

**Status:** Proposed architecture  
**Companion document:** `TripPals_MVP_Plan_and_User_Flows-v2.md`  
**Technology choices:** PostgreSQL, Elixir/Phoenix APIs, Kotlin Multiplatform mobile

## 1. Executive decision

Build TripPals as a modular Phoenix application backed by PostgreSQL, with a Kotlin Multiplatform (KMP) mobile application for Android and iOS. PostgreSQL is the authoritative store for accounts, activities, RSVP capacity, moderation, chat persistence, and lifecycle transitions. Phoenix owns all authorization and business rules; clients never directly query or write the database.

The initial deployment should be a modular monolith, not microservices. The MVP has tightly coupled workflows—joining an activity must atomically reserve a seat and grant chat access—and a single deployable application makes these workflows easier to secure, test, operate, and evolve. Clear domain boundaries, an outbox table, and background-job interfaces keep later extraction possible if scale warrants it.

```text
KMP iOS / Android apps                 Internal admin web
        │ HTTPS + WSS                         │ HTTPS
        └──────────────┬──────────────────────┘
                       ▼
             Phoenix API / Channels
     identity · discovery · activities · chat
       notifications · safety · admin/audit
                       │
      ┌────────────────┼────────────────────┐
      ▼                ▼                    ▼
 PostgreSQL      Object storage        Push providers
  source of       avatars/evidence      APNs / FCM
    truth              │
                       ▼
               background workers
       reminders · delivery · expiry · moderation
```

## 2. Architecture principles

- **Server-authoritative:** Activity, RSVP, permissions, seat counts, status transitions, and precise meeting details are decided by the API, never by device state or client clocks.
- **Transactional coordination:** A Going RSVP, capacity change, chat authorization, invitation acceptance, event revision, and related outbox records are written in PostgreSQL transactions.
- **Privacy by response shape:** Guest, member, host, moderator, and administrator API responses are separately shaped. Fields such as participant rosters and private meeting instructions must not merely be hidden by the app UI.
- **Offline-aware, not offline-authoritative:** The mobile app caches read data and queues safe idempotent commands. The server re-validates every queued operation on replay.
- **Consent is distinct from browsing:** A Discover date filter is a local search preference, never invitation availability. Invitation suggestions use a separate, explicit, revocable availability record and are filtered server-side for one activity.
- **Reliable side effects:** Event updates, invitations, push notifications, and analytics are emitted through a database outbox after the primary transaction commits.
- **Least privilege and auditable moderation:** Moderator actions have scoped roles, explicit reasons, and immutable audit records. Sensitive reporter data is not returned to the reported party.
- **One city at launch, multi-city in data model:** City, IANA timezone, launch status, and city-scoped discovery exist from day one; geographic expansion does not require a schema rewrite.

## 3. System boundaries

| Component | Responsibility | Does not own |
|---|---|---|
| KMP mobile apps | Navigation, local cache, forms, presentation, push/deep-link handling, reconnect/retry UX | Authorization, lifecycle decisions, seat counting, moderation enforcement |
| Phoenix API | Public/member/host/admin APIs, authentication session issuance, policy enforcement, validation, transactions | Native credential acquisition, APNs/FCM device delivery guarantees |
| Phoenix Channels | Durable activity-chat transport, presence hints, event update fan-out | Message permanence or membership decisions independent of PostgreSQL |
| PostgreSQL | Durable product state, idempotency, outbox, audit trail, full-text/search indexes | Push delivery and media blobs |
| Background jobs | Scheduled lifecycle checks, reminders, delivery retries, cleanup, optional search projections | Synchronous user-facing request handling |
| Object storage + CDN | Avatars and report evidence using private signed access | Public authorization decisions |
| Admin web | Internal moderation/support interface, ideally Phoenix LiveView initially | A separate public backend |

## 4. Elixir/Phoenix backend

### 4.1 Application shape

Use Phoenix with Ecto, Phoenix Channels, Oban, and a JSON API. Prefer Phoenix LiveView for the P0 internal console: it shares validation, authorization, audit behavior, and deployment with the API while avoiding a second front-end application. Expose versioned REST endpoints at `/v1`; use a WebSocket only for activity chat and live activity updates.

Suggested umbrella-like domain modules inside one Phoenix project:

```text
lib/trip_pals/
  accounts/          identity links, profiles, sessions, deletion
  cities/            supported cities and time-zone metadata
  activities/        ideas, drafts, publishing, revisions, lifecycle, capacity
  participation/    interest, going, leave, reconfirmation, attendance
  invitations/       consented availability, candidate eligibility, quotas, invite lifecycle
  conversations/    event chat, membership, messages, retention
  notifications/    preferences, devices, outbox consumers, deep links
  trust_safety/      blocks, reports, cases, restrictions, appeals
  media/             upload intent and file metadata
  analytics/         privacy-aware product events/outbox
  admin/             operator authorization and audit logging
  workers/           Oban jobs and scheduled reconciliations
```

Contexts may call each other through explicit public functions, rather than reaching into another context's repositories or schemas. This preserves a clean seam if chat, search, or notifications later need separate services.

### 4.2 API and transport conventions

- JSON field names use `snake_case`; timestamps use RFC 3339 UTC strings; activity responses also include the event IANA timezone for display. Discover date filters use inclusive event-city local calendar dates, which the API converts into the correct UTC range; clients never add fixed 24-hour intervals across DST boundaries.
- All create and state-changing requests require `Idempotency-Key`. Store the authenticated actor, endpoint scope, request hash, response status/body, and expiry in PostgreSQL. Reusing a key with a different body returns `409`.
- Use cursor pagination for discovery, plans, messages, notifications, reports, and audit views. Avoid offset pagination for chat and changing activity lists.
- Return machine-readable error codes, human-safe messages, field errors, current entity version where relevant, and a correlation ID. Examples: `capacity_full`, `activity_not_joinable`, `version_conflict`, `blocked_interaction`, `profile_incomplete`.
- Every mutable activity request carries `If-Match` or `expected_version`. The API returns `409 version_conflict` with the current public activity view if a stale edit would overwrite a change.
- Use opaque UUID/UUIDv7 public IDs. Never expose sequential database IDs.
- Apply endpoint-specific rate limits by account, IP, device, and target where appropriate. Tighter limits apply to sign-up attempts, chat sends, join attempts, reports, and uploads.

### 4.3 API resource outline

| Area | Core endpoints | Notes |
|---|---|---|
| Public discovery | `GET /v1/cities`, `GET /v1/activities?city_id&start_local_date&end_local_date`, `GET /v1/activities/:id`, `GET /v1/activity-ideas` | Scheduled activities and non-joinable idea templates are separately typed and rendered; activity results expose only guest-safe fields |
| Account/profile | `POST /v1/auth/*`, `POST /v1/auth/refresh`, `DELETE /v1/auth/session`, `GET/PATCH /v1/me`, `DELETE /v1/me` | Auth is described in section 8 |
| Activities | `POST /v1/activities`, `PATCH /v1/activities/:id`, `POST /publish`, `/confirm`, `/start`, `/finish`, `/cancel` | Idea selection only pre-fills a draft; a published activity has a 2–10 total capacity including its host |
| Participation | `POST /v1/activities/:id/interest`, `POST /join`, `POST /leave`, `POST /reconfirm`, `POST /attendance` | Join and leave are idempotent, capacity-aware commands |
| Plans/invitations | `GET /v1/me/plans`, `GET /v1/me/invitations`, `GET /v1/invitations/:id`, `POST /v1/invitations/:id/decline` | Invitation view or decline never reserves a seat or grants chat access; Join uses the normal activity Join command |
| Availability/invite settings | `GET/PATCH /v1/me/invitation-settings`, `POST/PATCH/DELETE /v1/me/availabilities`, `GET /v1/activities/:id/invitation-candidates`, `POST /v1/activities/:id/invitations` | Candidate endpoint is host-only for one eligible published activity; it returns consent-limited cards, never raw itineraries |
| Chat | `GET /v1/conversations/:id/messages`, `POST /messages` plus `activity:{id}` Channel | HTTP is fallback/history; Channel is low-latency transport |
| Notifications | `GET /v1/notifications`, `POST /devices`, `PATCH /notification_preferences` | Payloads contain IDs, never private chat text |
| Safety | `POST /reports`, `POST/DELETE /blocks/:user_id`, `GET /v1/me/restrictions`, `POST /appeals` | Report target types are activity, message, or account |
| Admin | `/admin/*` LiveView routes or protected JSON endpoints | Separate staff role and stronger step-up authentication |

### 4.4 Real-time design

Phoenix Channels provide topic subscriptions only after the server checks current authorization:

- `activity:{activity_id}` — activity status/revision updates for authorized viewers. Guests receive only guest-safe update payloads.
- `conversation:{conversation_id}` — chat messages, message moderation state, typing indicator if later added, and membership/access changes. Going participants and active hosts may subscribe; permissions are rechecked on join and revoked broadcasts close the channel.

Persist a message before broadcasting it. Each message has a client-generated UUID (`client_message_id`) and a unique `(conversation_id, sender_id, client_message_id)` constraint, which makes retries safe. Clients acknowledge a message only after server persistence and return a server cursor for resumption.

Use PostgreSQL-backed Phoenix PubSub for the first deployment if a single app node is sufficient. Add a dedicated distributed PubSub adapter only when multiple API nodes make it necessary. Presence is ephemeral UI information and must never be interpreted as attendance.

### 4.5 Background work

Use Oban with PostgreSQL rather than a separate queue for the MVP. Job uniqueness and retries are visible in the same operational datastore.

| Job class | Trigger | Required behavior |
|---|---|---|
| `OutboxDispatch` | Transaction commits a domain event | Delivers notifications/analytics with retry and deduplication |
| `HostConfirmationReminder` | Published activity approaches deadline | Sends disclosed reminder once per policy/version |
| `AttendanceReminder` | Before start / after end | Reconfirmation and voluntary check-in notifications |
| `ActivityLifecycleSweep` | Scheduled | Expires unconfirmed activities and marks stale outcomes as unknown according to policy |
| `InvitationLifecycleSweep` | Scheduled or activity/version change | Expires, revokes, or marks pending invitations unavailable/needs-review without granting a seat |
| `ConversationRetentionSweep` | Conclusion/cancellation or scheduled | Moves chat through disclosed grace/read-only/archive states; safety actions can freeze it sooner |
| `PushDelivery` | Notification event | APNs/FCM retry, token invalidation, delivery state recording |
| `MediaCleanup` | Upload expiration/deletion request | Removes unreferenced or expired media within policy windows |
| `DeletionWorkflow` | Account deletion request | Revokes sessions/chat access, releases future seats, de-identifies or retains safety records per policy |

Jobs must use stable domain IDs, explicit retry policies, and idempotent handlers. A job failure must not roll back a committed RSVP or falsely show notification delivery as complete.

## 5. PostgreSQL design

### 5.1 Database posture

Use a managed PostgreSQL service with high availability, point-in-time recovery, encrypted backups, TLS-only connections, and separate application and read-only/operations credentials. Run Ecto migrations in deployment pipelines; never permit ad hoc production DDL from the mobile app.

All primary product tables should include `inserted_at` and `updated_at` as UTC `timestamptz`. Store activity local timezone as IANA text (for example, `Africa/Nairobi`) alongside `start_at` and `end_at` UTC timestamps. The server, not the client, evaluates time-dependent eligibility.

### 5.2 Core schema

The product plan's entities map to the following normalized tables. UUID primary keys are assumed.

| Domain | Tables | Important design notes |
|---|---|---|
| Identity | `users`, `auth_identities`, `passkey_credentials`, `webauthn_challenges`, `refresh_tokens`, `sessions` | A user has many login methods; store passkey public keys only, and never store biometric data or third-party access tokens |
| Profile/cities | `profiles`, `cities`, `browse_preferences`, `availabilities`, `community_rule_acceptances` | Browse dates are separate from explicit invitation availability; city stores launch status and IANA timezone |
| Activities | `activity_ideas`, `activities`, `activity_revisions`, `activity_change_acknowledgements`, `activity_host_assignments` | Ideas are curated non-events; published activities keep public area separate from private participant meeting details and use `version` for concurrency |
| Participation | `participations`, `participation_history` | One current row per `(activity_id, user_id)`; history records changes without exposing it publicly |
| Invitations | `invitations`, `invitation_quota_events`, `host_invitation_rate_windows` | One invitation per activity/recipient; quota counts distinct successful recipients and never reserves a seat |
| Chat | `conversations`, `conversation_memberships`, `messages`, `event_system_messages`, `message_reports` | One activity has one event conversation; membership is derived/updated with Going status and retention rules |
| Notifications | `devices`, `notification_preferences`, `notifications`, `notification_deliveries`, `outbox_events` | Notification records are product history; delivery attempts are separate |
| Safety/admin | `blocks`, `reports`, `moderation_cases`, `moderation_case_events`, `account_restrictions`, `appeals`, `audit_log` | Reporter identity is protected in query layers and never supplied to subject-facing views |
| Platform | `idempotency_keys`, `media_objects`, `analytics_outbox`, `feature_flags` | An outbox is the boundary between transactional state and external effects |

`browse_preferences` may be anonymous/local or account-scoped and stores only selected city, date range, and filters. It is never joined into invitation candidate queries. `availabilities` is an explicit, default-off consent record with user, city, traveler/resident role, optional local start/end dates and time preferences, shareable profile-field settings, visibility flag, expiry, and revocation timestamp.

`activity_ideas` stores curated title/category/description templates only—no host, Going count, or scheduled time. Recommended published `activities` fields include `host_id`, `city_id`, optional `idea_id`, `title`, `category`, `description`, `start_at`, `end_at`, `iana_timezone`, `public_area`, encrypted/private `participant_meeting_details`, cost fields, `capacity_total`, `status`, `confirmation_deadline_at`, `host_confirmed_at`, `started_at`, `concluded_at`, `cancel_reason`, and `version`. `capacity_total` is an integer from 2 through 10 inclusive and includes the host seat.

An `invitations` row contains activity, host, recipient, status (`pending`, `joined`, `declined`, `expired`, `revoked`, `unavailable`, `needs_review`), sent/expiry/response timestamps, event version seen, and idempotency metadata. It does not contain a copied itinerary or create a participation row. `event_system_messages` persist structured lifecycle/revision events separately from member message text.

### 5.3 Constraints and indexes

- `activities`: `CHECK (end_at > start_at)`, `CHECK (capacity_total BETWEEN 2 AND 10)`, and indexed `(city_id, status, start_at)` for live discovery. Build city-local date bounds with the stored IANA timezone and query `start_at` against those bounds; a partial index covers public, active statuses only.
- `participations`: unique `(activity_id, user_id)`, status enum/check, and index `(user_id, status, updated_at DESC)` for My Plans.
- `auth_identities`: unique `(provider, provider_subject)`. Do not use an email claim as an external-provider identity key or automatically merge accounts from it.
- `passkey_credentials`: unique binary `credential_id`; indexed `user_id`; store the credential public key, signature counter, relying-party ID, transports, backup state, AAGUID where supplied, and last-used time. Do not store a private key, fingerprint, Face ID data, or device PIN.
- `webauthn_challenges`: a random, single-use, hashed challenge with account/session binding, ceremony type, expiry, and consumed timestamp. Expire unused challenges promptly and reject replay.
- `messages`: unique `(conversation_id, sender_id, client_message_id)`, index `(conversation_id, created_at DESC, id DESC)` for cursor history.
- `invitations`: unique `(activity_id, recipient_id)`; index recipient/status/expiry for Inbox; index activity/status for host dashboard. Enforce the 15-distinct-successful-recipient per-activity quota and host rolling rate limits in the send transaction, not in client state.
- `availabilities`: index only active/visible records by city and local date range; query candidates only inside the activity-specific authorization path. Do not expose counts of opted-out or unmatched people.
- `conversations`: unique `activity_id`; `event_system_messages` has a unique activity-local sequence so client reconciliation is deterministic.
- `blocks`: unique `(blocker_id, blocked_id)`, `CHECK (blocker_id <> blocked_id)`.
- `idempotency_keys`: unique `(actor_id, operation_scope, key)` with expiry index.
- `outbox_events`: index `(status, available_at, inserted_at)` for worker polling; payload includes an immutable event ID.
- Case/audit tables: indexes by subject, status, assigned operator, and time. Restrict direct query access to the admin role.

### 5.4 Concurrency-critical RSVP transaction

Use a single `Ecto.Multi` transaction or a PostgreSQL function. Serialize concurrent joins for an activity by locking its row (`SELECT ... FOR UPDATE`) or using an equivalent advisory lock keyed by activity ID.

```text
join(activity_id, user_id, idempotency_key):
  1. Resolve replayed idempotency result if present.
  2. Lock activity row; read server time and current status/version.
  3. Reject canceled, expired, past-cutoff, restricted, blocked, or ineligible activity.
  4. Lock existing participation for user, if present.
  5. If already Going, return the current successful state (idempotent).
  6. Count current non-host Going rows under the same lock/transaction.
  7. If one host seat + current non-host Going count reaches capacity, return capacity_full.
  8. Upsert participation as Going and grant conversation membership.
  9. Write participation history, notification/outbox events, and idempotency response.
 10. Commit; only then broadcast and deliver notifications asynchronously.
```

Do not maintain an unprotected cached RSVP counter as the capacity authority. A denormalized count may be maintained for fast reads only when it is updated in the same transaction and periodically reconciled against `participations`.

When a Join is initiated from an invitation, lock that invitation in the same transaction. Only after the participation row succeeds, transition the invitation to `joined`; a full, expired, revoked, or invalid activity leaves the invitation in the correct explanatory terminal/review state and grants no conversation membership.

### 5.5 Invitation candidate and send transaction

Candidate selection is a read-only, activity-scoped server query. It requires a published/eligible activity, current host authority, available seats, invitation matching enabled for the city, and an active, explicit invitation-availability consent record. It excludes the host, existing participants, already-invited/declined recipients, blocked pairs, restricted accounts, expired availability, event-date non-overlaps, and frequency/rate-limit failures. It returns only the candidate fields the recipient elected to share plus an intentionally limited availability label.

Sending invitations uses one transaction per bounded batch: lock the activity and quota record; revalidate every selected candidate; insert a unique pending invitation for every eligible recipient; increase quota only for successfully inserted distinct recipients; write notification outbox events; and commit. The API returns per-recipient success/failure without revealing why another person was unavailable. Withdrawing an invitation does not replenish quota.

### 5.6 Deletion and retention

Deletion must be a workflow, not one `DELETE` statement. Immediately revoke refresh tokens/devices, prevent login, disable invitation discoverability and availability, revoke pending invitations, remove the user from future activities, release seats, and revoke future chat access. De-identify retained references where permitted, while preserving the minimum necessary report, case, and audit material for the documented safety/legal retention period. Final retention periods require launch-country legal and policy review before public launch.

## 6. Activity and authorization policy implementation

Encode event states as an explicit enum and permit transitions only in a domain service:

```text
DRAFT → PUBLISHED → HOST_CONFIRMED → IN_PROGRESS → COMPLETED_HOST_REPORTED
                   ↘ EXPIRED_UNCONFIRMED
PUBLISHED / HOST_CONFIRMED / IN_PROGRESS → CANCELED
eligible past activity → OUTCOME_UNKNOWN
eligible activity → UNDER_REVIEW → restore or cancel
```

The transition command records actor, timestamp, reason, prior/new state, current version, and outbox events in one transaction. Scheduled jobs use a service account actor and follow the same transition rules. Terminal activities never return to discovery due to stale client cache.

Authorization is policy-based and centralized in the backend:

| Actor | Allowed scope |
|---|---|
| Guest | Supported cities and public activity preview fields only |
| Member | Own profile, browse preference, explicit invitation settings/availability, own RSVP/check-in/invitations, chat for qualifying activities |
| Host | Member scope plus own eligible activities, participant status summaries, lifecycle transitions, and consent-limited candidate/invitation actions for one eligible activity |
| Moderator | Assigned/scoped reports and cases, proportionate restrictions, no unlogged overrides |
| Admin | Staff administration and audit review; tightly limited, step-up authenticated |

Blocks are enforced before joining, invitation candidate selection/sending, conversation access, and user-profile resolution. An invitation view, decline, or push open does not create a participation, reserve a seat, or grant chat access. A block in a shared activity may not remove physical co-attendance; the API and UI should state its precise online effect rather than promising otherwise.

Conversation state is also explicit: publishing creates one host-owned conversation; Going membership grants access; completed/canceled activities pass through a disclosed grace window before read-only/archive; and a safety action can freeze access sooner. Structured revision/lifecycle events are persisted as system messages and are never the sole source for canonical logistics.

## 7. Kotlin Multiplatform mobile architecture

### 7.1 Recommended client shape

Use KMP for the shared domain/data layer and Compose Multiplatform for shared screens where the team can support it. Keep platform adapters native: Swift/SwiftUI integration for iOS-specific shell/auth/passkeys/push behavior and Android integration for Android-specific shell/auth/passkeys/push behavior. This balances shared product behavior with reliable native identity and notification integration.

```text
shared KMP module
  core/        configuration, logging, result/error model, clock abstraction
  network/     Ktor client, auth interceptor, REST DTOs, Channel client
  database/    SQLDelight cache and migration layer
  domain/      activity, RSVP, chat, safety, profile use cases
  data/        repositories, cache/network synchronization, outbox commands
  ui/          optional shared Compose screens and design system

androidApp/    Credential Manager, BiometricPrompt app lock, FCM, encrypted storage, navigation host
iosApp/        AuthenticationServices, LocalAuthentication app lock, Apple/Google auth bridge, APNs, Keychain, SwiftUI shell
```

Suggested KMP libraries: Ktor for HTTP/WebSocket, Kotlin Serialization for wire models, SQLDelight for local storage, Kotlin Coroutines/Flow for reactive state, and a cross-platform logging/crash-reporting abstraction. Choose one maintained OAuth/OIDC library that supports iOS and Android rather than implementing credential flows manually.

The KMP shared layer defines `PasskeyAuthenticator` and `LocalAppLock` interfaces; each platform implements them with its supported system API. Android uses Credential Manager for passkeys and iOS uses AuthenticationServices. Neither biometric API nor shared code handles biometric templates: the operating system performs user verification and returns only a success/failure result or a signed passkey assertion.

### 7.2 Client data behavior

- Treat a repository as the single source for each screen: emit cached data quickly, refresh from the API, and expose loading/stale/error state explicitly.
- Cache selected city, optional Discover date range/category filters, separately typed scheduled activity previews and ideas, activity details available to the member, joined-plan and invitation summaries, pinned logistics permitted to the account, recent messages, and pending local commands. Never turn a cached browse range into invitation availability.
- Encrypt local database or sensitive rows where platform policy and library support make this practical. Store refresh tokens only in Keychain (iOS) / Android Keystore-backed encrypted storage, never in SQLDelight or logs.
- Use a persistent command queue only for safe, user-initiated mutations such as message sends, attendance responses, drafts, and bounded invitation sends. Each command holds an idempotency key, creation time, retry state, and enough UI state to show Pending/Failed/Retry. Re-fetch candidate eligibility on replay; never queue a client-side roster as authority.
- Re-fetch activity state before displaying a queued Join as successful. A join queued offline is an attempt, not a seat reservation, until the server returns success.
- Preserve `return_to` and `desired_action` locally through authentication and restore only after the API confirms profile completeness and current activity eligibility.
- Offer **App lock** as an opt-in, per-device privacy setting. When enabled, require the platform's biometric prompt with device PIN/passcode fallback before displaying cached private content or using a cached session after an inactivity interval. It is a local UI gate, not a server-authentication factor, and a user can still sign in through a normal account method on another device.

### 7.3 Navigation and deep links

Define typed routes for `discover(city, date_range)`, `activity(id)`, `activity_idea(id)`, `invitation(id)`, `chat(activity_id)`, `my_plans`, `profile`, and authentication return routes. A public URL uses a stable opaque activity ID. Push payloads contain only `type`, `activity_id`, `invitation_id`, `conversation_id` where needed, and a notification ID; the app fetches authorized current data after opening. This prevents leakage of chat content on a locked screen and handles canceled/revoked activity access correctly.

### 7.4 Mobile resiliency requirements

- Maintain a visible offline/stale state for discovery and chat; do not show a locally queued message as delivered.
- A failed message remains retryable with the same client message ID.
- On app start, refresh session first, replay valid command queue items in order where dependencies exist, then reconnect channels.
- Reconcile server activity versions with cache after any live update, push open, resume, or conflict response.
- Treat activity ideas as templates with no RSVP/chat state. Revalidate invitation, capacity, and material-change state on every invitation deep link, action, or reconnect.
- Test daylight-saving/time-zone display using event city timezone, changing device timezone, cross-midnight activities, process death, poor network, and auth cancellation.

## 8. Authentication and account linking

### 8.1 Supported methods

TripPals supports passkeys, Google, and Sign in with Apple. Credentials are acquired through system/native identity flows; the Phoenix backend verifies the credential and issues its own TripPals session. The sign-in UI calls the account method **Passkey**, not "fingerprint login": the device may use fingerprint, Face ID, device PIN/passcode, or another available local user-verification method.

| Method | Client behavior | Backend verification and identity key |
|---|---|---|
| Google | Use Authorization Code Flow with PKCE through the system browser/native Google Identity flow | Exchange/validate the code or ID token server-side; verify issuer, audience/client ID, signature/JWKS, expiry, nonce, and `sub`; key identity by `(google, sub)` |
| Apple | Use Sign in with Apple native/system flow, nonce, and authorization code/identity token | Verify Apple JWT signature/JWKS, issuer, audience, expiry, nonce, and stable `sub`; key identity by `(apple, sub)`; capture name only when Apple supplies it on first authorization |
| Passkey | Use Android Credential Manager or iOS AuthenticationServices; the OS performs local user verification | Issue a short-lived WebAuthn challenge; verify `clientDataJSON`, challenge, origin/RP ID, authenticator data, user-presence/user-verification flags, and assertion signature against the stored public key; update the signature counter/credential metadata |

The server must never trust a Google/Apple display name, raw email, client-declared provider subject, or client-declared biometric result without validating the relevant signed credential. Apple relay email can change or be absent in later payloads; the stable Apple `sub` is the account identity. Passkeys are scoped public-key credentials: the device/private key and biometric information remain with the credential provider, while TripPals stores only the public credential material needed to verify an assertion.

### 8.2 Passkey enrollment, sign-in, and recovery

Use WebAuthn as the server protocol and configure a stable TripPals relying-party ID under the production API/web domain. Mobile apps must be associated with that domain through Android Digital Asset Links and Apple's Associated Domains; staging uses separate domains and credentials. Require user verification for passkey ceremonies, while allowing the operating system to offer an accessible device PIN/passcode fallback when biometrics are unavailable.

Recommended flows:

1. A new user may create an account with a passkey, then completes the minimal profile. Encourage them to add Google or Apple as a recovery login method without requiring it before they can use the core product.
2. An existing authenticated user can add one or more passkeys from Settings after recent authentication. Give credentials a user-facing device/name label and allow revocation individually.
3. On sign-in, the app requests a passkey assertion and sends it to the server for verification. The server resolves the credential ID to a user; no email is required for a discoverable passkey flow.
4. A lost device/passkey is recovered through a separately verified existing method. Support must never bypass account ownership based on a name, public profile, or claimed device loss.
5. A passkey is a login method, not a second factor added on top of a session. Use recent authentication/step-up for security-sensitive actions.

### 8.3 Account model and linking policy

Create `users` as the product account and `auth_identities` as the Google/Apple provider links. `auth_identities` includes `provider`, `provider_subject`, `user_id`, verification metadata, and timestamps. `passkey_credentials` is a separate one-to-many relation to `users`.

Default linking rules:

1. A returning valid provider subject or passkey credential signs into its linked user.
2. A new Google/Apple provider subject creates a pending account/profile flow. Do not merge or link accounts based only on an email claim from a provider.
3. A signed-in user may add a Google or Apple identity after recent authentication. Linking requires successful authentication to both the existing TripPals account and the new provider identity.
4. Let signed-in users add/remove a login method in Settings, but require recent authentication and prohibit removal of the final usable method. Present a recovery-method warning before a user removes their only Google or Apple login method.

### 8.4 TripPals sessions and app lock

Use short-lived signed access tokens (for example, 10–15 minutes) and rotating opaque refresh tokens. Refresh tokens are stored hashed server-side, bound to a device/session record, revocable individually, and rotated on every successful refresh. Detect refresh-token reuse and revoke the affected session family. Mobile clients send access tokens in `Authorization: Bearer`; browser-based admin sessions use secure, `HttpOnly`, `SameSite` cookies with CSRF protection.

Require recent authentication for passkey management, login-method changes, account deletion, and sensitive moderation roles. Record security events such as provider link/unlink, passkey create/revoke/use failure, session revocation, and suspicious token reuse without logging raw credentials, bearer tokens, biometric results, or credential assertions.

App lock is distinct from this session model. It guards private content already available on one device and may require re-unlock after backgrounding or a configured idle period; it neither changes the server session's identity nor substitutes for recent authentication on sensitive API operations. If biometric enrollment changes or the local secure store is invalidated, clear the local lock state and require normal sign-in/session restoration.

### 8.5 Authentication flow endpoints

```text
POST /v1/auth/google/complete       { authorization_code, code_verifier, redirect_uri }
POST /v1/auth/apple/complete        { authorization_code, identity_token, nonce }
POST /v1/auth/passkeys/register/options
POST /v1/auth/passkeys/register/complete { credential }
POST /v1/auth/passkeys/authenticate/options
POST /v1/auth/passkeys/authenticate/complete { credential }
DELETE /v1/me/passkeys/:credential_id
POST /v1/auth/refresh               { refresh_token }
POST /v1/auth/logout                { refresh_token? }
```

The passkey option endpoints return a short-lived ceremony challenge and public WebAuthn options; completion endpoints verify the signed result before returning a product session and `profile_completion_required` indicator. Preserve the activity return intent locally, then have the client fetch its current state before issuing join/interest.

## 9. Notifications, media, search, and analytics

### Notifications

Store a notification row before push delivery. Essential event status changes—host confirmation, material change, cancellation, access revocation—are generated transactionally through the outbox. Invitation notifications are optional, carry only minimal event context, and honor discoverability/notification settings at send time. Preference controls affect delivery of nonessential categories, but event state remains visible in-app. Deep links identify the target; payloads avoid private meeting details, recipient availability, and raw chat text.

### Media

The API creates short-lived, scoped upload intents for avatars and report evidence. The client uploads directly to private object storage, then confirms the object metadata with the API. Validate size, MIME type, content signature, and malware scan status before making any avatar available. Store object keys, not permanent public URLs. Reports/evidence use stricter access controls and retention.

### Discovery search

For one launch city, PostgreSQL indexes plus `pg_trgm` and optional full-text search are sufficient. Query scheduled activities by city, active status, category, capacity, and a UTC range derived from the inclusive event-city local dates; return activity ideas through a separate typed query. Do not introduce Elasticsearch/OpenSearch before real scale/search relevance requires it. Candidate matching remains a private, activity-scoped PostgreSQL query, not a general people-search index.

### Analytics and observability

Emit the MVP funnel as server events where possible (`join_succeeded`, `host_confirmed`, lifecycle transition, invitation state) and client UX events where necessary (`city_preview_viewed`, `date_filter_applied`, activity-idea view, screen/performance events). Send analytics through the outbox or a privacy-reviewed analytics adapter. Candidate metrics use aggregate buckets only. Never use analytics events to transmit chat body, exact location, private meeting details, availability/trip dates, report evidence, raw email, or authentication tokens.

Instrument structured logs with correlation IDs, HTTP/channel latency, database query timing, job retries, RSVP conflicts, chat delivery outcomes, push-provider responses, crash-free sessions, and key lifecycle counts. Use error tracking with payload scrubbing; restrict production logs and admin audit access.

## 10. Security, privacy, and operational controls

- Enforce TLS end to end, secure headers, input validation, output encoding, request-size limits, and dependency/security patching.
- Keep API secrets, OAuth client secrets, signing keys, database credentials, push keys, and object-storage credentials in a managed secret store; rotate them with documented runbooks.
- Keep passkey private keys and all biometric templates off TripPals infrastructure. Verify WebAuthn challenge, RP ID/origin, signature, user-verification flags, and counter semantics server-side; monitor anomalous credential reuse or counter regressions without treating them as automatic account compromise.
- Encrypt private meeting details and sensitive moderation content at rest using managed encryption plus application-level envelope encryption if the threat model requires separation from broad database access.
- Generate different serializers/query projections for guest, member, host, and staff data. Add automated tests proving private fields cannot appear in guest APIs, link previews, logs, notification payloads, or analytics.
- Make invitation discoverability default-off and enforce candidate eligibility, repeated-decline suppression, 15-recipient event quota, host rolling rate limits, and send-time revalidation in the API/database. Candidate cards may expose only opted-in fields; never expose exact trip dates, accommodation, phone/email, live GPS, or counts of unavailable users.
- Rate-limit and monitor signup, login, passkey ceremonies, provider completion, joins, publishes, sends, reports, and upload-intent endpoints. Use generic responses for login-method recovery and appropriate bot-abuse controls.
- Make content reports, restrictions, appeals, and staff actions immutable/auditable. Staff accounts use separate roles, MFA, least privilege, and access review.
- Write a data inventory, legal basis/consent record, retention schedule, incident response plan, backup restore procedure, deletion workflow, and launch-country privacy review before broad release.

## 11. Deployment and environments

### MVP topology

```text
Mobile clients
  → CDN/WAF/load balancer
  → Phoenix API + Channels (stateless containers/releases, minimum two in production)
  → managed PostgreSQL (primary, automated backups/PITR)
  → private object storage + CDN
  → APNs / FCM
```

Run separate local, development, staging, and production environments with different OAuth/passkey credentials, APNs/FCM credentials, storage buckets, databases, domains, and analytics projects. Staging must support end-to-end Google, Apple, and passkey test identities, invitation deep links, push delivery, and lifecycle jobs under safe timing configuration.

Use infrastructure as code, CI/CD with immutable release artifacts, environment-scoped migrations, health/readiness checks, and zero-downtime rollout safeguards. Apply Ecto migrations before application code that depends on them, favor additive/expand-contract database changes, and test restoration from backups periodically.

Initial scale target is modest: horizontal Phoenix API nodes, a primary PostgreSQL instance sized for transactional integrity, and Oban workers tuned separately from web request concurrency. Scale PostgreSQL and add read/search projections only from measured load; the write path remains on the primary.

## 12. Testing strategy and acceptance checks

| Layer | Required coverage |
|---|---|
| Domain unit tests | Valid/invalid activity, invitation, and conversation transitions; permissions; status display rules; blocks; availability consent; deletion policy decisions |
| Database/integration tests | Two simultaneous final-seat joins produce exactly one Going record; host + Going never exceeds 10; idempotency replays; invitation quota/rate-limit transactions; transaction rollback; indexes/query plans |
| API contract tests | Guest-safe response shapes; local-date discovery across DST; ideas never expose Join/host/Going state; invitation candidate privacy and send-time revalidation; profile completion; stale versions; Google/Apple/passkey authentication; WebAuthn challenge replay rejection; session refresh/revocation |
| Channel tests | Membership checks, duplicate message retry, access revocation, persisted-before-broadcast, reconnect cursor behavior |
| Mobile shared tests | Repository cache/refresh states, date-filter persistence, ideas/template routing, invitation deep links, queued command replay, timezone conversion, error mapping |
| Native integration tests | Google/Apple/passkey handoff, Keychain/Keystore storage, biometric/PIN app-lock fallback and enrollment-change reset, APNs/FCM handling, process-death recovery |
| End-to-end tests | Guest → city/date filter → auth → profile → join; idea → create → publish → candidate query → invite → join; confirm → chat → conclude; cancel/material edit/invitation reconciliation; report/block/appeal |
| Security/operations tests | Token reuse/revocation, WebAuthn RP/origin/signature/user-verification checks, passkey revocation/recovery, invitation scraping/consent/blocked-pair bypass attempts, rate limits, dependency scan, backup restore, secret/log scrubbing |

The MVP acceptance gates in the product plan are architecture gates too: no GPS requirement for guest browsing, no overbooking, durable and correctly authorized chat, correct push deep links, truthful lifecycle labels, deletion/revocation, and auditable safety operations.

## 13. Delivery sequence

### Phase A — foundation

1. Establish Phoenix release, managed PostgreSQL, migrations, secrets, environments, CI/CD, structured logging, and error tracking.
2. Implement `users`, `auth_identities`, `passkey_credentials`, sessions, WebAuthn ceremonies, Google, Apple, profile completion, city data, city-local date filtering, activity ideas, and guest discovery.
3. Build the KMP network/auth/session/cache foundation, native passkey adapters, optional local app-lock adapter, typed navigation, selected-city/date-filter persistence, and separately typed activity/idea views.

**Exit:** A guest can browse real public activity previews without GPS or signup; Google, Apple, and passkey authentication return safely to the intended action; optional app lock never prevents login-method recovery.

### Phase B — reliable activity participation

1. Implement activity drafts from an idea or custom creation, publication checks, capacity 2–10 including host, versions/revisions, host lifecycle commands, and public/member detail serializers.
2. Implement transactional interest/join/leave, My Plans/Inbox, conversation membership, and idempotency.
3. Add initial admin activity review only where moderation policy requires it.

**Exit:** A host publishes/confirms/cancels; concurrent last-seat joins cannot overbook; all state is accurate after app restart.

### Phase C — coordination

1. Add conversations, messages, Phoenix Channels, cursor synchronization, offline command queue, and pinned structured logistics.
2. Add outbox, Oban workers, device registration, APNs/FCM delivery, and deep-link routing.
3. Implement material-change acknowledgements and lifecycle reminder/expiry jobs.

**Exit:** Chat persists and retries without duplication; every essential event update reaches the correct activity or a useful status page.

### Phase D — trust, invitations, completion, and launch hardening

1. Add explicit invitation availability/consent, activity-scoped candidate cards, bounded invite sending, recipient Inbox/decline, quotas, send-time revalidation, reports, blocks, cases, restrictions, appeals, staff roles, audit log, and protected Phoenix admin console.
2. Add post-event check-in, chat-retention states, account deletion workflow, data-retention controls, observability dashboards, and backup restore test.
3. Conduct threat modeling, invite-abuse/concurrency tests, accessibility and weak-network tests, and one-city pilot operational rehearsals. Keep invitations feature-flagged per city until the rollout gate passes.

**Exit:** The complete discover → join or invite → coordinate → conclude loop, safety operation, invitation privacy controls, and deletion path work before controlled launch.

## 14. Decisions to make before implementation starts

1. Select managed hosting, PostgreSQL, object storage, error monitoring, analytics, and push-notification vendors based on launch-country data residency, support, and cost requirements.
2. Set the host-confirmation deadline, late-join policy, chat history retention, message/edit policy, report/SLA rules, deletion/safety retention schedules, invitation expiry/review rules, and post-event chat grace period. Capacity is fixed at 2–10 total people including the host for the MVP.
3. Confirm whether KMP UI is fully Compose Multiplatform or shared domain/data with native SwiftUI/Android UI; the backend contract is unchanged either way.
4. Register and configure production/staging Google OAuth clients, Apple Service/App IDs and keys, WebAuthn relying-party domains, Android Digital Asset Links, Apple Associated Domains, universal/app links, APNs, and FCM projects.
5. Confirm invitation consent language, candidate-card fields, availability expiry, per-activity 15-recipient quota, host rate limits, and city feature-flag rollout rules through the concierge pilot.
6. Complete legal/privacy/security review for adult age gate, consent copy, cross-border data transfers, invitation availability, incident reporting, and moderator operating procedures.

## 15. Explicit non-goals for this architecture

- Direct client access to PostgreSQL, Supabase-style row policies as the main authorization layer, or client-calculated capacity.
- Microservices, a separate message broker, event sourcing, dedicated search cluster, maps, payments, ticketing, a general people directory, or general direct messages in the MVP.
- Mandatory location permission, background location tracking, public attendance histories, or unrestricted user ratings.
- Treating host conclusion, Going RSVP, presence, or self-reported attendance as independently verified physical attendance.

This architecture deliberately optimizes for the product's core promise: a traveler can discover a credible plan, join without overbooking, coordinate safely, and receive truthful updates through the event's outcome.
