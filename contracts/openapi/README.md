# API contracts

`trippals-v1.json` is the authoritative machine-readable contract for the API
surface that has shipped. Every new endpoint must update it and add a contract
test. Public application routes live under `/v1`; operational `/up` and
`/ready` checks are intentionally outside that namespace.

Model public IDs as opaque UUID strings, document idempotency and
optimistic-concurrency headers on mutations, and define separate guest/member/
host/staff response schemas where fields differ.

The API contract must never make private meeting details, invitation
availability, contact data, report material, or chat bodies available to an
unauthorized response shape.
