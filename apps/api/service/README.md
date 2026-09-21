# TripPals API

Run local development from the repository root. It uses the Homebrew
`postgresql@14` service directly; Docker is not used.

```sh
cp .env.example .env
brew services start postgresql@14
make bootstrap-api
make setup-api
make test-api
make up
```

The API listens at `http://127.0.0.1:4000`. Confirm setup with:

```sh
curl http://127.0.0.1:4000/v1/hello
# {"data":{"message":"Hello, TripPals!"}}
```

`GET /up` provides the unauthenticated health response. The repository-root
`.env` contains local database URLs and is intentionally not tracked.
