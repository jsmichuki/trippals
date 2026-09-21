# TripPals — MVP Plan and Detailed User Flows

**Version:** 1.1 (brand updated to TripPals)  
**Date:** 19 September 2026  
**Source:** `nomadtable_competitive_teardown_and_prd.md` from the project resources (originally prepared under an earlier working name), informed by the supplied Nomadtable listing and review exports.  
**Status:** Proposed plan. Targets, timelines, prices, and operating rules below are hypotheses or design decisions to validate, not established customer or business results.

---

## 1. Brand and positioning

### Selected name: TripPals

**TripPals** is the selected product name, replacing the earlier working name used in the initial planning documents. The name communicates friendly travel companionship and can encompass spontaneous small-group activities, connections with local residents, and future trip coordination.

**Brand direction:** TripPals — Find your people. Make a real plan.

**Naming considerations:** The name may suggest companions for entire trips rather than individual meetups, so the descriptor below should make the core activity experience clear. Trademark, domain, social-handle, and app-store availability have **not** been verified; check them before public launch or major brand spending.

- **Tagline:** Find your people. Make a real plan.
- **Descriptor:** Group meetups for travelers and locals.
- **Short pitch:** Discover, join, and organize small-group activities with fellow travelers and locals. Confirm the plan, coordinate easily, and explore together.
- **Category framing:** Friendship-first travel activities; not dating, lodging, or a general social feed.

## 2. Product thesis and MVP objective

**Vision:** Help people feel connected in a destination through reliable, respectful, in-person small-group activities.

**First target user:** A solo traveler staying roughly 2–14 days in one destination who wants a public-place activity today or tomorrow. **Additional participants:** local residents, longer-stay travelers, and digital nomads. **Supply side:** a small cohort of dependable traveler and resident organizers.

**Aha moment:** A participant reports attending a worthwhile activity with people they had not previously met. An RSVP or message alone is not the delivered outcome.

**MVP hypothesis:** If a traveler can see credible upcoming activities before signup, join one easily, receive clear confirmation and logistics, and communicate with a real group, more travelers will make it to an actual meetup and consider using the app again.

**Initial boundaries:** One launch city; public-location social activities (coffee, casual meals, walks, sightseeing, cultural outings); typically three to six people per activity, including the host. This group size is a design default, not a hard universal limit. Essential features are free. Do not promise guaranteed attendance or safety.

**Primary outcome:** Weekly completed meetups with credible, privacy-appropriate evidence that people met in person. Distinguish *host concluded*, *participant self-reported attendance*, and *independently verified* (the MVP does not independently verify physical attendance).

## 3. Why these requirements exist

The supplied teardown identifies a useful incumbent core: spontaneous traveler activities and real friendships. It also documents reviewer-reported friction around slow and unreliable chat, long onboarding, compulsory GPS, paid gates on social participation, unwanted approaches, unreliable RSVPs, poor event logistics, unclear event completion, opaque suspensions, and disguised promotions. Those reviews are self-selected reports, **not** verified population-level defect rates or proof about every current version of the incumbent.

TripPals's key product responses:

| Source-derived need | MVP response |
|---|---|
| Show value before asking for private information | Guest city browsing and honest empty states |
| Help travelers make a real plan | Complete event details, status, host confirmation, attendee confirmation |
| Reduce missed meetups | Reminders, change notifications, permanent logistics and reliable group chat |
| Make hosting straightforward | Explicit create → confirm → start → conclude/cancel flow |
| Respect the friendship-first use case | Group-first interaction; no unrestricted stranger DM or swiping |
| Preserve trust | Report/block, clear rules and enforcement notices, human review for consequential appeals |
| Keep the local network useful | Free core discovery, posting, joining, and event communication; launch in one seeded city |

## 4. User roles, permissions, and core jobs

| Role | Job | MVP abilities |
|---|---|---|
| Guest | Determine whether the app is useful in a city | Search a city, filter, view eligible public activity previews; no participant details or chat |
| Member / traveler | Find and attend a group activity | Complete minimal profile, express interest, join, chat, leave, report, confirm own attendance |
| Member / resident | Socialize with travelers and locals | All member abilities; optionally identify as resident in profile |
| Organizer | Bring a group together reliably | All member abilities; create/edit/confirm/start/conclude/cancel own activities, view participant statuses |
| Moderator / support operator | Keep the service usable and respond to reports | Review activity and account reports, take proportionate action, send notices, handle appeals, view operational audit trail |

One member account may be both a traveler/resident and an organizer. A resident label is self-declared; it is not a verified identity credential.

## 5. MVP functionality: build versus defer

