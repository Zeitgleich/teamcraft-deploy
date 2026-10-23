# Changelog

Changes of the playbook. Each release pins a TeamCraft version (`teamcraft_version`); entries marked
**Breaking** need you to act before running `just install-all` (docs/updating.md). Format: [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- The push gateway behind a web server the host already runs (Plesk, Apache, nginx):
  `push_gateway_caddy_enabled: false` binds nothing to 80/443 and writes the proxy configuration (Plesk's
  additional Apache or nginx directives, a plain Apache vhost or nginx server block) to
  `/srv/teamcraft/reverse-proxy/push-gateway/`; `push_gateway_upstream_address` picks its loopback address.
- Push gateway hosts can run Ubuntu 24.04 (Podman 4.9 from Ubuntu's archive) as well as Debian 13.
- Preflight checks on gateway hosts: 80/443 taken while its Caddy is enabled, its ports taken, the
  playbook's firewall on a host with Plesk or Docker (`push_gateway_preflight_enabled`).

- Device tokens are bound to servers: the apps seal them for the push gateway, so the server never holds
  a usable token. `teamcraft_push_gateway_accept_unbound_tokens` / `push_gateway_accept_unbound_tokens`
  (both off) keep old apps working during a transition; the gateway's token keys are in its volume.
- Push gateway for the store apps: `teamcraft_push_gateway_url` points the server at the publisher's
  gateway (default `https://push-gw.zeitgleich.de`) (generated secret `push_gateway_key`), and the optional role `push_gateway` runs a gateway on
  its own host (inventory group `teamcraft_push_gateways`, off by default). See
  [docs/components/push-gateway.md](docs/components/push-gateway.md).
- The gateway is a separate project with its own releases: `push_gateway_version` pins its image.

### Changed

- `net.ipv4.ip_unprivileged_port_start` is only lowered to 80 where a bundled Caddy needs it
  (`base_unprivileged_web_ports`).

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
