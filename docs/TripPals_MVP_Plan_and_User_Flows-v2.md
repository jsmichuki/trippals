# TripPals — MVP Plan & Detailed User Flows

**Version:** 2.0 
**Prepared:** September 20, 2026  
**Product:** TripPals — *Find your people. Make a real plan.*  
**Status:** Product proposal for design, validation, engineering estimation, and an initially limited launch; not evidence of implemented functionality.

## 0. Executive summary and change log

TripPals helps solo travelers and interested local residents **discover or organize real small-group activities, coordinate in a dedicated group chat, and meet in person**. The primary experience is activity-first, not a general traveler directory or dating-style social network. A completed, worthwhile meetup—not an install, profile view, invitation, or RSVP—is the intended user outcome.

### What changed from the previous MVP and the current six-screen wireframe

| Decision | v2 specification | Reason / constraint |
|---|---|---|
| Remove standalone duration screen | **No “How many days?” step** in onboarding or the primary discovery journey. | One fewer gate before the user sees real activities. |
| Dates move to Discover | An **optional editable date-range selector at the top of the activity discovery page**, alongside the selected city. | Browse first; refine without completing a questionnaire. |
| First-session journey | Welcome → city selection → Discover. Guests can preview legitimate public activities without creating an account or granting GPS. | Value before commitment, including truthful empty states. |
| Activity supply | Separate **Scheduled activities** (real, publishable events) from **Activity ideas** (templates only). | An idea is not a hosted or joinable event. |
| Group size | Activity organizer chooses a **total capacity of 2–10 people, including themself**. Suggested default: 6. | “Max 10 people” means the host + up to 9 other attendees. |
| Organizer-assisted invitations | After publishing, a host can optionally **invite discoverable, eligible people in the same city whose declared trip/availability overlaps the event**. | Help new activities find participants; never auto-enroll invitees. |
| Person discovery boundaries | **No general People going directory in the base MVP.** The narrowly scoped host invitation picker is the only person-suggestion surface; users opt in. | Prevent duplicating a full people-browsing, stranger-DM, and moderation product. |
| Group messaging | A **durable chat attached to each activity**, available to its host and Going participants, with pinned logistics and event system updates. | Essential coordination must survive city changes, app restarts, and poor connectivity. |
| Financial model | Discovery, ordinary hosting, invitations within limits, joining, chat, safety and event updates are free. **No MVP paywall.** | Avoid throttling early network liquidity. |

**Scope change vs. the earlier MVP:** The earlier proposal deferred future-trip matching and people discovery to P1. This version brings a **small, opt-in, activity-specific invitation picker** into P0 because it is part of the requested organizer experience. General traveler matching, saved multi-city itinerary management, private direct messaging, and automated group assembly remain later work. Whether this addition is operationally feasible should be validated in the concierge pilot and can be switched off per city without disabling ordinary hosting or joining.

### Provenance and evidence boundaries

This document revises the project resource `old/TripPals_MVP_Plan_and_User_Flows(old).md` (v1.1) and follows the problem framing of `old/nomadtable_competitive_teardown_and_prd.md`. That teardown synthesized the supplied Nomadtable listing and review exports. Reported concerns include lengthy onboarding, unreliable chat, no-shows, incomplete meetup details, unwanted contact, unclear moderation, and paywall/billing frustration. The reviews are self-selected accounts, not verified population-wide findings or measurements of TripPals. **All v2 UX rules, matching filters, invitation caps, group-size defaults, performance goals, and implementation recommendations are proposed design decisions to test**, not proven customer behavior.

---

## 1. Product thesis, target users, and success definition

**Job to be done:** “I am in—or will be in—a city, want company for a particular activity, and need a dependable way to find or gather a small group and agree on the plan.”

**Primary user:** Solo traveler on a short trip who wants a public-place outing today, tomorrow, or during a chosen visit. **Secondary users:** Local residents who opt in to meeting visitors, digital nomads, longer-stay travelers, and members who organize activities. One account can act as both participant and host.

**Core promise:** See genuine upcoming plans quickly; join an existing one or organize your own; invite eligible, willing people; use one activity-specific conversation and reliable logistics to meet.

**Aha moment:** A member actually participates in a worthwhile meetup. The product may only have host-reported completion and voluntary participant-reported attendance; it must not present these as independent verification.

**Pilot boundaries:** One supported city with deliberately seeded, real host supply; adult-only pilot as a product assumption subject to local review; public-venue, low-complexity social activities (coffee, casual food, walks, sightseeing, cultural outings). No transportation coordination or cash collection in the app. Host sets total activity capacity between 2 and 10 inclusive. The host occupies one seat. No claims of guaranteed safety or turnout.

**North-star measurement:** Weekly activities with credible evidence that an actual in-person meeting took place, reported by evidence source (host-concluded, at least one attendee self-report, multiple independent attendee self-reports). Secondary metrics: first relevant preview, join-to-meetup conversion, attendee-reported experience, repeat participation across trips, RSVP and host reliability, chat delivery, recipient opt-out/report rates, and safety response quality.

---

## 2. Product principles and non-negotiable rules

1. **Discovery first:** city → real activity feed, with optional date refinement directly on the feed. Never gate browsing on a trip duration, account, GPS, rating prompt, or payment.
2. **Honest inventory:** an activity idea is a template; a proposed but unhosted outing is not a scheduled event; an invitation is not attendance; a Going RSVP is not a verified meetup.
3. **Group-first:** participants connect around a specific activity. No unrestricted stranger DMs, public dating-like browsing, swiping, or mandatory ratings of other people.
4. **Explicit consent:** opted-out users are not listed in organizer suggestions. Hosts cannot inspect hidden travel dates or personal information through invitations.
5. **Reliable logistics:** time, timezone, safe public meeting area or venue, price and important changes are authoritative event fields outside chat. Chat can fail without destroying the plan.
6. **No involuntary participation:** being suggested or invited never adds a person to an activity or chat or reserves a place.
7. **Free core:** activity preview, ordinary creation, invitation, joining, messaging, notification of essential changes, reporting/blocking and appeals remain free.
8. **Accountability with recourse:** moderation should give appropriate, meaningful notices, support and appeal paths while protecting reporters and legitimate investigation needs.
9. **Geographic discipline:** a smaller city with reliably available activities is preferable to unsupported or empty cities presented as active.

---

## 3. Scope: P0, P1 and deliberate exclusions

| Workstream | P0: controlled launch | P1: after evidence of completed meetups | Exclude from v1 |
|---|---|---|---|
| Entry and discovery | Guest access; supported city picker; **top-of-feed date range**; Today / Tomorrow / Next 7 days shortcuts; category; actual activity list and honest empty states | Interactive map; richer filters; multiple saved trips; additional cities | Forced GPS; mandatory duration onboarding |
| Activity ideas | Small, curated, clearly labeled **idea templates**; “Organize this” pre-fills creation form | Optional interest expression on unhosted ideas; proposal-to-host conversion | Presenting ideas as existing meetups |
| Activities | Create, edit, publish, join, leave, interested/bookmark, host-confirm, start, cancel, conclude; capacity 2–10 including host | Waitlist, optional host approval for specific formats; more host insights | Public social scoring; automatic “completed” from elapsed time |
| Invitations | Opt-in activity-specific discoverability; limited host suggestions by city/date/availability; controlled batch invitation; accept/decline, expiry and revocation | Better relevance using explicit availability/interests; suggested groups; batching across recurring events | General people directory; unrestricted mass invitation or DMs |
| Group chat | Activity-specific text conversation; join-gated membership; pinned plan and system updates; durable delivery and retry; push/deep links; block/report/mute | Rich attachments/polls where justified; optional mutual-contact requests | Mandatory city-wide chat or automatic chats between strangers |
| Trust and operations | Report/block; clear rules; basic risk checks; moderation queue; restriction notices and appeal; participant privacy; account deletion | More comprehensive organizer history, optional verification and paid convenience | Verification as a safety guarantee; undisclosed commercial listings |
| Monetization | None; core free | Validate optional nonrenewing trip pass and openly labeled commercial programs separately | Pay-to-message, pay-to-RSVP, surprise recurring trial |