### P0 — required for launch

1. Guest discovery; manual selection of supported city; activity list with date/category/availability filters; honest empty and error states.
2. Reliable authentication; minimal profile, optional interests, 18+ age gate for the proposed adult-only pilot (verify local product/legal requirements separately); consent to community rules; account recovery and deletion.
3. Structured activity creation: title, category, description, city, local start/end times and timezone, public meeting venue/area, approximate cost and any mandatory external charges, capacity, host, participation rules.
4. Discovery and details with state, host confirmation, separate interested/going counts, and clear join or interest action.
5. Participant lifecycle: interested → going → left; capacity-aware and concurrency-safe joining; organizer-attendee messaging; optional reconfirmation reminder.
6. Activity lifecycle: draft → published → host-confirmed → in-progress → completed/canceled, with expired/unconfirmed handling; editing rules and attendee notifications.
7. Durable activity group chat for going members and host; pinned immutable-to-chat logistics; send/error/retry UI; deep links; basic abuse controls.
8. My Plans (going, interested, hosting, past/canceled); push/in-app notifications with granular settings for nonessential notifications.
9. Reporting, blocking, content rules, restriction notice and appeal/support route; internal report queue and audit trail.
10. Analytics, crash/error monitoring, data minimization, basic accessibility, testing on slower phones and intermittent connectivity.

### P1 — after completed meetups are reliably occurring

Interactive activity map; future-trip planning; optional one-to-one contact requests with recipient controls; additional discovery filters as density permits; factual host history; optional non-renewing travel pass for planning convenience; additional cities after local launch gates are met.

### P2 — later experiments

AI suggestions, large city chats, sponsored/verified commercial listings, bookings and ticketing, complicated feed or swiping mechanics. No mandatory public people ratings.

**Free-core rule:** No paywall on previewing public activities, creating an ordinary noncommercial activity, joining, leaving, activity chat, essential updates, or safety controls. MVP includes no purchase screen.

## 6. Navigation, screens, and screen contract

**Bottom navigation:** Discover · My Plans · Chats · Profile. A prominent **Create activity** action appears in Discover/My Plans. Full-screen activity details and chat open on top of the tabs; returning preserves the previous city, filters, and list scroll position.

| ID | Screen | Key elements and actions | Required states |
|---|---|---|---|
| S01 | Welcome / guest entry | Value statement; Explore activities; Sign in; safety/community link | Initial, offline |
| S02 | City picker | Search supported cities; city label; clear unsupported-city response; optional location prompt *only if chosen* | Results, none, error |
| S03 | Discover | Selected city; Today/Tomorrow/7 days; activity categories; list cards; create CTA | Loading skeleton, results, no matches, no city supply, offline, retry |
| S04 | Activity details | Schedule/timezone; public venue or general area; costs; host intro; host/event status; available seats; interested vs going; share; report; join/interested | Guest, signed-in, interested, going, full, canceled, past, removed |
| S05 | Sign up / sign in | Email magic link or password-based method with reliable recovery; supported native auth; return-to-intended-action | Validating, sent, expired, error, success |
| S06 | Minimum profile | Display name; profile image (optional or a safe avatar fallback); age eligibility confirmation; user type traveler/resident/other (optional); rules consent; privacy default | Validation, upload failure/retry, save success |
| S07 | My Plans | Upcoming Going, Interested, Hosting, Past; activity status badges | Empty per section, canceled, updated |
| S08 | Activity chat | Event title and pinned logistics; member list limited to appropriate participants; messages and retry; report/block; notification controls | Connecting, loaded, delayed, send failed, removed from group |
| S09 | Create / edit activity | Guided fields; preview; save draft; publish; disclose any financial/commercial affiliation | Unsaved changes, validation, offline draft, moderation review, published |
| S10 | Organizer activity dashboard | Status; list/count of interested/going; confirm, edit, start, conclude, cancel; chat entry | Confirmable, full, low turnout, missed deadline, finished |
| S11 | Post-event check-in | Did you attend? yes/no/prefer not to say; optional private experience feedback; report incident | Optional, submitted, skipped, window expired |
| S12 | Profile & settings | Basic profile, contact visibility, notification settings, rules, support/appeal, sign out, delete account | Normal, deletion confirmation, restricted |
| S13 | Report / block | Object, reason, optional description/evidence, block independently; urgent safety guidance | Submitted, duplicate, failed/retry |
| S14 | Admin console (internal web) | Queues, event/user records, action reasons, notifications, appeals, audit log | Assigned, pending, resolved/escalated |

