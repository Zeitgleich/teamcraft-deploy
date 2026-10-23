# Apache in front

For a server that runs Apache 2.4 on 80/443. General part and settings:
[../reverse-proxy.md](../reverse-proxy.md). The generated file is syntax-checked by the dry run
(`apachectl configtest`); the full end-to-end run uses nginx.

```yaml
# vars.yml
caddy_enabled: false
base_firewall_enabled: false     # if the host has its own firewall; then open udp/4433 there
teamcraft_sfu_certificate_path: /etc/letsencrypt/live/sfu.chat.example.com/fullchain.pem
teamcraft_sfu_certificate_key_path: /etc/letsencrypt/live/sfu.chat.example.com/privkey.pem
```

Certificates: one per host name, e.g. `sudo certbot certonly --apache -d chat.example.com` (and `sfu.`,
`id.`, `s3.`, `cal.`), before the playbook runs (the SFU needs its certificate at start).

```sh
just setup-all
ssh chat.example.com
sudo a2enmod ssl http2 headers proxy proxy_http proxy_wstunnel rewrite
sudo cp /srv/teamcraft/reverse-proxy/apache/teamcraft.conf /etc/apache2/sites-available/teamcraft.conf
sudo a2ensite teamcraft && sudo apachectl configtest && sudo systemctl reload apache2
```

The file has one `<VirtualHost *:443>` per host name (port 80 and its redirect stay with your existing
configuration). The server's:

```apache
<VirtualHost *:443>
    ServerName chat.example.com
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/chat.example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/chat.example.com/privkey.pem
    Protocols h2 http/1.1

    ProxyRequests Off
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"
    ProxyPass /api/internal/ !
    <Location "/api/internal/">
        Require all denied
    </Location>
    ProxyPass /api/v1/gateway http://127.0.0.1:8080/api/v1/gateway upgrade=websocket timeout=3600
    ProxyPass /api/v1/rendezvous http://127.0.0.1:8080/api/v1/rendezvous upgrade=websocket timeout=3600
    ProxyPass / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/
    LimitRequestBody 8388608
</VirtualHost>
```

- `upgrade=websocket` needs Apache 2.4.47 or newer (Debian 13 has 2.4.6x). Older: `mod_proxy_wstunnel`
  with `ProxyPass /api/v1/gateway ws://127.0.0.1:8080/api/v1/gateway`.
- `timeout=3600` on the WebSocket paths: Apache's default (`ProxyTimeout`, = `Timeout`, 60 s) would
  close quiet connections. Setting `ProxyTimeout` globally works as well.
- `ProxyPreserveHost On` keeps `Host`; mod_proxy adds `X-Forwarded-For` (appending the client's
  address, which the server takes), `X-Forwarded-Host` and `X-Forwarded-Server` itself;
  `X-Forwarded-Proto` is set explicitly.
- `/api/internal/` answers 403 (`Require all denied`), which the self-check accepts.
- Keycloak's host: only `/realms/`, `/resources/`, `/robots.txt` are proxied, everything else is denied
  (`<LocationMatch "^/(?!realms/|resources/|robots\.txt$)">`).
- S3: `nocanon` and `AllowEncodedSlashes NoDecode` keep the path exactly as signed, `LimitRequestBody 0`,
  CORS headers via `SetEnvIf Origin` for every host name of the web client, `OPTIONS` answered with 204
  by mod_rewrite.
- With **mpm_prefork** (mod_php) Apache serves no HTTP/2; `Protocols` is then ignored. mpm_event is
  better for many long-lived WebSockets as well: each open connection holds a worker under prefork.

## Check

The list in [../reverse-proxy.md](../reverse-proxy.md#checking-it), plus `sudo apachectl -S` (the
virtual hosts are active) and `/var/log/apache2/error.log` (`AH01144` = missing module,
`AH00898` = backend unreachable).
