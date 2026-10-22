# Keycloak (identity provider)

TeamCraft signs users in through OIDC. By default the playbook runs Keycloak for you, rootless as
`tc-keycloak`, with its database in the bundled PostgreSQL, at `https://id.<domain>`. It imports a
realm `teamcraft` on the first start with:

- the public client `teamcraft` (code flow + PKCE) for the web client (`https://<domain>/*`), the
  desktop app (loopback redirect, any port) and `keycloak_extra_redirect_uris` (mobile apps),
- client roles `owner`, `admin`, `member`, `guest` (users need one to get in),
- the confidential client `teamcraft-server` with a service account the server uses to deactivate
  disabled or deleted users, and back-channel logout to the server.

Later changes to the realm are made in Keycloak, not by the playbook (the import only runs once).

## Users

```sh
just ensure-admin alice 'a long password'           # role owner
just ensure-admin dave 'another password' guest
```

The admin console is **not** published by default. Reach it through SSH:

```sh
ssh -L 8180:127.0.0.1:8180 deploy@chat.example.com
# http://127.0.0.1:8180/admin/ — user admin, password: sudo cat /srv/teamcraft/secrets/keycloak_admin_password
```

`keycloak_admin_console_public: true` publishes it at `https://id.<domain>/admin/` instead.

## Settings

| Setting                          | Default     | Meaning                                                              |
|----------------------------------|-------------|----------------------------------------------------------------------|
| `keycloak_realm`                 | `teamcraft` | realm name                                                           |
| `keycloak_extra_redirect_uris`   | `[]`        | e.g. `["com.example.teamcraft:/oauth/callback"]` for the mobile apps |
| `keycloak_access_token_lifespan` | `300`       | seconds                                                              |
| `keycloak_image`                 | pinned      | image                                                                |

## An external provider instead

```yaml
keycloak_enabled: false
teamcraft_oidc_issuer: https://id.example.com/realms/example
teamcraft_oidc_client_id: teamcraft
```

Set the provider up like the realm above: a public client with PKCE and the redirect URIs, the four
client roles in the access token (`resource_access.<client>.roles`), and an ID token claim
`tc_identity_key` from a user attribute of the same name that users may edit (TeamCraft stores the
user's identity key fingerprint there). For deprovisioning also a confidential client with a service
account (`teamcraft_server_oidc_sync_enabled: true`, secret `oidc_sync_client_secret`).