**Guest privacy:** Do not expose private participant rosters, personal contact details, detailed profiles, chats, or someone's live GPS. A guest may see public event time, category, host's public display name, general meeting area, cost, available places, and appropriately aggregated going count. Exact meetup instructions can become visible only to confirmed participants when necessary.

## 7. Detailed user flows

### F01 — First-time guest finds an activity

**Trigger:** Someone hears about TripPals, opens the app or a shared public activity link.

1. Show S01 with **Explore activities** as an equal, prominent choice to **Sign in**; no paywall, ratings prompt, or forced GPS request.
2. On Explore, open S02. If an invitation link includes a valid city and public activity ID, resolve the activity directly, then allow city changes.
3. Visitor searches for a supported city and selects it. Persist the chosen city locally for guest convenience; location permission is not requested.
4. Open S03 for that city. Show a small set of upcoming, eligible public activities with clear local dates, type, approximate area, going count, and seats remaining.
5. Visitor filters to today/tomorrow or a category, then opens S04 for an activity.
6. On S04 show the full public plan, cost disclosures, whether the host has confirmed, and **Interested** and **Join activity** actions.
7. If they choose Join/Interested, start F02 and preserve `returnTo=activityId` and `desiredAction`.

**Exceptions:** Unsupported city → disclose that no community has launched there; let visitor change city and optionally register interest *without fabricated activities*. No matching activities → remove filters and show the next genuinely scheduled option, if any; never display old, canceled, or placeholder events as live. Connection failure → retain city/filters and show retry without navigating to an unrelated screen. Full/canceled activity → read-only details and other eligible activities.

**Acceptance:** Guest reaches a useful public preview without account creation or precise GPS. A deep link preserves the same activity after sign-in. Initial design target: under one minute to a relevant preview in an adequately supplied launch city, excluding external network delays.

### F02 — Sign in and minimal profile, then resume the action

**Trigger:** Guest presses Join/Interested/Create, or taps Sign in directly.

1. S05 offers at least one email-based method with recovery and supported native sign-in; explain only what data is needed.
2. User authenticates. If an existing profile is complete, return to the saved action immediately.
3. For a new account, show S06. Require only a display name, confirmation of adult eligibility for the proposed pilot, and acceptance of community rules/privacy terms. Allow a safe default avatar if photo upload fails; ask for bio, interests, languages, and resident/traveler label progressively or optionally.
4. Apply privacy-protective defaults: no stranger direct messages (there are no DMs in P0), no live-location exposure, optional marketing notifications off.
5. Save profile; return to the exact activity or creation form. Re-fetch current activity state before attempting a join.
6. Complete the originally requested action if still valid, or explain if the event has filled or changed while signing in.

**Exceptions:** Auth timeout/magic link expired → reissue securely without erasing saved action. Already registered email with another method → offer account recovery/linked sign-in, not an unexplained error. Photo upload fails → keep placeholder and let user continue. Ineligible age → do not create an active participation account. Restricted account → display restriction status and support/appeal path as appropriate; do not silently send to Discover.

**Acceptance:** No onboarding rating prompt, no required GPS, no purchase or long questionnaire; previous activity and intent survive authentication.

### F03 — Member joins or expresses interest in an activity

**Trigger:** Signed-in member opens S04 for a published eligible activity.

1. Display precise event start time **in the event city's timezone**, end time, place/public venue, any fees, seats, host-confirmation status, and activity rules.
2. Tap **Interested** to bookmark/express tentative interest without taking a seat or joining the chat. Count it separately from Going. User may change to Going later.
3. Tap **Join activity** to declare intent to attend. Confirm any mandatory fee paid outside the app is clearly disclosed; if the event is ineligible, show why.
4. Server atomically checks capacity, start cutoff, block/moderation restrictions, duplicate membership, and current event state. If valid, create/update participation to Going and reserve one seat.
5. Show **You're going** with event state: `Awaiting host confirmation` or `Host confirmed`. Provide **Open activity chat**, **View meeting details**, **Add to calendar** (optional native share/export), and **Leave activity**.
6. Add activity to S07 Going and chat to S08. Notify host of a new Going participant where enabled.
7. If the host has not confirmed by the policy deadline, show that clearly and issue an automatic host reminder; do not imply the event is guaranteed.

**Exceptions:** Last seat taken concurrently → show Full and do not add participant or chat access; optionally retain Interested status without holding a seat. Event changed materially → require member acknowledgment of changed time/venue before confirming if the change occurred between read and join. Organizer blocked member or vice versa → reject conflicting participation with a neutral explanation, without exposing the other user's privacy settings. Leave → immediately free the seat, remove write access to event chat, retain limited event history, and notify host of relevant changes. No show is not automatically assigned just because a user failed to click a button.

