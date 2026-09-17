# S3 Adapter (Source)

Polls an S3 prefix on a timer, downloads objects older than a minimum age, pushes each one downstream, and optionally deletes it from the bucket. Uses the aws_s3 library for signing and transport.

| | |
|---|---|
| **Slug** | `s3_source` |
| **Node type id** | `LKFLOW_S3_SOURCE` |
| **Node type** | source |
| **Version** | 1.0.0 |
| **Interval driven** | yes |
| **Libraries** | aws_s3 1.0.0 |

## Configuration

| Field | Type | Default | Notes |
|---|---|---|---|
| Interval | number | `60000` | How often, in milliseconds, the runtime invokes the polling script. 60000 is one minute. |
| Region | string | `us-east-1` | The AWS region the bucket lives in. Must match the bucket, or S3 rejects the signature. |
| Bucket Name | string | _(empty)_ | The S3 bucket to poll. |
| Access Key | password | _(empty — set on the node)_ | AWS access key ID. Stored encrypted and decrypted only when the script reads it. |
| Secret Key | password | _(empty — set on the node)_ | AWS secret access key. Stored encrypted and decrypted only when the script reads it. |
| Endpoint Override | string | _(empty)_ | Leave blank for AWS. Set to a full base URL to point at an S3-compatible service such as MinIO or LocalStack. |
| Prefix | string | `incoming/` | Only keys under this prefix are polled. A trailing slash makes it behave like a folder. |
| Minimum Object Age | number | `60` | The minimum age, in seconds, an object must reach before it is downloaded. Stops the poller picking up an object that another process is still uploading. 60 is one minute. |
| Max Objects Per Poll | number | `10` | Upper bound on how many objects one poll handles, so a large backlog is drained over several intervals rather than in one long run. |
| Delete After Download | bool | `true` | Delete each object from S3 after it has been pushed downstream. Turn off for a read-only demo that can be replayed. |
| Live Mode | bool | `false` | When off, requests are signed and logged but never sent. Lets you prove configuration and signing are correct before touching a real bucket. |
| Verify TLS | bool | `true` | Verify the server certificate. Leave on for AWS; turn off only for a local S3-compatible service with a self-signed certificate. |
