# TeamCraft server

The API, the WebSocket gateway and (optionally) the web client, rootless as `tc-server`, read-only
root filesystem, no capabilities, `127.0.0.1:8080` behind Caddy. Configuration is rendered to
`/home/tc-server/config/teamcraft.toml`; secrets come in as podman secrets.

| Setting                                        | Default                                         | Meaning                                                |
|------------------------------------------------|-------------------------------------------------|--------------------------------------------------------|
| `teamcraft_version`                            | the playbook's release                          | image tag of server and SFU                            |
| `teamcraft_server_image`                       | `ghcr.io/zeitgleich/teamcraft-server:<version>` | or pin `…@sha256:<digest>`                             |
| `teamcraft_server_web_enabled`                 | `true`                                          | serve the web client; `false`: apps only               |
| `teamcraft_server_web_url`                     | the release's `teamcraft-web-<version>.tar.gz`  | where the web client archive comes from                |
| `teamcraft_server_web_checksum`                | empty: from `SHA256SUMS` next to the archive    | `sha256:<hex>` to override (e.g. an archive elsewhere) |
| `teamcraft_server_log_filter`                  | `info`                                          | `tracing` filter                                       |
| `teamcraft_push_gateway_url`                   | `https://push-gw.zeitgleich.de`                 | push gateway for the store apps (push-gateway.md)      |
| `teamcraft_push_gateway_accept_unbound_tokens` | `false`                                         | accept raw device tokens of old apps (transition only) |
| `teamcraft_server_extra_config`                | empty                                           | more TOML (any section of `teamcraft.example.toml`)    |

The web client is the release's `teamcraft-web-<version>.tar.gz`, downloaded by the server and
unpacked to `/home/tc-server/web` when `teamcraft_version` changes. The playbook checks it against the
release's `SHA256SUMS` (`teamcraft_server_web_sums_url`, next to the archive), so a version bump is one
setting; a release without the archive or its line in `SHA256SUMS` stops the run with that reason.
`teamcraft_server_web_checksum: sha256:<hex>` takes precedence (for an archive from elsewhere), and
`teamcraft_server_web_enabled: false` leaves the web client out: the desktop and mobile apps work
without it.

Every option of the server is documented in `teamcraft.example.toml` of the TeamCraft repository;
`teamcraft_server_extra_config` adds sections the playbook doesn't set itself, e.g. guest policy or
limits. Operations background (upgrades, key rotation): `docs/operations.md` of TeamCraft.