**Acceptance:** Interested and Going never inflate each other's counts. Two simultaneous joins cannot overbook the final seat. An authenticated member can access event chat for an activity they have joined without paying.

### F04 — Organizer creates and publishes an activity

**Trigger:** Signed-in member taps Create activity.

1. Open S09 with city inherited from Discover, editable within supported cities. Show a concise activity template such as Coffee, Walk, Meal, or Culture.
2. Enter a human-readable title, description, category, language (optional), local start and end time, IANA timezone inferred from selected city, publicly safe venue or general meeting area, approximate price and **any unavoidable cover, entry, purchase, or booking fees**, and total capacity (including organizer).
3. Require a contactable, participating host; clarify that an ordinary personal meetup is free to publish and commercial promotion is not part of MVP. Disallow hidden paid promotions or unsupported commercial organizers pending review.
4. Show public preview and a checklist of required fields. Save draft at any time; restore it after app interruption. Warn before discarding unsaved edits.
5. On Publish, server validates date/time ordering, future start, capacity, supported city, basic duplicate/spam signals, and content/rules. If clean, mark Published and show organizer dashboard S10. If review needed, show `Pending review` with reason category and accessible support path, not a silent disappearing listing.
6. Organizer can share a public event link and invite people to a plan without forcing them to register just to view it.
7. Ask organizer to confirm the plan is proceeding before the confirmation deadline; send reminders when appropriate.

**Exceptions:** Venue/time missing → inline field error, retain all other entries. Start time already passed → block publishing. Network drops during publish → idempotency key prevents duplicate events; show pending/retry rather than creating another. Near-identical events from same host → warning/manual moderation, not an automatic unexplained ban. Editing an already published event follows F06.

**Acceptance:** Cannot publish an activity without usable timing, place, costs, capacity, and organizer. Drafts are distinct from live activities. Clear publication state and next host action are always available.

### F05 — Host and attendees confirm that the plan is going ahead

**Trigger:** A published activity receives RSVPs and approaches its start time.

1. S10 shows organizer the Going and Interested counts separately, activity time, and a **Confirm activity** button.
2. Organizer reviews details and selects Confirm activity; server transitions Published → Host confirmed when the host is still eligible and details are valid.
3. All Going members receive an in-app event update and push notification if enabled; S04/S07 display `Host confirmed` clearly. Confirmation is an intention to proceed, not a guarantee.
4. At a configurable reminder time (proposed 24 hours and/or 2 hours before start, adjusted for last-minute events), send attendees `Still going?` with **Yes, I'll be there** and **I can no longer attend**; not answering does not silently remove an attendee unless an explicitly disclosed event policy calls for reconfirmation.
5. Host sees voluntary reconfirmation states distinct from actual attendance. Host may contact the group through event chat to coordinate meeting instructions.
6. At start, host can tap **Start activity**; if they forget, display time-aware status and enable appropriate late action rather than pretending it occurred.

**Exceptions:** Host does not confirm by a proposed deadline (for example, two hours before start) → mark `Unconfirmed — do not travel based on this listing alone`, notify Going members, and surface cancel/confirm controls to host; define an operator-assisted decision or automatic expiry before start. Member leaves after host confirmation → update seat count and host view. Host cancels → F06, notify all Going members immediately.

**Acceptance:** Host-confirmed, attendee-going, attendee-reconfirmed, and attended are independent data fields. No UI refers to Interested users as confirmed attendees.

### F06 — Edit, reschedule, cancel, expire, and conclude an activity

**Trigger:** Host opens S10 and selects a lifecycle action.

**Edit:** For non-material copy edits, publish the update with a clear change record. For start time, meeting location, essential cost, or significant plan change, show host a warning, update the event revision, notify Going users, and mark their acknowledgment as pending. For major changes close to start, consider requiring a fresh RSVP; implement one transparent rule and test it. Do not silently move a participant to a materially different activity.

**Cancel:** Require host to select a reason or enter a short explanation; transition to Canceled; immediately remove from live discovery, notify all Going users, preserve chat as limited read-only history for a defined retention window, and show cancellation in My Plans. Guests following the public link see Canceled and cannot join.

**Expire:** If an event passes the confirmation deadline without a valid host confirmation, apply a clearly announced unconfirmed/expired policy; if the start time passes without a host start or completion, escalate for host follow-up and ultimately archive as `Unverified outcome`, **not** automatically `Successfully completed`.

**Start:** Host transitions Host confirmed → In progress at/near the scheduled time. Pin latest logistics and preserve the event chat while active.

