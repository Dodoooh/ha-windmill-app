#!/usr/bin/env bash
# =============================================================================
# Home Assistant add-on launcher for Windmill.
#
# Reads /data/options.json (populated by the supervisor from the user's
# add-on configuration), bootstraps a local PostgreSQL cluster on first
# start (unless the user supplied an external_database_url), then runs a
# Windmill server and one or more Windmill worker processes side by side.
#
# Any child dying is treated as fatal: we tear the rest down and exit so
# the supervisor restarts the container.
# =============================================================================
set -euo pipefail

OPTIONS_FILE="/data/options.json"
PG_DATA_DIR="/data/postgres"
PG_RUN_DIR="/var/run/postgresql"
PG_LOG_DIR="/data/postgres-log"
PG_BIN_DIR="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -n1)"
PG_PASSWORD_FILE="/data/.postgres_password"

WINDMILL_BIN="/usr/src/app/windmill"
[[ -x "${WINDMILL_BIN}" ]] || WINDMILL_BIN="$(command -v windmill || true)"
[[ -n "${WINDMILL_BIN}" && -x "${WINDMILL_BIN}" ]] \
    || { echo "[run] Cannot locate windmill binary." >&2; exit 1; }

log() { echo "[run] $*"; }

# ---------------------------------------------------------------------------
# Read configuration from /data/options.json. Use sensible defaults if the
# file is missing (e.g. when running the image outside of HA for testing).
# ---------------------------------------------------------------------------
read_opt() {
    local key="$1" default="$2"
    if [[ -f "${OPTIONS_FILE}" ]]; then
        jq -r --arg k "${key}" --arg d "${default}" \
            '(.[$k] // empty | tostring) as $v | if $v == "" then $d else $v end' \
            "${OPTIONS_FILE}"
    else
        printf '%s' "${default}"
    fi
}

BASE_URL="$(read_opt base_url "")"
NUM_WORKERS="$(read_opt num_workers "1")"
LOG_LEVEL="$(read_opt log_level "info")"
DISABLE_TELEMETRY="$(read_opt disable_telemetry "true")"
EXPOSE_HOMEASSISTANT_TOKEN="$(read_opt expose_homeassistant_token "false")"
ENTERPRISE_LICENSE_KEY="$(read_opt enterprise_license_key "")"
EXTERNAL_DATABASE_URL="$(read_opt external_database_url "")"

# ---------------------------------------------------------------------------
# PostgreSQL bootstrap (skipped when an external DB URL is supplied).
# ---------------------------------------------------------------------------
if [[ -z "${EXTERNAL_DATABASE_URL}" ]]; then
    if [[ -z "${PG_BIN_DIR}" ]]; then
        log "PostgreSQL binaries not found under /usr/lib/postgresql"; exit 1
    fi

    mkdir -p "${PG_DATA_DIR}" "${PG_LOG_DIR}" "${PG_RUN_DIR}"
    chown -R postgres:postgres "${PG_DATA_DIR}" "${PG_LOG_DIR}" "${PG_RUN_DIR}"

    if [[ ! -s "${PG_PASSWORD_FILE}" ]]; then
        # Generated once and stored on the persistent /data volume.
        head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32 > "${PG_PASSWORD_FILE}"
        chmod 600 "${PG_PASSWORD_FILE}"
    fi
    PG_PASSWORD="$(cat "${PG_PASSWORD_FILE}")"

    if [[ ! -s "${PG_DATA_DIR}/PG_VERSION" ]]; then
        log "Initializing PostgreSQL cluster in ${PG_DATA_DIR}"
        gosu postgres "${PG_BIN_DIR}/initdb" \
            -D "${PG_DATA_DIR}" \
            --auth-local=trust \
            --auth-host=scram-sha-256 \
            --encoding=UTF8 \
            --locale=C.UTF-8 >/dev/null

        # Listen only on localhost — we never want to expose Postgres to
        # the HA host network.
        {
            echo "listen_addresses = '127.0.0.1'"
            echo "unix_socket_directories = '${PG_RUN_DIR}'"
            echo "log_min_messages = warning"
        } >> "${PG_DATA_DIR}/postgresql.conf"
    fi

    log "Starting PostgreSQL"
    gosu postgres "${PG_BIN_DIR}/pg_ctl" \
        -D "${PG_DATA_DIR}" \
        -l "${PG_LOG_DIR}/postgres.log" \
        -o "-c listen_addresses=127.0.0.1 -c unix_socket_directories=${PG_RUN_DIR}" \
        -w start

    /usr/local/bin/wait-for-postgres.sh 127.0.0.1 5432 60

    # Ensure the windmill role/database exist.
    if ! gosu postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='windmill'" | grep -q 1; then
        log "Creating windmill role"
        gosu postgres psql -v ON_ERROR_STOP=1 \
            -c "CREATE ROLE windmill WITH LOGIN SUPERUSER PASSWORD '${PG_PASSWORD}';"
    else
        # Keep the password in sync in case the secret file was rotated.
        gosu postgres psql -v ON_ERROR_STOP=1 \
            -c "ALTER ROLE windmill WITH PASSWORD '${PG_PASSWORD}';" >/dev/null
    fi

    if ! gosu postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='windmill'" | grep -q 1; then
        log "Creating windmill database"
        gosu postgres psql -v ON_ERROR_STOP=1 \
            -c "CREATE DATABASE windmill OWNER windmill;"
    fi

    DATABASE_URL="postgres://windmill:${PG_PASSWORD}@127.0.0.1:5432/windmill?sslmode=disable"

    PG_PID_FILE="${PG_DATA_DIR}/postmaster.pid"
    PG_PID="$(head -n1 "${PG_PID_FILE}" 2>/dev/null || true)"
