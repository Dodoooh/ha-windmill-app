# Windmill Home Assistant Add-on Repository

This repository contains a Home Assistant add-on that deploys
[Windmill](https://www.windmill.dev/) — an open-source developer platform and
workflow engine for scripts, flows and apps — directly inside your Home
Assistant Operating System installation.

[![Open your Home Assistant instance and show the add-on store with this repository.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FDodoooh%2Fha-windmill-app)

## Add-ons in this repository

### [Windmill](./windmill)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

Self-hosted Windmill instance (server + worker + bundled PostgreSQL) running
as a Home Assistant add-on.

## Installation

1. In Home Assistant go to **Settings → Add-ons → Add-on Store**.
2. Click the three-dot menu in the top-right and choose **Repositories**.
3. Paste the URL of this repository and click **Add**.
4. Refresh the store and install the **Windmill** add-on.
5. Start the add-on and open the Web UI.

The default login on first start is `admin@windmill.dev` / `changeme` — change
it immediately from the Windmill UI.

## Requirements

- Home Assistant Operating System (or Supervised). Add-ons are not available
  on Home Assistant Container or Core installations.
- An `amd64` or `aarch64` host. A Raspberry Pi 4 with at least 2 GB of free
  RAM is the practical minimum; 4 GB+ is recommended.

## Disclaimer

This add-on is a community integration of Windmill into Home Assistant. It is
not officially affiliated with [Windmill Labs, Inc.](https://www.windmill.dev/)
or the [Home Assistant](https://www.home-assistant.io/) project.

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
