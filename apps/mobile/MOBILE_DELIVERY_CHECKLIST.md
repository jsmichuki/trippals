# TripPals mobile delivery checklist

This is the feature-led implementation checklist for the Android and iOS
TripPals clients. It implements the MVP described in
[`docs/TripPals_Architecture_Plan.md`](../../docs/TripPals_Architecture_Plan.md)
and [`docs/TripPals_MVP_Plan_and_User_Flows-v2.md`](../../docs/TripPals_MVP_Plan_and_User_Flows-v2.md).

Complete an item only when the relevant UI behavior, shared KMP code, native
adapter (where needed), API integration, privacy/error behavior, and focused
test are present. The API remains authoritative for authorization, activity
state, capacity, RSVP, invitations, chat access, and moderation decisions.

Use the following to derive theme, look & feel for the entire app:
- apps/mobile/inspiration/look and feel 1.png
- apps/mobile/inspiration/look and feel 2.png

## Scope, ownership, and completion rules

- [x] Build one KMP workspace with `shared`, `androidApp`, and `iosApp` modules;
  do not let either client talk to PostgreSQL or make client state authoritative.
- [x] Put pure models, use cases, Ktor transport, SQLDelight cache, repositories,
  command queue, and `StateFlow` screen state in `shared/commonMain`.
- [x] Put Android-only Credential Manager, Keystore-backed token storage,
  BiometricPrompt, FCM, Android permissions, app links, and Android shell
  navigation in `androidApp`/`androidMain`.
- [x] Put iOS AuthenticationServices, Keychain, LocalAuthentication, APNs,
  universal links, and SwiftUI shell/navigation in `iosApp`/`iosMain`.
- [x] Use `expect`/`actual` only for a genuinely shared contract with different
  platform implementations (for example, secure session storage,
  `PasskeyAuthenticator`, `LocalAppLock`, push token provider, clock, and
  network reachability). Keep platform-native UX and navigation platform-local.
- [x] Decide and document the UI boundary before screen implementation: shared
  Compose Multiplatform screens/design system, or shared state/domain with
  Android Compose and iOS SwiftUI shells. The API/data contracts must be shared
  either way.
- [x] Use Ktor HTTP and WebSocket clients, Kotlin Serialization, SQLDelight,
  Coroutines/Flow, and a cross-platform logging/crash-reporting abstraction.
- [x] Never log, cache in plaintext, analytics-track, or put in a push preview:
  bearer/refresh tokens, passkey assertions, biometric results, chat bodies,
  private meeting directions, exact availability, report evidence, or media
  access URLs.
- [x] Treat server error codes, current entity version, correlation ID, and
  field errors as first-class UI data. Surface a safe error message and a retry
  action where retry is valid.
- [x] Preserve stable opaque IDs in routes and storage. Do not infer meaning
  from an ID or expose sequential/local database IDs.

## API integration foundation

### Contract and transport

- [ ] Generate or maintain Kotlin wire DTOs from
  [`contracts/openapi/trippals-v1.json`](../../contracts/openapi/trippals-v1.json);
  keep DTOs separate from domain models and map all JSON `snake_case` fields
  explicitly.
- [ ] Before wiring a feature, add or confirm its operation, request/response
  schemas, auth requirements, errors, pagination, and headers in OpenAPI. The
  committed contract currently covers core discovery, activity lifecycle, and
  participation, while several implemented router routes (auth, invitations,
  chat, safety, devices, notifications, and media) still require complete
  OpenAPI coverage.
- [x] Configure environment-specific HTTPS and WSS base URLs without committing
  secrets. Reject clear-text production traffic and validate TLS normally.
- [x] Add an HTTP client interceptor that attaches the access token only to the
  TripPals API origin, assigns a correlation header when appropriate, and
  redacts sensitive headers and bodies from diagnostics.
- [x] Implement a single-flight refresh flow for expired access tokens using
  `POST /v1/auth/refresh`; retry the original safe request once after a
  successful refresh, and clear the local session on revocation/reuse failure.
- [x] Require a newly generated `Idempotency-Key` for every user-initiated
  state-changing HTTP operation. Persist the key with the queued command and
  reuse it only for retries of the same payload.
- [ ] Send `If-Match`/expected version for every activity edit. On
  `409 version_conflict`, retain the draft, fetch/use the returned current
  activity projection, and offer an explicit review/reapply flow.
