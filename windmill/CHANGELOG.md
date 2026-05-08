<!-- https://developers.home-assistant.io/docs/add-ons/presentation#keeping-a-changelog -->

## 0.3.0

- Home Assistant integration is now opt-in via the new
  `expose_homeassistant_token` config option (default: off). When on, the
  add-on re-exports the Supervisor-issued token as `HOMEASSISTANT_TOKEN`
  + `HOMEASSISTANT_URL` and adds them to `WHITELIST_ENVS` so Windmill
  Python/Deno/Bun sandboxes can read them. When off, `SUPERVISOR_TOKEN`
  is actively unset before Windmill starts so no job — including bash —
  can pick it up.
- `homeassistant_api: true` is set in the manifest so HA grants the
  add-on API access; whether jobs actually see the token is controlled
  by the user via the option above.
- Add four integration recipes plus a security trade-off note to DOCS.md
  (call HA service, read state, trigger Windmill from HA, subscribe to
  HA events via WebSocket trigger).

## 0.2.2

- Drop `startup`, `boot`, `hassio_role`, `host_network` from `config.yaml`
  and `args: {}` from `build.yaml` — all of them just restated defaults
  that the add-on linter rejects.
- No add-on functional changes.

## 0.2.1

- CI: cancel superseded builder/lint runs on the same branch.
- No add-on functional changes (image content identical to 0.2.0).

## 0.2.0

- Switch to prebuilt multi-arch images from
  `ghcr.io/dodoooh/addon-windmill`. Home Assistant now pulls the image
  instead of building it locally — first install drops from minutes to
  seconds.
- Added GitHub Actions builder workflow.

## 0.1.0

- Initial release.
- Bundles Windmill `1.699.0` server + worker with PostgreSQL on
  `/data/postgres`.
- Exposes the Windmill UI on port `8000`.
- Configurable number of workers, log level, telemetry, EE license key and
  optional external database URL.
