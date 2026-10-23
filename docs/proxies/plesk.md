# Plesk

Plesk runs nginx on 80/443 (with Apache behind it for PHP sites). TeamCraft goes next to your sites:
rootless Podman containers on loopback, one Plesk domain per TeamCraft host name whose nginx forwards
to them. General part: [../reverse-proxy.md](../reverse-proxy.md).

Tested on an Ubuntu 24.04 VM laid out like a Plesk server: Plesk's nginx vhost structure with these
directives in `vhost_nginx.conf`, certificates in the Let's Encrypt extension's `live/` directories,
Docker with containers, a foreign PostgreSQL on 5432, port 8090 taken. That covered sign-in, the
gateway WebSocket, S3, the SFU over QUIC and a renewal of its certificate. Not tested against a real
Plesk panel: check each step on your server; the [checks](../reverse-proxy.md#checking-it) at the end
tell you whether it works.

## Before you start

- **Debian 13 or Ubuntu 24.04**: Plesk supports Debian 13 from Plesk Obsidian 18.0.74 and Ubuntu 24.04
  as well. On Ubuntu the playbook installs Podman 4.9 from Ubuntu's archive and `crun` with it (Docker's
  `runc` can't start TeamCraft's read-only containers). The host must have only cgroup v2: `cat
  /proc/self/cgroup` shows a single line starting with `0::` (the preflight check stops otherwise).
- **Podman next to Plesk's Docker extension** is fine: the playbook installs Podman and runs every
  container rootless under its own user (`tc-server`, `tc-db`, ...); nothing goes through Docker's
  daemon, Plesk's Docker page won't list them, and they don't touch Docker's networks or iptables
  rules. Don't use Plesk's "Docker Proxy Rules" for TeamCraft (they add a `location ~ ^/.*` that
  doesn't upgrade WebSockets); the directives below replace them.
- **Ports**: Plesk uses 8443 and 8880 (panel), 7080/7081 (Apache behind nginx), 3306 (MariaDB) and,
  if installed, 5432 (PostgreSQL); Docker containers publish their own. TeamCraft's defaults (8080,
  8081, 8180, 9180, 3900–3903, 5232, 5432) are on loopback; the preflight check stops the run if one is
  taken. Move only those, the rest keep their defaults:

  ```yaml
  teamcraft_ports: {postgres: 13100, server: 13101, sfu: 4433, sfu_control: 13102}
  ```

  TeamCraft's PostgreSQL is its own (rootless, on its own port); an existing PostgreSQL stays untouched.
- **Mail**: Plesk's own mail server can relay TeamCraft's invitations ([../components/mail.md](../components/mail.md)).

## 1. Domains and certificates in Plesk

For each host name – `chat.example.com`, `sfu.chat.example.com`, `id.chat.example.com`,
`s3.chat.example.com` (and `cal.chat.example.com` with CalCraft, plus brand host names):

1. **Websites & Domains → Add Domain** (or **Add Subdomain** under `example.com`), hosting type
   *Website*, any document root. DNS: A and AAAA to the server ([../dns.md](../dns.md); Plesk's DNS
   does it if it serves the zone).
2. **SSL/TLS Certificates → Let's Encrypt**: issue a certificate for the name (with the `www.` alias
   off – it has no DNS record). Plesk renews it.
3. **Hosting Settings**: *Permanent SEO-safe 301 redirect from HTTP to HTTPS* on. No PHP needed.

The SFU's domain needs nothing else: it exists only so Plesk gets and renews its certificate.

## 2. Playbook

```yaml
# inventory/host_vars/chat.example.com/vars.yml
caddy_enabled: false
# Plesk manages the firewall (the preflight check insists, also when Docker runs).
base_firewall_enabled: false
# The SFU's certificate, from the Let's Encrypt extension's live directory (symlinks to the current
# files, swapped on every renewal):
teamcraft_sfu_certificate_path: /usr/local/psa/var/modules/letsencrypt/etc/live/sfu.chat.example.com/fullchain.pem
teamcraft_sfu_certificate_key_path: /usr/local/psa/var/modules/letsencrypt/etc/live/sfu.chat.example.com/privkey.pem
# If that directory doesn't exist on your Plesk (it depends on the extension's version), take the
# certificate Plesk's nginx uses instead: its files have random names that change with every renewal
# (/usr/local/psa/var/certificates/cert-XXXXXXX, key and chain in one), so name the configuration:
# teamcraft_sfu_certificate_nginx_conf: /var/www/vhosts/system/sfu.chat.example.com/conf/last_nginx.conf
```

```sh
sudo ls -l /usr/local/psa/var/modules/letsencrypt/etc/live/sfu.chat.example.com/   # which one you have
```