**P0 invitation rollout gate:** Build privacy, eligibility and abuse controls before enabling suggestion visibility. The host can still publish and share an activity link if matching is disabled, nobody opts in, or the city is too sparse.

---

## 4. Roles, permission model and navigation

| Role | Can see | Can do | Cannot do |
|---|---|---|---|
| Guest | Supported cities, eligible public activity cards/details, general meeting area, aggregate availability | Search and filter, open share link, begin sign-in when wanting to act | View private roster, full profiles, precise participant-only meeting directions or event chat |
| Signed-in member | Guest content, own activities/joins/invites, opted-in invitation settings | Bookmark interest, join/leave, receive invitations when opted in, read/write chats for their joined activities, report/block | Read a chat merely because they expressed interest or received an invitation |
| Host / organizer | Own hosted activity and permitted Going roster; eligible opted-in suggestion cards where matching is on | Publish/edit/confirm/start/conclude/cancel, invite within policy, view invitation and RSVP states | Reveal undisclosed stay dates, send arbitrary DMs to suggestions, exceed cap or bypass blocks |
| Invited member | Activity preview and own invitation state | Accept by explicitly joining, decline, disable future invitations | Enter chat or appear Going before joining |
| Moderator/support | Scoped content, reports, audit and appeal information according to role | Review, enforce, restore, document and notify | View unrelated private data or expose reporter identity to reported users |

**Bottom navigation after sign-in:** **Discover · My Plans · Chats · Profile**. A persistent **Create activity** CTA lives on Discover and My Plans. Invitations appear as an Inbox subsection of My Plans and through a notification destination (no new top-level tab required). Guests see Discover and clear contextual options to sign in. Switching Discover city or filters must not change memberships, invitations, or chats. Open event details/chat as stable ID-based routes and preserve feed scroll/filter state on return.

**No general People going tab in P0:** The organizer's **Invite people** sheet is a bounded workflow attached to one published activity. A standalone People tab can be designed only after opt-in, moderation capacity and liquidity are demonstrated.

---

## 5. Screen inventory and contracts

| ID | Screen / component | Visible actions and key data | Critical variants |
|---|---|---|---|
| S01 | Welcome | Simple value proposition; **Explore activities**; Sign in; community/safety links | Initial, offline |
| S02 | City selection | Search supported cities; optional featured supported cities; supported/coming-soon distinction | Supported, no results, unsupported, loading/error |
| S03 | **Discover** | Selected city, **date-range picker at top**, quick Today/Tomorrow/Next 7 days/Any upcoming shortcuts, category filters, Scheduled activities, distinct Activity ideas, Create CTA | Default dates, custom range, no matches, no city inventory, loading/offline |
| S03a | Date-range sheet | Start and end calendar dates; Apply, Clear/Reset; event-city timezone and selected range summary | Invalid reversed/past range, long range, timezone boundaries |
| S04 | Activity detail | Host and confirmation status; local date/time, general public area, price, available seats; Going vs Interested; Join/Interested/Share/Report | Guest, available, full, canceled, past, updated, Going, invited |
| S05 | Authentication | **Passkey**, **Continue with Google**, **Continue with Apple**; login-method recovery and intended-action resume | Passkey unavailable/canceled, provider cancel, restricted, conflict |
| S06 | Minimal profile | Display name, adult eligibility confirmation, community rules; optional photo and interests; safe privacy defaults | Validation, photo failure, existing account |
| S07 | My Plans | Going, Interested, Hosting, Invitations, Past/Cancelled; status and next action | Empty/active, invited, full, canceled, restricted |
| S08 | Activity group chat | Event header and **pinned authoritative plan**, Going member roster as permitted, messages, compose/retry, essential system messages, notification mute, Report/Block/Leave | Member, host, connecting/offline, failed send, member leaves, canceled/completed, moderation |
| S09 | Create/edit activity | Choose template or custom; details, timing, location, cost, capacity 2–10, preview, draft, publish | Field errors, moderation review, offline draft, publish retry, material revision |
| S10 | Host dashboard | Event state, host confirmation, occupancy, Going/Interested, Invite people, invitation results, edit/start/conclude/cancel, chat | Low turnout, full, pending review, cutoff missed, terminal |
| S11 | Invite people | Optional matching eligibility explanation; opt-in suggestion cards with limited public data; select/invite and quota counter | No eligible matches, opt-out, quota exhausted, blocked or pre-existing member |
| S12 | Incoming invitation | Inviter public name, event context, date/area/cost/status, Join, Decline, Report, manage preferences | Open, expired, revoked, full, canceled, already Going |
| S13 | Post-event check-in | Did you attend? Yes / No / Prefer not to say; optional private feedback and report | Host-reported complete, canceled, unknown outcome, skipped |
| S14 | Profile & settings | Optional visitor/resident info and interests; **Discoverable for activity invites**; availability dates if opted in; notification/privacy settings; passkey/login-method management; optional local app lock; deletion, support | Opted out/default, trip edited/expired, restricted |
| S15 | Report/block/appeal | Category, evidence/context, submit, independent block, case state, appeal path | Sent, failed/retry, escalation |
| S16 | Admin panel (internal) | Flagged activities/invites/messages/users; notices, appeals, audit trail | Pending, reviewed, actioned, overturned |

**Header behavior:** In S03 the city label and date selector remain visible at top as users scroll, or collapse into a clearly accessible compact header. The chosen range applies to **scheduled activities** and activity-date relevance; **activity ideas** are evergreen templates and must never be misrepresented as occurring during that range.

---

## 6. Canonical journey map

```text
OPEN APP / SHARED ACTIVITY LINK
    |
    +--> Welcome --> City picker --> Discover (real activities immediately)
    |                                  | [optional top date-range filter]
    |                                  +--> Scheduled event --> Details
    |                                  |                       +--> Interested/bookmark --> Sign in if guest --> My Plans
    |                                  |                       +--> Join --> Sign in if guest --> Capacity check
    |                                  |                                     --> Going --> Event chat --> Attend
    |                                  +--> Activity idea --> Organize this --> Sign in if guest
    |                                  |                                         --> Prefilled event form
    |                                  +--> Create activity --> Sign in if guest --> Event form
    |                                                                              --> Publish
    |                                                                              --> Host dashboard
    |                                                                                 +--> Invite people
    |                                                                                 |     --> Eligible opted-in suggestions
    |                                                                                 |     --> Send invitations
    |                                                                                 |     --> Invitee reviews --> Join or Decline
    |                                                                                 +--> Confirm --> Event chat
    |                                                                                 +--> Start --> Conclude / Cancel
    +--> Deep link to event/invitation/chat --> Resolve state + permissions
                                          --> relevant details, chat, or explanation

POST-EVENT: host-reported outcome + optional attendee self-reports --> Past --> Repeat/share
```

### Functional handoffs that must be preserved

- `cityId`, selected event-date range, category filters and Discover scroll position persist when opening/backing out of details or authentication.
- `activityId`, `intendedAction` and, for invited users, `invitationId` survive sign-in and return only to the **same** action after server-side revalidation.
- Activity membership and chat are indexed by **activity ID**, not by the currently viewed city or date filter.
- An organizer cannot invite anyone before the activity is actually published and eligible; a draft or pending-review activity is not inviteable.
- An invited person must explicitly **Join**; merely opening or accepting a notification is not a seat reservation or permission to read the group chat.

---

## 7. Detailed user flows

The flows below are written as screen-to-screen contracts. For each, the **server is authoritative** about event/participant/invitation state; cached UI is only a rendering aid.

### F01 — First visit, city selection, and immediate guest discovery

**Actor/trigger:** New visitor opens the app. **Entry:** S01 or a supported shared event link.

