# Home Assistant Add-on: Windmill

## About

This add-on runs a self-contained [Windmill](https://www.windmill.dev/)
deployment inside Home Assistant:

- **Windmill server** — serves the web UI and API on port `8000`.
- **Windmill worker(s)** — execute scripts, flows and apps.
- **PostgreSQL** — bundled database, persisted under `/data/postgres`.

All state lives on the add-on's persistent `/data` volume, so updating the
add-on or rebooting Home Assistant keeps your scripts, flows, schedules and
job history intact.

## Installation

1. Add this repository to Home Assistant:
   **Settings → Add-ons → Add-on Store → ⋮ → Repositories**.
2. Install the **Windmill** add-on.
3. (Optional) Tweak the configuration — see below.
4. Start the add-on, watch the log until you see
   `Starting Windmill server` and the worker lines, then click **Open Web UI**.

## First-time login

Default credentials on a fresh database:

- Email: `admin@windmill.dev`
- Password: `changeme`

Change them from the Windmill UI right away.

## Configuration

```yaml
base_url: ""
num_workers: 1
log_level: info
disable_telemetry: true
enterprise_license_key: ""
external_database_url: ""
```

### Option: `base_url`

Public URL under which Windmill is reachable, e.g.
`https://windmill.example.com` if you front the add-on with a reverse proxy.
Leave empty when you only access it via `http://homeassistant.local:8000/`.
Webhook and OAuth callback URLs in Windmill are generated from this value, so
set it correctly if you intend to use those features behind a custom domain.

### Option: `num_workers`

Number of worker processes to run alongside the server. One worker is enough
for light personal use; bump this to 2–4 if you run many flows in parallel.
Each worker uses roughly 1 vCPU and 200–500 MB of RAM at idle and more under
load — pick a value your hardware can handle.

### Option: `log_level`

Verbosity of the Windmill log output. One of `debug`, `info`, `warn`,
`error`. Defaults to `info`.

### Option: `disable_telemetry`

When `true` (default), Windmill's anonymous telemetry is disabled.

### Option: `enterprise_license_key`

Optional Windmill Enterprise Edition license key. Leave empty for the
standard open-source build.

### Option: `external_database_url`

Optional. If you would rather point Windmill at an existing PostgreSQL
instance (e.g. on a NAS, a separate Pi, or a managed cloud database), put
its connection string here in the form
`postgres://USER:PASSWORD@HOST:5432/windmill`.

When set, the add-on does **not** start its bundled PostgreSQL. The user in
the connection string must own the target database (or have the
`windmill_admin` and `windmill_user` roles granted) — see the upstream
[self-hosting docs](https://www.windmill.dev/docs/advanced/self_host) for
the SQL bootstrap script Windmill expects.

## Data and persistence

| Path                   | Purpose                                      |
|------------------------|----------------------------------------------|
| `/data/postgres`       | Bundled PostgreSQL data directory.           |
| `/data/postgres-log`   | PostgreSQL log files.                        |
| `/data/.postgres_password` | Generated password for the `windmill` Postgres role. |
| `/share`               | Mounted into the container; usable from Windmill scripts to read/write Home Assistant shared files. |

If you want to fully reset Windmill, stop the add-on and delete the
`postgres` directory from `/data` (visible via the Samba/SSH add-ons).

## Updating

The add-on tracks a specific Windmill version in its `Dockerfile`. To pick
up a newer release, install the latest version of the add-on from the
add-on store. Database schema migrations are run automatically by the
Windmill server on startup.

## Limitations

- **Process isolation:** Home Assistant add-ons don't have access to
  `nsjail`, so Windmill's optional `nsjail` sandboxing is disabled. Scripts
  run as ordinary processes inside the add-on container — only run scripts
  you trust, just as you would on any self-hosted Windmill instance.
- **Single-container setup:** Server, worker(s) and PostgreSQL share one
  container. For heavy multi-worker production use cases, follow the
  upstream Docker Compose / Helm guides on a separate machine instead.
- **Architecture:** Only `amd64` and `aarch64` are supported. Older 32-bit
  Raspberry Pi installations cannot run Windmill.

## Support

- Windmill upstream docs: <https://www.windmill.dev/docs>
- Issues with this add-on: open a GitHub issue against the repository that
  hosts it.
