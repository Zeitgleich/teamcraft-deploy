# Changelog

Changes of the playbook. Each release pins a TeamCraft version (`teamcraft_version`); entries marked
**Breaking** need you to act before running `just install-all` (docs/updating.md). Format: [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- The SFU's call fallback listens on the upstream address only (`127.0.0.1:8082` by default,
  `TEAMCRAFT_SFU_FALLBACK_BIND`). With TeamCraft 1.0.20 or later and host networking it listened on
  `[::]:8082`, plain HTTP on every address of the host, guarded only by the firewall. Move it with
  `teamcraft_ports.sfu_fallback` if 8082 is taken on the host.

- Caddy and the generated nginx, Plesk, Apache and HAProxy files answer `/share-target` with a 303 without
  reading the body. A share from another app can carry plaintext files, which a buffering proxy would
  otherwise keep on disk. Web shares stay off in TeamCraft until this is rolled out. Own proxies:
  docs/reverse-proxy.md. Traefik doesn't buffer, so nothing changes there.
- **Breaking:** the SFU's default port is now **udp/3478** (was 4433), the STUN/TURN port restrictive
  firewalls often allow already. Open udp/3478 (IPv4 and IPv6) in any host or hoster firewall before
  running `just install-all`, or keep the old port with `teamcraft_ports.sfu: 4433`.

### Added

- The SFU's call fallback goes through the reverse proxy (TeamCraft#1226): clients whose network blocks
  UDP reach the SFU over a WebSocket at `wss://<teamcraft_sfu_hostname>/call/ws` on TCP 443. The path
  needs a TeamCraft release that serves `/call/ws` (TeamCraft#TBD; earlier releases call it
  `/call/fallback`, which the proxies don't route). New loopback port `teamcraft_ports.sfu_fallback` (8082),
  checked by the preflight. Caddy routes exactly `/call/ws` on the SFU's name to it, with
  `stream_close_delay 5m`; the generated nginx, Plesk, Apache, HAProxy and Traefik configurations have a
  site for the SFU's name with that route, which so far only had a certificate. Behind Plesk, when the
  SFU's name is an alias of the chat domain, `teamcraft_proxy_sfu_alias_of` puts the location into
  that domain's directives. `just self-check` expects `101` from the route. **Own proxy:** paste or
  copy the regenerated configuration after `just install-all` (docs/reverse-proxy.md); until then
  clients on such networks fail to join, as before.
- The SFU container's open file limit is raised to 4096 (`teamcraft_sfu_nofile`) for the fallback's
  connections.

- GlitchTip stores and shows the spans of performance transactions (`glitchtip_duckdb_enabled`, on by
  default): its DuckDB cold storage was off, so every transaction group showed "No span data". The worker
  moves spans every 5 minutes into Parquet files in the new volume `glitchtip-cold-storage` (or the S3
  bucket with `glitchtip_s3_endpoint`); raw spans are kept for `glitchtip_span_raw_retention_days` (30).
- Optional role `glitchtip` (`glitchtip_enabled`, off by default): GlitchTip 6.2.6, a self-hosted error
  tracker that speaks the Sentry protocol, for the crash reports of TeamCraft's apps (TeamCraft#1508).
  Web, one worker and Valkey run rootless as `tc-glitchtip` (about 1 GB), on loopback behind Caddy or the
  generated proxy configurations at `glitchtip_hostname` (default `glitchtip.<domain>`: add its DNS
  records). Its database is in the bundled Postgres, which then runs with `max_locks_per_transaction =
  512` (one Postgres restart when you turn it on) and is in the nightly dumps. Registration is closed;
  the playbook creates a superuser for `glitchtip_admin_email` with a generated password. Events are
  kept for `glitchtip_retention_days` (30). Any other Sentry-protocol backend works as well: TeamCraft
  only needs a DSN (docs/components/glitchtip.md). `DRY_RUN_GLITCHTIP=1` adds it to the dry run.
- GlitchTip on a host of its own: the play "Set up crash reports (GlitchTip) on its own host" for the new
  inventory group `[teamcraft_crash_reports]` installs only Postgres (database `glitchtip`) and GlitchTip,
  behind the web server the host already runs, and writes Plesk, Apache and nginx configurations to
  `/srv/teamcraft/reverse-proxy/glitchtip/`. It can share a machine with the push gateway under a second
  inventory name; ports are `teamcraft_ports.glitchtip`, `glitchtip_valkey` and `postgres`.
  `DRY_RUN_CRASH_REPORTS=1 test/gateway-dry-run.sh` tests it next to the push gateway.
- GlitchTip organization roles from the identity provider: with `glitchtip_sso_role_claim` (e.g.
  `glitchtip_roles`), a timer (`glitchtip_sso_role_sync_interval`, 5 minutes) sets the role of everyone
  who signs in through an organization's SSO app from that claim (`glitchtip_sso_role_map`), and removes
  members without one (`glitchtip_sso_remove_without_role`). Local accounts and an organization's last
  owner are never touched. Roles follow the claim as of the person's last SSO sign-in.

- The SFU role raises the host's `net.core.rmem_max` to at least 4 MiB (`teamcraft_sfu_rmem_max_bytes`,
  in `/etc/sysctl.d/60-teamcraft.conf`), so the SFU gets the UDP receive buffer it asks for and a big
  keyframe isn't lost while it is busy. The next `just install-all` restarts the SFU once, which
  interrupts running calls briefly. Details: docs/components/teamcraft-sfu.md.