1. S01 offers **Explore activities** prominently and Sign in secondarily. No trip-duration question, forced GPS, purchase, or app-rating prompt.
2. Explore opens S02. Search suggests **supported** cities; unsupported cities are explicitly labeled unavailable or coming soon rather than shown as populated.
3. Visitor selects Nairobi; save a non-sensitive local preference for the current browsing city and open S03 immediately.
4. S03 defaults to **Today–Next 7 days** in the *event city's timezone* (the exact shortcut default is an experiment, not an onboarding gate). The date-range selector appears at the top and says e.g. `Sep 20–26 · Change dates`.
5. Render **Scheduled activities** with truthful upcoming eligible event cards: title/category, local start, public area, price, host-confirmation flag, Going count and seats. Below or in a distinct section render **Activity ideas — not yet organized**, each with **Organize this**.
6. Visitor opens S04 without signing in. Show enough public logistics to assess fit, but not private participant roster, exact member-only directions, chat or undisclosed stay dates.
7. Tapping Interested, Join or Create starts F03 and preserves the selected action and event context.

**Exceptions:** No supported cities → launch notice and optional city-interest signup without fabricated data. Empty activity feed → F02. Network failure → cached event data clearly marked stale when safe, with Retry. Shared event URL → resolve that event directly, using its real city/date; do not redirect to an unrelated default feed.

**Acceptance:** A guest reaches an actual public activity preview without providing trip dates or account details. A deep link opens the intended activity or a specific no-longer-available state.

### F02 — Date-range selector at the top of Discover

**Actor/trigger:** Guest or member taps the persistent date control in S03.

1. Open S03a with **start date and end date** (inclusive calendar dates for discovery) and selected city shown. Provide quick options Today, Tomorrow, Next 7 days, and Any upcoming.
2. User chooses a range directly on a calendar or uses a shortcut. Both endpoints are editable; show local timezone, e.g. `Nairobi time (Africa/Nairobi)` where needed.
3. Do not ask for **number of days** anywhere in this flow. If helpful, show duration calculated from endpoints as *informational only*, not as a separate required input.
4. Validate `start <= end`, supported product horizon (proposed max display/search window 90 days), and non-past dates where relevant. A range is a **search filter**, not proof of where a user physically is.
5. On Apply, return to S03, update the top date label, query scheduled activities whose event **start instant** falls within the chosen city-local calendar dates, and refresh any previewed invite-match context only where authorized.
6. Allow Clear/Any upcoming without clearing the selected city or wiping My Plans. If signed in, retain chosen browse filter as a preference; do not silently publish it as someone's travel availability.
7. A member may explicitly choose **Save these as my trip dates for activity invitations** in S14 or an unobtrusive opt-in prompt after choosing a range. Explain visibility and let them edit/delete at any time. Browsing alone never opts the member into discoverability.

**Important edge cases:** A one-day range includes all eligible event starts on that local day. The user's device timezone may differ from the city timezone. Cross-midnight events are shown by **start date** in MVP; an activity that began the prior day is not automatically included unless a later design explicitly supports in-progress discovery. Arrival/departure days do not assert all-day availability. When an event is outside a changed filter but already joined, it remains accessible in My Plans/Chats.

**Acceptance:** Date control is discoverable on S03; any range change takes effect without restarting onboarding; duration screen has been removed everywhere.

### F03 — Contextual sign-in, account creation, and action resume

**Actor/trigger:** Guest selects Join, Interested, Organize this, Create or invitation Join.

1. Store an expiring navigation intent: `targetActivityId?`, `invitationId?`, `desiredAction`, `cityId`, `dateRange`, and form draft where appropriate. Do **not** pre-commit a seat or send an invitation.
2. S05 offers **Passkey**, **Continue with Google**, and **Continue with Apple**. Explain the data each method supplies and that passkeys use the device's secure verification (fingerprint, Face ID, device PIN/passcode, or another supported method) without exposing biometric data to TripPals. On successful authentication, return existing members to the saved target. There is no email/password sign-in.
3. New members complete S06: display name, age-eligibility confirmation for the adult pilot, rules/terms acknowledgment; optional avatar, interests, traveler/resident label. Start with invitation discoverability **OFF** and no stranger DMs.
4. Re-fetch target activity/invitation, current capacity, eligibility and policy state. If still valid, present/execute the original explicit action consistent with platform consent: Join may complete once the user confirms on the same event; creation restores the form; invitation returns to its detail.
5. If a venue, price, time, status or capacity changed during authentication, show the new details and require fresh Join confirmation.

**Exceptions:** Expired or canceled passkey/provider ceremony, unavailable credential, duplicate-account conflict, rate limit, restricted user, photo failure, app restart or navigation cancellation must retain safe intent/draft as appropriate and show a concrete resolution path. A lost passkey can be recovered only through another already-linked Google or Apple method; support must not bypass account ownership. Do not accidentally join an activity because a stale `desiredAction` was replayed after cancellation.

**Acceptance:** No onboarding rating/paywall/GPS. Authentication never changes the target to a different event or duplicates a join.

### F04 — Read an event, express interest, join, or leave

**Actor/trigger:** Member opens S04 from Discover, a shared link, invitation, or My Plans.

1. Show activity title, host public identity, local start/end, approximate area or public venue, exact cost/mandatory outside fees, capacity, Going count, seats remaining, confirmation state and any participation rules. Reveal more precise meeting directions only to permitted members where needed.
2. **Interested** bookmarks the activity and records noncommittal interest; no reserved seat, invitation response or chat membership. Put it in My Plans → Interested.
3. **Join** shows any essential fee, travel/transport responsibility and major rules, then atomically checks current state, seat availability, block/moderation conditions, start cutoff and uniqueness.
4. On success set participation to Going and reserve one of the available seats. Show `You're going`, plus `Host confirmed` or `Awaiting host confirmation` separately. Add to My Plans → Going and grant event chat read/write per F10.
5. A joined member may leave before the cutoff; free the seat atomically, revoke chat write and future member-only details immediately, preserve only explicitly permitted historical data, and notify the host. Permit rejoin while eligible and seats remain.
6. If Going was reached through invitation F08, mark that invitation accepted/joined only after join succeeds; remove stale pending notices.

**Exceptions:** Full or terminal events cannot be joined. If two members race for the last seat, exactly one can succeed. A person already Going sees an idempotent response, not a second seat. Interested users never inflate Going. A material event revision requires acknowledgment. If blocked accounts are co-members, flag for host/moderator resolution and explain limits of blocking; do not promise physical separation.

**Acceptance:** Seat limit `host seat + Going attendees <= total capacity`; chat access requires actual Going membership or eligible host role.

### F05 — Create an activity from an idea or from scratch

**Actor/trigger:** Member taps **Organize this** on an Activity idea or **Create activity** from navigation.

1. Open S09. An idea supplies editable template title/category/description only. Label it `Template: no event exists yet`; it does not carry invented RSVP counts, host or date.
2. Pre-fill current browsing city and, optionally, propose a date within the selected Discover range; never silently assume the chosen date. The host chooses precise local start/end time and confirms appropriate city timezone.
3. Require title, category, concise plan, real public venue/area, date/time, approximate cost **including unavoidable fees**, activity language if operationally necessary, and total capacity **2–10 including host** (suggested default 6). Show venue/transport responsibility and any participation constraints.
4. Require the organizer to be an eligible, contactable participant with the host seat reserved. Flag/disallow commercial promotion under the initial noncommercial policy and explain any moderation outcome.
5. Save an editable draft, provide preview of exactly what guests versus Going members will see, and warn before discarding. Support draft restoration after interruption.
6. On Publish, validate all fields and policy, use an idempotency key, create Published activity + host membership + group conversation, then open S10. Publishing **does not mean host confirmed** and does not imply anyone else is Going.
7. Show **Invite people** as an optional next action after successful publication (F07), plus **Share activity**. Hosting must work even without eligible suggestions.

**Exceptions:** Past/invalid local times, DST gaps/ambiguous times, unsupported city, capacity too small, undisclosed fee or missing venue block publish with inline errors. Connection failure must not duplicate a published event. Pending moderation must be visible as `Pending review` and **cannot** enter public feed or send invitations until approved.

