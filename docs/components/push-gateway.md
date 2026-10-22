# Push gateway

The iOS and Android **store apps** can only be pushed to with the credentials of their publisher (the
APNs key and the Firebase project). A **push gateway** holds them and forwards the sealed wake-ups of
any TeamCraft server; it sees device tokens and ciphertext, never users or messages
(the gateway is its own project, [teamcraft-push-gateway](https://github.com/Zeitgleich/teamcraft-push-gateway):
its `docs/design.md` explains the threat model and limits, `docs/api.md` the protocol). Two sides here:

1. **Your TeamCraft server** sends through a gateway: this is on by default
   (`teamcraft_push_gateway_url`, the gateway of the official apps). Almost everybody needs nothing else.
2. **A gateway host**: only for whoever publishes apps. Optional, off by default, on its **own host**,
   separate from every chat server, because it holds the publisher's credentials.

## Your server uses a gateway

```yaml
# inventory/host_vars/chat.example.com/vars.yml
teamcraft_push_gateway_url: https://push-gw.zeitgleich.de   # the default; "" turns it off
```

`just install-all` adds `[push.gateway]` to the server's configuration. The server's key for the gateway
is the generated secret `push_gateway_key` (kept with the other secrets in `/srv/teamcraft/secrets`, or
in your sops file); the server registers it at the gateway by itself. Keep the key: it is your server's
identity at the gateway. For self-built, self-signed apps use your own credentials instead
(`teamcraft_server_extra_config` with `[push.apns]` / `[push.fcm]`, see the TeamCraft `operations.md`);
Web Push and UnifiedPush never use a gateway.

## Running a gateway

Put a separate Debian 13 host in the inventory group `teamcraft_push_gateways` (not in
`teamcraft_servers`):

```ini
# inventory/hosts
[teamcraft_push_gateways]
gateway.example.com ansible_host=203.0.113.20 ansible_user=deploy
```

```yaml
# inventory/host_vars/gateway.example.com/vars.yml
push_gateway_enabled: true
push_gateway_hostname: gateway.example.com        # A + AAAA records; Caddy gets the certificate
push_gateway_admin_email: ops@example.com
push_gateway_apns_key: "{{ lookup('file', 'AuthKey_ABC123DEFG.p8') }}"   # or from your sops file
push_gateway_apns_key_id: ABC123DEFG
push_gateway_apns_team_id: DEF456GHIJ
push_gateway_apns_bundle_id: com.example.teamcraft
push_gateway_fcm_service_account: "{{ lookup('file', 'fcm-service-account.json') }}"
```

`just install-all` installs and starts it (`--limit gateway.example.com` for this host only). It runs two
rootless containers: the gateway as `tc-gateway` (loopback only, SQLite state in the volume
`gateway-data`) and its own Caddy as `tc-gwproxy` on ports 80/443. The firewall allows SSH and 80/443
(no SFU port). Health and metrics (`127.0.0.1:8091`) are not public: scrape them over a tunnel or add
a Prometheus agent on the host.

| Setting                            | Default                                               | Meaning                                                                 |
|------------------------------------|-------------------------------------------------------|-------------------------------------------------------------------------|
| `push_gateway_enabled`             | `false`                                               | install the gateway on this host                                        |
| `push_gateway_hostname`            | empty (required)                                      | public host name                                                        |
| `push_gateway_admin_email`         | empty (required)                                      | Let's Encrypt contact                                                   |
| `push_gateway_apns_*`              | empty                                                 | `key` (the `.p8` text), `key_id`, `team_id`, `bundle_id`, `use_sandbox` |
| `push_gateway_fcm_service_account` | empty                                                 | the Firebase service account JSON (at least one provider is needed)     |
| `push_gateway_registration_mode`   | `open`                                                | `closed`: only keys added with `servers allow`                          |
| `push_gateway_limits`              | `{}`                                                  | overrides of `[limits]`, e.g. `{pushes_per_day: 50000}`                 |
| `push_gateway_version`             | `1.0.0`                                               | release of the gateway (its own project)                                |
| `push_gateway_image`               | `ghcr.io/zeitgleich/teamcraft-push-gateway:<version>` | or pin `…@sha256:<digest>`                                              |
| `push_gateway_tls`                 | `acme`                                                | `internal`: Caddy's own CA (tests)                                      |

Operating it (block list, limits, metrics): run the CLI inside the container, e.g.

```sh
sudo -iu tc-gateway podman exec teamcraft-push-gateway /usr/local/bin/teamcraft-push-gateway servers list
sudo -iu tc-gateway podman exec teamcraft-push-gateway /usr/local/bin/teamcraft-push-gateway servers block <server-id> <reason>
```

(`sudo -iu` needs `XDG_RUNTIME_DIR=/run/user/$(id -u tc-gateway)`.) Back up the volume `gateway-data` if you
want the block list and quotas to survive a lost disk; the gateway works without it.
