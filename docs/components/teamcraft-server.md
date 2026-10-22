# TeamCraft server

The API, the WebSocket gateway and (optionally) the web client, rootless as `tc-server`, read-only
root filesystem, no capabilities, `127.0.0.1:8080` behind Caddy. Configuration is rendered to
`/home/tc-server/config/teamcraft.toml`; secrets come in as podman secrets.

| Setting                         | Default                                         | Meaning                                             |
|---------------------------------|-------------------------------------------------|-----------------------------------------------------|
| `teamcraft_version`             | the playbook's release                          | image tag of server and SFU                         |
| `teamcraft_server_image`        | `ghcr.io/zeitgleich/teamcraft-server:<version>` | or pin `…@sha256:<digest>`                          |
| `teamcraft_server_web_enabled`  | `false`                                         | serve the web client from the release archive       |
| `teamcraft_server_web_checksum` | empty                                           | `sha256:<hex>` from the release's `SHA256SUMS`      |
| `teamcraft_server_log_filter`   | `info`                                          | `tracing` filter                                    |
| `teamcraft_push_gateway_url`    | `https://push-gw.zeitgleich.de`                 | push gateway for the store apps (push-gateway.md)   |
| `teamcraft_server_extra_config` | empty                                           | more TOML (any section of `teamcraft.example.toml`) |

Every option of the server is documented in `teamcraft.example.toml` of the TeamCraft repository;
`teamcraft_server_extra_config` adds sections the playbook doesn't set itself, e.g. guest policy or
limits. Operations background (upgrades, key rotation): `docs/operations.md` of TeamCraft.
