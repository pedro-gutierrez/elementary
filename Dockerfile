
FROM elixir:1.10.3-alpine AS builder
RUN apk add build-base curl imagemagick inotify-tools 

RUN mkdir -p /app
WORKDIR /app
ADD lib /app/lib
ADD mix.exs /app
ADD mix.lock /app

ENV MIX_ENV prod

RUN mix local.hex --force && \
    mix local.rebar && \
    mix deps.get && \
    mix release

FROM elixir:1.10.3-alpine
RUN apk add inotify-tools

RUN mkdir -p /app
WORKDIR /app
COPY --from=builder /app/_build/prod /app
ADD examples/bot /app/etc
ENV ELEMENTARY_HOME /app/etc
ENV DEPLOYMENT_VERSION v0.1 
CMD [ "/app/rel/elementary/bin/elementary", "start" ]
