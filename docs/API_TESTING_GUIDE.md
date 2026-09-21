# API testing guide

This guide is the human companion to the importable [Postman collection](../contracts/postman/TripPals_API.postman_collection.json). It tests the locally running Phoenix API with synthetic people, activities, messages, tokens, and media only. Do not place production credentials, provider identity tokens, or personal information in Postman environments or collection examples.

## Start a local API

From the repository root, start the local PostgreSQL 14 service, then create the local databases and run the API:

```sh
cp .env.example .env
make bootstrap-api
make setup-api
make up
```

The default base URL is `http://127.0.0.1:4000`. Import both the collection and [local environment](../contracts/postman/TripPals_Local.postman_environment.json), select **TripPals Local**, and send `00 Health and discovery / Cities` first. Its test script stores the first supported city in `city_id`. If there is no supported city, create one through the local developer workflow before continuing; public creation of cities is intentionally not an API capability.

The collection has three intentionally separate credentials: `host_access_token`, `member_access_token`, and `moderator_access_token`. Never reuse a token across those roles when checking authorization. `target_user_id` must be a fourth account when testing blocks or reports.

## Creating local-only test accounts

Interactive provider and passkey sign-in is the correct end-to-end route. For controller and workflow testing, create disposable local sessions in `iex -S mix` from `apps/api/service` after loading the repository environment:

```elixir
{:ok, user} = TripPals.Accounts.create_user()
{:ok, _profile} = TripPals.Accounts.update_me(user.id, %{
  "display_name" => "Postman Host",
  "adult_confirmation" => true,
  "community_rule_version" => "v1"
})
{:ok, session} = TripPals.Accounts.create_session(user.id, "postman-host")
TripPals.AccessToken.issue(session)
```

Repeat with distinct names/device IDs for the member and target accounts. Copy each returned access token only into the selected local Postman environment. For moderator tests, assign the account the moderator role through the local staff setup used by the test suite; a member token must receive `403` from `/v1/admin/*`.

This shortcut is local-development test data, not an authentication design: production authentication must use a verified Google/Apple identity token or a server-verified WebAuthn ceremony. Delete the local database or the disposable accounts when finished.

## Common request rules

All JSON uses `snake_case` and every API response is an envelope: success values live in `data`; API failures live in `error` with a stable `code`, a safe `message`, and sometimes `fields`.

| Rule | Where it applies | How the collection handles it |
| --- | --- | --- |
| `Authorization: Bearer <access token>` | Member, host, and staff endpoints | Folder-level token variables keep identities separate. |
| `Idempotency-Key` | Every state-changing request | Every mutation has `{{$guid}}` as a fresh synthetic key. Re-send one unchanged request to verify a safe replay; reusing its key with changed JSON must return `409`. |
| `If-Match` | `PATCH /v1/activities/:id` | The create and activity GET requests store `activity_version`; use that value and verify stale versions return `409`. |
| Opaque IDs | All resource IDs | IDs are captured from responses or are environment placeholders. Do not substitute database primary keys. |
| Sensitive data | All requests/logs | The collection has placeholders only. Avoid real refresh tokens, passkey assertions, provider JWTs, push tokens, chat bodies, and report evidence in shared exports. |

`Idempotency-Key` applies even when a controller has no payload. Postman’s `{{$guid}}` is evaluated per send. To deliberately test replay behavior, replace it with a fixed temporary UUID for two identical sends.

## Feature-by-feature test sequence

Run folders in numeric order. A request may be sent individually after its prerequisite variable is populated. Expected errors are useful authorization/privacy tests, not collection failures to work around.

### 00 — health and public discovery

1. `GET /up` and `GET /ready` must return `200`; readiness also proves PostgreSQL reachability.
2. `GET /v1/hello`, `/v1/cities`, `/v1/activity-ideas`, and `/v1/activities?city_id={{city_id}}&date=2026-10-15` are guest-safe discovery calls.
3. Verify discovery returns only published/host-confirmed activities and no private meeting details, host contact data, availability, or invitation information.

### 01 — identity, profile, and sessions

1. With a disposable host token, `GET /v1/me`, then `PATCH /v1/me` with the synthetic profile data in the collection. Confirm the response never returns authentication credentials.
2. `POST /v1/auth/passkeys/authenticate/options` returns a challenge/options object. Complete it only from a real browser/platform WebAuthn client; Postman cannot produce a valid authenticator signature. Use `authenticate/complete` only after copying that genuine assertion and ensure a failed or replayed challenge is rejected.
3. With a real, configured provider token, `POST /v1/auth/google/complete` or `/apple/complete` requires both `identity_token` and the exact nonce. A bogus JWT or nonce must receive `401`; do not paste live provider tokens into a checked-in environment.
4. `POST /v1/auth/passkeys/register/options` and `register/complete` likewise require a real platform attestation and the authenticated user. The collection deliberately uses placeholders so that its sample stays non-sensitive.
5. Test refresh/logout/delete-session only with a disposable real refresh/session token. `DELETE /me/passkeys/:credential_id` and `DELETE /me/identities/:provider` require recent auth and must not permit removal of the final login method.

### 02 — activity lifecycle and authorization

