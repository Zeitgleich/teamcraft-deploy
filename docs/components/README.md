# Components

| Page                                       | Role                    | Default                           |
|--------------------------------------------|-------------------------|-----------------------------------|
| [caddy.md](caddy.md)                       | `caddy`                 | on, or [your own proxy](../reverse-proxy.md) |
| [postgres.md](postgres.md)                 | `postgres`              | on                                |
| [teamcraft-server.md](teamcraft-server.md) | `teamcraft_server`      | on                                |
| [teamcraft-sfu.md](teamcraft-sfu.md)       | `teamcraft_sfu`         | on                                |
| [teamcraft-bridge.md](teamcraft-bridge.md) | `teamcraft_bridge`      | off, webhooks and logs            |
| [keycloak.md](keycloak.md)                 | `keycloak`              | on, or an external OIDC provider  |
| [garage.md](garage.md)                     | `garage`                | on, or external S3                |
| [push-gateway.md](push-gateway.md)         | `push_gateway`          | off, own host, for app publishers |
| [mail.md](mail.md)                         | (server settings)       | off                               |
| [calcraft.md](calcraft.md)                 | `calcraft`              | off                               |
| [branding.md](branding.md)                 | server, Caddy, Keycloak | one built-in brand                |
| [../backups.md](../backups.md)             | `backups`               | on                                |

Every role's settings, with their defaults and comments, are in `roles/<role>/defaults/main.yml`;
the wiring between components is in `group_vars/teamcraft_servers.yml`. Override any of them in your
`vars.yml`. Shared to all: `base` (packages, firewall, secrets, the per-service user setup).
