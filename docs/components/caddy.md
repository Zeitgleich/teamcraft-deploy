# Caddy

Reverse proxy and TLS for every host name, rootless as `tc-proxy` on 80/443 (tcp, and udp for HTTP/3),
IPv4 and IPv6. Certificates come from Let's Encrypt; a timer copies the SFU's certificate to
`/srv/teamcraft/certs` for `tc-sfu`. `/api/internal/` of the server is refused from outside.

| Setting            | Default                 | Meaning                                                                 |
|--------------------|-------------------------|-------------------------------------------------------------------------|
| `caddy_tls`        | `acme`                  | `internal`: Caddy's own CA (test machines; clients must trust its root) |
| `caddy_acme_email` | `teamcraft_admin_email` | Let's Encrypt account                                                   |
| `caddy_image`      | pinned                  | image                                                                   |

With `caddy_enabled: false` you put your own proxy in front (nginx, Apache, Plesk, Traefik, HAProxy,
another Caddy): the playbook then writes configurations for it to `/srv/teamcraft/reverse-proxy/` and
the SFU takes an existing certificate ([../reverse-proxy.md](../reverse-proxy.md)). The preflight check
stops a run with Caddy enabled when another web server holds 80/443.
