# Push gateway

The iOS and Android **store apps** can only be pushed to with the credentials of their publisher (the
APNs key and the Firebase project). A **push gateway** holds them and forwards the sealed wake-ups of
any TeamCraft server; it sees device tokens and ciphertext, never users or messages
(the gateway is its own project, [teamcraft-push-gateway](https://github.com/Zeitgleich/teamcraft-push-gateway):
its `docs/design.md` explains the threat model and limits, `docs/api.md` the protocol). Two sides here:

1. **Your TeamCraft server** sends through a gateway: this is on by default
   (`teamcraft_push_gateway_url`, the gateway of the official apps). Almost everybody needs nothing else.
2. **A gateway host**: only for whoever publishes apps. Optional, off by default, on its **own host**,
   separate from every chat server, because it holds the publisher's credentials.

## Your server uses a gateway

```yaml
# inventory/host_vars/chat.example.com/vars.yml
teamcraft_push_gateway_url: https://push-gw.zeitgleich.de   # the default; "" turns it off
```

`just install-all` adds `[push.gateway]` to the server's configuration. The server's key for the gateway
is the generated secret `push_gateway_key` (kept with the other secrets in `/srv/teamcraft/secrets`, or
in your sops file); the server registers it at the gateway by itself. Keep the key: it is your server's
identity at the gateway. For self-built, self-signed apps use your own credentials instead
(`teamcraft_server_extra_config` with `[push.apns]` / `[push.fcm]`, see the TeamCraft `operations.md`);
Web Push and UnifiedPush never use a gateway.

## Running a gateway

Put a separate Debian 13 or Ubuntu 24.04 host in the inventory group `teamcraft_push_gateways` (not in
`teamcraft_servers`):

```ini
# inventory/hosts
[teamcraft_push_gateways]
gateway.example.com ansible_host=203.0.113.20 ansible_user=deploy
```

```yaml
# inventory/host_vars/gateway.example.com/vars.yml
push_gateway_enabled: true
push_gateway_hostname: gateway.example.com        # A + AAAA records; Caddy gets the certificate
push_gateway_admin_email: ops@example.com
push_gateway_apns_key: "{{ lookup('file', 'AuthKey_ABC123DEFG.p8') }}"   # or from your sops file
push_gateway_apns_key_id: ABC123DEFG
push_gateway_apns_team_id: DEF456GHIJ
push_gateway_apns_bundle_id: com.example.teamcraft
push_gateway_fcm_service_account: "{{ lookup('file', 'fcm-service-account.json') }}"
```

`just install-all` installs and starts it (`--limit gateway.example.com` for this host only). It runs two
rootless containers: the gateway as `tc-gateway` (loopback only, SQLite state in the volume
`gateway-data`) and its own Caddy as `tc-gwproxy` on ports 80/443. The firewall allows SSH and 80/443
(no SFU port). Health and metrics (`127.0.0.1:8091`) are not public: scrape them over a tunnel or add
a Prometheus agent on the host.

| Setting                              | Default                                               | Meaning                                                                 |
|--------------------------------------|-------------------------------------------------------|-------------------------------------------------------------------------|
| `push_gateway_enabled`               | `false`                                               | install the gateway on this host                                        |
| `push_gateway_hostname`              | empty (required)                                      | public host name                                                        |
| `push_gateway_admin_email`           | empty (required)                                      | Let's Encrypt contact                                                   |
| `push_gateway_apns_*`                | empty                                                 | `key` (the `.p8` text), `key_id`, `team_id`, `bundle_id`, `use_sandbox` |
| `push_gateway_fcm_service_account`   | empty                                                 | the Firebase service account JSON (at least one provider is needed)     |
| `push_gateway_registration_mode`     | `open`                                                | `closed`: only keys added with `servers allow`                          |
| `push_gateway_accept_unbound_tokens` | `false`                                               | also accept raw device tokens (transition only)                         |
| `push_gateway_limits`                | `{}`                                                  | overrides of `[limits]`, e.g. `{pushes_per_day: 50000}`                 |
| `push_gateway_version`               | `1.0.0`                                               | release of the gateway (its own project)                                |
| `push_gateway_image`                 | `ghcr.io/zeitgleich/teamcraft-push-gateway:<version>` | or pin `…@sha256:<digest>`                                              |
| `push_gateway_tls`                   | `acme`                                                | `internal`: Caddy's own CA (tests)                                      |
| `push_gateway_caddy_enabled`         | `true`                                                | `false`: behind the web server the host already runs (below)            |
| `push_gateway_upstream_address`      | `127.0.0.1`                                           | loopback address of the API (and health): `127.0.0.1` or `::1`          |
| `push_gateway_port` / `_health_port` | `8090` / `8091`                                       | loopback ports of the API and of health + metrics                       |
| `push_gateway_preflight_enabled`     | `true`                                                | checks before installing (below)                                        |

Operating it (block list, limits, metrics): run the CLI inside the container, e.g.

```sh
sudo -iu tc-gateway podman exec teamcraft-push-gateway /usr/local/bin/teamcraft-push-gateway servers list
sudo -iu tc-gateway podman exec teamcraft-push-gateway /usr/local/bin/teamcraft-push-gateway servers block <server-id> <reason>
```

(`sudo -iu` needs `XDG_RUNTIME_DIR=/run/user/$(id -u tc-gateway)`.) The volume also holds the **token keys** the apps seal their device tokens to
(`teamcraft-push-gateway keys list|rotate|prune`, see the gateway's operations.md); without them every sealed
token stops opening and the apps register again, so back the volume up. Back up the volume `gateway-data` if you
want the block list and quotas to survive a lost disk; the gateway works without it.

**A backup of `gateway-data` is as sensitive as the APNs key and the FCM service account:** the token keys in it
open every sealed device token of every server. Encrypt it, keep it off the hosts the TeamCraft servers run on,
and limit who can read it; after a suspected leak, rotate the token keys (`keys rotate`, then `keys prune` once
the apps have sealed again).

## Behind a web server the host already runs (Plesk, Apache, nginx)

On a host that already serves websites on 80/443 – a Plesk server, say – the gateway goes behind that
web server instead of bringing its own Caddy:

```yaml
# inventory/host_vars/gateway.example.com/vars.yml
push_gateway_enabled: true
push_gateway_hostname: gateway.example.com
push_gateway_caddy_enabled: false
# The host's firewall stays as it is (Plesk's, fail2ban, Docker's rules). Required on Plesk and with Docker.
base_firewall_enabled: false
# push_gateway_admin_email is not needed: the web server has the certificate.
push_gateway_apns_key: "{{ lookup('file', 'AuthKey_ABC123DEFG.p8') }}"
# ... the other credentials as above
```

`just install-all --limit gateway.example.com` then:

- installs Podman from the distribution (Debian 13: 5.x, Ubuntu 24.04: 4.9 – both have Quadlet) and runs
  the gateway rootless as `tc-gateway` on `127.0.0.1:8090` (`push_gateway_upstream_address`,
  `push_gateway_port`); health and metrics on `127.0.0.1:8091`. Docker, if installed, is left alone:
  Podman runs next to it and touches neither its daemon nor its networks;
- binds nothing to 80/443, creates no `tc-gwproxy`, and leaves unprivileged users unable to bind ports
  below 1024 (`net.ipv4.ip_unprivileged_port_start` stays at the kernel's 1024);
- writes the web server's configuration, filled in with your host name and port, to
  `/srv/teamcraft/reverse-proxy/push-gateway/`: `plesk-apache-https.conf`, `plesk-nginx.conf`,
  `apache.conf`, `nginx.conf`.

The gateway takes the client's address (for its registration limits) from the last `X-Forwarded-For`
entry. That is safe because only the local web server can reach `127.0.0.1:8090`.

Before installing, the playbook stops if:

- `push_gateway_caddy_enabled` is on while another web server holds 80/443;
- 8090/8091 are taken by other software;
- `base_firewall_enabled` is on while Plesk or Docker runs on the host: the playbook's firewall replaces the
  whole nftables ruleset, theirs included.
- (Ubuntu) the host mounts a cgroup v1 hierarchy next to v2 (`/proc/self/cgroup` has lines other than
  `0::`, e.g. `net_cls` from VPN software). Podman 4.9 then moves its monitor process out of the service's
  cgroup, and systemd stops the container right after it starts. Podman 5 (Debian 13) is not affected.

`push_gateway_preflight_enabled: false` skips these checks.

On Ubuntu, AppArmor restricts unprivileged user namespaces (`kernel.apparmor_restrict_unprivileged_userns`);
Ubuntu's own `podman` package ships the AppArmor profile that allows them, so rootless Podman works as is.
If a service doesn't start and its journal (`sudo journalctl _UID=$(id -u tc-gateway)`) says
`cannot set up namespace` or `newuidmap: ... Operation not permitted`, a hardened profile or a Podman from
elsewhere is in the way.

### Plesk with Apache only (no nginx)

1. **Domain**: Websites & Domains → *Add Domain* (or *Add Subdomain*) `gateway.example.com`, hosting
   type *Website*. DNS A and AAAA to the server.
2. **Certificate**: *SSL/TLS Certificates* → *Let's Encrypt* for the name; Plesk renews it. In *Hosting
   Settings*, turn on *Permanent SEO-safe 301 redirect from HTTP to HTTPS*.
3. **Apache modules**: Tools & Settings → *Apache Web Server*: `proxy`, `proxy_http` and `headers` on (Plesk
   restarts Apache).
4. **Playbook**: with the settings above, `just install-all --limit gateway.example.com`.
5. **Directives**: the domain → *Apache & nginx Settings* → **Additional directives for HTTPS**: paste
   `/srv/teamcraft/reverse-proxy/push-gateway/plesk-apache-https.conf` (`sudo cat` it on the server), *OK*.
   Leave *Additional directives for HTTP* empty: the redirect sends everything to HTTPS.

```apache
ProxyRequests Off
ProxyPreserveHost On
RequestHeader set X-Forwarded-Proto "https"
ProxyPass /.well-known/acme-challenge/ !
ProxyPass /healthz !
ProxyPass /metrics !
RedirectMatch 404 ^/(healthz|metrics)$
ProxyPass / http://127.0.0.1:8090/ timeout=60
ProxyPassReverse / http://127.0.0.1:8090/
```

What each line is for:

- `ProxyPreserveHost` keeps `Host`.
- mod_proxy appends the client's address to `X-Forwarded-For` by itself; `X-Forwarded-Proto` is set
  explicitly.
- The ACME path stays with Plesk for renewals.
- Health and metrics answer 404.
- Pushes wait on APNs/FCM for a few seconds at most; `timeout=60` covers that.

The test for this setup (`test/gateway-dry-run.sh`) puts exactly this file into an Apache 2.4 virtual
host on Ubuntu 24.04, the way Plesk includes it.

### Plesk with nginx in front

The domain → *Apache & nginx Settings*:

Paste `plesk-nginx.conf` into **Additional nginx directives**. *Proxy mode* can stay on or off: the
catch-all is a regex location (`~ ^/(?![.]well-known/acme-challenge/)`), which wins over Plesk's own
`location /`, so Plesk doesn't refuse it as a duplicate, and it leaves the ACME challenges to Plesk.

The Apache directives above are then not needed.

```nginx
location = /healthz {
    return 404;
}
location = /metrics {
    return 404;
}
location ~ ^/(?![.]well-known/acme-challenge/) {
    proxy_pass http://127.0.0.1:8090;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 60s;
}
```

### Plain Apache or nginx

`apache.conf` and `nginx.conf` in the same directory are a complete virtual host / server block with
certbot's certificate paths. Copy one, check it (`apachectl configtest` / `nginx -t`) and reload.

### Check

```sh
just self-check --limit gateway.example.com
curl -s https://gateway.example.com/v1/info                                      # providers
curl -s -o /dev/null -w '%{http_code}\n' https://gateway.example.com/healthz          # 404
curl -s -o /dev/null -w '%{http_code}\n' https://gateway.example.com/metrics          # 404
ssh gateway.example.com 'sudo ss -tlnp | grep -E ":(8090|8091) "'                     # 127.0.0.1 only
```

Then point a TeamCraft server at it (`teamcraft_push_gateway_url: https://gateway.example.com`). The
server registers itself, and a test push from an app arrives.

