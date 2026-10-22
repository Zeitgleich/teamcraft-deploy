# Mail (SMTP relay)

The server sends meeting invitations (iMIP) and space invitations by e-mail through an SMTP relay of
your choice: your mail server or a sending provider. Without it, invitations are shown in the app only.

```yaml
teamcraft_smtp_enabled: true
teamcraft_smtp_host: smtp.example.com
teamcraft_smtp_port: 587
teamcraft_smtp_security: start_tls   # tls for port 465
teamcraft_smtp_username: teamcraft
teamcraft_mail_from: teamcraft@example.com
# password: smtp_password in your sops file (or teamcraft_smtp_password)
```

Set SPF and DKIM for the sender's domain at your mail provider so invitations aren't treated as spam.
