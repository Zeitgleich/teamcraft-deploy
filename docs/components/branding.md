# Brands (several host names on one server)

One TeamCraft server can appear under several host names, each with its own name, logo, colors,
login text, links and e-mail identity. Users, spaces and permissions are the same behind every host
name; a brand is presentation only. Needs TeamCraft with brand support (the `[[brands]]` section of
`teamcraft.example.toml`, `docs/branding.md` in the TeamCraft repository).

Brand data is yours: keep it in your own inventory, never in this repository.

```yaml
# inventory/host_vars/chat.example.com/vars.yml
teamcraft_brands:
  - id: brand-a                       # a-z, 0-9, "-"; stable
    is_default: true                  # exactly one
    hostnames: [chat.example.com]     # teamcraft_domain must be in one brand
    display_name: Brand A
    logo: brand-a/logo.svg            # relative to teamcraft_server_brand_assets_src
    favicon: brand-a/favicon.png
    login_title: {en: Welcome to Brand A, de: Willkommen bei Brand A}
    colors:
      light: {accent: "#0b7f78"}
      dark: {accent: "#35c6ba"}
    support_url: https://support.example.com
  - id: brand-b
    hostnames: [chat.brand-b.example.com]
    display_name: Brand B
    email_domains: [brand-b.example.com]   # their invitation mail goes out as Brand B
    logo: brand-b/logo.svg
    mail: {sender_name: Brand B Team, from_address: chat@brand-b.example.com}

# Directory with the image files, on your machine (copied to the server, mounted read-only).
teamcraft_server_brand_assets_src: "{{ inventory_dir }}/brand-assets"
# A host name no brand lists: default (the default brand) or reject (421).
teamcraft_server_branding_unknown_host: default
```

Each entry is written as a `[[brands]]` table into the server's configuration: plain keys, lists and
nested tables (`login_title`, `colors.light`, `mail`, ...) as in `teamcraft.example.toml`.

What the playbook does with the host names:

- **DNS**: add an A and an AAAA record for each brand host name ([../dns.md](../dns.md)).
- **Caddy** serves all of them in one site block, passing the `Host` header unchanged, with a
  Let's Encrypt certificate for each. The server picks the brand from the host name.
- **Keycloak** (bundled): every host name becomes a redirect URI and web origin of the one
  `teamcraft` client, on every run (not just at the first import), so brands can be added later.
  With an external provider add `https://<host>/*` to the client's redirect URIs and `https://<host>`
  to its web origins yourself; a brand without them cannot sign in.
- The server's database migrations for brands run by themselves when it starts.

## Organizations

The server can show a user's organization as a badge and filter the directory by it, from a claim of
the access token:

```yaml
teamcraft_oidc_organization_claim: organization
# Bundled Keycloak: map this user attribute to the claim (a mapper on the teamcraft client).
keycloak_organization_attribute: organization
```

Then set the attribute on users in Keycloak (user, *Attributes*). With an external provider, add a
mapper for the claim to the access token there.