- Optional role `teamcraft_notetaker` (`teamcraft_notetaker_enabled`, off by default): the notetaker
  from the TeamCraft release that adds it (TeamCraft#984), an AI participant that transcribes calls
  through OpenRouter and posts a summary and the transcript. It listens on no port and runs with a
  liveness-file health check; its image follows `teamcraft_version`. The bot token
  (`notetaker_bot_token`, from the admin console) goes in the sops file, as does the OpenRouter key if it
  should not be stored on the server (`notetaker_openrouter_api_key`); the database key and recovery
  passphrase are generated. It takes call audio out of the end-to-end encryption, about $0.22 per meeting
  hour: read docs/components/teamcraft-notetaker.md before turning it on.

- `teamcraft_oidc_app_scopes` (default adds `offline_access`): devices get long-lived refresh tokens and
  stay signed in instead of following the provider's browser session.

- Optional role `teamcraft_bridge` (`teamcraft_bridge_enabled`, off by default): the integration bridge
  from TeamCraft 1.0.4 on, so webhooks and log lines reach encrypted channels. Caddy and the generated
  proxy configurations route `/hooks/` and `/ingest/` of `teamcraft_domain` to it; it listens on
  loopback. The bot token (`bridge_bot_token`, from the admin console) goes in the sops file; the
  database key and recovery passphrase are generated (docs/components/teamcraft-bridge.md).

- Generated secret `settings_key`, passed to the server as `TEAMCRAFT_SECRETS__KEY`: the admin console can
  now store passwords (mail server, CalDAV). Keep it with your backups; without it, stored passwords
  can't be read.

- The web client's archive is checked against the release's `SHA256SUMS` by itself
  (`teamcraft_server_web_sums_url`): a version bump no longer needs a new `teamcraft_server_web_checksum`,
  which stays as an optional override.

- Ubuntu 24.04 for the whole stack (Podman 4.9 from Ubuntu's archive; `crun` is installed with it, because
  Docker's `runc` can't start the read-only containers). Tested on an Ubuntu 24.04 VM laid out like a Plesk
  server, with nginx, Docker and its own PostgreSQL on 5432.
- Two nginx configurations: `nginx/teamcraft.conf` for nginx 1.25.1 and newer with HTTP/2 and HTTP/3,
  `nginx/teamcraft-legacy.conf` for older nginx (Ubuntu 24.04's 1.24) with HTTP/2.
- `teamcraft_ports` can name only the ports you move; the others keep their defaults
  (`teamcraft_port_defaults`).
- Preflight checks on servers: the playbook's firewall on a host with Docker (as with Plesk), and on Ubuntu
  a cgroup v1 hierarchy next to v2.
- The push gateway behind a web server the host already runs (Plesk, Apache, nginx):
  `push_gateway_caddy_enabled: false` binds nothing to 80/443 and writes the proxy configuration (Plesk's
  additional Apache or nginx directives, a plain Apache vhost or nginx server block) to
  `/srv/teamcraft/reverse-proxy/push-gateway/`; `push_gateway_upstream_address` picks its loopback address.
- Push gateway hosts can run Ubuntu 24.04 (Podman 4.9 from Ubuntu's archive) as well as Debian 13.
- Preflight checks on gateway hosts: 80/443 taken while its Caddy is enabled, its ports taken, the
  playbook's firewall on a host with Plesk or Docker (`push_gateway_preflight_enabled`).
- Behind your own reverse proxy (nginx, Apache, Plesk, Traefik, HAProxy, another Caddy):
  `caddy_enabled: false` binds nothing of TeamCraft to 80/443, trusts the local proxy's forwarded
  headers, and writes configurations for it, filled in with your host names and ports, to
  `/srv/teamcraft/reverse-proxy/` (role `proxy_snippets`). Guide: [docs/reverse-proxy.md](docs/reverse-proxy.md)
  with a page per proxy, Plesk step by step.
- The SFU can use an existing certificate (`teamcraft_sfu_certificate_path` / `_key_path`, or
  `teamcraft_sfu_certificate_nginx_conf` for Plesk's renamed files): a root path unit and timer copy it
  for `tc-sfu` when it changes and the SFU restarts.
- Preflight checks before installing: ports 80/443 taken while Caddy is enabled, a service's port taken
  by other software, the playbook's firewall on a Plesk server (`teamcraft_preflight_enabled`).
- `teamcraft_upstream_address`: the services' loopback address, `127.0.0.1` (default) or `::1`.
- Device tokens are bound to servers: the apps seal them for the push gateway, so the server never holds
  a usable token. `teamcraft_push_gateway_accept_unbound_tokens` / `push_gateway_accept_unbound_tokens`
  (both off) keep old apps working during a transition; the gateway's token keys are in its volume.
- Push gateway for the store apps: `teamcraft_push_gateway_url` points the server at the publisher's
  gateway (default `https://push-gw.zeitgleich.de`) (generated secret `push_gateway_key`), and the optional role `push_gateway` runs a gateway on
  its own host (inventory group `teamcraft_push_gateways`, off by default). See
  [docs/components/push-gateway.md](docs/components/push-gateway.md).
- The gateway is a separate project with its own releases: `push_gateway_version` pins its image.

### Changed

- **The web client is on by default** (`teamcraft_server_web_enabled: true`): releases ship
  `teamcraft-web-<version>.tar.gz`. Set it to `false` for apps only.

- The SFU's certificate copy also watches the certificate's directory: renewals that swap symlinks
  (certbot's and Plesk's `live/`) restart the SFU within seconds instead of within the hour.

- `net.ipv4.ip_unprivileged_port_start` is only lowered to 80 where a bundled Caddy needs it
  (`base_unprivileged_web_ports`; without Caddy it stays at the kernel's 1024).
- `caddy_enabled` moved to `group_vars/teamcraft_servers.yml` (set it in `vars.yml` as before).
- `just self-check` accepts 403 as well as 404 for the refused internal API (Apache and Traefik answer 403).

### Fixed

- The Plesk nginx directives (`plesk/<domain>.conf`, the gateway's `plesk-nginx.conf`) used `location /`,
  which Plesk's own vhost already has: `duplicate location "/"`. The catch-all is a regex location now
  (`~ ^/(?![.]well-known/acme-challenge/)`), which works with proxy mode on or off and leaves Let's
  Encrypt challenges to Plesk.
- A PostgreSQL port other than 5432 (`teamcraft_ports.postgres`): creating the databases, backups and
  restores used the default socket; the container now sets `PGPORT`.
- The SFU's Quadlet unit used `GroupAdd=`, which Podman 4.9 (Ubuntu 24.04) doesn't know; it's a
  `PodmanArgs` option now.

## [1.0.0] - 2026-10-23

First release, for TeamCraft 1.0.0 (`teamcraft_version: "1.0.0"`).

### Added

- One role per component: Caddy, PostgreSQL, TeamCraft server and SFU, bundled Keycloak or an external
  OIDC provider, bundled Garage or external S3, SMTP relay settings, optional CalCraft, backups.
- Rootless Podman + Quadlet, one unprivileged user per service, host networking with loopback-only
  internal ports, nftables firewall for IPv4 and IPv6.
- Secrets generated on the server on the first run; optionally from a sops + age file.
- Tags `install-all`, `setup-all`, `start`, `stop`, `self-check`, `ensure-admin`, `backup` and a
  justfile around them.
- Dry run against a throwaway systemd container, used by CI.
- Brands: several host names on one server (`teamcraft_brands`). Caddy serves every brand host, the bundled Keycloak client gets their redirect URIs and
  web origins on every run, brand images are copied from `teamcraft_server_brand_assets_src`.
- Organizations: `teamcraft_oidc_organization_claim`, and for the bundled Keycloak a token mapper from
  `keycloak_organization_attribute`.

[Unreleased]: https://github.com/Zeitgleich/teamcraft-deploy/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Zeitgleich/teamcraft-deploy/releases/tag/v1.0.0
