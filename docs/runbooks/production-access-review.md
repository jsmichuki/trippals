# Production access review

Perform monthly and before each launch expansion.

1. Export identities and role bindings from cloud, database, deployment,
   observability, error-reporting, object-storage, and support systems.
2. Validate every grant against a named role, business justification, MFA, and
   expiry. Remove dormant, shared, break-glass-unused, and departed-user access.
3. Verify least privilege: support cannot query unrelated private data;
   moderators use scoped server paths; database write/admin grants are limited
   to operational roles; log and evidence access are separately restricted.
4. Review admin/moderator audit events, break-glass use, and unsuccessful
   privileged access attempts. Escalate unexplained access promptly.
5. Record reviewer, scope, removals, exceptions, owners, and next review date
   in the approved access-review system without exporting user content.
