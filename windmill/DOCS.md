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

## Talking to Home Assistant

The add-on can hand its Supervisor token to Windmill jobs so scripts and
flows can call the Home Assistant REST API without the user having to
create and paste a long-lived token. **This is opt-in and disabled by
default** — set `expose_homeassistant_token: true` in the add-on
configuration to enable it.

When enabled, the launcher exports two environment variables and adds
them to `WHITELIST_ENVS` so Python / Deno / Bun / Go sandboxes can read
them:

| Variable | Value |
|---|---|
| `HOMEASSISTANT_URL` | `http://supervisor/core` |
| `HOMEASSISTANT_TOKEN` | Per-add-on token managed by the Supervisor |

When disabled (default) the launcher actively unsets `SUPERVISOR_TOKEN`
before starting Windmill, so no script — not even a bash one — can read
it. If you want HA access in this mode, generate a long-lived token in
HA (*Profile → Long-lived access tokens*), store it as a Windmill
*Variable* (marked secret) or *Resource*, and reference it from your
scripts.

### Security trade-off

The opt-in token is short-lived (rotates on every add-on restart) and
never touches disk, but **anyone who can run a Windmill job inherits
full HA-REST-API access**. Only enable this if you are the sole admin of
both Windmill and Home Assistant, or if every Windmill workspace user is
trusted with HA-admin-equivalent rights.

### Recipe 1 — Call an HA service from Windmill (Python)

```python
import os, requests

def main(entity_id: str = "light.living_room"):
    url = os.environ["HOMEASSISTANT_URL"]
    token = os.environ["HOMEASSISTANT_TOKEN"]
    r = requests.post(
        f"{url}/api/services/light/toggle",
        headers={"Authorization": f"Bearer {token}"},
        json={"entity_id": entity_id},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()
```

### Recipe 2 — Read HA state from Windmill (TypeScript / Deno)

```ts
export async function main(entity: string = "sensor.outside_temperature") {
  const url = Deno.env.get("HOMEASSISTANT_URL")!;
  const token = Deno.env.get("HOMEASSISTANT_TOKEN")!;
  const res = await fetch(`${url}/api/states/${entity}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`HA returned ${res.status}`);
  return await res.json();
}
```

### Recipe 3 — Trigger a Windmill flow from a Home Assistant automation

In Windmill, open your script or flow and copy its **webhook URL** from
the *Triggers → Webhooks* tab (something like
`http://<addon-host>:8000/api/w/admins/jobs/run/p/u/admin/my_flow`). Then
in HA's `configuration.yaml`:

```yaml
rest_command:
  run_windmill_flow:
    url: "http://a0d7b954-windmill:8000/api/w/admins/jobs/run/p/u/admin/my_flow"
    method: POST
    headers:
      Authorization: "Bearer !secret windmill_token"
    content_type: "application/json"
    payload: '{"some_arg": "{{ trigger.payload }}"}'
```

`a0d7b954-windmill` is the internal hostname HA assigns to this add-on
on the `hassio` Docker network (you can also use `homeassistant.local:8000`
from outside). The Windmill token comes from *Account → Tokens* in the
Windmill UI — store it as a HA secret.

Use the `rest_command` from any automation:

```yaml
automation:
  - alias: "Run Windmill flow at 7am"
    trigger:
      platform: time
      at: "07:00:00"
    action:
      service: rest_command.run_windmill_flow
      data:
        some_arg: "good morning"
```

### Recipe 4 — Subscribe to HA events from Windmill (advanced)

Windmill has a built-in WebSocket trigger. Point it at
`ws://supervisor/core/api/websocket`, send the standard HA auth handshake
(`{"type":"auth","access_token":"<HOMEASSISTANT_TOKEN>"}`) followed by
`{"id":1,"type":"subscribe_events","event_type":"state_changed"}`, and
your flow will be invoked once per HA event. This replaces a Node-RED
`events: state` node — without the always-on flow runtime.

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
