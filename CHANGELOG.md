# Changelog

Changes of the playbook. Each release pins a TeamCraft version (`teamcraft_version`); entries marked
**Breaking** need you to act before running `just install-all` (docs/updating.md). Format: [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Brands: several host names on one server (`teamcraft_brands`, needs TeamCraft with brand
  support). Caddy serves every brand host, the bundled Keycloak client gets their redirect URIs and
  web origins on every run, brand images are copied from `teamcraft_server_brand_assets_src`.
- Organizations: `teamcraft_oidc_organization_claim`, and for the bundled Keycloak a token mapper from
  `keycloak_organization_attribute`.

### Changed

- The bundled Keycloak's `teamcraft` client is updated on every run (redirect URIs, web origins),
  not only at the first realm import. Redirect URIs you added by hand in the admin console are
  replaced: put them in `keycloak_extra_redirect_uris`. **Breaking** if you rely on hand-made ones.

## [1.0.0-beta.1] - 2026-10-22

First release, for TeamCraft 1.0.0-beta.1.

### Added

- One role per component: Caddy, PostgreSQL, TeamCraft server and SFU, bundled Keycloak or an external
  OIDC provider, bundled Garage or external S3, SMTP relay settings, optional CalCraft, backups.
- Rootless Podman + Quadlet, one unprivileged user per service, host networking with loopback-only
  internal ports, nftables firewall for IPv4 and IPv6.
- Secrets generated on the server on the first run; optionally from a sops + age file.
- Tags `install-all`, `setup-all`, `start`, `stop`, `self-check`, `ensure-admin`, `backup` and a
  justfile around them.
- Dry run against a throwaway systemd container, used by CI.

[Unreleased]: https://github.com/Zeitgleich/teamcraft-deploy/compare/v1.0.0-beta.1...HEAD
[1.0.0-beta.1]: https://github.com/Zeitgleich/teamcraft-deploy/releases/tag/v1.0.0-beta.1
