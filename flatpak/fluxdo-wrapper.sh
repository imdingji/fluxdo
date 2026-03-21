#!/usr/bin/env bash

set -euo pipefail

export LD_LIBRARY_PATH="/app/fluxdo/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cd /app/fluxdo
exec /app/fluxdo/fluxdo "$@"
