<!-- https://developers.home-assistant.io/docs/add-ons/presentation#keeping-a-changelog -->

## 0.1.0

- Initial release.
- Bundles Windmill `1.602.0` server + worker with PostgreSQL on
  `/data/postgres`.
- Exposes the Windmill UI on port `8000`.
- Configurable number of workers, log level, telemetry, EE license key and
  optional external database URL.
