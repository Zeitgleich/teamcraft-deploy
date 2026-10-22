# Backups

| What                            | How                                                                                           |
|---------------------------------|-----------------------------------------------------------------------------------------------|
| Databases (TeamCraft, Keycloak) | dumped nightly by `tc-db` to `/srv/teamcraft/backups/postgres`, kept `backups_keep_days` (14) |
| Attachments (bundled Garage)    | ciphertext only; copy them off-site (below)                                                   |
| Secrets                         | `/srv/teamcraft/secrets` (or your sops file)                                                  |
| Caddy certificates              | not needed; reissued automatically                                                            |

The server holds only ciphertext; a lost database still loses every message history, so back it up.

## Off-site copy

```yaml
backups_remote_enabled: true
backups_remote_endpoint: https://s3.other-provider.example
backups_remote_region: eu-central-1
backups_remote_bucket: teamcraft-backup
# keys: backups_remote_access_key / backups_remote_secret_key in your sops file
```

A nightly rclone job (`tc-db`) syncs the dumps to `<bucket>/postgres` and the attachment bucket
to `<bucket>/attachments`. Copy `/srv/teamcraft/secrets` yourself (it is root-only on purpose), or
keep the secrets in sops.

`just backup` runs both now.

## Restore

```sh
just stop
# on the server, as tc-db
podman start teamcraft-postgres 2>/dev/null || systemctl --user start postgres
podman exec -i teamcraft-postgres pg_restore -U postgres --clean --if-exists -d teamcraft < teamcraft-<date>.dump
podman exec -i teamcraft-postgres pg_restore -U postgres --clean --if-exists -d keycloak < keycloak-<date>.dump
just start
```

On a new server: restore `/srv/teamcraft/secrets` (or use the sops file), run `just install-all`,
then restore the dumps and the attachment bucket as above.
