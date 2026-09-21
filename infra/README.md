# Infrastructure configuration

Keep deployment manifests, environment templates, monitoring configuration, and
operational runbooks here as they are selected. Infrastructure must reference
secrets by secret-manager identifier; it must not contain secret values.

Local Docker Compose remains at the repository root. Production topology and
environment separation are defined in `docs/TripPals_Architecture_Plan.md`.
