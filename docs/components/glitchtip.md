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

## On its own host

GlitchTip can also run on a host without the chat server, behind the web server that host already
runs (Plesk, Apache, nginx), for example the push gateway's machine. It then has its own Postgres
(only the database `glitchtip`) and nothing of TeamCraft; the play "Set up crash reports (GlitchTip) on
its own host" in `setup.yml` installs it for the inventory group `[teamcraft_crash_reports]`
(`group_vars/teamcraft_crash_reports.yml` sets the rest). There is no bundled Caddy in this mode.

`inventory/hosts`:

```ini
[teamcraft_crash_reports]
crashlogs.example.com ansible_host=203.0.113.20 ansible_user=deploy
```

On a machine that is already in the inventory under another name (the push gateway's
`gateway.example.com`), add it **under a second name with the same `ansible_host`**, as above; don't put
the gateway's name into both groups (their group variables collide). The two names share
`/srv/teamcraft` (each writes its own subdirectory of `reverse-proxy/`), the secrets directory (only the
GlitchTip play uses it) and `/etc/sysctl.d/60-teamcraft.conf`: keep `base_firewall_enabled` and
`base_unprivileged_web_ports` the same for both (behind Plesk: `false` and `false`). Users and units don't
overlap (`tc-gateway` / `tc-db`, `tc-glitchtip`).

`inventory/host_vars/crashlogs.example.com/vars.yml`:

```yaml
glitchtip_hostname: crashlogs.example.com
glitchtip_admin_email: ops@example.com
# Loopback ports; move any that other software on the host uses (the preflight check says which).
teamcraft_ports: {glitchtip: 18092, glitchtip_valkey: 18093, postgres: 18094}
# The firewall belongs to Plesk (or Docker).
base_firewall_enabled: false
```

The secrets are generated on the host on the first run (`/srv/teamcraft/secrets`): `postgres_password`,
`glitchtip_secret_key`, `glitchtip_db_password`, `glitchtip_valkey_password` and
`glitchtip_admin_password` (the superuser's). Only `glitchtip_email_url` (mail) and the optional S3 keys
can't be generated: put them in a sops file (`base_secrets_sops_file`, [../configuring.md](../configuring.md)).

Then `just install-all` (or `ansible-playbook -i inventory/hosts setup.yml --limit crashlogs.example.com
--tags=install-all,start`). The playbook writes the configuration for the web server in front to
`/srv/teamcraft/reverse-proxy/glitchtip/` on the host:

| File                      | For                                                             |
|---------------------------|-----------------------------------------------------------------|
| `plesk-apache-https.conf` | Plesk with Apache only: "Additional directives for HTTPS"       |
| `plesk-nginx.conf`        | Plesk with nginx in front: "Additional nginx directives"        |
| `apache.conf`             | a plain Apache 2.4 virtual host                                 |
| `nginx.conf`              | a plain nginx server block                                      |

**Plesk (Apache only):**

1. Websites & Domains → add the domain or subdomain `crashlogs.example.com` (A and AAAA records to the
   host), and get its certificate (SSL/TLS Certificates → Let's Encrypt).
2. Tools & Settings → Apache Web Server: the modules `proxy`, `proxy_http` and `headers` are on.
3. Websites & Domains → `crashlogs.example.com` → Apache & nginx Settings → **Additional directives for
   HTTPS**: paste the content of `/srv/teamcraft/reverse-proxy/glitchtip/plesk-apache-https.conf` (as
   root: `cat` it on the host). Leave "Additional directives for HTTP" empty; Plesk redirects to HTTPS.
4. `just self-check` checks `https://crashlogs.example.com/_health/` and the units.

Backups: the nightly dump of `glitchtip` goes to `/srv/teamcraft/backups/postgres/`; the off-site copy of
the backups role is for the chat server and stays off here. Continue with the first organization below.

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

Dry runs: `DRY_RUN_GLITCHTIP=1 test/dry-run.sh` on a chat server, and `DRY_RUN_CRASH_REPORTS=1
test/gateway-dry-run.sh` on its own host next to the push gateway, behind Apache with the generated
Plesk directives. S3 storage of debug files is not covered.