- [x] Normalize API outcomes into typed success, validation, authentication,
  authorization, conflict, rate-limit, offline/transport, and unexpected-error
  results; do not branch UI behavior on human-readable error text.
- [x] Support cursor pagination for activities, plans, invitations, messages,
  and notifications; deduplicate by server ID and avoid offset pagination.
- [x] Parse timestamps as instants and display activity dates/times in the
  activity's supplied IANA timezone, not by adding fixed 24-hour intervals or
  assuming the device timezone.

### Session, cache, and command queue

- [x] Store refresh tokens only in Keychain (iOS) or Keystore-backed encrypted
  storage (Android); keep access tokens memory-resident where practical and
  clear both on logout/deletion/revocation.
- [x] Create SQLDelight tables and migrations for non-sensitive cached read
  models: selected city and filters, activity previews/details, ideas, plans,
  invitations, permitted pinned logistics, recent messages, notifications, and
  pending commands.
- [x] Add cache metadata (`fetched_at`, server version/cursor, stale state, and
  authorization scope where relevant); remove or re-scope private cache rows on
  logout, account deletion, membership loss, block/restriction, and access
  denial.
- [x] Make each repository the single source of data for its screen: emit cache
  promptly, refresh from the API, and expose loading, refreshing, stale, empty,
  and retryable-error states.
- [x] Persist only safe, user-initiated commands (for example drafts, messages,
  attendance, and bounded invitation sends). Do not queue a Join as though it
  reserves a seat or queue an old invitation candidate list as authority.
- [x] Give each queued command its payload hash, idempotency key, creation time,
  dependency/order, retry count, last safe error, and user-visible
  Pending/Failed/Retry state.
- [x] On launch/resume: restore secure session, refresh it, replay valid queued
  commands in dependency order, refresh relevant activity state, then reconnect
  Channels. Stop replay and require review after an authorization/conflict or
  terminal-state result.
- [ ] Test retry after process death, network changes, token expiry, server
  replay, different-payload idempotency conflict, and stale cache denial.

## Feature 1 — Entry, city choice, and guest discovery

### Experience and shared state

- [ ] Implement Welcome with Explore activities CTA(should look like apps/mobile/inspiration/welcome.png). Do not require GPS, trip duration, account creation,
  payment, or a rating prompt to browse.
- [ ] Implement city search/selection with supported and coming-soon/unavailable
  states; persist only the selected browsing city locally.
- [ ] Implement Discover with a persistent city label, date range, Today,
  Tomorrow, Next 7 days, and Any upcoming shortcuts, category filters, list
  loading, pull-to-refresh, pagination, and truthful empty/offline states.
- [ ] Implement the date-range sheet with local calendar dates, clear/reset,
  invalid/reversed/past range feedback, and an event-city-timezone summary.
- [ ] Render scheduled activities and evergreen activity ideas as distinct types.
  Ideas must never have a time, Going count, chat, or Join affordance.
- [ ] Preserve city, date range, category filters, and Discover scroll position
  through detail navigation and authentication.

### API integration

- [ ] Integrate `GET /v1/cities`; model supported versus unavailable status and
  never invent inventory for an unsupported city.
- [ ] Integrate `GET /v1/activities` with `city_id`, inclusive
  `start_local_date`/`end_local_date`, filters, cursor, and guest-safe response
  shape. Keep the server's activity status authoritative.
- [ ] Integrate `GET /v1/activity-ideas` independently of scheduled results;
  preserve its separate typed response in cache and UI.
- [ ] Handle expired cursors, malformed filters, rate limiting, no inventory,
  and a previously viewed/canceled activity without converting an error into an
  empty feed.

### Verification

- [ ] Test guest first launch, city persistence, city switch, default/custom
  dates, no results, unsupported city, offline cached feed, and device timezone
  changes around event-city DST boundaries.

## Feature 2 — Activity detail, return intent, interest, and RSVP

### Experience and state

- [ ] Implement a stable `activity(id)` route that loads the current permitted
  detail view and shows guest/member/host variants without assuming UI-hidden
  data is protected.
- [ ] Display authoritative title, activity state, city-local time, public area,
  cost, capacity/available seats, confirmation status, material-change status,
  and only the roster/logistics the current server projection permits.
- [ ] Support guest Join/Interested/Create flows by saving a local
  `return_to`/`desired_action`; after authentication, resume only after profile
  completion and a fresh server eligibility check.
