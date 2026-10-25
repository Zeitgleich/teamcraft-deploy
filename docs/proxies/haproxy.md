# HAProxy in front

For a server or load balancer running HAProxy 2.6 or newer. General part and settings:
[../reverse-proxy.md](../reverse-proxy.md). The generated file is syntax-checked by the dry run
(`haproxy -c`); the full end-to-end run uses nginx.

```yaml
# vars.yml
caddy_enabled: false
base_firewall_enabled: false     # if the host has its own firewall; then open udp/3478 there
teamcraft_sfu_certificate_path: /etc/haproxy/certs/sfu.chat.example.com.pem   # key and chain in one file: fine
```

The playbook writes `/srv/teamcraft/reverse-proxy/haproxy/teamcraft.cfg`: a frontend on 443 (and 80,
redirecting) for IPv4 and IPv6 and one backend per service. Merge it into `/etc/haproxy/haproxy.cfg`
(your `global` and `defaults` stay), put one PEM per host name (certificate chain and key) into
`/etc/haproxy/certs/` (HAProxy picks by SNI), then `haproxy -c -f /etc/haproxy/haproxy.cfg` and reload.

What it does, and why:

- `http-request del-header X-Forwarded-For` + `option forwardfor`: only HAProxy's own header (the
  client's address) reaches the server. Without the deletion a client could send its own
  `X-Forwarded-For` first, and the server reads the first such header.
- `X-Forwarded-Proto`, `-Port`, `-Host` set; `Host` is passed unchanged (HAProxy's default).
- `http-request return status 404` for `/api/internal/` on the server's names and for anything on
  Keycloak's name besides `/realms/`, `/resources/`, `/robots.txt`.
- `timeout tunnel 1h` in the server's backend: WebSockets switch to tunnel mode after the upgrade, and
  `timeout tunnel` (not `timeout server`) applies then.
- S3: CORS for every web client origin (preflight answered by HAProxy with 204), `timeout server 10m`
  for large attachments.
- ACME: HAProxy has no client of its own; use certbot with `--http-01-port` behind a backend, or
  acme.sh, and concatenate `fullchain.pem` + `privkey.pem` into the PEM per name.

## Check

The list in [../reverse-proxy.md](../reverse-proxy.md#checking-it). `echo "show stat" | socat
stdio /run/haproxy/admin.sock` (with a stats socket) shows the backends' state.
