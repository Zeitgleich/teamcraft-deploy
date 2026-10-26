# Behind your own reverse proxy

By default the playbook runs [Caddy](components/caddy.md) on ports 80 and 443, which gets certificates
and forwards every host name. On a server that already has a web server on those ports – nginx,
Apache, Plesk, Traefik, HAProxy, another Caddy – turn Caddy off and let that web server forward to
TeamCraft:

```yaml
# inventory/host_vars/chat.example.com/vars.yml
caddy_enabled: false

# The SFU's certificate (below). certbot:
teamcraft_sfu_certificate_path: /etc/letsencrypt/live/sfu.chat.example.com/fullchain.pem
teamcraft_sfu_certificate_key_path: /etc/letsencrypt/live/sfu.chat.example.com/privkey.pem
# or Plesk:
# teamcraft_sfu_certificate_nginx_conf: /var/www/vhosts/system/sfu.chat.example.com/conf/last_nginx.conf

# A host that has its own firewall (Plesk, a hoster's panel, ufw, firewalld): keep it.
base_firewall_enabled: false
```

Then `just setup-all` (not `install-all`: switching from Caddy needs Caddy removed). What changes:

- No Caddy container, no `tc-proxy` user in use, nothing of TeamCraft binds 80 or 443, and the
  playbook no longer lets unprivileged users bind ports from 80 (`net.ipv4.ip_unprivileged_port_start`
  goes back to the kernel's 1024).
- The services listen on loopback as before: the server on `127.0.0.1:8080`, Keycloak `:8180`,
  Garage's S3 API `:3900`, CalCraft `:5232`. Your proxy forwards to them.
- The server trusts `X-Forwarded-For` and `X-Forwarded-Host` from loopback
  (`teamcraft_trusted_proxies`), so rate limits count per client and brands see the host name the
  client asked for.
- The playbook writes ready-made configurations for your proxy, filled in with your host names and
  ports, to **`/srv/teamcraft/reverse-proxy/`** on the server: `nginx/`, `plesk/` (one file per
  domain), `apache/`, `haproxy/`, `traefik/`, `caddy/`. Copy the one you need.
- The SFU gets its certificate from files you already have (below).

| Setting                                                             | Default                                     | Meaning                                                                                       |
|---------------------------------------------------------------------|---------------------------------------------|-----------------------------------------------------------------------------------------------|
| `caddy_enabled`                                                     | `true`                                      | `false`: your own proxy                                                                       |
| `teamcraft_upstream_address`                                        | `127.0.0.1`                                 | loopback address of the proxied services: `127.0.0.1` or `::1`                                |
| `teamcraft_ports`                                                   | 8080, 8180, 3900, 5232, …                   | move any that other software uses (the preflight check says which)                            |
| `teamcraft_trusted_proxies`                                         | `[127.0.0.1, ::1]` without Caddy            | addresses whose `X-Forwarded-Host` counts                                                     |
| `teamcraft_sfu_certificate_path` / `_key_path`                      | –                                           | existing certificate and key of the SFU's host name (may be one file)                        |
| `teamcraft_sfu_certificate_nginx_conf`                              | –                                           | instead: the nginx file that names them (Plesk)                                               |
| `teamcraft_proxy_certificate_path` / `_key_path`                    | `/etc/letsencrypt/live/{host}/fullchain.pem` | what the generated nginx/Apache files use per host name                                     |
| `teamcraft_proxy_snippets_dir`                                      | `/srv/teamcraft/reverse-proxy`              | where the generated files go                                                                  |
| `teamcraft_preflight_enabled`                                       | `true`                                      | the checks below                                                                              |

Each service binds one address: `127.0.0.1` (default) or `::1`. Both at once is not possible, and not
needed – the proxy talks to loopback, whatever family clients use. Your proxy should still listen on
IPv4 **and** IPv6 (`listen 443` and `listen [::]:443` in nginx).

## Per proxy

| Proxy                                    | Generated file                       |
|------------------------------------------|--------------------------------------|
| [nginx](proxies/nginx.md)                | `nginx/teamcraft.conf` (1.25.1+, HTTP/3), `nginx/teamcraft-legacy.conf` (older) |
| [Plesk](proxies/plesk.md) (nginx inside) | `plesk/<host name>.conf`             |
| [Apache](proxies/apache.md)              | `apache/teamcraft.conf`              |
| [HAProxy](proxies/haproxy.md)            | `haproxy/teamcraft.cfg`              |
| [Traefik](proxies/traefik.md)            | `traefik/teamcraft.yml`              |
| [Caddy](proxies/caddy.md) (your own)     | `caddy/Caddyfile`                    |

Anything else works too if it can do what this list says.

## What the proxy has to do

For each host name ([dns.md](dns.md)):

| Host name              | Forward to       | Needs                                                                                     |
|------------------------|------------------|-------------------------------------------------------------------------------------------|
| `chat.example.com`     | `127.0.0.1:8080` | WebSocket upgrade on `/api/v1/gateway` and `/api/v1/rendezvous`; refuse `/api/internal/` |
| brand host names       | `127.0.0.1:8080` | the same (one certificate per name, or one with all names)                               |
| `id.chat.example.com`  | `127.0.0.1:8180` | only `/realms/`, `/resources/`, `/robots.txt` (the admin console stays private)          |
| `s3.chat.example.com`  | `127.0.0.1:3900` | `Host` unchanged, no body size limit, CORS for the web client's origins                  |
| `cal.chat.example.com` | `127.0.0.1:5232` | CalCraft only                                                                             |
| `sfu.chat.example.com` | – (not proxied)  | only a certificate; the SFU itself answers on **udp/3478**                                |

With the integration bridge (`teamcraft_bridge_enabled`), `chat.example.com` also sends `/hooks/` and
`/ingest/` to `127.0.0.1:8088`; `/ingest/` unbuffered, without a body size limit and with a long read
timeout (log lines can be a stream). The generated files do it.

And everywhere:

- **TLS** with a certificate per name, HTTP → HTTPS redirect, HTTP/2.
- **`Host` unchanged.** Brands are told apart by it, and S3 presigned URLs are signed for it: a
  rewritten `Host` gives `SignatureDoesNotMatch` on every attachment.
- **`X-Forwarded-For`** with the client's address as its last entry (best: replace what the client
  sent), **`X-Forwarded-Proto: https`**, **`X-Forwarded-Host`**. Keycloak reads them
  (`KC_PROXY_HEADERS=xforwarded`); the server counts rate limits by the address. Without them every
  client shares one rate limit and a few wrong passwords block everybody.
