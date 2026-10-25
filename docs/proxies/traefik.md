# Traefik in front

For a server running Traefik v3. General part and settings: [../reverse-proxy.md](../reverse-proxy.md).
Not covered by the dry run.

```yaml
# vars.yml
caddy_enabled: false
base_firewall_enabled: false     # if the host has its own firewall; then open udp/3478 there
```

The playbook writes `/srv/teamcraft/reverse-proxy/traefik/teamcraft.yml`, a dynamic configuration for
Traefik's **file provider**. Put it into the directory of `providers.file.directory` (Traefik reloads
it). It assumes an entry point `websecure` on 443 and a certificate resolver `letsencrypt`; rename
them to yours.

**Traefik must reach TeamCraft's loopback.** The services listen on `127.0.0.1` of the host. Traefik
installed as a binary reaches it; Traefik in a container only with host networking
(`network_mode: host` in Compose, `--network host` with Podman/Docker). In a bridge network,
`127.0.0.1` is the container itself and every router answers 502.

What it does:

- Routers per host name; the server's router for every brand host name.
- `/api/internal/`: a router with high priority and an `ipAllowList` middleware that only lets
  loopback through (403 for everybody else).
- Keycloak: the router matches `/realms/`, `/resources/` and `/robots.txt` only; anything else on that
  name finds no router (404).
- S3: the `headers` middleware adds CORS for every web client origin and answers preflight requests.
- WebSockets need nothing: Traefik upgrades them by itself, and `Host` is passed unchanged
  (`passHostHeader`, the default).
- `X-Forwarded-For`: Traefik replaces what clients send unless they come from
  `entryPoints.<name>.forwardedHeaders.trustedIPs`.

## The SFU's certificate from Traefik

The configuration has a router for the SFU's host name so that Traefik gets a certificate for it
(the router itself only answers loopback). Traefik keeps certificates in `acme.json`, which the SFU
can't read. Either get the SFU's certificate with certbot (`--standalone` doesn't work while Traefik
holds port 80; use DNS-01, e.g. a `certbot-dns-*` plugin) and set `teamcraft_sfu_certificate_path`, or
export Traefik's certificate into files with a tool such as `traefik-certs-dumper` and point
`teamcraft_sfu_certificate_path` / `_key_path` at its output (the copy service picks up renewals).

## Uploads

Traefik's entry point `respondingTimeouts.readTimeout` (60 s by default in v3) limits how long reading
a request may take. Large attachments over slow uplinks can hit it; raise it on the entry point if
uploads of big files break off.

## Check

The list in [../reverse-proxy.md](../reverse-proxy.md#checking-it); Traefik's dashboard shows the
routers `teamcraft*` and their services' health.
