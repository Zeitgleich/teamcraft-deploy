# Configuring

Everything about your instance lives in `inventory/`, which git ignores. Keep it in a private
repository of its own if you like (`inventory/` can be a clone or a symlink).

```sh
mkdir -p inventory/host_vars/chat.example.com
cp examples/hosts inventory/hosts
cp examples/vars.yml inventory/host_vars/chat.example.com/vars.yml
```

`inventory/hosts` names the server (the name must match the `host_vars` directory) and how to reach
it. `vars.yml` needs only:

| Setting                 | Example             | Meaning                                         |
|-------------------------|---------------------|-------------------------------------------------|
| `teamcraft_domain`      | `chat.example.com`  | the instance's host name; others derive from it |
| `teamcraft_admin_email` | `admin@example.com` | Let's Encrypt contact, sender of system mail    |

Every other setting has a default in `roles/<component>/defaults/main.yml` or
`group_vars/teamcraft_servers.yml`; set it in `vars.yml` to change it. The component pages in
[components/](components/README.md) list the useful ones.

## External identity provider or storage

Without changes the playbook runs Keycloak and Garage. To use what you have:

```yaml
keycloak_enabled: false
teamcraft_oidc_issuer: https://id.example.com/realms/example
teamcraft_oidc_client_id: teamcraft

garage_enabled: false
teamcraft_s3_endpoint: https://s3.example.com
teamcraft_s3_region: eu-central-1
teamcraft_s3_bucket: teamcraft
```

The OIDC client must be public with PKCE, carry client roles `owner`, `admin`, `member`, `guest`
([components/keycloak.md](components/keycloak.md)). The S3 keys are secrets (`s3_access_key`,
`s3_secret_key`, below); the bucket must allow CORS from `https://chat.example.com` for the web client.

## Secrets

On the first run the playbook generates every secret it needs on the server, in
`/srv/teamcraft/secrets` (root only), and reads them from there on later runs. Nothing secret is
stored on your machine or in git. Back that directory up with the server
([backups.md](backups.md)).

To keep secrets on your machine instead – for several operators, or to rebuild a server from
scratch – put them in a **sops + age** encrypted file; its values win over the generated ones:

```yaml
# inventory/host_vars/chat.example.com/vars.yml
base_secrets_sops_file: "{{ inventory_dir }}/host_vars/chat.example.com/secrets.sops.yml"
```

```sh
age-keygen -o ~/.config/sops/age/keys.txt          # once per operator; share the public key
cat > inventory/.sops.yaml <<'SOPS'
creation_rules:
  - path_regex: secrets\.sops\.ya?ml$
    age: age1replace_with_your_public_key
SOPS
sops inventory/host_vars/chat.example.com/secrets.sops.yml
```

Keys you can set there (all optional; missing ones are generated): `postgres_password`,
`teamcraft_db_password`, `keycloak_db_password`, `keycloak_admin_password`,
`keycloak_server_client_secret`, `garage_rpc_secret`, `garage_admin_token`, `garage_access_key`,
`garage_secret_key`, `sfu_registration_token`, `meetings_guest_token_secret`, `call_signing_key`
(Ed25519 PEM), `vapid_private_key`, `calcraft_password`; and those that can't be generated:
`s3_access_key` / `s3_secret_key` (external S3), `oidc_sync_client_secret` (external OIDC),
`smtp_password`, `caldav_password` (external CalDAV), `backups_remote_access_key` /
`backups_remote_secret_key`. Rotating: change the value and run `just install-all`; the affected
services restart.
