# Backup and restore verification

1. Confirm managed PostgreSQL backups, encryption, cross-failure-domain copies,
   point-in-time recovery, and retention meet the production baseline.
2. At least monthly, restore a recent backup into an isolated environment with
   no public ingress and no production push/analytics/error-reporting keys.
3. Verify schema migration state, referential integrity, critical indexes,
   activity/participation consistency, outbox records, and application
   readiness against the restored database.
4. Measure recovery point and recovery time, compare against objectives, then
   securely destroy the temporary restore according to the retention policy.
5. Store the date, backup identifier, operator, duration, validation results,
   and remediation tickets. Never store restored user content in the report.
