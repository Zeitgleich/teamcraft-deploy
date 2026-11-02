# TeamCraft SFU

Media forwarding for calls (WebTransport over QUIC), rootless as `tc-sfu`, on **udp/3478**, one
dual-stack socket for IPv4 and IPv6. It uses the certificate Caddy obtains for `sfu.<domain>` – or,
behind your own proxy, an existing one (`teamcraft_sfu_certificate_path` / `_key_path` /
`teamcraft_sfu_certificate_nginx_conf`, [../reverse-proxy.md](../reverse-proxy.md#the-sfus-certificate))
– and restarts by itself when it is renewed. Its control port (`127.0.0.1:8081`, used by the server for host
controls) is loopback only. Join tokens are signed by the server and checked with its public key.

| Setting                        | Default                                      | Meaning                                                  |
|--------------------------------|----------------------------------------------|----------------------------------------------------------|
| `teamcraft_sfu_image`          | `ghcr.io/zeitgleich/teamcraft-sfu:<version>` | image                                                    |
| `teamcraft_sfu_memory`         | `1g`                                         | memory limit                                             |
| `teamcraft_ports.sfu`          | `3478`                                       | public UDP port (firewall and DNS docs follow it)        |
| `teamcraft_sfu_rmem_max_bytes` | `4194304`                                    | lower limit for the host's `net.core.rmem_max`; 0: leave |

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