**Acceptance:** An idea becomes a real discoverable event only through successful publication with a host and complete logistics.

### F06 — Host dashboard: confirm, update, start, cancel, or conclude

**Actor/trigger:** Host opens S10 for a published/eligible activity.

1. Dashboard displays current state, complete latest logistics, actual Going occupancy, Interested total, invitations sent/pending/accepted/declined and remaining invite allowance; all counters have separate labels.
2. Host taps **Confirm activity** by a disclosed pre-start deadline. Transition Published → Host confirmed and notify Going members; an invitation recipient sees the updated status upon review. Do not call unconfirmed Going users “confirmed attendees.”
3. When modifying a published event, distinguish non-material copy edits from **material** changes (start/end, venue, significant price, activity character). Version every change. Material changes notify Going members and pending invitees, and require attendee acknowledgment or reconfirmation according to a consistent pilot rule.
4. Near the event's start, show **Start activity** only to eligible host at an appropriate time; keep current logistics pinned in chat. If start is forgotten, do not automatically assert that the event occurred.
5. **Cancel activity:** require a short reason, atomically transition to Canceled, stop further joins/invitations, invalidate pending invites, send essential notifications, hide it from live discovery and preserve limited read-only history.
6. **Finish activity:** from an eligible near/past-end state, host confirms whether the meeting actually occurred. If yes, record `Completed — host reported`; if no, use canceled/not held or `Outcome unknown` with a precise reason rather than recording success. Trigger optional attendee check-in F14.
7. If host confirmation cutoff is missed, show `Unconfirmed — do not rely on this plan yet`; send relevant notices and apply the published expiry policy. Past abandoned events become `Outcome unknown`, not automatically completed.

**Exceptions:** A host may be restricted, leave their own activity only after formally canceling/transferring under a later supported workflow, or lose connectivity mid-action. Ensure state transitions are atomic/idempotent and terminal outcomes cannot be silently resurrected from stale caches. Host removal by moderation requires activity-level disposition and member notification.

**Acceptance:** Host has a clear end-of-event control. Participants see meaningful status and material changes independently of chat delivery.

### F07 — Organizer discovers eligible people and sends activity invitations

**Actor/trigger:** Host of a *published, eligible* activity taps **Invite people** in S10. This is **not** a global People going tab.

1. Open S11 with event title/date/city, remaining Going places, an explanation that suggestions come only from members who opted in, and a `Skip` option.
2. Server requests candidates for the **specific activity ID**. A candidate must: (a) be a member with activity-invitation discoverability enabled; (b) have a currently valid declared stay/availability in the event city, or be a resident who explicitly opted in there; (c) have declared dates overlapping the **event's city-local date** (and time when specific availability is supplied); (d) be eligible to receive this host's activity invitation under block, safety, moderation, account, existing participation, prior-decline, and frequency rules.
3. Suggested cards show only fields the candidate agreed to share (e.g. display name/avatar, optional broad interests, `Available for this activity`). **Do not expose a full exact itinerary, private accommodation, phone/email, live GPS or off-platform contact details.** Interest similarity is optional relevance ranking, not a hard eligibility requirement.
4. Host selects candidates up to a conservative **proposed maximum of 15 distinct recipients per activity**. Count all successfully sent invitations toward that lifetime event quota; do not replenish it by withdrawing, deleting or re-sending an invite. A rate limit across a host's events also applies; final values require pilot tuning.
5. On **Send invitations**, server **revalidates each candidate** at send time, records an invitation per successful recipient, and sends an activity-specific in-app notification/push (if allowed). Return individual successes/failures and remaining quota; do not claim all were invited after partial failure.
6. The host may review only permitted invitation state in S10: pending, joined, declined, expired/revoked. No free-form opening DM to suggested people. An invite is never a reserved seat and never adds a member to chat.
7. When an activity fills, ends, is canceled/restricted, or is materially rescheduled, pending invitations are disabled or marked `Needs review` until recipients see the updated plan. New invitations stop for terminal/ineligible events.

**No matches:** State honestly: `No eligible people available for invitations right now`; offer Share activity, adjust event date if genuinely flexible, and remain in ordinary hosting. Do not fabricate people or reveal counts of opted-out members. **Resident availability:** A resident can opt in to city-level suggestions but should optionally set days/times; membership in a city alone does not assert availability for every hour.

**Acceptance:** Hosts can target only a real published plan; suggestion eligibility is enforced on server, not merely hidden in UI; privacy and event quotas survive pagination, reinstallation and concurrent requests.

### F08 — Recipient receives, declines or joins an invitation

**Actor/trigger:** Opted-in member receives an in-app/push invitation. **Entry:** S07 → Invitations, S12 via push, or deep link.

1. Notification preview contains minimal event context and a safe display name, not recipient itinerary or private meeting directions. In S12 display the event's real city-local date/time, public meeting area, cost, host, confirmation status and seats available.
2. **View invitation** never auto-joins. The recipient can **Join activity**, **Decline**, report the event/host, or change invitation preferences. No chat access while Pending.
3. Join follows the **same atomic F04 capacity/state/rule checks** as any other path. Only on success set Going, mark invite Joined, reserve seat, add My Plans and grant chat membership.
4. Decline marks the invite Declined, removes it from pending, and prevents another invite by the same organizer to the **same activity**. Do not send follow-up pressure or a conversational DM.
5. Invite automatically becomes Expired/Unavailable at a disclosed expiration, terminal activity state, start cutoff, loss of eligibility, or when the event fills. If seats reopen before expiry, a product decision is needed on reactivation; MVP default: leave an already marked Unavailable invite unavailable, but allow the recipient to use the normal public Join path where eligible.
6. Invitee can opt out of future suggestions/invitations immediately. Existing pending invites can be hidden/withdrawn from Inbox according to an explicit privacy policy without changing activity memberships already accepted.

**Exceptions:** User sees `Activity is full`, `Time or place changed`, `Invitation expired`, `Activity canceled`, or `You no longer have access` as applicable. Network retry must not submit duplicate Join actions. The host never receives a read receipt that discloses a person's precise whereabouts.

**Acceptance:** Recipient remains in control. Invitation → Going requires a deliberate, successful Join transaction; invitation open/decline never grants roster or chat access.

### F09 — My Plans, returning users, and city switching

**Actor/trigger:** Member visits S07, returns after inactivity, changes Discover city, or follows an activity notification.

1. Show Going/upcoming first when an imminent activity exists, then Interested, Hosting, Invitations, and Past/Cancelled. Show next actionable state (`Host confirmation needed`, `Starts in 2 hours`, `Time changed — review`, `Invite expires soon`).
2. Opening a Going activity reaches S04, S08 or S10 through stable `activityId`; no repeated city/date onboarding.
3. Changing city or date range updates Discover only. Existing memberships, invitations and chats remain in My Plans and Chats across cities.
4. Returning signed-in users may see their next actionable plan first or restore their last Discover city; do not auto-update their published trip availability just because they browse another city.
5. A canceled, expired, rejected, or completed event stays in appropriate history with actual status and a way to understand what happened.

**Acceptance:** The app never “loses” a joined group chat when the member changes location, filter or device session.

### F10 — Activity group chat: creation, membership, and access

**Actor/trigger:** Host publishes an activity or a member successfully Joins.

1. On successful publication, create exactly **one conversation per activity**, linked to the host; retain a stable chat ID. A host can open the chat even before any attendee joins, but the UI should explain that nobody else is there yet.
2. On successful Going join, authorize the participant to read the applicable event conversation and send messages. Add the participant to the roster; show a minimal system message such as `A member joined` if appropriate without leaking identities to guests.
3. S08 header identifies the activity and city-local time and shows current **pinned logistics derived from canonical Activity fields**, not a manually copied chat message. A material plan change inserts a versioned **system update** linking to the latest event detail.
4. A member can open S08 from My Plans, Chats, event details, or a valid notification. The backend rechecks membership and account/event permissions on each read/write and real-time channel subscription.
5. **Interested, invited-but-not-joined, guest, left, removed and restricted nonmembers cannot read or send current chat messages.** A member who leaves loses new-message visibility and send access; any permissible historical transcript retention must be specified, minimized, and enforced separately.
6. Completed or canceled activities become read-only after an announced grace period (proposal: 24 hours after conclusion/cancellation) and move to Chats → Past; users can always access a persistent event summary/history according to retention policy. Do not delete it immediately while participants still need essential post-event details.

