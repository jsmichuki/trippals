.DEFAULT_GOAL := help

.PHONY: help bootstrap-api setup-api up down test-api format-api

help:
	@printf '%s\n' \
	  'make bootstrap-api  Fetch Phoenix dependencies (or generate the API if absent)' \
	  'make setup-api      Create the local development and test databases' \
	  'make up             Run the Phoenix API directly on this machine' \
	  'make down           Stop the local PostgreSQL 14 Homebrew service' \
	  'make test-api       Run Phoenix tests against local PostgreSQL 14' \
	  'make format-api     Format Phoenix code'

bootstrap-api:
	@if [ -d apps/api/service ]; then \
		cd apps/api/service && mix deps.get; \
	else \
		cd apps/api && mix archive.install hex phx_new --force && \
		mix phx.new service --app trip_pals --module TripPals --database postgres \
			--no-html --no-live --no-mailer --no-assets --no-gettext --no-dashboard --install; \
	fi

setup-api:
	@set -a; . ./.env; set +a; cd apps/api/service && mix ecto.create && mix ecto.migrate
	@set -a; . ./.env; set +a; cd apps/api/service && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate

up:
	@set -a; . ./.env; set +a; cd apps/api/service && mix phx.server

down:
	brew services stop postgresql@14

test-api:
	@set -a; . ./.env; set +a; cd apps/api/service && MIX_ENV=test mix test

format-api:
	@set -a; . ./.env; set +a; cd apps/api/service && mix format