**Conclude:** Host taps **Finish activity** after the event, optionally records whether it occurred and a factual count estimate. Transition In progress or eligible past event → Completed (host-reported) and open the participant check-in F08. Never require deleting an event to conclude it. Automatically close stale events after a grace period as `Outcome unknown` unless evidence supports completion.

**Acceptance:** The same action cannot generate duplicate notifications or invalid transitions. Terminal states leave Discover but remain appropriately visible in participants' history.

### F07 — Activity group chat and meeting-day coordination

**Trigger:** Going participant or host opens Chat from S04 or S07; push notification links into the same event chat.

1. S08 opens the correct activity conversation, with the **meeting time, public meeting point, host-confirmation status, and essential cost** pinned above messages.
2. Load newest messages promptly; allow reading recent cached messages and pinned logistics under intermittent connectivity. Show an explicit stale/offline indicator.
3. User sends a text message; render Sending → Sent or Failed with Retry. Use stable client message IDs and server deduplication so reconnecting never creates duplicate messages.
4. Changes to time or venue appear as structured event updates, not only a chat message. Tapping an update opens current activity details.
5. Tapping a push notification opens S08 for the related event; if access was revoked or the activity was canceled, open a useful explanation or event history instead of the app home screen.
6. User may mute nonessential chat pushes, leave, report a message, or block another account using a clear safety menu.

**Exceptions:** Offline send → queue locally only if storage/retention is safe, show pending and retry; never display as delivered until acknowledged. Server rejects message because user left/was removed → show failed and disable compose, retain allowed history. Blocked person in same group → hide or collapse their content consistently, prevent prohibited direct interactions, and allow escalation; do not promise they are physically absent from an event. System moderation action → provide appropriate user-facing reason and appeal path without exposing reporter identity.

**Acceptance:** Event details remain accessible when chat transport fails. Chats persist across app restarts and changing the browsing city. No unrestricted stranger DMs in P0.

### F08 — Attending, ending, and voluntary feedback

**Trigger:** Event reaches its end time or host taps Finish activity.

1. Host sees a clear Finish activity CTA and records whether the meetup actually occurred; host-reported conclusion is labeled as such.
2. Participants receive optional S11 check-in: **Did you attend?** Yes / No / Prefer not to say. Skipping is allowed and does not force a public rating.
3. Optionally ask whether the meetup was worthwhile and whether there were any logistics or safety issues. Keep private satisfaction feedback distinct from a formal abuse report and explain which information is visible to moderators.
4. Show the activity in My Plans → Past with transparent labels such as `Host marked completed` and `You reported attendance`, not a falsely verified count.
5. Present contextual **Find another activity** or **Host a similar activity**; ask for a share/referral only after actual reported attendance and with consent.

**Exceptions:** Host absent and meetup did not occur → user chooses No, reports issue if desired; event remains canceled/unknown according to evidence. Participant alleges a safety issue → route to report and urgent escalation guidance; never substitute a satisfaction rating. Members can decline check-in without losing their account or ability to join future activities.

**Acceptance:** Event completion can be initiated explicitly; attendance confirmation is voluntary and attributable to its source; no compulsory rating of other people.

### F09 — Safety, blocking, reporting, and appeals

**Trigger:** User selects Report/Block on an activity, profile, or message, or receives an account restriction.

1. Open S13 with the correct object attached and clear categories (harassment/unwanted sexual contact, spam/scam, misleading commercial activity, hate/abuse, safety concern, other); optionally attach context, without requiring a lengthy narrative.
2. Provide **Block account** independently of reporting. Apply block/contact restrictions across relevant profile visibility, join/invite eligibility, and direct interaction. In a shared group, explain the remaining visibility implications.
3. Submission yields a case ID and status; user can access support without exposing the reporter's identity to the reported user.
4. Admin S14 prioritizes urgent physical-safety reports, reviews evidence under limited permissions, takes proportionate action, and records action, reason, operator, and time.
5. If account or listing is restricted, display a specific policy category and meaningful explanation to the extent safe and lawful; show duration/effect and how to appeal. Consequential permanent actions require human review or accessible human appeal.
6. User files appeal; operator reviews and sends a response, including whether restrictions remain, change, or end. Do not promise a particular outcome.

**Exceptions:** Immediate danger → provide practical local emergency guidance and in-app escalation, without suggesting app moderation replaces emergency services. False/malicious reports → track patterns while preserving genuine reporting access. A blocked user's shared event membership may require further organizer/moderator intervention, not a misleading safety guarantee.

**Acceptance:** Report and block controls work from chat and activity details; no unexplained silent suspension; report and appeal actions have a trackable operational route.

