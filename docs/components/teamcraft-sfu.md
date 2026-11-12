# TeamCraft SFU

Media forwarding for calls (WebTransport over QUIC), rootless as `tc-sfu`, on **udp/3478**, one
dual-stack socket for IPv4 and IPv6. It uses the certificate Caddy obtains for `sfu.<domain>` – or,
behind your own proxy, an existing one (`teamcraft_sfu_certificate_path` / `_key_path` /
`teamcraft_sfu_certificate_nginx_conf`, [../reverse-proxy.md](../reverse-proxy.md#the-sfus-certificate))
– and restarts by itself when it is renewed. Its control port (`127.0.0.1:8081`, used by the server for host
controls) is loopback only. Join tokens are signed by the server and checked with its public key.
Clients whose network blocks UDP fall back to a WebSocket through the reverse proxy (below).

| Setting                        | Default                                      | Meaning                                                  |
|--------------------------------|----------------------------------------------|----------------------------------------------------------|
| `teamcraft_sfu_image`          | `ghcr.io/zeitgleich/teamcraft-sfu:<version>` | image                                                    |
| `teamcraft_sfu_memory`         | `1g`                                         | memory limit                                             |
| `teamcraft_ports.sfu`          | `3478`                                       | public UDP port (firewall and DNS docs follow it)        |
| `teamcraft_sfu_rmem_max_bytes` | `4194304`                                    | lower limit for the host's `net.core.rmem_max`; 0: leave |
| `teamcraft_ports.sfu_fallback` | `8082`                                       | loopback port of the call fallback (TCP, behind proxy)   |
| `teamcraft_sfu_nofile`         | `4096`                                       | open file limit of the container; 0: Podman's            |

## Call fallback for networks that block UDP

Calls use QUIC on udp/3478. A client whose network blocks UDP (guest Wi-Fi, some company networks)
falls back to a WebSocket at `wss://sfu.<domain>/call/fallback` on TCP 443, at lower call quality
("Limited network, call quality may be lower" in the call bar). The server offers that URL with every
join token from TeamCraft 1.0.20 on; the route goes through the reverse proxy:

- The SFU listens for it on the upstream address only, `127.0.0.1:8082`
  (`TEAMCRAFT_SFU_FALLBACK_BIND`, from `teamcraft_upstream_address` and `teamcraft_ports.sfu_fallback`).
  It runs with host networking, so the image's default `[::]:8082` would be plain HTTP on every
  address of the host. When `teamcraft_upstream_address` isn't loopback, the role also sets
  `TEAMCRAFT_SFU_FALLBACK_TRUSTED_PROXIES` to it, so the SFU counts its limits per client.
- Caddy sends exactly `/call/fallback` on the SFU's host name there; every other path still gets the
  placeholder. Behind your own proxy, the generated configurations do the same
  ([../reverse-proxy.md](../reverse-proxy.md#what-the-proxy-has-to-do)).
- The fallback's connections need about 1,216 file descriptors at the SFU's defaults: the container
  gets `--ulimit=nofile=4096:4096` (`teamcraft_sfu_nofile`). The SFU logs a warning at start when the
  limit is lower.

Checked by `just self-check`; by hand, from outside the server:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' --http1.1 --max-time 10 \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' https://sfu.chat.example.com/call/fallback
```

- `101`: the route works (the SFU closes the connection 3 s later for want of a `join`).
- `401`: the SFU as well, with `TEAMCRAFT_SFU_FALLBACK_REQUIRE_UPGRADE_TOKEN=1`.
- `200` or `404`: the request didn't reach the SFU (Caddy's placeholder, the chat server, or an nginx
  prefix location losing to a regex one).
- `502` or `504`: the proxy can't reach the SFU's port, or the request had no upgrade headers.

Then a call from a client with UDP blocked joins after about 3 s. To roll back, remove the route from
the proxy (clients fail as before) or set `[calls] sfu_fallback_enabled = false` on the server.
TeamCraft's docs/operations.md, "Call fallback through the proxy", has the details.

## UDP receive buffer

A big keyframe (about half a megabyte at 1440p) arrives as one burst. If it overflows the socket's
receive buffer while the SFU is busy, viewers see a blurry or frozen picture until the next keyframe.
So the SFU asks for a 4 MiB buffer, and the kernel silently caps that at `net.core.rmem_max`, often
about 200 KiB. It is a host-wide setting that a container can't change, so the role sets it on the
host, in `/etc/sysctl.d/60-teamcraft.conf`, and restarts the SFU when it changed it. A host value that
is already higher stays.

If the cap is too low, the SFU's log says so at start: "the system caps the UDP receive buffer". To
check a host:

```sh
sysctl net.core.rmem_max      # at least 4194304
sudo -u tc-sfu XDG_RUNTIME_DIR=/run/user/$(id -u tc-sfu) \
  journalctl --user -u teamcraft-sfu -b --no-pager | grep 'caps the UDP'      # no output
```

A value that is back down after a reboot comes from a sysctl file that is read later and sets it
lower: `grep -r rmem_max /etc/sysctl.conf /etc/sysctl.d`.

The playbook can't set it when the target is itself a container with its own network namespace (LXC,
some cheap VPS), where the setting is missing or read-only: it skips the step, and the limit has to be
raised on the machine underneath. To manage it yourself, set `teamcraft_sfu_rmem_max_bytes: 0`.
