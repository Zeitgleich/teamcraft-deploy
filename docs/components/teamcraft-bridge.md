# TeamCraft integration bridge

Optional, off by default. The bridge puts webhooks (Slack/Mattermost-compatible JSON: Grafana, CI,
scripts) and log lines into end-to-end encrypted channels. It is a small headless TeamCraft client with
its own bot account and device: it encrypts itself, the server only sees ciphertext. Rootless as
`tc-bridge`, listening on loopback (`127.0.0.1:8088`); the reverse proxy sends two paths of the
instance's host name to it:

| URL                                         | Accepts                                                          |
|---------------------------------------------|------------------------------------------------------------------|
| `https://chat.example.com/hooks/<token>`    | incoming-webhook JSON (`text`, `username`, `attachments`, ...)   |
| `https://chat.example.com/ingest/<token>`   | log lines, plain text or NDJSON, also streamed (`journalctl -f`) |

The token of a source is the only credential and travels in the URL: unknown tokens get 404. The
bridge's own health endpoint stays on loopback. What the bridge does in detail: `docs/bridge.md` in the
TeamCraft repository.

**Where it runs.** The bridge holds the bot's keys and the content keys of the channels the bot is in,
next to the server. Someone who takes over this host can read those channels (and only those): put
logs and alerts there, not conversations. For a producer that should stay off this host, run the
bridge where the data comes from instead (the TeamCraft repository's `docs/bridge.md`) and leave
this role off.

## Setup

1. **Admin console → Integrations:** create the bot. Its token (`tcb_...`) is shown once.
2. Put it in the sops file ([../configuring.md](../configuring.md#secrets)) as `bridge_bot_token`. It
   can't be generated; the database key (`bridge_store_key`) and the recovery passphrase of the bot's
   backup key (`bridge_passphrase`) are.
3. Turn the role on and deploy once:

   ```yaml
   # inventory/host_vars/chat.example.com/vars.yml
   teamcraft_bridge_enabled: true
   ```

   `just install-all`. On its first start the bridge enrolls the bot's device.
4. **Channel settings → Integrations** of each channel: add the bot, then **Sources → Add source**
   (a name, webhook or log lines). The app shows the URL once,
   `https://<teamcraft_domain>/hooks/<token>` or `/ingest/<token>`; point the producer at it. The
   bridge reads the new source from the channel (encrypted) and serves it within a second.

Adding a source or a channel later needs no deployment: it all happens in the app, and revoking a
source there stops its token at once. Sources need a bridge image from the release that added
them: an older image refuses the configuration's `[app_sources]` section and doesn't start.

**Sources in the inventory (optional).** `teamcraft_bridge_sources` still writes `[[sources]]` into the
configuration, for producers you'd rather keep in the inventory; changing it restarts the bridge:

```yaml
teamcraft_bridge_sources:
  - name: ci
    token: "{{ base_secrets.bridge_source_ci }}"   # bridge_source_ci: 24+ random characters, in sops
    conversation_id: "123456789012345678"
    mentions: [{user_id: "123456789012345680", name: alice}]
```

| Setting                                      | Default                                         | Meaning                                                       |
|----------------------------------------------|-------------------------------------------------|---------------------------------------------------------------|
| `teamcraft_bridge_enabled`                   | `false`                                         | run the bridge and route `/hooks/`, `/ingest/` to it          |
| `teamcraft_bridge_image`                     | `ghcr.io/zeitgleich/teamcraft-bridge:<version>` | image (released with the server from 1.0.4)                   |
| `teamcraft_bridge_app_sources_enabled`       | `true`                                          | serve the sources channel admins add in the app               |
| `teamcraft_bridge_app_sources_history_pages` | `200`                                           | older history read once per channel for a new database        |
| `teamcraft_bridge_sources`                   | `[]`                                            | optional `[[sources]]`: name, token, conversation_id, options |
| `teamcraft_bridge_server_url`                | `https://<teamcraft_domain>`                    | the server the bot signs in to                                |
| `teamcraft_bridge_device_name`               | `<teamcraft_domain> bridge`                     | the bot's device name                                         |
| `teamcraft_bridge_memory`                    | `512m`                                          | memory limit                                                  |
| `teamcraft_bridge_max_body_bytes`            | `1048576`                                       | largest webhook request                                       |
| `teamcraft_bridge_batch_interval_ms`         | `1000`                                          | log lines collected into one message                          |
| `teamcraft_bridge_index_interval_secs`       | `3600`                                          | how often it builds its channels' search index segments       |
| `teamcraft_ports.bridge`                     | `8088`                                          | loopback port                                                 |

## Data and recovery

The bridge's database (bot keys, content keys, the outbox of unsent messages) is the podman volume
`teamcraft-bridge-data` of `tc-bridge`, encrypted with `bridge_store_key`. It is not in the backups:
when it is lost, the bridge enrolls a new device and restores the bot's keys from the server with
`bridge_passphrase`. Keep both secrets (they are in `/srv/teamcraft/secrets` or your sops file).

Disabling the role stops the bridge and removes its unit; the volume stays
([../uninstalling.md](../uninstalling.md)). Revoke the bot in the admin console when it is gone for
good.
