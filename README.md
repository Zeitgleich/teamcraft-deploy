# TeamCraft deployment

An Ansible playbook that installs [TeamCraft](https://github.com/Zeitgleich/TeamCraft) – self-hosted,
end-to-end encrypted team chat with calls and meetings – on your own Debian server. Every component
runs as a rootless Podman container under its own unprivileged user, managed by systemd through
Quadlet. IPv4 and IPv6 throughout.

You need a Debian 13 server, a domain name and about 15 minutes.

```sh
git clone https://github.com/Zeitgleich/teamcraft-deploy.git && cd teamcraft-deploy
mkdir -p inventory/host_vars/chat.example.com
cp examples/hosts inventory/hosts                                       # your server's address
cp examples/vars.yml inventory/host_vars/chat.example.com/vars.yml      # your domain, admin e-mail
just install-all                                                        # install and start
just ensure-admin alice 'a long password'                               # first user (owner)
just self-check
```

| Guide                                   | Content                                                           |
|-----------------------------------------|-------------------------------------------------------------------|
| [Prerequisites](docs/prerequisites.md)  | Server, software on your machine, firewall                        |
| [DNS](docs/dns.md)                      | The host names and records (A + AAAA, the SFU's UDP port)         |
| [Configuring](docs/configuring.md)      | Inventory, the few required settings, secrets (generated or sops) |
| [Installing](docs/installing.md)        | Running the playbook, tags, the first user                        |
| [Updating](docs/updating.md)            | New TeamCraft versions, `just update`                             |
| [Backups](docs/backups.md)              | Database dumps, off-site copies, restore                          |
| [Uninstalling](docs/uninstalling.md)    | Removing components or everything                                 |
| [Components](docs/components/README.md) | One page per component and its settings                           |

## Components

| Component                                               | Default               | Runs as              | Toggle                     |
|---------------------------------------------------------|-----------------------|----------------------|----------------------------|
| [Caddy](docs/components/caddy.md)                       | on                    | `tc-proxy`           | `caddy_enabled`            |
| [PostgreSQL](docs/components/postgres.md)               | on                    | `tc-db`              | `postgres_enabled`         |
| [TeamCraft server](docs/components/teamcraft-server.md) | on                    | `tc-server`          | `teamcraft_server_enabled` |
| [TeamCraft SFU](docs/components/teamcraft-sfu.md)       | on                    | `tc-sfu`             | `teamcraft_sfu_enabled`    |
| [Keycloak](docs/components/keycloak.md)                 | on (or external OIDC) | `tc-keycloak`        | `keycloak_enabled`         |
| [Garage](docs/components/garage.md)                     | on (or external S3)   | `tc-garage`          | `garage_enabled`           |
| [Mail relay](docs/components/mail.md)                   | off (external SMTP)   | –                    | `teamcraft_smtp_enabled`   |
| [CalCraft](docs/components/calcraft.md)                 | off                   | `tc-calcraft`        | `calcraft_enabled`         |
| [Backups](docs/backups.md)                              | on                    | `tc-db` | `backups_enabled`          |
| Base (users, Podman, firewall, secrets)                 | always                | root                 | `base_firewall_enabled`    |

## Testing changes

`just dry-run all` deploys to a throwaway Debian container on your machine and checks the result end
to end, including two users exchanging encrypted messages ([test/dry-run.sh](test/dry-run.sh)). CI runs
it, ansible-lint and yamllint on every pull request.

## License

AGPL-3.0-or-later, like TeamCraft. See [LICENSE](LICENSE). Changes: [CHANGELOG.md](CHANGELOG.md).
