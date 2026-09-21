# syntax=docker/dockerfile:1.7

# Update deliberately after checking Phoenix/OTP compatibility and image digests.
FROM hexpm/elixir:1.18.4-erlang-27.2.4-debian-bookworm-20260824-slim AS base

RUN apt-get update \
    && apt-get install --no-install-recommends -y build-essential ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex

RUN mix local.hex --force \
    && mix local.rebar --force \
    && mix archive.install hex phx_new --force \
    && chmod -R a+rX /opt/mix /opt/hex

FROM base AS development

WORKDIR /workspace
ENV MIX_ENV=dev

# The source is mounted by Compose. This target deliberately builds before the
# Phoenix project exists so `make bootstrap-api` can generate it.
CMD ["mix", "phx.server"]

FROM base AS build

WORKDIR /app
ENV MIX_ENV=prod

COPY service/mix.exs service/mix.lock ./
RUN mix deps.get --only "$MIX_ENV" \
    && mix deps.compile

COPY service/config ./config
COPY service/lib ./lib
COPY service/priv ./priv
COPY service/rel ./rel
RUN mix compile \
    && mix release

FROM debian:bookworm-slim AS production

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl libstdc++6 libssl3 ncurses-base \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 trip_pals \
    && useradd --uid 10001 --gid trip_pals --create-home --shell /usr/sbin/nologin trip_pals

WORKDIR /app
COPY --from=build --chown=trip_pals:trip_pals /app/_build/prod/rel/trip_pals ./

USER trip_pals
EXPOSE 4000

# Phoenix's generated release exposes /up once its health route is configured.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD ["curl", "--fail", "--silent", "http://localhost:4000/up"]

CMD ["/app/bin/trip_pals", "start"]
