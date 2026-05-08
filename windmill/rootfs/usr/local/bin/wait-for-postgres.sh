#!/usr/bin/env bash
# Block until the local PostgreSQL accepts connections, or fail after timeout.
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-5432}"
TIMEOUT="${3:-60}"

for ((i = 1; i <= TIMEOUT; i++)); do
    if pg_isready -h "${HOST}" -p "${PORT}" -q; then
        exit 0
    fi
    sleep 1
done

echo "[wait-for-postgres] PostgreSQL did not become ready within ${TIMEOUT}s" >&2
exit 1
