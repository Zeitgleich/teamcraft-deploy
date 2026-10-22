# CalCraft (meeting calendar, optional)

TeamCraft can write meetings into a CalDAV calendar and show who is busy. The playbook can run
[CalCraft](https://github.com/Zeitgleich/CalCraft) for that, rootless as `tc-calcraft`, at
`https://cal.<domain>`, and create the account the server writes with. CalCraft publishes no image
yet: build one from its repository and push it to a registry the server can pull from.

```yaml
calcraft_enabled: true
calcraft_image: registry.example.com/calcraft:<tag>
```

Not covered by the dry run. An external CalDAV server works too:

```yaml
teamcraft_caldav_calendar_url: https://cal.example.com/dav/calendars/teamcraft/meetings/
teamcraft_caldav_username: teamcraft
# password: caldav_password in your sops file
```