- [ ] Add explicit states for full, canceled, expired, past, restricted,
  unavailable, updated, Going, Interested, invited, and retryable loading
  failures.
- [ ] Implement Share as an opaque public activity link; it must not include
  private logistics, roster, authentication material, or invitation data.
- [ ] Implement Interested/bookmark as distinct from Going. Neither a pending
  invitation nor Interested status provides a seat or chat access.

### API integration

- [ ] Integrate `GET /v1/activities/{id}` on route entry, resume, push open,
  conflict, and material live update; replace/redact cached detail on a changed
  permission projection.
- [ ] Integrate `POST /v1/activities/{id}/interest` with an idempotency key and
  reconcile the returned state into detail and My Plans.
- [ ] Integrate `POST /v1/activities/{id}/join` with an idempotency key. Show
  “Joining…” until the server returns success; an offline attempt remains
  “Pending — seat not reserved,” never Going.
- [ ] Map Join errors such as `capacity_full`, `activity_not_joinable`, block or
  restriction decisions, profile incompleteness, and idempotency conflict to
  specific explanatory UI and refetch the activity where warranted.
- [ ] Integrate `POST /v1/activities/{id}/leave`, `/reconfirm`, and `/attendance`.
  Update chat eligibility/cache only from the successful server result.

### Verification

- [ ] Test final-seat contention from two devices, duplicate retry, guest
  return intent, offline Join replay, terminal event state, leave/rejoin rules,
  and server-driven loss of chat access.

## Feature 3 — Authentication, profile, account, and local privacy

### Experience and native adapters

- [ ] Implement Passkey, Google, and Apple entry points, including unavailable,
  canceled, interrupted, provider-conflict, restricted, and return-intent
  states. Label passkeys as “Passkey,” not as a specific biometric.
- [ ] Define shared `PasskeyAuthenticator` and provider-auth contracts; use
  Android Credential Manager in Android code and AuthenticationServices in iOS
  code. The OS handles biometric/PIN verification; shared code receives only
  the signed assertion/result required for the API exchange.
- [ ] Implement the minimum profile flow: display name, adult eligibility,
  community-rule acceptance, optional avatar/interests, field errors, and
  profile-completion gating before an action resumes.
- [ ] Implement Profile/Settings for credential management, notification and
  privacy settings, support, restrictions, appeal entry, and account deletion
  status.
- [ ] Implement optional per-device app lock behind the shared `LocalAppLock`
  interface, using BiometricPrompt/LocalAuthentication with system
  PIN/passcode fallback. Gate cached private content after the configured
  inactivity interval; this is a local UI lock, not server MFA.
- [ ] Clear private screens, in-memory tokens, and sensitive clipboard/input
  state on logout, deletion, lock, and backgrounding according to platform
  lifecycle policy.

### API integration

- [ ] Integrate passkey options/completion routes for registration and
  authentication; send only the system-produced WebAuthn payload to the API and
  never persist raw assertions in logs or SQLDelight.
- [ ] Integrate `POST /v1/auth/google/complete` and
  `POST /v1/auth/apple/complete` via their native/system authorization flows;
  never treat an email/display name/client-declared subject as verified identity.
- [ ] Integrate `POST /v1/auth/refresh`, `POST /v1/auth/logout`, and
  `DELETE /v1/auth/session` with session clearing and Channel disconnect.
- [ ] Integrate `GET /v1/me` and `PATCH /v1/me`; hydrate the shared current-user
  session only from server responses.
- [ ] Integrate passkey removal, identity unlinking, and `DELETE /v1/me` with
  recent-auth flows and clear, irreversible-action confirmation UI.

### Verification

- [ ] Test passkey/provider cancellation, account switching, refresh rotation
  failure, revoked session, profile validation, app-lock timeout, relaunch,
  logout, deletion initiation, and no credential/token data in logs or cache.

## Feature 4 — My Plans, lifecycle actions, and post-event check-in

### Experience and shared state

- [ ] Implement My Plans with Going/upcoming first, then Interested, Hosting,
  Invitations, Past, and Canceled/terminal views, cursor pagination, empty
  states, and the next actionable event state.
- [ ] Keep plans and chats accessible by activity ID across Discover city/date
  changes; do not re-run onboarding or silently remove historical state.
- [ ] Implement host dashboard with occupancy, participant summaries only where
  permitted, host confirmation, start, conclude, cancel, edit, chat, and
  invitation entry points.
