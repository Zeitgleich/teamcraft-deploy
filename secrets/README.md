Encrypted secrets (`*.enc.yaml`, sops + age). Expected keys in `production.enc.yaml`:

| Key                         | Used as                                   |
|-----------------------------|-------------------------------------------|
| `postgres_password`         | podman secret for `tc-db` and `tc-server` |
| `oidc_server_client_secret` | podman secret for `tc-server`             |
| `s3_access_key`             | podman secret for `tc-server`             |
| `s3_secret_key`             | podman secret for `tc-server`             |
| `sfu_registration_token`    | podman secret for `tc-server`, `tc-sfu`   |
| `oidc_issuer`               | rendered into `teamcraft.toml`            |
| `s3_endpoint`               | rendered into `teamcraft.toml`            |
