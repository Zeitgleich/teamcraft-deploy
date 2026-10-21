# teamcraft-deploy

Private deployment configuration for a TeamCraft instance. The application code lives in the
`teamcraft` monorepo; this repository only describes **where and how** it runs.

| Path                         | Content                                                         |
|------------------------------|-----------------------------------------------------------------|
| `compose/`                   | Docker Compose stack for the VPS (server, SFU, Postgres, Caddy)  |
| `ansible/`                   | Playbook + role that installs Docker and deploys the stack       |
| `secrets/`                   | sops-encrypted secrets (`*.enc.yaml`), never plaintext           |
| `.sops.yaml`                 | Which age keys can decrypt the secrets                          |

## Components on the VPS

| Service            | Purpose                                         | Ports                         |
|--------------------|-------------------------------------------------|-------------------------------|
| `caddy`            | TLS termination, HTTP/2 + HTTP/3 for the API     | 80/tcp, 443/tcp, 443/udp      |
| `teamcraft-server` | REST API, gateway, push, MLS delivery            | internal 8080                 |
| `teamcraft-sfu`    | WebTransport media forwarding                    | 4433/udp (QUIC, own TLS cert) |
| `postgres`         | Metadata and message ciphertext                  | internal                      |

Not on the VPS: the OIDC provider (separate server), S3 (external provider), optional
`teamcraft-bridge` / `teamcraft-vault` (trusted hosts), optional `teamcraft-pbx` (telephony host or VPS).

## Secrets

```sh
sops secrets/production.enc.yaml        # edit (needs an age key listed in .sops.yaml)
```

Contains database password, S3 credentials, OIDC confidential client secret, APNs/FCM keys,
SFU registration token.

## Deploy

```sh
ansible-playbook -i ansible/inventories/production ansible/site.yml
```

The playbook decrypts secrets locally with sops, renders `compose/.env` on the host and runs
`docker compose up -d`. Image versions are pinned in `ansible/inventories/production/group_vars/all.yml`.