### F10 — Empty city, no supply, and returning traveler

**Trigger:** Visitor or member selects a city with no relevant activities or returns after a long gap.

1. Show the factual empty state: `No upcoming activities here yet` (or `No matches for these filters` where supply exists).
2. Offer **Clear filters**, **See next 7 days**, **Create an activity** (requires sign-in), and **Change city**; optionally collect consent to hear when this city launches.
3. Do not show fake users, manufactured Going counts, expired events, or a paid upgrade as the solution to a supply problem.
4. Returning signed-in user lands on upcoming confirmed My Plans when relevant, otherwise restores their last chosen city and sees current activities.
5. A city switch changes Discover, not membership in existing events or their chats; trip-based return usage is measured separately from daily app opens.

**Acceptance:** The product remains truthful and useful when local liquidity is low. No registration is required merely to find out a city is unsupported.

## 8. Core state machines and business rules

### Event state machine

```text
DRAFT ──publish──> PUBLISHED ──host confirms──> HOST_CONFIRMED
  │                    │                              │
  └──discard            ├──cancel/expire              ├──start──> IN_PROGRESS
                       │                              │                │
                       └──unconfirmed at deadline      └──cancel        ├──finish──> COMPLETED_HOST_REPORTED
                                  │                                     └──unresolved──> OUTCOME_UNKNOWN
                                  └──EXPIRED/UNCONFIRMED

Published / Confirmed / In progress ──eligible cancel──> CANCELED
```

**Source of truth:** Server, not device clock. Store timestamps in UTC and the activity's IANA timezone; render in the event city's local timezone with timezone label when users travel. `COMPLETED_HOST_REPORTED` is a product-level operational status, not independent verification of physical attendance. Archived/removed activities must never reappear as active simply because a device has stale cached data.

### Participation state machine

```text
NONE ──mark interested──> INTERESTED ──join──> GOING ──leave──> LEFT
  └─────────────join───────────────────────> GOING
GOING ──optional reminder yes──> GOING + reconfirmed_at
GOING ──event ends──> ATTENDANCE_UNKNOWN / SELF_REPORTED_YES / SELF_REPORTED_NO / DECLINED
```

**Capacity:** Going reserves one place; Interested does not. The organizer consumes a place if attending; maintain `goingCount + hostSeat <= capacity` using a single atomic server transaction or equivalent constraint. Repeated Join/Leave requests are idempotent. Canceling/removing an account must release applicable future-event seats and revoke chat access.

**Disclosure:** A seat labeled Going is a declared intention, not actual attendance. Do not display `3 attended` merely because three users RSVP'd.

### Timing defaults to test in the pilot

- Show activities happening today through the next seven days; default sort by event-city start time with sensible status/availability treatment.
- Remind the host to confirm ahead of start; for last-minute activities use a shorter, explicit confirmation window. Proposed two-hour cutoff is a test assumption.
- Notify attendees on material venue/time/cost changes, host confirmation, cancellation, and near-start reminders. Allow mute of promotional/nonessential updates, not loss of essential event status inside the app.
- Set a clear start-time cutoff for new joins, with host-controlled exceptions only if product rules make that safe and understandable.

## 9. Data model and authorization (implementation-ready sketch)

| Entity | Minimum fields |
|---|---|
| User | `id`, `auth_provider`, `created_at`, `account_status`, `age_eligible_at`, `rules_version_accepted`, `deleted_at` |
| Profile | `user_id`, `display_name`, `avatar_url?`, `intro?`, `interests[]?`, `residency_label?`, `home_city_id?`, `contact_preferences` |
| City | `id`, `name`, `country`, `iana_timezone`, `launch_status` |
| Activity | `id`, `host_id`, `city_id`, `title`, `category`, `description`, `start_at_utc`, `end_at_utc`, `iana_timezone`, `public_area`, `participant_meeting_details?`, `cost_amount?`, `cost_currency?`, `cost_description`, `capacity_total`, `status`, `host_confirmed_at?`, `version`, `created_at`, `updated_at` |
| Participation | `activity_id`, `user_id`, `status` (interested/going/left), `reconfirmed_at?`, `attendance_self_report?`, `attendance_reported_at?`, `created_at` |
| Event revision | `activity_id`, `version`, `changed_fields`, `changed_by`, `changed_at`, `material_change_flag`, `participant_acknowledgment_state` |
| Event conversation | `id`, `activity_id`, `visibility`, `created_at`, `archived_at?` |
| Message | `id`, `conversation_id`, `sender_id`, `client_message_id`, `body`, `created_at`, `moderation_status` |
| Notification | `id`, `recipient_id`, `type`, `activity_id?`, `message_id?`, `created_at`, `read_at?`, `delivery_state` |
| Report/case | `id`, `reporter_id`, `target_type`, `target_id`, `category`, `evidence_reference?`, `case_status`, `assigned_operator?`, `created_at`, `resolved_at?` |
| Restriction/appeal | `id`, `user_id`, `reason_category`, `effect`, `duration?`, `notice_delivered_at?`, `appeal_status?`, `reviewed_by?`, `audit_log_reference` |
| Block | `blocker_id`, `blocked_id`, `created_at` |

