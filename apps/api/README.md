# Phoenix API workspace

The Phoenix application lives in `service/` and is run directly on the host for
local development. Docker is not part of the local workflow.

## Bootstrap

From the repository root, ensure the local PostgreSQL 14 Homebrew service is
running, then:

```sh
cp .env.example .env
make bootstrap-api
make setup-api
make test-api
make up
```

`make up` runs the API at `http://127.0.0.1:4000`. Verify it with
`curl http://127.0.0.1:4000/v1/hello`; `GET /up` is also available for health
checks. The root `.env` supplies the local development and test database URLs
and is deliberately gitignored.

`GET /ready` additionally checks that PostgreSQL is reachable without exposing
database configuration. Staging and production run as `MIX_ENV=prod` releases:
their database URL, signing key, permitted browser origins, and any future
OAuth/WebAuthn, push, object-storage, and analytics credentials come from the
deployment secret manager. Run release migrations with `bin/trip_pals eval
"TripPals.Release.migrate"` (or the generated `bin/migrate` helper) before
starting the release.

Local development uses only the Homebrew `postgresql@14` service on
`127.0.0.1:5432`. Production uses a managed PostgreSQL deployment with TLS,
point-in-time recovery and restore verification, encrypted backups, and
separate least-privilege application and operations credentials; those
operational settings do not belong in this repository.

Keep the
backend modular: contexts in `lib/trip_pals/`, HTTP adapters in
`lib/trip_pals_web/controllers/v1/`, Channels in `lib/trip_pals_web/channels/`,
and migrations in `priv/repo/migrations/`.

For manual API verification, import the synthetic local Postman collection at
[`contracts/postman/TripPals_API.postman_collection.json`](../../contracts/postman/TripPals_API.postman_collection.json)
and follow [`docs/API_TESTING_GUIDE.md`](../../docs/API_TESTING_GUIDE.md). The guide
includes the authorization roles, WebAuthn/provider limitations, privacy checks,
and cleanup sequence for every shipped feature.
