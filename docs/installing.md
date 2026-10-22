# Installing

```sh
just install-all          # = ansible-playbook -i inventory/hosts setup.yml --tags=install-all,start
```

The first run installs Podman, creates the service users, generates the secrets, pulls the images,
gets the certificates and starts everything: 5–10 minutes, most of it downloads. Later runs only
change what changed and restart the affected services; a run without changes reports `changed=0`.

## Tags

| Recipe                      | Tags                | Does                                                                                                                  |
|-----------------------------|---------------------|-----------------------------------------------------------------------------------------------------------------------|
| `just install-all`          | `install-all,start` | installs and starts the enabled components                                                                            |
| `just setup-all`            | `setup-all,start`   | the same, and removes components you disabled                                                                         |
| `just install-component X`  | `install-X,start`   | one component (`postgres`, `caddy`, `keycloak`, `garage`, `teamcraft-server`, `teamcraft-sfu`, `calcraft`, `backups`) |
| `just start` / `just stop`  | `start` / `stop`    | starts (restarting changed services) / stops everything                                                               |
| `just self-check`           | `self-check`        | services active, public endpoints, internal API not exposed                                                           |
| `just ensure-admin u p [r]` | `ensure-admin`      | user `u` with password `p` and role `r` (default `owner`) in the bundled Keycloak                                     |
| `just backup`               | `backup`            | runs the backups now                                                                                                  |

Always run `install-*` together with `start` (the recipes do): restarts of changed services happen in
the `start` step.

## The first user

```sh
just ensure-admin alice 'a long password'           # owner
just ensure-admin bob 'another password' member
```

Then install the desktop app, enter `https://chat.example.com` and sign in. The first device of
every user creates their keys; set up the recovery passphrase when asked. More users: in Keycloak's
admin console ([components/keycloak.md](components/keycloak.md)) or with `ensure-admin`.

With an external identity provider, create users there and give them one of the client roles.

## Checking

```sh
just self-check
```

Under the hood each service is a systemd user unit of its service user:

```sh
sudo -u tc-server XDG_RUNTIME_DIR=/run/user/$(id -u tc-server) systemctl --user status teamcraft-server
sudo -u tc-server XDG_RUNTIME_DIR=/run/user/$(id -u tc-server) journalctl --user -u teamcraft-server -f
```
