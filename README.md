# teamcraft-deploy

Private deployment configuration for a TeamCraft instance. The application code lives in the
`teamcraft` monorepo; this repository only describes **where and how** it runs.

| Path                                       | Content                                                     |
|--------------------------------------------|-------------------------------------------------------------|
| `ansible/`                                 | Playbook + role that deploys TeamCraft with rootless Podman |
| `ansible/roles/teamcraft/templates/*.container.j2` | Quadlet units, one per service                      |
| `secrets/`                                 | sops-encrypted secrets (`*.enc.yaml`), never plaintext       |
| `.sops.yaml`                               | Which age keys can decrypt the secrets                      |

## Runtime model: rootless Podman + Quadlet, one user per service

Every service runs as its **own unprivileged user** with its own subuid range, its own systemd
`--user` instance (lingering) and only the podman secrets it needs. Quadlet turns the
`.container` files into native systemd units, so `systemctl --user status` and `journalctl` work as
for any other service.

| Service            | User        | Network              | Secrets it gets                                     |
|--------------------|-------------|----------------------|-----------------------------------------------------|
| `caddy`            | `tc-proxy`  | host, 80/443 tcp+udp | none                                                |
| `teamcraft-server` | `tc-server` | host, 127.0.0.1:8080 | DB password, OIDC client secret, S3 keys, SFU token |
| `teamcraft-sfu`    | `tc-sfu`    | host, 4433/udp       | SFU registration token                              |
| `postgres`         | `tc-db`     | host, 127.0.0.1:5432 | DB password                                         |

Why host networking: rootless containers of different users can't share a podman network, and the
SFU shouldn't pay the per-packet cost of user-mode networking. Each container still runs in its
own user namespace; internal services bind to loopback only.

Hardening: images pinned by digest, `DropCapability=ALL`, `NoNewPrivileges`, read-only root
filesystem with noexec tmpfs, `RunInit=yes`, memory limits, journald logging.

The SFU certificate is obtained by Caddy; a `tc-proxy` timer copies it to `/srv/teamcraft/certs`
(group `tc-certs`), which `tc-sfu` reads.

Not on the VPS: the OIDC provider (separate server), S3 (external provider), optional
`teamcraft-bridge` / `teamcraft-vault` (trusted hosts), optional `teamcraft-pbx`.

## Secrets

```sh
sops secrets/production.enc.yaml
```

Expected keys: [secrets/README.md](secrets/README.md). The playbook decrypts them on the control
machine and creates podman secrets per service user – no env files with secrets on disk.

## Deploy

```sh
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventories/production ansible/site.yml
```

Versions and digests are pinned in `ansible/inventories/production/group_vars/all.yml`.