- [ ] Implement post-event attendance prompt: Yes, No, Prefer not to say,
  optional private feedback, report action, and truthful host-reported/unknown
  outcome labels.

### API integration

- [ ] Integrate `GET /v1/me/plans` with typed sections, cursor state, current
  entity versions, and terminal explanations.
- [ ] Integrate `POST /v1/activities/{id}/confirm`, `/start`, `/finish`, and
  `/cancel` with a new idempotency key per deliberate action and refetch current
  detail on conflict/terminal outcome.
- [ ] Reconcile lifecycle responses into activity detail, plans, chat header,
  invitations, notifications, and local cached commands in one repository-level
  update.

### Verification

- [ ] Test a plan surviving city switch/relaunch, host confirmation cutoff,
  canceled/expired views, repeated lifecycle taps, attendance retry, and a
  restricted host/member response.

## Feature 5 — Create, edit, publish, and activity ideas

### Experience and shared state

- [ ] Implement Create activity from scratch and “Organize this” from an idea.
  An idea pre-fills editable draft fields only; it never becomes a real activity
  until the server accepts publication.
- [ ] Implement draft form/validation for category, title, description, city,
  local start/end time, public area, participant-only details, cost/currency,
  capacity (2–10 including the host), and applicable policy fields.
- [ ] Store private meeting details in a deliberately protected form and show
  them only from the server-authorized member/host projection; do not attach
  them to share links, guest cache, analytics, or push notifications.
- [ ] Support local draft recovery, server validation errors, moderation/review
  status, publish retry, material-change review, and an explicit discard flow.
- [ ] For edit, retain the user's unsaved changes after a version conflict and
  compare them with the freshly returned server version before a new submission.

### API integration

- [ ] Integrate `POST /v1/activities` to create a server draft with an
  idempotency key; replace a local-only draft with its opaque server ID only on
  success.
- [ ] Integrate `PATCH /v1/activities/{id}` with `If-Match`/expected version and
  material-change response handling. Never blindly retry a stale edit.
- [ ] Integrate `POST /v1/activities/{id}/publish` and reconcile the created
  conversation, activity version/state, and host plan locally after success.
- [ ] Validate/API-test DST-invalid local times, end-before-start, capacity
  bounds, private/public logistics, and activity lifecycle errors at the client
  boundary without duplicating server authority.

### Verification

- [ ] Test idea-prefilled creation, process death with local draft, create
  replay, stale edit conflict, material revision, failed publish, city timezone
  change, capacity 2/10 limits, and a guest attempting Create then authenticating.

## Feature 6 — Invitations and consented availability

### Experience and shared state

- [ ] Implement invitation settings as default-off discoverability with clear
  consent, revocation, previewable shared fields, availability expiry, and an
  explicit statement that Discover dates are not invitation availability.
- [ ] Implement availability create/edit/delete with city, optional local dates
  and time preferences, traveler/resident role, shared-field selection, visible
  state, and immediate opt-out behavior.
- [ ] Implement host-only Invite people sheet attached to one eligible published
  activity. Show consent-limited candidate cards, selection, batch progress,
  quota, generic per-recipient outcomes, and no eligible/feature-disabled/full
  states.
- [ ] Never display exact trip dates, accommodation, contact details, GPS, raw
  itinerary, opt-out counts, or a general people directory.
- [ ] Implement Incoming Invitation with real event context, Join, Decline,
  Report, and settings entry. Opening an invitation must not mark Going, reserve
  a seat, or expose chat/roster.

### API integration

- [ ] Integrate `GET/PATCH /v1/me/invitation-settings` and
  `POST/PATCH/DELETE /v1/me/availabilities` with idempotency, local cache
  invalidation, and immediate UI removal after opt-out.
- [ ] Integrate `GET /v1/activities/{id}/invitation-candidates` only in the
  host dashboard for a current eligible activity; clear candidates whenever the
  activity changes, becomes full, or permission changes.
- [ ] Integrate `POST /v1/activities/{id}/invitations` for bounded batches.
  Generate one idempotency key per unchanged batch; show generic failures and
  refetch event/candidate state rather than revealing server eligibility reasons.
- [ ] Integrate `GET /v1/me/invitations`, `GET /v1/invitations/{id}`, and
  `POST /v1/invitations/{id}/decline`; perform an invitation Join through the
  normal activity Join endpoint, with the invitation ID/context retained only
  as allowed by the contract.
