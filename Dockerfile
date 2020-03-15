# Base system
FROM hexpm/elixir:1.10.1-erlang-22.2.6-alpine-3.11.3 as builder
ENV MIX_ENV=prod
ENV VERSION=1
RUN apk add --update git build-base
WORKDIR /opt/app
COPY mix.* /opt/app/
RUN mix do \
  local.hex --force, \
  local.rebar --force, \
  deps.get, \
  deps.compile

# Build release
FROM builder as releaser
COPY lib /opt/app/lib
RUN \
  mkdir -p /opt/built && \
  mix compile && \
  mix release --overwrite && \
  cp -r _build/prod/rel/elementary/* /opt/built/

# Build production image
FROM hexpm/elixir:1.10.1-erlang-22.2.6-alpine-3.11.3 as runner
RUN apk add --update inotify-tools
ENV USER=elementary
ENV UID=12345
ENV GID=23456

RUN addgroup --gid "$GID" "$USER" \
  && adduser \
  --disabled-password \
  --gecos "" \
  --home "$(pwd)" \
  --ingroup "$USER" \
  --no-create-home \
  --uid "$UID" \
  "$USER"

COPY --from=releaser /opt/built /opt/app/
WORKDIR /opt/app
ENV REPLACE_OS_VARS=true \
  LANG=C.UTF-8 \
  PATH=/opt/bin:$PATH

ENTRYPOINT ["bin/elementary"]
CMD ["start"]
