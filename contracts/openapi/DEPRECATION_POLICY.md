# API versioning and deprecation policy

TripPals adds backward-compatible fields to `/v1` without changing their
meaning. Breaking behavior or schema changes require a new versioned route.

Before deprecating a `/v1` operation, publish its replacement in the OpenAPI
contract, add a `Deprecation` response header and a `Sunset` date at least 90
days ahead, notify active integrators, and retain contract tests until removal.
Security fixes may shorten this window only when documented in an ADR.
