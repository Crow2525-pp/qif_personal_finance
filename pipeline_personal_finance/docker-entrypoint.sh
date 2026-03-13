#!/bin/sh
set -eu

if [ -n "${DAGSTER_HOME:-}" ]; then
  mkdir -p "$DAGSTER_HOME"
fi

exec "$@"
