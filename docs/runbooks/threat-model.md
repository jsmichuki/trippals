# Threat model review

Run this before launch, every material architecture change, and after a safety
or security incident.

1. Enumerate trust boundaries: mobile client, HTTPS/WSS edge, Phoenix API,
   PostgreSQL, object storage, push providers, analytics/error reporting, and
   admin access.
2. Review spoofing, tampering, repudiation, information disclosure, denial of
   service, and privilege escalation for each boundary.
3. Confirm server authority for sessions, lifecycle transitions, capacity,
   invitations, chat membership, media access, and staff actions.
4. Verify controls for tokens, WebAuthn assertions, CSRF/browser admin access,
   rate limits, idempotency, optimistic concurrency, blocks/restrictions, and
   audit trails.
5. Confirm telemetry/error/analytics fields remain allow-listed and cannot
   contain chat, meeting, identity, location, availability, or report content.
6. Record risks, owners, due dates, and acceptance decisions in the approved
   security tracker; do not copy sensitive payloads into the record.

Launch is blocked for any unowned high-severity risk affecting account access,
private meeting details, chat authorization, moderation evidence, or database
integrity.
