# Production runbooks

These runbooks apply to the Phoenix API, its managed PostgreSQL service, Oban,
and vendor adapters. They intentionally use no vendor credentials, user data,
or production identifiers. Operators must record the incident/change ticket,
correlation IDs, and the minimum necessary evidence in the approved system.

Runbooks:

- [Threat model](threat-model.md)
- [Dependency patching](dependency-patching.md)
- [Secure transport](secure-transport.md)
- [Secret rotation](secret-rotation.md)
- [Production access review](production-access-review.md)
- [Backup and restore verification](backup-restore.md)