else
    log "Using externally-provided database"
    DATABASE_URL="${EXTERNAL_DATABASE_URL}"
    PG_PID=""
fi

# ---------------------------------------------------------------------------
# Common environment for the Windmill server and worker processes.
# ---------------------------------------------------------------------------
export DATABASE_URL
export RUST_LOG="${LOG_LEVEL}"
export DISABLE_NSJAIL="true"           # nsjail isn't usable inside an HA add-on
export DISABLE_NUSER="true"
export METRICS_ADDR="false"
if [[ -n "${BASE_URL}" ]]; then
    export BASE_URL
fi
if [[ "${DISABLE_TELEMETRY}" == "true" ]]; then
    export DISABLE_TELEMETRY="true"
fi
if [[ -n "${ENTERPRISE_LICENSE_KEY}" ]]; then
    export LICENSE_KEY="${ENTERPRISE_LICENSE_KEY}"
fi

# ---------------------------------------------------------------------------
# Home Assistant integration. The Supervisor injects SUPERVISOR_TOKEN
# whenever `homeassistant_api: true` is set in config.yaml. We only
# re-export it under HOMEASSISTANT_* and add it to WHITELIST_ENVS when the
# user explicitly opts in via `expose_homeassistant_token: true`. When the
# user keeps the default (false) we actively unset SUPERVISOR_TOKEN so no
# Windmill-spawned process — including bash jobs — can pick it up.
# ---------------------------------------------------------------------------
if [[ "${EXPOSE_HOMEASSISTANT_TOKEN}" == "true" && -n "${SUPERVISOR_TOKEN:-}" ]]; then
    log "Exposing Home Assistant token to Windmill jobs (opt-in)"
    export HOMEASSISTANT_URL="http://supervisor/core"
    export HOMEASSISTANT_TOKEN="${SUPERVISOR_TOKEN}"
    export WHITELIST_ENVS="${WHITELIST_ENVS:+${WHITELIST_ENVS},}HOMEASSISTANT_URL,HOMEASSISTANT_TOKEN,SUPERVISOR_TOKEN"
else
    unset SUPERVISOR_TOKEN HOMEASSISTANT_URL HOMEASSISTANT_TOKEN
fi

# ---------------------------------------------------------------------------
# Process supervision: launch one server, N workers; if any of them exits
# we shut everything down and let the HA supervisor restart us.
# ---------------------------------------------------------------------------
PIDS=()

start_windmill() {
    local mode="$1" name="$2"
    log "Starting Windmill ${name}"
    MODE="${mode}" \
    NUM_WORKERS=1 \
    "${WINDMILL_BIN}" &
    PIDS+=("$!")
}

cleanup() {
    local code=$?
    log "Shutting down (exit ${code})"
    for pid in "${PIDS[@]:-}"; do
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    if [[ -n "${PG_PID}" ]]; then
        gosu postgres "${PG_BIN_DIR}/pg_ctl" \
            -D "${PG_DATA_DIR}" -m fast -w stop || true
    fi
    exit "${code}"
}
trap cleanup EXIT INT TERM

start_windmill server server
for ((i = 1; i <= NUM_WORKERS; i++)); do
    start_windmill worker "worker-${i}"
done

# Wait for the first child to exit, then propagate its exit code.
wait -n "${PIDS[@]}"
EXIT_CODE=$?
log "A Windmill process exited with code ${EXIT_CODE}; restarting container"
exit "${EXIT_CODE}"
