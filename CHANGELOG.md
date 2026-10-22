# Changelog

Changes of the playbook. Each release pins a TeamCraft version (`teamcraft_version`); entries marked
**Breaking** need you to act before running `just install-all` (docs/updating.md). Format: [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
