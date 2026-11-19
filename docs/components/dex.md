# Dex (small identity provider)

A small alternative to [Keycloak](keycloak.md) for instances whose users never change, such as a
[demo instance](demo.md) for the app store reviews: Dex with a fixed user list, rootless as `tc-dex`,
at `https://id.<domain>` (`dex_hostname`, the name Keycloak would use: one A + AAAA record more). Not
under a path of the server's name: the web client's service worker serves only its signed release and
`/api/` there. About 30 MB of memory instead of Keycloak's 400+.

```yaml
# vars.yml
keycloak_enabled: false
dex_enabled: true
dex_users:
  - {username: alex, email: alex@example.com, name: Alex Example,
     user_id: 6f0c1d7e-0000-4000-8000-000000000002, groups: [teamcraft-member], password: alex}
dex_extra_redirect_uris: ["de.zeitgleich.teamcraft:/oauth/callback"]   # the store apps
```

- **Sign-in** is with the e-mail address and the password. Passwords are generated on the host, 20
  letters and digits, in `/srv/teamcraft/secrets/dex_password_<password>` (users that name the same
  `password` share it). Only bcrypt hashes reach Dex, as podman secrets. To change one, write the new
  password into the file, delete `dex_hash_<password>` next to it and run `just install-component dex`.
- **Roles** come from Dex's `groups` claim: the server reads them with `[oidc] roles_claim = "groups"`
  and the distinctive names in `dex_server_oidc_roles` (`teamcraft-owner`, `teamcraft-admin`,
  `teamcraft-member`, `teamcraft-guest`). Every group equal to one of them grants the role, so keep to
  the static users (no upstream connectors that let others name groups).
- **Not available** without Keycloak (TeamCraft docs/operations.md, "Without Keycloak"): the
  deprovisioning sync and group sync, provider events, back-channel logout, the account API for
  identity key attestation and client roles in the ID token. Users are the list above; removing one
  from it ends their sign-in when their tokens expire.
- **Clients:** the public client `teamcraft` with the web client on every host name and
  `dex_extra_redirect_uris`; no consent screen. Dex compares redirect URIs exactly, so the **desktop
  app** (a loopback callback on a new port each time) can't sign in; the web client and the mobile
  apps can.
- Refresh tokens and signing keys live in a sqlite file in the volume `dex-data` of `tc-dex`.

Settings: `roles/dex/defaults/main.yml`.