**Enforce server-side permissions:** Guests read only public event fields. Members can edit only their profiles and participation. Hosts can modify only their eligible activities. Event chat is readable/writable only under documented membership/retention rules. Moderators have least-privilege scoped access with auditable actions. Deny access to private meeting detail fields in guest responses, logs, notifications, and link previews.

**Security/privacy basics:** Rate-limit account creation, join, chat, and reporting endpoints. Protect against enumeration and spam. Use managed authentication and encrypted transport/storage. Define retention/deletion policy and evaluate applicable requirements for the chosen launch country before launch. Do not collect continuous background location for this MVP.

## 10. Suggested technical delivery approach

A pragmatic founder-budget implementation could use one cross-platform app (Flutter or React Native, chosen according to team experience), a managed relational backend with transactional RSVP logic, managed authentication, object storage, real-time chat or a managed messaging service, push delivery, and a simple protected admin web console. This is an implementation proposal, not a requirement for specific vendors.

**Architecture priorities:**

- Model activity and RSVP state in one authoritative backend, separate from UI and chat delivery.
- Make publish/join/leave/change/cancel operations idempotent and transactionally safe.
- Store event logistics separately from messages; cache them for poor network conditions.
- Make notification payloads carry stable event/conversation IDs for correct deep linking.
- Instrument failure rates and latency before opening the pilot broadly.
- Prefer managed service components where they reduce risk, but verify data access, cost, and support requirements for the initial geography.

## 11. Build sequence and acceptance gates

| Phase | Proposed work | Exit gate |
|---|---|---|
| 0. Research / supply validation | Interview ~20–30 travelers and ~10 possible organizers, choose one launch city, recruit partner venues/hosts; run a lightweight concierge pilot | Repeatable attendance at real manually organized meetups; evidence on no-shows and acceptable group sizes |
| 1. Foundation | Auth, profile, cities, public activity feed/details, project analytics, logging | New guest can reach a real activity preview without GPS or signup; login and photo fallback work |
| 2. Participation | Create/publish, interest/join/leave, atomic capacity, My Plans, event lifecycle | Host can publish and confirm; member can join without overbooking; cancel removes from feed |
| 3. Coordination | Activity chat, pinned logistics, event revisions, notifications, deep links, offline/error states | Users receive essential updates and retrieve the correct chat/plan on weak connections |
| 4. Trust and completion | Report/block, admin queue, moderation notice/appeal, attendance check-in, deletion | Host can finish; attendee can voluntarily report attendance; reports are actionable and traceable |
| 5. Controlled launch | Seed recurring events, field-test logistics, improve performance, moderate active community | Local completion/attendance and safety guardrails support sustainable expansion |

**Resourcing assumption:** A small multidisciplinary team (product/design, 1–2 mobile/full-stack engineers, part-time QA, and a named community operator) can sequence the work, but the actual calendar depends on existing code, vendor selection, legal review, and organizer availability. Avoid promising a fixed launch date before estimating the implementation and running the concierge pilot.

## 12. Priority QA and end-to-end acceptance tests

- Guest selects city with GPS denied → public results remain usable; no account wall until Join/Create/Chat.
- Shared event URL → user signs in → returns to same event and action, or sees correct full/canceled state.
- Two users tap the last seat simultaneously → exactly one succeeds; Going count never exceeds capacity.
- User switches city or restarts app → joined event and chat remain in My Plans/Chats.
- A material time/venue change → Going members receive structured update and see latest pinned details.
- Phone goes offline mid-message → no false Sent status, queued retry does not duplicate the message.
- Push on slow-start device → opens correct event chat and accepts input without an unrelated navigation detour.
- Host confirms, starts, concludes, cancels, or misses deadline → only valid transitions and accurate history.
- Host forgets to finish → stale event is Outcome unknown, not silently considered completed.
- Blocking/reporting works from activity and chat; restricted member sees notice and appeal path without reporter information.
- Deletion removes public visibility and future seats, revokes session/chat access, and handles retained moderation records under documented policy.
- Test date/time across device timezone changes, daylight-saving boundaries in event locale, and cross-midnight activities.
- Accessibility: screen reader labels, text scaling, touch targets, non-color-only statuses, and keyboard/error focus.