**Shared-group blocks:** If two existing Going members block each other, collapse/mask blocked messages consistently where technically feasible, stop direct contact, and offer leave/report/escalation; explain that blocking inside the app **cannot ensure they will not encounter one another at the physical meetup**. A severe safety report may require organizer/moderator intervention rather than silently dropping one person's messages.

**Acceptance:** Invited and Interested users cannot peek at chat; joining grants it exactly once; switching cities and opening notifications returns to the correct activity conversation.

### F11 — Activity group chat: messaging, offline states, notifications and moderation

**Actor/trigger:** Authorized host/Going member sends, receives, reports or mutes chat.

1. On S08, fetch recent messages in deterministic order, show sender's permitted display name and local message timestamp, and render `Connecting`, `Offline — showing cached messages`, or `Couldn't load — Retry` accurately.
2. Compose supports **plain text** in MVP; send requires nonempty length-bounded content, account permission, spam/rate-limit checks and an idempotent `client_message_id` unique per sender/conversation.
3. Display pending bubble as **Sending** until server acknowledgment; then **Sent**. On failure show **Failed — Retry**. Retrying with the same client ID cannot create a duplicate. Do not claim `Delivered` or `Read` without corresponding actual signals; read receipts are not required for MVP.
4. Reconnect fetches missed messages by sequence/cursor and reconciles local pending messages. Never silently drop a failed send or display chat content from a different activity after navigation changes.
5. **Pinned panel:** current start/end time and timezone, publicly safe venue/meeting instructions appropriate for member permissions, cost, event state, host confirmation, and link to full plan. Remains accessible/cached when messaging transport fails, with a stale indicator if event state cannot be refreshed.
6. **System events:** Join/leave notices as appropriate, host confirmed, material changes, start, cancel, conclude, and moderator-important notices are structured, timestamped, and separated from user content. Essential state changes also appear in S04/S07, not chat alone.
7. Push notifications carry stable `activityId` and `conversationId`; tapping opens the right chat if authorized. If canceled, completed/read-only, left, restricted or deleted, route to a specific status/detail screen—not the generic home page. Handle duplicate/out-of-order pushes safely.
8. Members can mute **nonessential chat alerts**, but must be able to see essential event changes in-app and receive them via enabled essential channels under platform/permission constraints. The OS may suppress push, so do not rely solely on delivery for critical plan changes.
9. Long-press/report a message or member from the chat; include context/reference, route to S15, optionally Block separately. Moderators can remove abusive content and restrict send privileges using auditable actions; the UI explains unavailable messages without revealing reporter identity.
10. If membership is revoked during composition, reject send with a clear permission state, disable composer, and prevent resubmission. A temporary network interruption should not falsely be shown as removal.

**Suggested nonbinding engineering targets:** first usable cached event header quickly on mid-range devices; ≥99.5% crash-free sessions; monitor actual chat open latency, failed send rate, retry success, push deep-link resolution, and time-zone correctness. Do not promise a specific chat latency before field measurement.

**Acceptance:** Message order and deduplication survive reconnect; chat is useful on weak networks; report/block are present in chat; member-only details never appear in unauthorized notifications or guest previews.

### F12 — Confirmation, reminders, and attendance intentions

**Actor/trigger:** Activity approaches its start time.

1. Host confirms F06; show this as **host-confirmed plan**, independent of Going count.
2. Notify Going members of confirmation and prompt optional `Still going?` with Yes / Can't attend, scheduled using city-local event time and sensible rules for last-minute events.
3. A Yes records `reconfirmed_at` but is **not attendance proof** and cannot increase seat count beyond the existing Going membership.
4. Can't attend invokes a clear leave confirmation and releases the seat; notify host when useful. Do not silently treat nonresponse as nonattendance or remove members unless a disclosed re-confirmation policy is deliberately introduced later.
5. Pending invitees can receive no more than policy-permitted invitation reminder; an ignored invitation does not become a confirmed participant.
6. If host is unconfirmed by the deadline, surface warning, notify Going users and follow the published unconfirmed/expiry process. Guests and invited members must see the same genuine state.

**Acceptance:** Invited, Interested, Going, attendee-reconfirmed, host-confirmed and Attended are different facts and counters.

### F13 — Material rescheduling, cancellation, capacity and invitation reconciliation

**Actor/trigger:** Host edits time, date, city, public meeting point, significant costs or capacity; cancellation or moderation occurs.

1. Apply change with server validation, event version, audit record and appropriate notification. The organizer cannot choose a smaller capacity than current occupied seats without an explicit, separately designed member-removal/consent workflow; MVP rejects such a reduction.
2. For material changes, display diff and `Please review updated plan` to Going members and pending invitees. A moved date may invalidate previously matched invitees' declared availability; mark affected invitations `Needs review` or revoke rather than silently claiming eligibility. Do not expose the candidate's hidden dates to the host.
3. Existing Going members keep their seat provisionally until the disclosed change-acknowledgment rule resolves their status; a major change should enable a frictionless leave and appropriately constrained reconfirmation. Neither a modified event nor an invitation is an automatic new agreement.
4. A canceled, expired, removed or started-past-join-cutoff activity rejects new joins and invitations and removes actionable CTA from discovery. Pending invitations show explanatory terminal status.
5. When the last seat fills, pending invitees see Full; the server still uses atomic seat checks at Join. Host can invite within the quota only while the activity is open/eligible and seats remain; do not create false urgency counts.
6. A restricted host causes the activity to enter review/cancelation handling by an authorized operator; chat and participant notification follow explicit safety rules, not a silent disappearance.

**Acceptance:** The same change is reflected in activity details, My Plans, invitation, chat pinned plan and notifications; no inconsistent date/capacity values.

### F14 — Post-activity conclusion, attendance check-in, and repeat loop

**Actor/trigger:** Host finishes or an event passes its scheduled end.

1. Host chooses **Finish activity**, answers whether it actually occurred and optionally records a factual estimate. The system records who reported the outcome; `Host reported completed` is not independent verification.
2. Going participants receive an optional check-in: `Did you attend?` Yes / No / Prefer not to say / Skip. Feedback about organization, logistics or comfort is private and voluntary; safety concerns route to explicit Report.
3. A member who did not attend is not compelled to rate others and is not automatically publicly labeled a no-show. If host is absent or the event never happens, users can report that experience, and final status is Canceled/Not held/Outcome unknown according to evidence.
4. Move the activity to My Plans → Past with accurate state. Chat becomes read-only according to F10; preserve required historical info under a defined retention policy.
5. Invite an attendee, **after** the experience, to find a similar event, organize one, or share TripPals. Do not prompt for an app-store rating during onboarding or compel interpersonal scoring.

**Acceptance:** Real-world success metrics distinguish host report from voluntary participant reports; missing responses are Unknown, not Yes or No.

### F15 — Empty city, no relevant dates, no suggestions, and graceful degradation

**Actor/trigger:** City unsupported, no real activities fall in selected range, invitation pool has no eligible members, or network is unavailable.

1. If city unsupported, label it clearly and offer another supported city or optional launch-interest signup; never populate it with fictitious meetups.
2. If city supported but chosen dates have no scheduled events, say `No scheduled activities for these dates`. Offer **Change dates**, **Clear filters**, **Create activity**, and genuinely scheduled alternatives outside the range if any (clearly dated).
3. Display curated **Activity ideas** separately, each described as a template that a member may organize. There must be no `Join` action, attending count, fake host or pretend confirmation on idea cards.
4. If host suggestion pool is empty, keep **Share activity** and the public feed as alternative acquisition paths; do not require an invitee to publish.
5. If chat transport is offline, preserve legitimate cached event logistics, show last-sync time, allow safe retries, and prioritize a functional event overview.

**Acceptance:** Sparse inventory never appears as false social proof or a paywall problem. An event host can make progress without automated matching.

### F16 — Invitation discoverability, trip availability, privacy and account controls

**Actor/trigger:** Member visits S14 or accepts an optional invitation-discovery explanation.

1. Invitation discoverability defaults to **OFF**. Explain in plain language: consenting allows eligible organizers with actual activities in a selected city to see a limited profile card and send bounded invitations. No precise GPS or accommodation exposure.
2. Member explicitly enables it and chooses the city/cities where they are available. For a traveler, they may **save arrival and departure dates as an explicit availability interval** (a single city/range is sufficient for P0); for a resident, choose a city and optional available dates/times. The Browse date filter is never silently copied into this record.
3. Set optional interests and profile fields to share; display a preview of the organizer-visible card. Permit turning discoverability OFF, editing dates, deleting an old trip, or disabling all invitations at any time.
4. Match to **specific event date/time**, not merely overlapping two people’s travel periods. If exact daily time availability is not supplied, label suggestions `Dates overlap; time not confirmed` and avoid a stronger assertion.
5. Disabling discoverability removes the person from subsequent suggestion queries and prevents new invitations. Apply documented treatment to already-sent invitations; never revoke an activity the person has already intentionally joined merely because they opted out of new invites.
6. Handle notification preferences, block list, **login-method recovery**, deletion and support independently. A member may add or revoke passkeys and link/unlink Google or Apple after recent authentication, but cannot remove their final usable login method. Offer an optional local biometric/PIN app lock as a device-only privacy control; it is not an account authentication method. Deletion invalidates future seats/invitations, ends active sessions and applies documented retention exceptions for abuse evidence and legal obligations; do not claim immediate removal of everything without such a policy.

**Acceptance:** Changing browsing dates does not change discoverability; opt-out takes effect on the next authorized suggestion query and send-time revalidation.

### F17 — Safety, spam, reporting, restriction notices and appeals

**Actor/trigger:** Member reports a person, event, invitation or message; blocks another member; moderator reviews content; account/listing restricted.

1. Make Report and Block available from S04, S08, S12 and permitted profile surfaces. Report reason categories include harassment/unwanted sexual contact, scam/spam, misleading commercial activity, abuse, immediate safety concern and Other; carry referenced object/context without over-collecting data.
2. A report produces a case ID/status and routes urgent safety items to a staffed escalation process appropriate to pilot operating hours. Explain emergency support limitations; an app cannot replace local emergency services.
3. Blocking prevents new suggestions/invitations and prohibited direct interactions. In existing shared activity chats, apply masking and escalation where appropriate; explain that physical co-presence is not automatically prevented by an in-app block.
4. Enforce event-specific and host-level invitation rate limits, repeated-decline suppression, anti-scraping/pagination controls, abusive-content checks and duplicate-event signals; avoid unexplained automatic permanent bans from a single weak signal.
5. Internal S16 records evidence, reason, operator, action, time and appeal outcome. A consequential restriction shows appropriate policy category, impact, duration or review status, support link and an accessible appeal route while protecting reporter identity and investigation integrity.
6. Commercial listings must be disclosed and subject to a clear initial policy (ordinary noncommercial personal meetups only in P0); unsafe or misleading events can be removed with participant notices and appropriate refund/fee guidance if a third-party payment was involved.

**Acceptance:** Inviting and chatting are subject to the same abuse controls as publishing and joining; users have a real report/appeal route rather than silent disappearance.

---

## 8. State machines and business invariants

### 8.1 Activity lifecycle

```text
DRAFT --publish--> PUBLISHED --host confirms--> HOST_CONFIRMED
  |                 |   \                         |   \
 discard            |    \--cancel/expire          |    \--cancel
                    |                              \--start--> IN_PROGRESS
                    |                                             | \
                    \--cancel/expire                              |  \--cancel when justified
                                                                  \--finish--> COMPLETED_HOST_REPORTED
