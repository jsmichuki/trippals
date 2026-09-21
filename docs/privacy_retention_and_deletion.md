# Privacy, retention, and account-deletion operations

**Policy version:** `privacy-retention-v1`  
**Owner:** TripPals privacy and trust-and-safety leads  
**Launch gate:** the launch country counsel must approve this schedule, the
lawful bases, processors, and data-residency posture before public launch.

## Data inventory and lawful basis

| Data category | Purpose and basis | Default disposition after deletion |
| --- | --- | --- |
| Account identity, provider subject, passkey public key, sessions, refresh tokens, device push tokens | Contract, account security, and fraud prevention | Revoke sessions/devices immediately; delete identities, passkeys, challenges, and token material. |
| Profile and invitation consent/availability | Explicit consent and service delivery | Disable discoverability; revoke consent and availability immediately; replace the display name with `Deleted member`. |
| Activity participation and conversation membership | Contract and safety | Leave future activities, release Going seats, and revoke chat membership immediately. Retain minimal non-identifying transactional history only where needed for capacity/audit integrity. |
| Invitations | Contract and consent | Revoke every pending invitation in which the person is host or recipient. |
| Chat messages | Service delivery and safety | Access is revoked. Messages are not exported to or exposed through the deleted account; their retention is governed by conversation and safety policy. |
| Reports, cases, and immutable audit | Legitimate interests, legal obligation, and safeguarding | Retain the minimum necessary record for the approved safety period; remove a deleted reporter link when permitted and register the retention exception. |
| Backups, security logs, and operational records | Security and legal obligations | Expire through encrypted backup rotation; never restore a deleted account into production without replaying the deletion workflow. |

Consent records are versioned: invitation settings record consent/revocation
timestamps and community-rule acceptances record their accepted version. Browse
preferences are never treated as invitation availability or consent.

## Retention schedule and exceptions

`privacy-retention-v1` keeps the minimum necessary safety report, moderation
case, and immutable audit references for **seven years** from the deletion
request. The workflow writes an `account_retention_records` entry identifying
the category, record ID, retention deadline, and de-identification time. This
is not a promise that every historical backup is instantly erased.

Exceptions are limited to documented safety, legal-hold, fraud, tax, or
litigation requirements. A privacy lead must document the category, record,
authority, retention deadline, and release decision before extending a record.
No exception permits continued authentication, discoverability, invitations,
availability, future RSVP, or chat access.

## Deletion workflow

1. The authenticated member requests deletion with a session authenticated in
   the last 15 minutes. The API returns an honest `202` status: access is
   revoked immediately, while retention processing is durable and asynchronous.
2. In one transaction the server revokes sessions/refresh tokens/devices,
   removes provider/passkey/challenge material, disables consent/discoverability,
   revokes pending invitations, leaves future RSVP records/releases seats,
   cancels future hosted activities, and revokes conversation memberships.
3. The transaction writes the deletion state, immutable audit entry, retention
   records, and an outbox event. An idempotent Oban workflow completes the
   retention review state without restoring access.
4. Support may only report the workflow state and applicable retention
   exception; it must not claim instant erasure or expose case/report evidence.

## Backups and restore

Production PostgreSQL must use TLS, encryption at rest, PITR, and a tested
restore process. Restore drills run at least quarterly into an isolated,
access-controlled environment. A drill verifies that a deletion request can be
replayed from `account_deletions` before restored data is made available to any
production-facing process. Backup retention and deletion propagation must be
recorded in the launch-country privacy review.

## Launch-country privacy review

Before the one-city pilot, privacy/legal approves: controller/processor roles;
local age/consent rules; safety-retention period; deletion-response timeline;
subprocessor and object-storage residency; lawful-access procedure; data
subject request contact; incident notification rules; and backup/PITR schedule.
Any unresolved item keeps invitation matching and broad launch disabled.
