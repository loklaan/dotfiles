#!/usr/bin/env bash

#|-----------------------------------------------------------------------------|
#| Tracing functions                                                           |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Provides OpenTelemetry tracing integration for shell commands using        |
#| otel-desktop-viewer and otel-cli.                                           |
#|                                                                             |
#| NOTE: Unfinished, please don't use.                                        |
#|                                                                             |
#|-----------------------------------------------------------------------------|

GOPATH="$HOME/.go"
otel_viewer="$GOPATH/bin/otel-desktop-viewer"
otel_cli="$GOPATH/bin/otel-cli"

_tracing_start_server() {
  if [ -x "$otel_viewer" ] && [ -x "$otel_cli" ]; then
    export _ZSH_BENCH_SERVER_HTTP_PORT=3333
    export _ZSH_BENCH_SERVER_OTPL_PORT=4318
    export _ZSH_BENCH_SERVER_OTPL_GRPC_PORT=4317
    export OTEL_UI="http://localhost:${_ZSH_BENCH_SERVER_HTTP_PORT}"
    export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:${_ZSH_BENCH_SERVER_OTPL_PORT}"
    export OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
    export OTEL_TRACES_EXPORTER="otlp"

    # Start otel-desktop-viewer in a screen session named "otel"
    # To resume this session later: screen -r otel
    # To detach from session: Ctrl+A, then press D
    screen -dmS otel "$otel_viewer" \
      --http-port=${_ZSH_BENCH_SERVER_HTTP_PORT} \
      --otlp-http-port=${_ZSH_BENCH_SERVER_OTPL_PORT} \
      --otlp-grpc-port=${_ZSH_BENCH_SERVER_OTPL_GRPC_PORT}
  else
    echo "Tracing disabled."
  fi
}

_tracing_span_exec() {
  if [ -x "$otel_cli" ] && [ -n "$OTEL_EXPORTER_OTLP_ENDPOINT" ]; then
    "$otel_cli" exec "$@"
  fi
}