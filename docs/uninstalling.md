# Uninstalling

## One component

Set its toggle to false (e.g. `calcraft_enabled: false`) and run `just setup-all`: the service is
stopped and its unit removed. Its data (podman volumes and the home directory of its user) stays, so
enabling it again picks up where it left off.

## Everything

```sh
just stop
# on the server, as root: users, their containers, volumes and the shared directories
for user in tc-proxy tc-server tc-sfu tc-notetaker tc-db tc-keycloak tc-garage tc-calcraft; do
  id "$user" >/dev/null 2>&1 || continue
  loginctl disable-linger "$user"
  userdel -r "$user"
done
rm -rf /srv/teamcraft /etc/sysctl.d/60-teamcraft.conf
# behind your own proxy: the SFU certificate copy, and the TeamCraft parts of the proxy's configuration
systemctl disable --now teamcraft-sfu-cert.timer teamcraft-sfu-cert.path 2>/dev/null
rm -f /etc/systemd/system/teamcraft-sfu-cert.* /usr/local/libexec/teamcraft-sfu-cert-copy
```

This deletes every message, attachment and secret on the server. The firewall rules
(`/etc/nftables.conf`) stay; replace them with your own.
