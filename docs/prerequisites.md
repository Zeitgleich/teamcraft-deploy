# Prerequisites

## The server

- **Debian 13 (trixie)** or newer, freshly installed. Other distributions are not supported.
- 2 vCPU, 4 GB RAM (Keycloak and the server are the hungry ones), 20 GB disk plus the attachments
  if you use the bundled Garage.
- A public **IPv4 and IPv6** address. TeamCraft works with IPv4 only, but clients on IPv6-only
  networks then can't reach calls.
- SSH access as a user that can `sudo` (or root).

The playbook replaces the server's nftables ruleset with its own (SSH, 80/443 tcp, 443 udp, the SFU's
UDP port, both families). Set `base_firewall_enabled: false` if you manage the firewall yourself; then
open the same ports. A cloud provider's firewall in front needs the same ports for IPv4 and IPv6.

**A server that already runs a web server** (nginx, Apache, Plesk, ...) on 80/443: TeamCraft goes
behind it instead of bringing Caddy, and the firewall stays yours ([reverse-proxy.md](reverse-proxy.md)).

## Your machine

- Ansible ≥ 2.16 (`pipx install ansible-core` or your distribution's package)
- [just](https://github.com/casey/just) (optional; every recipe is a plain `ansible-playbook` call)
- `sops` and `age`, only if you keep secrets on your machine ([configuring.md](configuring.md))
- git

`just roles` installs the Ansible collections from `requirements.yml` (every `just install-all` does it).

## Elsewhere

- A domain where you can create A and AAAA records ([dns.md](dns.md)).
- Optionally: an existing OIDC provider (instead of the bundled Keycloak), an S3 provider (instead of
  Garage), an SMTP relay for invitation e-mail ([components/mail.md](components/mail.md)).
