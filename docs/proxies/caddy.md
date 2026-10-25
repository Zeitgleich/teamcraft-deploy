# Your own Caddy in front

If the server already runs Caddy (as a system service, or for other sites), let it serve TeamCraft too
instead of the playbook's own. General part and settings: [../reverse-proxy.md](../reverse-proxy.md).

```yaml
# vars.yml
caddy_enabled: false
base_firewall_enabled: false     # if the host has its own firewall; then open udp/3478 there
# Caddy's certificate for the SFU's name (path for Debian's caddy package, ACME from Let's Encrypt):
teamcraft_sfu_certificate_path: /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/sfu.chat.example.com/sfu.chat.example.com.crt
teamcraft_sfu_certificate_key_path: /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/sfu.chat.example.com/sfu.chat.example.com.key
```

The playbook writes `/srv/teamcraft/reverse-proxy/caddy/Caddyfile`: the same site blocks the bundled
Caddy uses (with your host names and ports). Copy the site blocks into your Caddyfile – leave out the
global options block at the top if you have your own – and `caddy reload`.

Caddy needs no extra settings for TeamCraft: it passes `Host`, sets `X-Forwarded-For/-Proto/-Host`
(replacing what clients send), upgrades WebSockets and has no read timeout on them.

The SFU's site block (`sfu.chat.example.com { respond "TeamCraft SFU" 200 }`) is there so Caddy gets a
certificate for that name. Caddy must have obtained it before the playbook starts the SFU: run
`caddy reload` with the new blocks first, wait until the files exist, then `just setup-all`. If Caddy
runs as another user or with another storage path, find the files with
`sudo find / -path '*certificates*' -name 'sfu.chat.example.com.crt'`.

## Check

The list in [../reverse-proxy.md](../reverse-proxy.md#checking-it).
