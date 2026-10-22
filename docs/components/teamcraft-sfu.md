# TeamCraft SFU

Media forwarding for calls (WebTransport over QUIC), rootless as `tc-sfu`, on **udp/4433**, one
dual-stack socket for IPv4 and IPv6. It uses the certificate Caddy obtains for `sfu.<domain>` and
restarts by itself when it is renewed. Its control port (`127.0.0.1:8081`, used by the server for host
controls) is loopback only. Join tokens are signed by the server and checked with its public key.

| Setting                | Default                                      | Meaning                                           |
|------------------------|----------------------------------------------|---------------------------------------------------|
| `teamcraft_sfu_image`  | `ghcr.io/zeitgleich/teamcraft-sfu:<version>` | image                                             |
| `teamcraft_sfu_memory` | `1g`                                         | memory limit                                      |
| `teamcraft_ports.sfu`  | `4433`                                       | public UDP port (firewall and DNS docs follow it) |