- [ ] Re-fetch authoritative invitation/activity state on deep link, resume,
  join result, and push open; represent pending, joined, declined, expired,
  revoked, unavailable, needs-review, full, and canceled states truthfully.

### Verification

- [ ] Test default opt-out, immediate revocation, candidate privacy, batch retry,
  quota/full/event terminal behavior, decline suppression, invite deep link,
  concurrent final-seat invitation join, and no chat before Going.

## Feature 7 — Activity chat and real-time updates

### Experience and shared state

- [ ] Implement chat as an activity-scoped route, not a general DM surface.
  Require a current server-authorized host/Going membership before rendering
  messages or composer.
- [ ] Render an authoritative pinned plan derived from activity fields, current
  city-local date/time, permitted roster, system updates, read-only/frozen
  state, mute, leave, report, and block actions.
- [ ] Implement recent history, deterministic pagination/resume cursor, cached
  messages, Connecting, Offline — showing cached messages, and Retry states.
- [ ] Implement plain-text, length-bounded composer with a UUID
  `client_message_id`; show queued, sending, persisted/delivered, failed, and
  retry states accurately. Never describe a queued message as delivered.
- [ ] On leave/restriction/revocation/read-only event, close the composer and
  Channel, remove access to unauthorized cached content, and route to an
  explanatory activity/plan state.

### API and Channel integration

- [ ] Integrate `GET /v1/conversations/{id}/messages` for initial history and
  cursor recovery, and `POST /v1/conversations/{id}/messages` as HTTP fallback;
  reuse the same `client_message_id` and idempotency identity on retry.
- [ ] Establish an authenticated Phoenix socket only after a valid session.
  Handle token refresh/reconnect without placing credentials in logs or URLs
  beyond the authenticated socket contract.
- [ ] Join `activity:{activity_id}` for permitted activity revision/lifecycle
  updates and `conversation:{conversation_id}` only for permitted conversation
  events. Treat Channel join errors as authorization state, not transient
  transport failures.
- [ ] Send `message:create` with the required body and `client_message_id`;
  acknowledge a send only after the persisted server reply/event and reconcile
  server cursor/sequence/order into the local cache.
- [ ] Reconcile live activity updates into detail, pinned chat logistics, plans,
  and invitation state. Re-fetch current detail if the update cannot safely
  replace the cached projection.
- [ ] Do not use Presence as attendance or membership authority; if exposed,
  label it as a transient online hint only.

### Verification

- [ ] Test member/host access, guest/Interested/pending-invite denial, offline
  queue/retry, duplicate client message, out-of-order events, cursor recovery,
  reconnect, membership revocation during composition, cancelled/read-only chat,
  pinned material changes, block masking, and no chat content in push/logs.

## Feature 8 — Notifications, deep links, and device registration

### Experience and native adapters

- [ ] Implement Android FCM and iOS APNs adapters behind a shared push-token
  provider; request notification permission contextually and handle denial.
- [ ] Register/unregister a device token for the current authenticated account;
  handle token rotation, logout, account deletion, and provider invalidation.
- [ ] Implement notification inbox with pagination, unread state, safe minimal
  labels, mark-read behavior, preferences, and empty/error states.
- [ ] Define typed deep links for activity, activity idea, invitation, chat,
  My Plans, and authentication return routes. Validate route inputs as opaque
  IDs and fetch current authorized data before displaying it.
- [ ] Keep push payload content minimal (type and relevant IDs/notification ID).
  Do not show chat text, private directions, availability, evidence, tokens, or
  sensitive context on a locked screen.
- [ ] Configure Android App Links/Digital Asset Links and iOS Universal Links/
  Associated Domains for production and staging separately; test cold start,
  warm start, authenticated, logged-out, expired, and revoked targets.

### API integration

- [ ] Integrate `POST /v1/devices` and device deletion with idempotency and
  authenticated ownership; never queue a raw token in logs/analytics.
- [ ] Integrate `GET /v1/notifications`, notification mark-read, and
  `GET/PATCH /v1/me/notification-preferences` with local update/retry behavior.
- [ ] On every push/deep link, fetch the latest activity/invitation/conversation
  state. Route unavailable, canceled, full, expired, or revoked targets to a
  truthful explanation, not generic Discover.

### Verification

- [ ] Test permission denial, token rotation, cross-account logout, duplicate
  and out-of-order notifications, deep-link process death, blocked/revoked
  access, and locked-screen content privacy on both platforms.

