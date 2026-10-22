# Caddy

Reverse proxy and TLS for every host name, rootless as `tc-proxy` on 80/443 (tcp, and udp for HTTP/3),
IPv4 and IPv6. Certificates come from Let's Encrypt; a timer copies the SFU's certificate to
`/srv/teamcraft/certs` for `tc-sfu`. `/api/internal/` of the server is refused from outside.

| Setting            | Default                 | Meaning                                                                 |
|--------------------|-------------------------|-------------------------------------------------------------------------|
| `caddy_tls`        | `acme`                  | `internal`: Caddy's own CA (test machines; clients must trust its root) |
| `caddy_acme_email` | `teamcraft_admin_email` | Let's Encrypt account                                                   |
| `caddy_image`      | pinned                  | image                                                                   |

With `caddy_enabled: false` you put your own proxy in front: forward `teamcraft_domain` to
`127.0.0.1:8080` (WebSockets on `/api/v1/gateway` and `/api/v1/rendezvous`, set `X-Forwarded-For`),
refuse `/api/internal/`, and provide the SFU certificate at `/srv/teamcraft/certs/sfu.{crt,key}`.
