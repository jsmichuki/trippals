# TripPals

TripPals is a one-city MVP for discovering, joining, and safely coordinating
small activities. The intended architecture is a Phoenix/PostgreSQL modular
monolith and Kotlin Multiplatform mobile client.

## Repository map

```text
apps/api/          Phoenix API workspace and generated service
apps/mobile/       Kotlin Multiplatform workspace
contracts/openapi/ Versioned HTTP API contracts
infra/             Deployment configuration and runbooks
docs/              Product plan, architecture, and ADRs
compose.yaml       Legacy container configuration (not used for local development)
```

## Local foundation

Local development runs directly on the machine. Do not install Docker for this
repository's local workflow. PostgreSQL 14 is provided by Homebrew and Phoenix
runs as a normal host process.

```sh
cp .env.example .env
make bootstrap-api
make setup-api
make test-api
make up
```

Start PostgreSQL if it is not already running with `brew services start
postgresql@14`. `make up` serves the API on `http://127.0.0.1:4000`; verify the
initial endpoint with `curl http://127.0.0.1:4000/v1/hello`.

Read [the architecture plan](docs/TripPals_Architecture_Plan.md) and
[repository guide](AGENTS.md) before implementation.
