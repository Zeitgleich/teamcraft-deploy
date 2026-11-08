# GlitchTip (crash reports, optional)

Optional, off by default. TeamCraft's apps can send crash reports and errors to an error tracker that
speaks the **Sentry protocol**; the apps only know a DSN, which an admin enters in the TeamCraft admin
console. The playbook can run [GlitchTip](https://glitchtip.com) for that, the documented default.
Any other Sentry-protocol backend works the same way (a DSN is all TeamCraft needs), and you can skip
this page if you run one already or don't want crash reports at all.

What runs, rootless as `tc-glitchtip`, at `https://glitchtip.<domain>`:

| Unit               | What                                                                    | Memory limit |
|--------------------|-------------------------------------------------------------------------|--------------|
| `glitchtip-web`    | web UI, API and event intake; migrates the database when it starts      | 512 MB       |
| `glitchtip-worker` | one worker process (event processing, mail, clean-up; scheduler inside) | 512 MB       |
| `glitchtip-valkey` | task queue and cache, loopback only, with a password                    | 128 MB       |

Its database `glitchtip` is in the bundled Postgres (with `max_locks_per_transaction = 512`, which
GlitchTip's partitioned tables need; Postgres restarts once when you turn GlitchTip on). Web and Valkey
listen on loopback only (`teamcraft_ports.glitchtip`, 8090, and `glitchtip_valkey`, 6390); the proxy
publishes the web unit.

## Turning it on

1. DNS: an A and an AAAA record for `glitchtip.chat.example.com` ([../dns.md](../dns.md)), or set
   `glitchtip_hostname` to another name.
2. In your `vars.yml`:

   ```yaml
   glitchtip_enabled: true
   ```

3. `just install-all` (or `just install-component glitchtip`). With Caddy the name gets its
   certificate; behind your own proxy, the generated configurations now contain it
   ([../reverse-proxy.md](../reverse-proxy.md)): copy them again and get a certificate for the name.
4. `just self-check` checks `https://glitchtip.chat.example.com/_health/`.

Registration is **closed**: nobody can sign up, and only superusers create organizations. So that
nobody else can be first, the playbook creates a superuser on the first run: `glitchtip_admin_email`
(default `teamcraft_admin_email`) with the generated password in `/srv/teamcraft/secrets/glitchtip_admin_password`
on the server (root only; or `glitchtip_admin_password` in your sops file). Changing it later in
GlitchTip is fine: the playbook only creates the user when it is missing.

## First organization, project and the DSN

1. Sign in at `https://glitchtip.chat.example.com` with that e-mail address and password, and change
   the password (Profile). Turn on two-factor authentication while you are there.
2. Create an **organization** (e.g. `Example`), then a **project** in it for TeamCraft's apps. One
   project is enough to start; separate ones per platform (desktop, web, Android, iOS) keep their
   issues apart and let you mute one.
3. The project's **Settings → Client Keys (DSN)** shows the DSN, a URL like
   `https://<key>@glitchtip.chat.example.com/<project id>`.
4. Paste the DSN into the **TeamCraft admin console**, in the crash reporting setting
   (TeamCraft#1508). From then on the apps send reports there; people can turn it off on their device.
5. Invite the people who should read the reports (Organization → Members). Invitations go out by
   e-mail, so set `glitchtip_email_url` first (without it, mail only goes to the log).

## Settings

All in `roles/glitchtip/defaults/main.yml`; the ones you are most likely to change:

| Setting                                                      | Default                        | Meaning                                                                                                          |
|--------------------------------------------------------------|--------------------------------|------------------------------------------------------------------------------------------------------------------|
| `glitchtip_hostname`                                         | `glitchtip.<teamcraft_domain>` | the public name (group_vars)                                                                                     |
| `glitchtip_retention_days`                                   | `30`                           | events, debug files and logs are deleted after this (GlitchTip's `GLITCHTIP_RETENTION_DAYS`)                     |
| `glitchtip_admin_email`                                      | `teamcraft_admin_email`        | the superuser created on the first run                                                                           |
| `glitchtip_from_email`                                       | `teamcraft_admin_email`        | sender of GlitchTip's mail                                                                                       |
| `glitchtip_email_url` (sops)                                 | –                              | mail server as a URL, e.g. `smtp+tls://user:password@mail.example.com:587`; without it mail only goes to the log |
| `glitchtip_user_registration`                                | `false`                        | `true`: anyone who reaches the page can sign up                                                                  |
| `glitchtip_organization_creation`                            | `false`                        | `true`: every user can create organizations                                                                      |
| `glitchtip_worker_concurrency`                               | `4`                            | tasks the worker runs at once                                                                                    |
| `glitchtip_web_memory` / `_worker_memory` / `_valkey_memory` | `512m` / `512m` / `128m`       | container memory limits                                                                                          |
| `glitchtip_uptime_enabled` / `glitchtip_logs_enabled`        | `false`                        | GlitchTip's uptime monitoring and log ingestion, not needed for crash reports                                    |
| `glitchtip_s3_endpoint`                                      | –                              | keep uploaded debug files in an S3 bucket (`glitchtip_s3_bucket`) instead of the volume                          |
| `glitchtip_extra_environment`                                | `{}`                           | more of [GlitchTip's settings](https://glitchtip.com/documentation/install), no secrets                          |

Debug files (symbols, source maps) are uploaded with `sentry-cli` or GlitchTip's own tooling to the
same host name; the proxy accepts bodies up to 100 MB. They stay in the volume `glitchtip-uploads`
unless `glitchtip_s3_endpoint` is set; the S3 keys go in the sops file as `glitchtip_s3_access_key`
and `glitchtip_s3_secret_key`.

## Privacy

Crash reports leave the devices without end-to-end encryption: they hold stack traces, the app
version, the operating system and device model, and whatever the app adds. TeamCraft's apps send no
message content, names or keys in them (TeamCraft's `docs/bug-reports.md`), but the reports are
personal data all the same (a device, an IP address at intake): name GlitchTip in your privacy notice,
keep `glitchtip_retention_days` short, and give access only to the people who fix the bugs.

## Backups, updates, removal

- The nightly database dump ([../backups.md](../backups.md)) includes `glitchtip`. The uploaded debug
  files (volume `glitchtip-uploads`) are not backed up: they come from your build pipeline and can be
  uploaded again.
- The image is pinned (`glitchtip_image`); a playbook release moves it. Migrations run when the web unit
  starts. Read [GlitchTip's blog](https://glitchtip.com/blog/) before a new major version.
- `glitchtip_enabled: false` and `just setup-all` stop and remove the units; the data (database,
  volumes) stays ([../uninstalling.md](../uninstalling.md)). To delete it for good: drop the database
  `glitchtip` and the role of the same name in Postgres, and remove the user `tc-glitchtip`.

Covered by the dry run with `DRY_RUN_GLITCHTIP=1` (`test/dry-run.sh`): the units start, the health
endpoint answers through the proxy over IPv4 and IPv6, the superuser exists, and the ports stay
closed from outside. S3 storage of debug files is not covered.