Past unresolved published/confirmed/in-progress ----------------------------> OUTCOME_UNKNOWN
Any review-eligible state --moderation hold--> UNDER_REVIEW --> restore/cancel
```

A host's `COMPLETED_HOST_REPORTED` and participant `attendance_self_report` are independent records. `OUTCOME_UNKNOWN` is not automatically marked successful. The exact state transitions for last-minute cancellation, expiry, and review require implementation-level guard tables; terminal transitions are idempotent and audited.

### 8.2 Participation and capacity

```text
NONE --> INTERESTED --> GOING --> LEFT
   \-----------------> GOING
GOING + reconfirmed_at (optional)
GOING after event --> attendance_self_report = YES | NO | DECLINED | UNKNOWN
```

- Total capacity `C` is an integer 2–10 **including host**. Maintain `1 host seat + count(current Going non-host members) <= C` in a single server transaction. A host is not double-counted as a regular member.
- Interested and pending invitation do **not** consume seats or appear as Going.
- Host-confirmed event and attendee-reconfirmed intent are **different** from a person being Going and from reported attendance.
- If host role becomes unavailable, disposition the whole event instead of leaving an orphaned hosted seat.
- Publish, Join, Leave, and invitation-send all support idempotent request keys and safe concurrent retries.

### 8.3 Invitation lifecycle

```text
ELIGIBLE_CANDIDATE --host sends--> PENDING
PENDING --recipient Joins successfully--> JOINED
PENDING --recipient declines--> DECLINED
PENDING --deadline/start cutoff--> EXPIRED
PENDING --host withdraws/event canceled/restricted--> REVOKED
PENDING --activity full/eligibility lost--> UNAVAILABLE
PENDING --material edit--> NEEDS_REVIEW --> PENDING (recipient shown updated plan)
```

`ELIGIBLE_CANDIDATE` is a transient server-side query result, **not** a public persistent account status or permission to contact someone. `JOINED` is recorded only after the standard participation transaction succeeds. Proposed invitation cap: up to **15 distinct successfully invited recipients per activity**, plus a separate sliding-window host/account anti-spam limit; exact limits are test assumptions. Declined recipients cannot be re-invited to the same event. A withdrawn invite does not refund the per-event quota. Host may still fill the event organically from public discovery.

### 8.4 Conversation lifecycle

```text
ACTIVITY_PUBLISHED --> CHAT_ACTIVE (host; Going members added on Join)
CHAT_ACTIVE --event completed/canceled--> CHAT_GRACE_READ_WRITE (bounded)
CHAT_GRACE_READ_WRITE --grace ends--> CHAT_READ_ONLY --> ARCHIVED/PURGED by policy
member GOING --> permitted access
member LEFT/REMOVED/RESTRICTED --> no new read/write access; historical access per policy
```

**Privacy note:** If an event is canceled for a safety incident, moderator may immediately freeze or restrict chat rather than allow the ordinary grace window. The proposed 24-hour grace period is a starting product assumption, not a guaranteed retention period.

### 8.5 Date and timezone semantics

- Every event stores actual start/end as UTC instants **and** its city/venue IANA timezone (e.g. `Africa/Nairobi`). Render the event-city local date/time consistently on Discover, event, invitation, chat, reminders and push. Device time zone does not redefine the event.
- Discover filters are **inclusive local calendar dates** and match events whose local **start date** lies inside the chosen range. Do not calculate a calendar date range by adding fixed 24-hour increments across daylight-saving boundaries.
- A declared trip is an explicit opted-in interval of local dates for a chosen city. An event intersects that stay when its local start date lies in the interval; an arrival/departure date match alone does not prove the traveler is free at the event time. Show that uncertainty when no specific availability is supplied.
- Correctly handle dates that straddle midnight, DST skipped/repeated times, changing city, travel across time zones, and stale client clocks. Server applies cutoff rules to UTC event timestamps.

---

## 9. Suggested data model and authorization

| Entity | Minimum fields / invariants |
|---|---|
| `User` | `id`, `account_status`, `age_eligible_at`, `rules_version_accepted`, `created_at`, `deleted_at?`; has one or more supported login methods |
| `AuthIdentity` | `id`, `user_id`, `provider=GOOGLE/APPLE`, stable provider subject, verification metadata, timestamps; unique `(provider, provider_subject)` |
| `PasskeyCredential` | `id`, `user_id`, unique credential ID, public key, relying-party ID, signature counter and credential metadata; never stores biometric data or a private key |
| `Profile` | `user_id`, `display_name`, `avatar_url?`, `bio?`, `interests[]?`, `residency_label?`, `visible_fields`, `invitation_discoverable=false` |
| `City` | `id`, `name`, `country`, `iana_timezone`, `launch_status` |
| `BrowsePreference` | `user_id?` or local anonymous key, `selected_city_id`, `filter_start_local?`, `filter_end_local?`, `category?` — **never treated as consented availability** |
| `Availability` | `id`, `user_id`, `city_id`, `role=traveler/resident`, `start_local_date?`, `end_local_date?`, `day/time_preferences?`, `visible_to_eligible_hosts`, `updated_at`, `expires_at?` — separate consented record |
| `ActivityIdea` | `id`, `city_id?`, `template_title`, `template_category`, `template_description`, `enabled`; **no host/Going count/date until an activity is published** |
| `Activity` | `id`, `host_id`, `city_id`, `idea_id?`, `title`, `category`, `description`, `start_at_utc`, `end_at_utc`, `iana_timezone`, `public_area`, `private_meeting_detail?`, `approx_cost_amount?`, `currency?`, `cost_description`, `capacity_total(2..10)`, `state`, `host_confirmed_at?`, `version`, timestamps |
| `Participation` | unique `(activity_id,user_id)`, `status=INTERESTED/GOING/LEFT`, `reconfirmed_at?`, `attendance_self_report?`, `updated_at` — host seat represented separately or counted once |
| `Invitation` | unique `(activity_id, recipient_id)`, `host_id`, `status`, `sent_at`, `expires_at`, `responded_at?`, `event_version_seen`, `idempotency_key` |
| `InvitationQuota` | activity/host lifetime distinct-successful-recipient count and rolling rate limit counters enforced transactionally |
| `ActivityRevision` | `activity_id`, `version`, changed fields, material flag, changed_by/time, required acknowledgments and notice records |
| `Conversation` | unique `activity_id`, `id`, `state`, `created_at`, `read_only_at?`, `archived_at?` |
| `Message` | `id`, `conversation_id`, `sender_id`, `client_message_id`, `sequence`, `body`, `created_at`, `moderation_state`; unique `(conversation_id,sender_id,client_message_id)` |
| `EventSystemMessage` | `activity_id`, `event_version?`, `type`, `payload_minimized`, `sequence`, timestamp; no private guest-leaking payloads |
| `Notification` | `recipient_id`, `type`, `activity_id?`, `invitation_id?`, `conversation_id?`, `event_version?`, `delivery_state`, `read_at?`, timestamp |
| `Block / Report / Case / Appeal` | reporter/blocker, target, reason/category, scoped evidence reference, case status, moderation action, notice, appeal, audit fields |

**Authorization matrix:** Guests read only public activity/idea fields. Candidate suggestions can only be fetched by the **eligible host for a specific published activity**; return already-filtered, consent-limited cards with no raw trip itinerary fields. Send-time authorization repeats eligibility. Invite recipients read only their own invitations. Host roster includes legitimate Going members; candidate suggestion cards do not grant profile/contact access elsewhere. Event chat and member-only logistics require host/Going permissions with checks on initial fetch, history pagination, real-time subscription and send. Moderators use least-privilege scoped access and audit logs.

**Backend constraints:** transactional joins and capacity check; idempotent publish/leave/invite/send; rate limit discovery, candidate pagination, invitations, auth and chat; prevent scraping, enumeration and invalid role escalation. Store only needed availability and report data, with defined expiration, deletion and retention policies before launch. Never include precise meeting directions in a guest API response or push preview.

---

## 10. Notifications and communication matrix

| Trigger | Recipients | Surface and user action | Essential? |
|---|---|---|---|
| Published activity invitation | Specific opted-in recipient | Inbox + optional push → S12 review/Join/Decline | Invitation itself optional; honor opt-out |
| Someone joins/leaves | Host; optionally relevant group | Host dashboard / in-app; avoid noisy pushes by default | Operational to host |
| Host confirms / fails confirmation deadline | Going attendees; relevant pending invitees on open | S04/S07/S08 structured state, push if enabled | Yes: plan status |
| Event start reminder and optional reconfirmation | Going attendees + host | Deep link event and current plan | Important; respect OS push availability |
| Material date/time/venue/cost edit | Going and pending invitees | Structured change summary, acknowledgment/review | Yes |
| Cancellation or safety closure | Going members and pending invitees | Event state, My Plans, notification → reason where appropriate | Yes |
| New group chat message | Host + Going, excluding sender and muted as applicable | Push deep links S08; in-app unread count | No, unless linked to essential event update |
| Invite declined/joined/expired | Host as limited aggregate/state; recipient as applicable | Host dashboard / invitation status | Usually no push to host |
| Post-event check-in | Going members | Optional S13 | No |
| Restriction/appeal response | Affected user | In-app notice and account support route | Yes, with privacy-sensitive payload |

**Notification guarantee boundary:** push can be disabled, delayed or dropped by platform/device. Essential plan states must always remain discoverable in the app; engineering should measure delivery rather than claiming guaranteed reception.

---

## 11. Acceptance criteria and end-to-end QA matrix

| Test | Expected result |
|---|---|
| Guest launches with GPS denied; selects a city | S03 shows real public activities immediately; no duration/date/signup gate. |
| Guest changes top date range | Results apply to start dates in event-city timezone; selection persists in Discover and can be cleared. |
| Guest filters date range and then joins | Same event/context persists through authentication; current seat and terms are rechecked. |
| User browses dates but has never opted into invitations | User is **not** eligible for suggestion queries; browse preference is not consented availability. |
| Traveler opts in with dates including event day | Eligible for a candidate query only if all other checks pass; no raw stay details sent to host. |
| Traveler's trip overlaps city dates but not selected event date | Not suggested for that event. |
| Resident opts in to city and indicates unavailable times | Host sees availability-qualified suggestion or nonconfirmed time status; never false `available at 9 AM`. |
| Host creates from Activity idea | Editable template opens; until published idea has no Join/Going/host identity. |
| Host selects capacity 10 then nine other members join | Going + host equals 10; tenth non-host fails with Full under concurrent requests. |
| Host publishes event and sends 15 invitations | Only 15 distinct successful recipients counted for per-event quota; further sends denied; retries do not duplicate. |
| Invitee opens or declines invitation | No reserved seat, roster membership or chat access; same-event re-invite blocked after decline. |
| Invitee joins while last public seat is taken | Atomic Join fails cleanly; invitation shows Full; group occupancy never exceeds capacity. |
| Activity changes date after invitations sent | Updated date everywhere; affected invites need review/revalidation; no hidden itinerary leak. |
| Member switches Discover city or restarts app | Existing events and activity chats remain in My Plans/Chats and open by stable ID. |
| Invited/Interested/guest attempts chat API read or send | Server denies; no private roster, meeting detail or messages leaked. |
| Going user sends while offline, retries after reconnect | Sending/Failed/Retry states are accurate; exactly one server message after idempotent retry; order reconciled. |
| Push tapped for active activity chat | Opens correct event conversation; access rechecked; no generic-home detour. |
| Push tapped after member leaves or event is canceled | Specific permission/event status and permitted history displayed; no unauthorized chat. |
| Host edits meeting point, then chat transport fails | Canonical pinned event logistics and event version remain accessible or correctly marked stale. |
| Host fails to confirm or finish | Show Unconfirmed/Outcome unknown according to policy; never auto-mark completed. |
| Host cancels a full event | It leaves public feed, prevents new joins/invites, and notifies Going/invited users. |
| Two co-members block each other | Contact restrictions/masking and safety explanation applied consistently; physical attendance is not falsely guaranteed. |
| Member opts out of suggestions after being invited | New suggestions/sends denied; accepted Going membership preserved; pending handling follows disclosed policy. |
| Member reports abusive chat or invite | Case record and appropriate moderation queue created; reporter not revealed; restricted user has notice/appeal path. |
| User changes device timezone or event crosses DST | Event city-local timing and filtering remain correct; no fixed-24-hour-date error. |
| Screen reader, enlarged text and slow network | Discover header/date controls, card status, Join, chat delivery, report and retry remain operable and labeled. |

---

## 12. Instrumentation and decision metrics

**Core funnel** (segment by city, date window, acquisition source and new/returning status):

`welcome_opened → city_selected → discover_loaded → date_filter_applied? → activity_detail_viewed → auth_started? → join_attempted → join_succeeded → host_confirmed → chat_opened → event_occurred_host_reported? → attendance_yes/no/unknown → repeat_join`.

**Organizer/invitation funnel:** `idea_viewed → organize_started → activity_draft_saved → activity_published → invitation_picker_opened → eligible_candidate_count_bucket → invitation_sent → invitation_opened → invitation_declined/join_succeeded/unavailable → host_confirmed → event_concluded`. Do not expose identifiable candidate inventories in analytics; use aggregate buckets and privacy-reviewed events.

| Metric | Definition and interpretation |
|---|---|
| Time to relevant activity preview | From first open/city selection to first eligible public event view, measured separately for cities with inventory and empty cities. Proposed design target: <60 seconds under healthy connectivity. |
| Discovery date-filter usage | Share changing/clearing the range, and whether it improves real detail views/joins; never count as travel consent. |
| Local liquidity | Actual eligible scheduled events, available seats and distribution by day/time; separate idea templates, invite pool and confirmed attendees. |
| Successful meetup rate | Host reported and voluntarily attendee corroborated separately; never equate published/Going with physical attendance. |
| Invitation quality | Eligible suggestions, sends, unique invitees, opens, Join conversions, declines, opt-outs, report rate and quota-hit rate, analyzed together. |
| Group occupancy | `host + Going` relative to capacity at event start; do not inflate with pending invitations or Interested. |
| Chat reliability | Conversation-open latency, sent/failed/retried messages, duplicates prevented, offline recoveries, deep-link success and stale pinned-plan occurrences. |
| Safety and governance | Reports per meaningful interaction, repeated violations, appeals, action time, wrongful-action reversals and user-reported comfort. Low reporting alone is not proof of safety. |
| Retention | Participation in a second meetup within the same trip and subsequent trips; daily app opens alone are weak for episodic travel. |

**Experiments to run before committing to advanced matching:** Do organizers prefer hand-picking opt-in candidates, shareable links, or an optional broadcast to eligible members? What percent of invites lead to genuine attendance, not merely RSVP? Do users value date range as a filter but choose not to publish availability? Does the presence of ideas motivate hosting or mislead visitors despite labeling?

---

## 13. Delivery plan, operations, and rollout gates

| Phase | Build/operational work | Exit criteria |
|---|---|---|
| 0 — Concierge pilot | Choose one city; interview travelers and residents; recruit dependable local hosts; manually run repeated activities. Test event templates, group size 2–10, attendance, opt-in invitations and unwanted-contact risk. | Evidence of repeated worthwhile in-person meetings; feasible moderation/invitation operation. |
| 1 — Guest value and identity | S01–S06, supported city inventory, real event feed, top date filter, detail and minimal auth; basic analytics/privacy. | No date/duration/signup wall before preview; correct date/time and empty states. |
| 2 — Activity lifecycle | S07/S09/S10, create/publish, capacity-safe Join/Leave, host confirm/edit/start/finish/cancel, My Plans. | Full standard activity flow passes concurrency and terminal-state tests. |
| 3 — Group coordination | Durable event group chat, pinned canonical logistics, offline/error/retry, push/deep links, system messages. | Attendees reliably coordinate on representative slow devices and weak networks. |
| 4 — Trust + invitation picker | Opt-in availability, limited suggestion cards, send-time revalidation, invitation Inbox/Join/Decline, quotas; reporting, blocking, moderation admin, notices and appeals. | No suggestion data leak, auto-join or spam bypass; support staffed; safe rollout switch. |
| 5 — Controlled launch | Seed recurring real activities and invite a limited local cohort; review outcomes/safety and expand only after reliable attendance. | Healthy repeated meetup delivery, manageable complaints, reliable tech and sustainable host supply. |

**Rollout fallback:** If invitation matching takes longer than expected or fails privacy/abuse testing, launch S01–S10 and S13–S16 with **manual sharing of published activity links** and turn on S11/S12 only when safe. Do not remove guest preview, structured hosting, confirmation or chat to make room for matching.

**Technical approach:** One cross-platform app and managed services are plausible choices, with a transactional relational source of truth for events/RSVPs/invitations and a durable real-time chat service. Technology selection depends on team capabilities and provider terms. Have a named human operator responsible for host reliability, incident response and appeals before public launch.

---

## 14. Explicit product decisions still to validate

1. **Date control default:** Today–Next 7 days is a suggested initial view; validate against trip-planning behavior. Any future date range must be accessible without a separate onboarding screen.
2. **Availability consent:** The proposed dedicated opt-in with a separately saved stay interval is required to avoid treating private browsing as permission for organizer discovery. Test the wording and opt-in rate.
3. **Invite quota:** Proposed 15 distinct successful invitations per event with additional per-host throttling; confirm against response rates and spam/harassment feedback. No claim that 15 is optimal.
4. **Candidate data:** Validate which explicitly shared information is useful for invitations. Do not disclose exact itinerary even if matching uses it internally.
5. **Group size:** Max 10 including host is decided for MVP; default 6 and minimum 2 are proposals. Test whether individual activity formats require lower limits.
6. **Join model:** Instant, capacity-controlled participation for ordinary public events is the MVP default; host approval is deferred.
7. **Events and invite lifecycle cutoffs:** Host confirmation deadline, start-time join cutoff, invite expiry, material-change acknowledgment and post-event chat grace period must be documented and tested in a field pilot.
8. **Safety/age/legal requirements:** Adult-only initial cohort, availability privacy, reporting escalation and record retention require review in the actual launch jurisdiction; this document is not legal advice.
9. **Launch city/hosts:** Choose from validated organizer supply, traveler demand, accessible venues and operating capacity; Nairobi in examples is illustrative, not a decided launch market.
10. **Brand clearance:** The name TripPals is selected within the project; trademark, domains and app-store availability have not been checked here.

---

## 15. One-page implementation definition of done

A person with no account can choose a supported destination and see **real, scheduled activities immediately**. The **date range is optional and editable at the top of Discover**; there is no duration screen. A user can inspect a plan, sign in only when taking an action, Join an existing event or publish a real event from an idea template. A published host can optionally invite only **opted-in, event-date-eligible people** within anti-spam limits. Recipients choose whether to Join; neither suggestions nor invitations reserve a seat or expose chat. Capacity is **at most 10 total including the host**. Host and Going attendees have a stable activity group chat with reliable messaging, pinned canonical logistics, event changes and correct notification deep links. The host can confirm, start, change, cancel and explicitly conclude the plan; participants can voluntarily report attendance. Trust/privacy controls and a staffed support route work from the relevant screens. The app reports what actually happened, not what an RSVP, suggested idea or invitation implied.

**Source documents used:** `TripPals_MVP_Plan_and_User_Flows.md` (v1.1), `nomadtable_competitive_teardown_and_prd.md`, and the supplied Nomadtable information and review exports, all provided as this project's resources. The September 20 wireframe and subsequent design decisions determine the v2 flow changes; no external market-validation claims are introduced.
