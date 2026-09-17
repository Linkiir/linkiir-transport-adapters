# S3 Adapter (Destination)

Uploads every message that reaches this node to an S3 bucket as its own object. Generates the object key from a prefix, a naming rule and an extension. Uses the aws_s3 library for signing and transport.

| | |
|---|---|
| **Slug** | `s3_destination` |
| **Node type id** | `LKFLOW_S3_DESTINATION` |
| **Node type** | destination |
| **Version** | 1.0.0 |
| **Interval driven** | no |
| **Libraries** | aws_s3 1.0.0 |

## Configuration

| Field | Type | Default | Notes |
|---|---|---|---|
| Region | string | `us-east-1` | The AWS region the bucket lives in. Must match the bucket, or S3 rejects the signature. |
| Bucket Name | string | _(empty)_ | The S3 bucket to upload into. |
| Access Key | password | _(empty — set on the node)_ | AWS access key ID. Stored encrypted and decrypted only when the script reads it. |
| Secret Key | password | _(empty — set on the node)_ | AWS secret access key. Stored encrypted and decrypted only when the script reads it. |
| Endpoint Override | string | _(empty)_ | Leave blank for AWS. Set to a full base URL to point at an S3-compatible service such as MinIO or LocalStack. |
| Key Prefix | string | `incoming/` | Prepended to every generated object key. A trailing slash makes it behave like a folder. |
| Key Naming | list | `Timestamp + GUID` | How the unique part of the object key is generated. Timestamp + GUID sorts chronologically and never collides. |
| Key Extension | string | `json` | File extension appended to the generated key, without the dot. Leave blank for no extension. |
| Content Type | string | `application/json` | The Content-Type stored with the object, which is what a browser uses to decide whether to render or download it. |
| Live Mode | bool | `false` | When off, requests are signed and logged but never sent. Lets you prove configuration and signing are correct before touching a real bucket. |
| Verify TLS | bool | `true` | Verify the server certificate. Leave on for AWS; turn off only for a local S3-compatible service with a self-signed certificate. |

## Samples

De-identified messages you can run the node against:

- `samples/fhir_patient.json`
