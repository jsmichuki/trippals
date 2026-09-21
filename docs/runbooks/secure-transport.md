# Secure transport

1. Terminate public HTTPS/WSS with current TLS and redirect HTTP before any API
   handler accepts credentials. Production Phoenix is configured to respect the
   trusted forwarded-proto header and emit HSTS.
2. Restrict edge-to-API traffic to the private deployment network; do not expose
   PostgreSQL, Oban, or object-storage control endpoints publicly.
3. Require TLS for managed PostgreSQL connections, validate the provider CA,
   and use least-privilege database credentials.
4. Limit CORS to reviewed app origins. Validate WebAuthn RP IDs/origins and
   provider JWT issuer/audience on the server.
5. At least quarterly, test TLS configuration, HSTS, CORS rejection, WSS auth,
   and database TLS from an external and internal vantage point.
6. Treat certificate/private-key exposure as an incident: revoke/replace the
   material, investigate access, and record the rotation without logging it.