## Feature 9 — Reporting, blocks, restrictions, appeals, and media

### Experience and shared state

- [ ] Implement report entry from activity, message, and account context with
  safe category/reason choices, minimal evidence collection, submission state,
  retry, and clear emergency/safety language appropriate to policy.
- [ ] Implement independent Block/Unblock actions with clear online effects and
  the limitation that blocking cannot guarantee physical separation at an event.
- [ ] Implement restriction notice and appeal flows using only the user's
  permitted reason/scope/duration/review information; never expose reporter
  identity or case details.
- [ ] Implement avatar and report-evidence upload flows with local size/type
  validation, explicit progress/failure, no public permanent URL, and careful
  cache cleanup.

### API integration

- [ ] Integrate `POST /v1/reports`, `POST/DELETE /v1/blocks/{user_id}`,
  `GET /v1/me/restrictions`, and `POST /v1/appeals` with idempotency and typed
  status/error handling.
- [ ] Integrate protected media upload-intent, upload, confirm, and authorized
  access routes. Use only the short-lived, server-authorized upload/access URL
  for its intended operation; do not persist it beyond its safe lifetime.
- [ ] Reconcile a successful block/restriction with current invitations,
  candidates, chat, plans, and cached profile/activity projections via fresh
  server reads rather than client-side assumptions.

### Verification

- [ ] Test report retry, report-context privacy, block effects in chat and
  invitations, restricted flows, appeal status, unauthorized media access,
  expired upload intent, scan/type/size failure, and absence of evidence URLs
  and report content from logs/analytics.

## Cross-feature accessibility, quality, and release gates

- [ ] Apply accessible labels, focus order, dynamic type/font scaling, adequate
  touch targets, contrast, screen-reader announcements for async outcomes, and
  non-color-only status indicators on Android and iOS.
- [ ] Localize user-facing strings, dates, currency, pluralization, error text,
  and timezone phrasing. Preserve server error codes separately from localized
  copy.
- [ ] Test small/large phones, tablets if in scope, dark/light modes, landscape
  where supported, slow/intermittent networks, no network, process death,
  background/foreground transitions, and device timezone changes.
- [ ] Add shared unit tests for serializers/mappers, repositories, command queue
  ordering, error mapping, time-zone formatting, pagination, and Channel event
  reconciliation.
- [ ] Add Android and iOS integration tests for secure storage, passkeys,
  app-lock adapters, push/deep links, lifecycle transitions, and native
  navigation handoff.
- [ ] Add UI/acceptance tests for the core loop: guest discovery → authenticate
  → profile → Join → plan/chat; idea → draft → publish → invite → recipient
  Join; host confirm → chat → finish; material edit/cancel; report/block.
- [ ] Confirm no client behavior grants a seat, chat access, invitation
  eligibility, activity lifecycle outcome, or moderation outcome without a
  successful server response.
- [ ] Run the shared module tests, Android tests/lint, iOS tests, formatting,
  dependency/security checks, and a release build for each target in CI.
- [ ] Before pilot release, verify Android signing/App Links/FCM and iOS signing/
  Associated Domains/APNs against their respective staging and production
  environments; keep all credentials in the platform/deployment secret stores.

## API coordination checklist

- [ ] Treat the OpenAPI file as the Kotlin client contract. Add schema and
  contract-test coverage for every route the mobile client consumes before
  calling that mobile integration complete.
- [ ] Agree stable error-code handling for at least `capacity_full`,
  `activity_not_joinable`, `version_conflict`, `blocked_interaction`,
  `profile_incomplete`, unauthorized/restricted, rate-limited, and
  conversation read-only/revoked outcomes.
- [ ] Agree response projections for guest, member, host, invited, Going,
  moderator, and terminal states before implementing conditional UI; missing
  data must never be guessed or synthesized client-side.
- [ ] Agree pagination cursor direction/order and duplicate-event reconciliation
  for activities, plans, invitations, notifications, and messages.
- [ ] Agree Channel authentication, event names/payload schemas, acknowledgement
  semantics, reconnect cursor behavior, revocation behavior, and minimum client
  versions before shipping real-time chat.
- [ ] Confirm product-policy values still marked unresolved in the backend
  checklist—host-confirmation deadline, join cutoff, invitation expiry,
  material-change acknowledgment/reconfirmation, chat grace/read-only period,
  message edit/deletion, candidate-card fields, quotas/rate limits, and city
  feature-flag rules—before making those UI states final.
