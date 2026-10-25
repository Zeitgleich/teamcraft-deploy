# nginx in front

For a server that already runs nginx on 80/443. General part and settings:
[../reverse-proxy.md](../reverse-proxy.md). Tested by the dry run (`DRY_RUN_PROXY=nginx`, Debian 13's
nginx 1.26) and on Ubuntu 24.04 (nginx 1.24 with `teamcraft-legacy.conf`, nginx.org's 1.28 with
`teamcraft.conf` over HTTP/3).

## 1. Certificates

One per host name (`chat.example.com`, `sfu.`, `id.`, `s3.`, and `cal.` with CalCraft; brand host
names too), e.g. with certbot. The generated file answers ACME challenges on port 80 from
`/var/www/letsencrypt`, so the order is: playbook, nginx configuration, certificates.

```yaml
# vars.yml
caddy_enabled: false
base_firewall_enabled: false     # if the host has its own firewall; then open udp/3478 there
teamcraft_sfu_certificate_path: /etc/letsencrypt/live/sfu.chat.example.com/fullchain.pem
teamcraft_sfu_certificate_key_path: /etc/letsencrypt/live/sfu.chat.example.com/privkey.pem
# certificate paths the generated file uses ({host} = each host name); certbot's are the default
# teamcraft_proxy_certificate_path: /etc/letsencrypt/live/{host}/fullchain.pem
# teamcraft_proxy_certificate_key_path: /etc/letsencrypt/live/{host}/privkey.pem
```

The SFU's certificate must exist before the playbook starts the SFU. On a fresh server:

```sh
sudo mkdir -p /var/www/letsencrypt
# a temporary server block for the challenges, until the generated file is in place
printf 'server { listen 80; listen [::]:80; server_name chat.example.com sfu.chat.example.com id.chat.example.com s3.chat.example.com;\n  location /.well-known/acme-challenge/ { root /var/www/letsencrypt; } }\n' \
  | sudo tee /etc/nginx/conf.d/teamcraft.conf && sudo nginx -t && sudo systemctl reload nginx
for host in chat.example.com sfu.chat.example.com id.chat.example.com s3.chat.example.com; do
  sudo certbot certonly --webroot -w /var/www/letsencrypt -d "$host" \
    --deploy-hook "systemctl start teamcraft-sfu-cert.service || true"
done
```

(One certificate for all names works too: `-d chat.example.com -d sfu.chat.example.com ...`; then point
both `teamcraft_proxy_certificate_path` and `teamcraft_sfu_certificate_path` at it without `{host}`.)

## 2. Playbook and configuration

```sh
just setup-all
ssh chat.example.com nginx -v       # 1.25.1 or newer: teamcraft.conf, older: teamcraft-legacy.conf
ssh chat.example.com sudo cp /srv/teamcraft/reverse-proxy/nginx/teamcraft.conf /etc/nginx/conf.d/teamcraft.conf
ssh chat.example.com 'sudo nginx -t && sudo systemctl reload nginx'
```

Two files, the same apart from the `listen` lines:

| File                    | nginx                                    | Protocols                                               |
|-------------------------|------------------------------------------|---------------------------------------------------------|
| `teamcraft.conf`        | 1.25.1 or newer (Debian 13: 1.26)        | HTTP/2 (`http2 on;`) and HTTP/3 (`listen 443 quic`, `http3 on;`, `Alt-Svc`) |
| `teamcraft-legacy.conf` | older (Ubuntu 24.04: 1.24)               | HTTP/2 (`listen 443 ssl http2;`)                        |

HTTP/3 needs an nginx built with it (`nginx -V 2>&1 | grep -o with-http_v3_module`: Debian's and nginx.org's
packages are) and **udp/443** open in the firewall. `reuseport` may appear only once per address in
the whole nginx configuration: the file puts it on its first `listen 443 quic`; if another site already
has `listen 443 quic reuseport`, delete it from TeamCraft's file.

On Debian's nginx, `conf.d/*.conf` is included inside `http {}`; `sites-available/` + a link in
`sites-enabled/` works the same. The file contains, for every host name:

- port 80: ACME challenges, everything else redirected to HTTPS;
- port 443 on IPv4 and IPv6 with HTTP/2 (and HTTP/3 in `teamcraft.conf`);
- `proxy_set_header Host $host`, `X-Forwarded-For $remote_addr` (replacing whatever the client
  sent), `X-Forwarded-Proto`, `-Host`, `-Port`;
- the server: `location = /api/v1/gateway` and `= /api/v1/rendezvous` with `Upgrade`,
  `Connection "upgrade"` and 1 h read/send timeouts; `location ^~ /api/internal/ { return 404; }`;
  `client_max_body_size 8m` (nginx's default of 1 MiB is too small);
- Keycloak: only `/realms/`, `/resources/`, `/robots.txt`, with bigger proxy buffers (Keycloak's
  cookies and headers overflow nginx's defaults: "upstream sent too big header");
- Garage: `client_max_body_size 0`, `proxy_request_buffering off`, 10 min timeouts, CORS headers for
  every host name of the web client and `204` for preflight requests.

An excerpt (the server's part):

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    listen 443 quic reuseport;
    listen [::]:443 quic reuseport;
    http2 on;
    http3 on;
    add_header Alt-Svc 'h3=":443"; ma=86400' always;
    server_name chat.example.com;
    ssl_certificate /etc/letsencrypt/live/chat.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chat.example.com/privkey.pem;

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
    # location = /api/v1/rendezvous: the same
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
}
```

`X-Forwarded-For $remote_addr` assumes nginx is the first hop. Behind a CDN or load balancer, restore
the client's address first (`set_real_ip_from` + `real_ip_header`) or use
`$proxy_add_x_forwarded_for`; the server takes the last entry.

## 3. Check

The list in [../reverse-proxy.md](../reverse-proxy.md#checking-it). nginx specifics:

```sh
sudo nginx -T | grep -A3 'location = /api/v1/gateway'      # the configuration is active
sudo tail -f /var/log/nginx/error.log                         # "upstream sent too big header", 413, 502
```

| Symptom                                      | Cause                                                                 |
|----------------------------------------------|-----------------------------------------------------------------------|
| apps connect, then reconnect every minute    | WebSocket location missing: default `proxy_read_timeout` of 60 s      |
| `502` on sign-in                             | Keycloak's big headers: the `proxy_buffer_size` lines are missing     |
| attachments fail with `SignatureDoesNotMatch` | `Host` not passed (`proxy_set_header Host $host`)                     |
| attachments fail in the web client only      | CORS headers missing on the S3 name                                   |
| everyone gets `429` after a few logins       | `X-Forwarded-For` missing: all clients look like 127.0.0.1            |
