# https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
#
# We base the add-on on the official Windmill image. It already ships the
# `windmill` binary together with all the language runtimes (Deno, Bun,
# Python, Go) the workers need at runtime, so we only have to add a bundled
# PostgreSQL plus a small launcher.
ARG BUILD_FROM=ghcr.io/windmill-labs/windmill:1.602.0
FROM ${BUILD_FROM}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install PostgreSQL (server + client) and a couple of small utilities used
# by the launcher script. The Windmill base image is Debian bookworm.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        postgresql \
        postgresql-client \
        ca-certificates \
        curl \
        jq \
        tini \
        gosu \
 && rm -rf /var/lib/apt/lists/*

# Copy add-on launcher and helper files.
COPY rootfs/ /

RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/wait-for-postgres.sh

# Tini handles signals and reaps zombies cleanly. The launcher itself
# supervises the postgres / windmill server / windmill worker children and
# exits if any of them dies, which is what Home Assistant expects.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/run.sh"]

LABEL \
    io.hass.name="Windmill" \
    io.hass.description="Open-source workflow engine and developer platform" \
    io.hass.type="addon" \
    io.hass.arch="aarch64|amd64" \
    org.opencontainers.image.title="Home Assistant Add-on: Windmill" \
    org.opencontainers.image.description="Self-hosted Windmill (server + worker + bundled PostgreSQL) for Home Assistant" \
    org.opencontainers.image.source="https://github.com/your-username/ha-windmill-addon" \
    org.opencontainers.image.licenses="Apache-2.0"
