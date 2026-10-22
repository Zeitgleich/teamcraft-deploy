# PostgreSQL

One PostgreSQL instance, rootless as `tc-db`, listening on `127.0.0.1:5432` only. It holds the
TeamCraft database (ciphertext of messages, structure, audit log) and, with the bundled Keycloak,
Keycloak's. Roles, databases and passwords are created by the playbook; passwords are secrets.

| Setting              | Default             | Meaning                                             |
|----------------------|---------------------|-----------------------------------------------------|
| `postgres_image`     | pinned              | image; a major version upgrade needs dump + restore |
| `postgres_memory`    | `2g`                | memory limit                                        |
| `postgres_databases` | teamcraft, keycloak | databases with owner and password secret            |

Backups: [../backups.md](../backups.md). `psql`: `podman exec -it teamcraft-postgres psql -U postgres`
as `tc-db`.