```sh
just setup-all
```

The playbook installs everything, copies the SFU's certificate (and keeps copying it when Plesk renews
it: `teamcraft-sfu-cert.path` watches the files and their directory, so a swapped symlink in `live/`
counts too; `teamcraft-sfu-cert.timer` checks hourly) and writes
one directives file per domain to `/srv/teamcraft/reverse-proxy/plesk/`.

Check that the SFU found its certificate:

```sh
sudo journalctl -u teamcraft-sfu-cert.service -n 3   # "copied the certificate for sfu.chat.example.com from ..."
```

With `teamcraft_sfu_certificate_nginx_conf`: `/var/www/vhosts/system/<domain>/conf/last_nginx.conf` is
where Plesk keeps the domain's current nginx configuration on Linux (`grep ssl_certificate` in it shows
the file). If your Plesk keeps it elsewhere, point the setting there.

## 3. nginx directives per domain

For `chat.example.com`, `id.chat.example.com`, `s3.chat.example.com` (and `cal.`, brand host names):

1. **Websites & Domains → the domain → Apache & nginx Settings**.
2. Under *nginx settings*, **switch Proxy mode off** and press **Apply** – on its own first. With proxy
   mode on, Plesk already has a `location /` (towards Apache) and refuses the directives with
   `duplicate location "/"`; switching it off and adding the directives in the same save doesn't work.
3. Paste the content of `/srv/teamcraft/reverse-proxy/plesk/<domain>.conf` into **Additional nginx
   directives** and press **OK**. Plesk checks the configuration before it saves.

```sh
ssh chat.example.com sudo cat /srv/teamcraft/reverse-proxy/plesk/chat.example.com.conf
```

The file for `chat.example.com` looks like this (Plesk adds `listen`, `server_name` and the certificate
itself, so it's only locations):

```nginx
location ^~ /api/internal/ {
    return 404;
}
location = /api/v1/gateway {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 1h;
    proxy_send_timeout 1h;
    proxy_buffering off;
}
# location = /api/v1/rendezvous { the same }
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header Connection "";
    client_max_body_size 8m;
}
```

Let's Encrypt keeps working: Plesk's own `/.well-known/acme-challenge/` location is more specific
than `location /`.

Plesk regenerates a domain's configuration whenever you change its settings and keeps your additional
directives; it never sees TeamCraft otherwise. After a playbook change of ports, host names or
`teamcraft_upstream_address`, paste the regenerated files again.

## Firewall

**Tools & Settings → Firewall** (the Firewall extension; install it from Extensions if it's missing):
*Add Custom Rule*, name `TeamCraft calls`, direction incoming, action allow, **UDP port 4433**, all
sources; **Apply Changes**. 80/443 are open already. The firewall extension handles IPv4 and IPv6.

```sh
sudo nft list ruleset | grep 4433     # or: sudo iptables -S | grep 4433; sudo ip6tables -S | grep 4433
```

A firewall at your hoster (security group, robot firewall) needs udp/4433 too.

## Where Plesk keeps things

| What                               | Where                                                                    |
|------------------------------------|--------------------------------------------------------------------------|
| certificates in use (key + chain)  | `/usr/local/psa/var/certificates/cert-*` (`/opt/psa/...` is the same)    |
| a domain's nginx configuration     | `/var/www/vhosts/system/<domain>/conf/last_nginx.conf`                   |
| your additional directives         | `/var/www/vhosts/system/<domain>/conf/vhost_nginx.conf`                  |
| Let's Encrypt extension's copies   | `/usr/local/psa/var/modules/letsencrypt/etc/` (layout varies by version) |
| Plesk's nginx                      | `/etc/nginx/` (`nginx -t` checks everything)                             |

## Check

The list in [../reverse-proxy.md](../reverse-proxy.md#checking-it), plus:

```sh
curl -sI http://chat.example.com/readyz | head -1        # 301 (Plesk's HTTPS redirect)
sudo nginx -t                                            # Plesk's nginx with your directives
sudo grep -c proxy_pass /var/www/vhosts/system/chat.example.com/conf/vhost_nginx.conf
```

| Symptom                                         | Cause                                                                   |
|-------------------------------------------------|-------------------------------------------------------------------------|
| `duplicate location "/"` when saving            | proxy mode still on (switch it off, Apply, then add the directives)     |
| the Plesk default page instead of TeamCraft     | directives not saved on this domain, or the wrong domain                |
| calls ring but never connect                    | udp/4433 closed (Plesk firewall, hoster), or the SFU certificate failed |
| SFU certificate copy fails after a renewal      | `journalctl -u teamcraft-sfu-cert.service`: the file it names, and why  |