- **WebSockets**: `Upgrade` and `Connection: upgrade` passed on, and a read timeout well over 30 s
  (clients send a heartbeat every 30 s; the generated files use 1 h).
- **Body size**: up to 4 MiB on the server's names (`security.max_request_body_bytes`; nginx's default
  is 1 MiB), unlimited on S3 (attachments are uploaded there directly), streamed.
- **`/api/internal/` refused** (404 or 403): the SFU reports joins and leaves there over loopback, and
  nobody else may.

Security headers need nothing from the proxy: the server sets them itself (`Content-Security-Policy`,
`X-Content-Type-Options`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store` on the API and
`Strict-Transport-Security`). Don't add a second `Content-Security-Policy` in the proxy: browsers apply
both, and the stricter one breaks the web client. HSTS for the other names (Keycloak, S3) is up to you.

## The SFU's certificate

Calls run over WebTransport (HTTP/3, QUIC) on **udp/3478**, which no HTTP reverse proxy forwards: the
SFU terminates TLS itself and needs a certificate for `sfu.chat.example.com` (`teamcraft_sfu_hostname`)
that clients trust. Get it like the others (certbot, Plesk, your proxy's ACME), then name the files:

```yaml
# certbot (any challenge; the generated nginx file serves HTTP-01 for the SFU's name on port 80)
teamcraft_sfu_certificate_path: /etc/letsencrypt/live/sfu.chat.example.com/fullchain.pem
teamcraft_sfu_certificate_key_path: /etc/letsencrypt/live/sfu.chat.example.com/privkey.pem

# A wildcard certificate *.chat.example.com works as well; so does a file that holds key and chain.

# Plesk: names change on every renewal, so give the domain's nginx configuration that names them
teamcraft_sfu_certificate_nginx_conf: /var/www/vhosts/system/sfu.chat.example.com/conf/last_nginx.conf
```

A root service (`teamcraft-sfu-cert.service`, script `/usr/local/libexec/teamcraft-sfu-cert-copy`)
copies them to `/srv/teamcraft/certs/sfu.{crt,key}` (group `tc-certs`, which `tc-sfu` is in): it splits
a combined file, puts the certificate of the key first, and refuses files that don't match each other,
don't cover the SFU's host name or have expired. It runs when the files change
(`teamcraft-sfu-cert.path`) and hourly (`teamcraft-sfu-cert.timer`); a changed certificate restarts the
SFU (running calls reconnect). The playbook runs it once and stops with its reason if it fails.

Check it on the server:

```sh
sudo systemctl start teamcraft-sfu-cert.service; sudo journalctl -u teamcraft-sfu-cert.service -n 5
sudo openssl x509 -in /srv/teamcraft/certs/sfu.crt -noout -subject -enddate
```

With certbot you can also trigger the copy right at renewal:
`certbot renew --deploy-hook "systemctl start teamcraft-sfu-cert.service"`.

## Firewall

Your proxy's 80/443 stay as they are. TeamCraft adds one port: **udp/3478** (`teamcraft_ports.sfu`),
IPv4 and IPv6, for calls. With `base_firewall_enabled: true` the playbook's nftables ruleset opens it –
but it **replaces the whole ruleset**, including your proxy's or panel's rules. On a shared server set
`base_firewall_enabled: false` and open the port yourself:

```sh
sudo ufw allow 3478/udp                                                        # ufw
sudo firewall-cmd --permanent --add-port=3478/udp && sudo firewall-cmd --reload  # firewalld
```

Plesk: [proxies/plesk.md](proxies/plesk.md#firewall). A hoster's firewall in front (cloud security
group) needs the same port.

## Preflight checks

Before installing anything the playbook checks (`teamcraft_preflight_enabled`):

- With Caddy enabled, nothing else may hold tcp/80, tcp/443 or udp/443. A web server there stops the
  run with a pointer to this page – Caddy would only crash-loop next to it.
- No other software may hold a port TeamCraft's services use (`teamcraft_ports`, loopback ports
  included, e.g. 8080 or 5432). Move TeamCraft's with `teamcraft_ports` if one is taken; only the ones
  you name change, e.g. `teamcraft_ports: {postgres: 13100, server: 13101}`.
- `base_firewall_enabled` is `false` on hosts with Plesk or Docker (the playbook's firewall would
  replace their rules).
- On Ubuntu (Podman 4.9) the host has only cgroup v2.

TeamCraft's own services (already installed) don't count as conflicts.

## Checking it

From your machine, after `just install-all` and reloading the proxy:

```sh
just self-check                                   # services, health, internal API refused, S3, Keycloak

# Health over IPv4 and IPv6, HTTP/2
curl -4 -sS -o /dev/null -w '%{http_version} %{http_code}\n' https://chat.example.com/readyz   # 2 200
curl -6 -sS -o /dev/null -w '%{http_version} %{http_code}\n' https://chat.example.com/readyz   # 2 200

# WebSocket upgrade of the gateway: 101 (curl waits afterwards; -m ends it)
curl -sS -o /dev/null -m 3 -w '%{http_code}\n' --http1.1 -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://chat.example.com/api/v1/gateway

# Internal API and Keycloak admin console refused: 404 (or 403)
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://chat.example.com/api/internal/v1/calls/participants/joined
curl -s -o /dev/null -w '%{http_code}\n' https://id.chat.example.com/admin/master/console/

# S3: answers (403 without credentials), CORS for the web client
curl -s -o /dev/null -w '%{http_code}\n' https://s3.chat.example.com/
curl -s -D - -o /dev/null -X OPTIONS -H 'Origin: https://chat.example.com' https://s3.chat.example.com/teamcraft/x \
  | grep -i access-control-allow-origin

# SFU: QUIC handshake with a trusted certificate (needs a curl with HTTP/3, e.g. Fedora's or Debian 13's)
curl -v -m 5 --http3-only https://sfu.chat.example.com:3478/ 2>&1 | grep -E 'SSL certificate verified|subject:'
```

Then the real thing: sign in with an app, send a message (gateway), upload an image (S3), and start a
call between two devices on different networks (SFU, UDP 3478). A call that rings but never connects
almost always means udp/3478 is blocked somewhere or the SFU's certificate is not trusted.

## Push gateway

The optional [push gateway](components/push-gateway.md) runs on its own host with its own Caddy; this
page is about the TeamCraft server.
