# Secret rotation

1. Keep production secrets only in the approved secret manager. Source code,
   analytics, logs, error reports, tickets, and shell history must not contain
   their values.
2. Inventory owners and rotation cadence for database credentials, Phoenix
   secret key base, signing keys, OAuth/WebAuthn configuration, push tokens,
   media signing keys, and integration credentials.
3. Create a replacement version, deploy consumers that accept it, validate
   readiness and a synthetic authenticated flow, then revoke the prior version.
4. For suspected exposure, disable/revoke first, rotate dependent credentials,
   revoke impacted sessions where appropriate, and open an incident.
5. Confirm old versions no longer work and record secret *identifiers*, timing,
   operator, and evidence—not secret values.
