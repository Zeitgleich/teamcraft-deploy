# Updating

Each release of this playbook pins a TeamCraft version (`teamcraft_version` in
`group_vars/teamcraft_servers.yml`) together with the images of the other components it was tested
with.

```sh
just update               # git pull; shows the TeamCraft version it pins now
# read CHANGELOG.md, especially entries marked "Breaking"
just install-all
```

The server migrates its database on start; migrations are forward-only, so take a backup first
(`just backup`). To stay on a version, pin it in your `vars.yml`
(`teamcraft_version: "1.0.0"`) or check out the playbook's tag (`git checkout v1.0.0`).
Images can also be pinned by digest: `teamcraft_server_image: ghcr.io/zeitgleich/teamcraft-server@sha256:…`
(the digests are in `images.txt` of each TeamCraft release).
