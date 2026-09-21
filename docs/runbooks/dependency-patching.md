# Dependency scanning and patching

1. Run the locked dependency scanner in CI for every pull request and nightly;
   fail release promotion on a known exploitable critical/high issue unless a
   time-bound security exception is approved.
2. Review direct and transitive Elixir, Erlang/OTP, JavaScript build, mobile,
   operating-system, and deployment dependencies.
3. Triage by exploitability in TripPals' deployed configuration, not CVSS alone.
   Record owner, mitigation, patch target, and planned verification.
4. Patch urgent remotely exploitable issues immediately through the normal
   review/release path; run focused tests plus `mix precommit` before promotion.
5. Rotate affected secrets and invalidate affected sessions if the advisory
   warrants it. Never paste secrets, tokens, or exploit payloads into tickets.
6. Re-scan the promoted artifact and retain the result with its immutable
   release record.
