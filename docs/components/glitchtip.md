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

| File                      | For                                                       |
|---------------------------|-----------------------------------------------------------|
| `plesk-apache-https.conf` | Plesk with Apache only: "Additional directives for HTTPS" |
| `plesk-nginx.conf`        | Plesk with nginx in front: "Additional nginx directives"  |
| `apache.conf`             | a plain Apache 2.4 virtual host                           |
| `nginx.conf`              | a plain nginx server block                                |

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

## Sign-in with SSO and roles

GlitchTip lets an organization use its own OpenID Connect provider (Keycloak, Entra ID, Okta, any other):
people who sign in through it join the organization automatically, as **members**. GlitchTip maps no
roles from the provider; the playbook can, from a claim (below).

1. **At the identity provider:** a confidential OIDC client for GlitchTip (e.g. client ID `glitchtip`),
   with the redirect URI `https://glitchtip.chat.example.com/accounts/*` (the exact callback is
   `https://glitchtip.chat.example.com/accounts/oidc/<provider id>/login/callback/`, the provider ID
   GlitchTip shows after step 2; use it where the provider doesn't take wildcards). For roles, a claim
   with the user's GlitchTip roles in the ID token and the userinfo response, e.g. `glitchtip_roles`
   with a list like `["admin"]` (Keycloak: client roles with a "User Client Role" mapper, token claim
   name `glitchtip_roles`, multivalued, added to ID token and userinfo).
2. **In GlitchTip,** as an owner or manager: Organization settings → **SSO** → add an OpenID Connect
   provider with the issuer URL (e.g. `https://id.example.com/realms/example`), client ID and secret.
   The organization's own login page (`https://glitchtip.chat.example.com/login/<organization slug>`)
   then offers it. The same from the shell, as `tc-glitchtip` on the host:

   ```sh
   podman exec teamcraft-glitchtip-web ./manage.py shell -c '
   from allauth.socialaccount.models import SocialApp
   from apps.organizations_ext.models import Organization, OrganizationSocialApp
   org = Organization.objects.get(slug="example")
   app = SocialApp.objects.create(provider="openid_connect", provider_id="example-sso", name="Example SSO",
       client_id="glitchtip", secret="<client secret>",
       settings={"server_url": "https://id.example.com/realms/example"})
   OrganizationSocialApp.objects.create(organization=org, social_app=app)'
   ```

3. **New people:** with registration closed, GlitchTip only lets people sign in through SSO who
   already have an account. To let the provider decide who gets in, allow sign-up through SSO apps
   only:

   ```yaml
   glitchtip_extra_environment:
     ENABLE_SOCIAL_APPS_USER_REGISTRATION: "true"
   ```

4. **Roles from the claim:**

   ```yaml
   glitchtip_sso_role_claim: glitchtip_roles
   # claim value -> owner, manager, admin or member (this is the default)
   glitchtip_sso_role_map: {owner: owner, manager: manager, admin: admin, member: member}
   glitchtip_sso_remove_without_role: true
   glitchtip_sso_role_sync_interval: 5min
   ```

   A timer of `tc-glitchtip` (`glitchtip-sso-role-sync.timer`) then sets, every interval, the role of
   each person who signed in through an organization's SSO app: the highest role their claim values
   map to. People with an SSO account but no organization membership are added when they have a role;
   members whose claim maps to no role are removed (with `glitchtip_sso_remove_without_role`). It never
   touches local accounts (the superuser) or accounts of other providers, and never demotes or removes
   an organization's last owner. Changes go to the journal (`journalctl --user -u
   glitchtip-sso-role-sync` as `tc-glitchtip`), by user ID.

   **The claim is read as it was at the person's last SSO sign-in**: GlitchTip stores the claims then
   (in `SocialAccount.extra_data`, `userinfo` first, then `id_token`). A role changed at the provider
   applies after that person's next sign-in through SSO and the next timer run; to take a role away at
   once, remove the member in GlitchTip as well (or disable the person at the provider, which ends their
   GlitchTip sessions only when they expire).

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
| `glitchtip_duckdb_enabled`                                   | `true`                         | store and show the spans of performance transactions (GlitchTip's DuckDB cold storage, see below)               |
| `glitchtip_span_raw_retention_days`                          | `30`                           | raw spans are deleted after this (`GLITCHTIP_SPAN_RAW_RETENTION_DAYS`); span trend rollups stay longer           |
| `glitchtip_s3_endpoint`                                      | –                              | keep uploaded debug files in an S3 bucket (`glitchtip_s3_bucket`) instead of the volume                          |
| `glitchtip_sso_role_claim`                                   | –                              | claim with the users' roles; set to sync organization roles from SSO (see above)                                 |
| `glitchtip_extra_environment`                                | `{}`                           | more of [GlitchTip's settings](https://glitchtip.com/documentation/install), no secrets                          |

Debug files (symbols, source maps) are uploaded with `sentry-cli` or GlitchTip's own tooling to the
same host name; the proxy accepts bodies up to 100 MB. They stay in the volume `glitchtip-uploads`
unless `glitchtip_s3_endpoint` is set; the S3 keys go in the sops file as `glitchtip_s3_access_key`
and `glitchtip_s3_secret_key`.

Spans of performance transactions (the steps of a slow operation, e.g. which job it waited behind) are
shown under Performance → a transaction group → "Span breakdown". GlitchTip stages them in Postgres;
every 5 minutes the worker writes the ones older than 5 minutes to Parquet files, which the web reads
with DuckDB (the extensions are in the image, nothing is downloaded). So a new transaction's spans show
up after 5 to 10 minutes. The files are in the volume `glitchtip-cold-storage`, or with
`glitchtip_s3_endpoint` under `cold_storage/` in the same bucket. DuckDB takes at most a quarter of a
container's memory limit (256 MB at most); with many spans, raise `glitchtip_worker_memory`.
`glitchtip_duckdb_enabled: false` keeps transactions without their spans.

## Privacy

Crash reports leave the devices without end-to-end encryption: they hold stack traces, the app
version, the operating system and device model, and whatever the app adds. TeamCraft's apps send no
message content, names or keys in them (TeamCraft's `docs/bug-reports.md`), but the reports are
personal data all the same (a device, an IP address at intake): name GlitchTip in your privacy notice,
keep `glitchtip_retention_days` short, and give access only to the people who fix the bugs.

## Backups, updates, removal

- The nightly database dump ([../backups.md](../backups.md)) includes `glitchtip`. The uploaded debug
  files (volume `glitchtip-uploads`) are not backed up: they come from your build pipeline and can be
  uploaded again. Neither are the span files (volume `glitchtip-cold-storage`): they are kept for
  `glitchtip_span_raw_retention_days` only.
- The image is pinned (`glitchtip_image`); a playbook release moves it. Migrations run when the web unit
  starts. Read [GlitchTip's blog](https://glitchtip.com/blog/) before a new major version.
- `glitchtip_enabled: false` and `just setup-all` stop and remove the units; the data (database,
  volumes) stays ([../uninstalling.md](../uninstalling.md)). To delete it for good: drop the database
  `glitchtip` and the role of the same name in Postgres, and remove the user `tc-glitchtip`.

Dry runs: `DRY_RUN_GLITCHTIP=1 test/dry-run.sh` on a chat server, and `DRY_RUN_CRASH_REPORTS=1
test/gateway-dry-run.sh` on its own host next to the push gateway, behind Apache with the generated
Plesk directives. S3 storage of debug files is not covered.
