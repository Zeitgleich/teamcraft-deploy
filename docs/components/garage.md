# Garage (attachment storage)

Attachments are encrypted on the clients and stored in S3; clients upload and download directly with
presigned URLs. By default the playbook runs a single-node [Garage](https://garagehq.deuxfleurs.fr/),
rootless as `tc-garage`, at `https://s3.<domain>` (Caddy also answers the CORS requests of the web
client). Bucket and access key are created by the playbook; the keys are secrets.

| Setting                | Default     | Meaning                                                                      |
|------------------------|-------------|------------------------------------------------------------------------------|
| `garage_capacity`      | `100G`      | capacity in the cluster layout                                               |
| `garage_data_path`     | empty       | host directory for the objects (e.g. a separate disk); empty = podman volume |
| `teamcraft_s3_bucket`  | `teamcraft` | bucket                                                                       |
| `garage_extra_buckets` | `[]`        | more buckets for the same key                                                |

## External S3 instead

```yaml
garage_enabled: false
teamcraft_s3_endpoint: https://s3.example.com
teamcraft_s3_region: eu-central-1
teamcraft_s3_bucket: teamcraft
teamcraft_s3_path_style: false
```

Keys in your sops file: `s3_access_key`, `s3_secret_key`. Allow CORS on the bucket from
`https://<domain>` (methods GET, HEAD, PUT, POST, DELETE; expose `ETag`) for the web client.
