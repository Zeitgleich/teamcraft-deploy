# DNS

All names derive from `teamcraft_domain` (here `chat.example.com`). Create an **A and an AAAA**
record for each, pointing at the server:

| Name                   | For                          | Needed when        |
|------------------------|------------------------------|--------------------|
| `chat.example.com`     | API, gateway, web client     | always             |
| `sfu.chat.example.com` | calls (QUIC on **udp/4433**) | always             |
| `id.chat.example.com`  | bundled Keycloak (sign-in)   | `keycloak_enabled` |
| `s3.chat.example.com`  | bundled Garage (attachments) | `garage_enabled`   |
| `cal.chat.example.com` | bundled CalCraft             | `calcraft_enabled` |

Every host name of a brand (`teamcraft_brands`, [components/branding.md](components/branding.md))
needs the same two records.

A wildcard `*.chat.example.com` (A + AAAA) next to `chat.example.com` covers all of them.

Caddy gets Let's Encrypt certificates for every name over HTTP (port 80), so the records must resolve
before the first run. Behind your own proxy you get them yourself ([reverse-proxy.md](reverse-proxy.md)),
the SFU's name included: it needs no proxying, only its certificate. The SFU uses the certificate of `sfu.chat.example.com`; clients connect to it on
**UDP port 4433**, which must be reachable over IPv4 and IPv6.

The names can be changed (`teamcraft_sfu_hostname`, `keycloak_hostname`, `garage_hostname`,
`calcraft_hostname`) if you prefer others.