1. Use the host token to create the synthetic draft (capacity `2`), which stores `activity_id` and `activity_version`.
2. Patch the draft with `If-Match: {{activity_version}}`; repeat with the old value to test the `409 version_conflict` response.
3. Publish, confirm, start, and finish in order. The host’s initial seat plus capacity two leaves one seat for the member. The cancel request is provided for an alternate branch; do not send it after finish.
4. Send a host-only transition using `member_access_token` to confirm a `403`; guest activity GET must still omit participant-only meeting details.

### 03 — participation, plans, and conversation access

1. Send interest and join with the member token. The host is already Going, so the first member join fills the final seat.
2. Re-run join from a second member to expect `409 capacity_full`. Re-send the exact first join with the same idempotency key to test replay safety.
3. `GET /v1/me/plans` must show the member’s own state only. Use leave/reconfirm/attendance only when the activity state makes each transition applicable.
4. The join response supplies `conversation_id` when chat becomes available. Confirm the member can list/send messages and that a non-Going account gets `403` without learning chat contents. For real-time coverage connect to `/socket?token=<member token>` and join the returned conversation topic; leave must revoke access.

### 04 — invitation consent and matching

1. Member A enables invitation settings and creates an availability with only minimal shareable fields. Before consent, availability creation must be rejected.
2. Invitation matching is launch-gated. For local testing, set `TRIPPALS_INVITATION_MATCHING_CITY_IDS` to the one disposable `city_id`, restart `make up`, and never enable an unapproved city.
3. As the host, list activity-scoped candidates, send to selected `recipient_ids`, then switch to the recipient token to list/show/decline the invitation or join with its ID.
4. Check candidate and inbox responses never disclose itineraries, accommodation, exact availability, contact details, or opt-out population counts.

### 05 — safety and moderation

1. With the member token, block then unblock `target_user_id`; a self-block must fail. A block conflict must prevent joining/inviting/chatting where applicable.
2. Submit a synthetic report, capture `report_id`/`case_id`, and request evidence intent only as its reporter. Reporters are not exposed in member-facing reports.
3. Use a moderator token to list the case queue, assign the case, impose a restriction with an explicit reason, and review a captured appeal. Repeat an admin request with the member token to verify `403`.
4. Inspect the database/test suite only for immutable audit evidence; API replies must not expose report evidence or reporter identity.

### 06 — notifications and device privacy

1. Read/update notification preferences and list notifications. Mark a captured notification as read; a foreign notification ID must be `404`.
2. Register the synthetic device token, capture `device_id`, and delete it. Responses must expose no raw token/ciphertext. Push payload tests should contain identifiers and event context only—never chat text, directions, availability, or evidence.

### 07 — private media

1. Create an avatar intent for `image/png` and the exact one-pixel PNG in the collection. Capture `media_id` and `upload_token`, upload with `X-Upload-Token`, then confirm.
2. Retrieve a short-lived access token and fetch content with `X-Media-Access-Token`. Try the same ID/token as another user and expect denial.
3. For report evidence, first create a report, then request `POST /reports/:report_id/evidence/upload-intents`. Validate unsupported type, incorrect byte size/signature, expired capability, and unconfirmed access are rejected. The collection contains no real evidence.

### 08 — deletion and release checks

`DELETE /v1/me` is intentionally the final, destructive request. It requires recent authentication; use a disposable account only. Confirm the account is immediately blocked from normal use, credentials/sessions are revoked, private media is inaccessible, and the retention/erasure job records remain server-side rather than in public API output.

Before handing changes off, run:

```sh
make format-api
make test-api
cd apps/api/service && MIX_ENV=test mix trip_pals.validate_openapi && mix precommit
```

## Endpoint inventory

The collection covers the public route surface below. “Role” is the minimum authorization requirement; all `POST`, `PATCH`, and `DELETE` endpoints also need an idempotency key.

| Feature | Routes | Role |
| --- | --- | --- |
| Operational/discovery | `GET /up`, `/ready`, `/v1/hello`, `/v1/cities`, `/v1/activities`, `/v1/activities/:id`, `/v1/activity-ideas` | Guest |
| Session and identity | `POST /v1/auth/refresh`, `/logout`, `/auth/passkeys/authenticate/options`, `/authenticate/complete`, `/auth/:provider/complete`; member passkey register routes; `DELETE /auth/session`, `/me/passkeys/:credential_id`, `/me/identities/:provider` | Guest/member as applicable |
| Profile and deletion | `GET/PATCH /v1/me`, `DELETE /v1/me` | Member (recent auth for destructive auth changes/deletion) |
| Activities | `POST /v1/activities`; `GET/PATCH /v1/activities/:id`; publish, confirm, start, finish, cancel commands | Member/host owner |
| Participation | interest, join, leave, reconfirm, attendance; `GET /v1/me/plans` | Member |
| Conversations | `GET/POST /v1/conversations/:id/messages`; authenticated socket | Going member |
| Invitations | settings, availabilities, candidates, sends, inbox, show, decline | Member/eligible host; consent + launch gate |
| Safety | restrictions, reports, blocks, appeals | Member |
| Moderation | case queue, assign, restrict, review appeal | Moderator |
| Notifications | notifications, preferences, devices, mark-read | Member |
| Media | avatar/report-evidence intents, upload, confirm, access, content | Owning/authorized member |

The machine-readable OpenAPI file remains the versioned contract for endpoints it describes; this guide and collection are executable workflow documentation for the complete shipped API surface.
