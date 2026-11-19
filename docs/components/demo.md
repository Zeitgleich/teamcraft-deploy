# Demo instance for the app store reviews

Google Play and the App Store review every app update with an account they are given. A demo instance
gives them one without showing real people's names, presence or spaces: placeholder content only, a
fixed user list, reset to its seed every night, and as small as possible since nobody uses it most of
the time. Background and the seed: TeamCraft `docs/operations.md`, "Demo instance for store reviews".

Start from [examples/demo-vars.yml](../../examples/demo-vars.yml). It turns on:

| Setting                                    | What                                                                     |
|--------------------------------------------|--------------------------------------------------------------------------|
| `dex_enabled`, `keycloak_enabled: false`   | [Dex](dex.md) with the seed's users and two reviewer accounts            |
| `teamcraft_db_name`, `teamcraft_s3_bucket` | `teamcraft_demo` / `teamcraft-demo`: the reset refuses names without it  |
| `demo_reset_enabled`                       | the nightly reset (below)                                                |
| `*_memory`, `postgres_settings`            | small container limits and a tiny Postgres                               |
| `backups_enabled: false`                   | no dumps of a database that is reset anyway                              |

Push to the store apps goes through the publisher's push gateway as on any instance, under the demo
server's own gateway key; mail is off. The SFU stays on so that reviewers can try a call.

## Memory

Measured on a Debian 13 host behind an existing Caddy, idle after seeding (TeamCraft 1.0.37). "Slice"
is the service user's whole cgroup (container, `systemd --user`, dbus, conmon; page cache included,
which the kernel reclaims under pressure); "anon" is what can't be reclaimed:

| Service          | Limit | Slice   | Anon   |
|------------------|-------|---------|--------|
| Postgres         | 128m  | 127 MiB | 18 MiB |
| Garage           | 128m  | 36 MiB  | 3 MiB  |
| Dex              | 64m   | 46 MiB  | 15 MiB |
| TeamCraft server | 256m  | 87 MiB  | 27 MiB |
| TeamCraft SFU    | 128m  | 55 MiB  | 5 MiB  |
| **Total**        |       | 351 MiB | 68 MiB |

About 20 MiB of each slice is the user's `systemd --user` and dbus. The bundled Caddy (96m limit)
comes on top when no proxy runs on the host already.

## Setting it up

1. Install with the example's settings (`just install-all`), with DNS for `<domain>`, `sfu.<domain>`,
   `s3.<domain>` and `id.<domain>` (Dex).
2. Seed it once from a machine with the TeamCraft repository at the deployed release
   (`git worktree add ../seed v<teamcraft_version>`): TeamCraft `docs/operations.md`, "Setting it up",
   step 2, with `E2E_DEPLOYED_URL=https://<domain>`, `DEV_TOKEN_ISSUER=https://id.<domain>` and the
   passwords from `/srv/teamcraft/secrets/dex_password_{seed,owner,reviewer_1,reviewer_2}` on the host
   (pass them through the environment, never on a command line others see). Choose a recovery
   passphrase for the reviewers (`DEMO_RECOVERY_PASSPHRASE`) and keep it with their passwords.
3. Take the seed on the host: `teamcraft-demo-reset snapshot` (stops the server, dumps the database,
   copies the bucket to `/srv/teamcraft/demo-seed`, starts it again).
4. Sign in on a phone as a reviewer and check the channels, messages and files.
5. Give the stores the reviewer's e-mail address, password and recovery passphrase (App Store Connect:
   App Review Information; Play Console: App access). They never go into a repository.

## Reset

`teamcraft-demo-reset.timer` runs `teamcraft-demo-reset restore` every night (`demo_reset_on_calendar`,
03:00 UTC): it stops the server, empties the database and restores the seed's dump, makes the bucket
equal to the seed's copy, starts the server and waits until it is ready. Every step goes to the
journal and `/var/log/teamcraft-demo-reset.log`; a failure leaves the unit failed and starts
`demo_reset_on_failure` if set.

```sh
systemctl start teamcraft-demo-reset          # reset now
teamcraft-demo-reset check                    # settings and seed only
teamcraft-demo-reset snapshot                 # new seed, after seeding again
systemctl list-timers teamcraft-demo-reset.timer
```

The script is TeamCraft's `dev/demo/demo-reset.sh` of the deployed release. It runs `psql`, `pg_dump`
and `pg_restore` inside the Postgres container (the host's client may be older), and `rclone` against
Garage on loopback. Dex is not reset: its users are the configuration, its refresh tokens survive.

After an update of TeamCraft the server migrates the restored seed forward when it starts. When a
release can no longer read the seed (the nightly `demo_signin` end-to-end test in TeamCraft goes red
first), seed again (steps 2 and 3).