## 13. Metrics and instrumentation

**North star:** Number of weekly activities with credible evidence of actual participation, reported separately by evidentiary level.

**Primary funnel:** `city_preview_viewed` → `activity_detail_viewed` → `join_attempted` → `join_succeeded` → `host_confirmed` → `attendee_reconfirmed?` → `event_concluded_by_host` → `participant_attendance_self_reported` → `repeat_join`.

| Metric | Meaning / guardrail |
|---|---|
| Time to first relevant preview | Speed to value in a supported city; proposed design target under 60 seconds on healthy connectivity |
| Preview → signup and detail → Going | Whether public previews create motivated participation; segment by city and activity type |
| Host-confirmation rate | Of published eligible events, share confirmed before the disclosed deadline |
| Going → self-reported attended | Track Yes/No/Unknown separately; do not treat nonresponse as absence or attendance |
| Host-reported completed meetups/week | Operational measure, displayed separately from participant corroboration |
| No-show and cancel reports | Trust/reliability, assessed alongside trip dates and host/activity cohorts |
| Message send success, chat open latency, crash-free sessions | Technical coordination quality; propose ≥99.5% crash-free sessions as a preliminary engineering target |
| Reports and resolution/appeal times | Safety and moderation quality, not an incentive to suppress reporting |
| First-trip successful meetup, repeat participation | More informative than daily active use for episodic travel |
| City supply/liquidity | Real eligible upcoming activities, remaining seats, host reliability, suitable timing by neighborhood/day |

**Privacy:** Do not publish participant-level attendance histories or public interpersonal ratings. Aggregate analytics where possible, honor deletion, and restrict sensitive moderation data.

## 14. Launch and community operations

**One-city launch:** Choose a destination after traveler/host interviews and partner feasibility, not simply because a city is famous. Recruit a small dependable organizer cohort (the teardown proposes about ten hosts running roughly two events per week as a *planning assumption*). Prefer recurring low-complexity activities at familiar public venues. Have a real operator confirm that scheduled plans are happening during the pilot.

**Supply before acquisition:** Do not spend heavily acquiring travelers into an empty city. Share authentic, publicly viewable activity links with local hostels, communities, and existing traveler networks. Referrals should come after a completed, worthwhile event, not directly after signup.

**Community practices:** Published event rules, clear host expectations, transparent commercial-disclosure policy, accessible incident response, backup host/alternative plan procedures where feasible, and realistic support coverage aligned with event times. Verification or moderation cannot guarantee personal safety; recommend appropriate public meeting practices without transferring responsibility for misconduct to victims.

**Launch readiness gates:** The full discover → join → coordinate → attend → conclude loop works; usable supply exists across a real set of days; chat and notifications pass weak-network tests; safety operations and support are staffed; organizers can complete events; permissions/deletion are tested; the product does not misrepresent activity counts or attendance.

## 15. Important open decisions

1. **Exact launch city:** choose after market-level traveler density, partner access, venue practicality, safety/operations, and local legal review.
2. **Join model:** instant Going for ordinary public activities in v1 versus host approval for selected formats; default recommendation is instant, capacity-controlled join.
3. **Late join / capacity:** define when someone can still join an in-progress event, if ever; default v1 is no late join after start without host action.
4. **Confirmation deadline and reminder schedule:** set with pilot data; proposed two-hour host cutoff is only a starting test.
5. **Attendance evidence:** treat voluntary attendee self-report and host conclusion separately, rather than declaring a meetup objectively verified.
6. **Profile image policy:** optional avatar fallback reduces onboarding failures; community interviews may reveal additional trust needs.
7. **Safety staffing and retention policy:** finalize before inviting a broad public audience.
8. **Brand availability:** conduct trademark, domain, handle, and store-name checks before launch; not verified in this plan.

## 16. Founder decision summary

**Build a reliable activity-to-attendance loop, not a comprehensive traveler social network.** The initial app must allow a guest to find real plans, a member to join them for free, a host to confirm and conclude them, and everyone involved to coordinate reliably with meaningful controls over safety and privacy. Seed one location with real organizers and measure actual completed meetups before adding maps, global chats, AI, or monetization.

---

**Reference:** Project resource `nomadtable_competitive_teardown_and_prd.md` (19 September 2026); project's Nomadtable store description and review exports. All branded positioning, workflow defaults, proposed thresholds, software architecture, and feature sequencing above are TripPals recommendations, not existing Nomadtable functionality or independently validated market facts.
