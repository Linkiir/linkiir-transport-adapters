# Linkiir Transport Adapters

Adapters for moving bytes and messages: object storage, file transport and encryption envelopes, and streaming or message brokers.

A **catalog** is a package of adapter content that one Linkiir Grid publishes and other grids subscribe to. Subscribing adds these adapters to your grid without a product upgrade.

| | |
|---|---|
| **Catalog id** | `lkflow` |
| **Publisher** | Linkiir Inc |
| **Adapters** | 2 |
| **Libraries** | 1 |
| **Documentation** | [https://help.linkiir.com/docs/catalogs/](https://help.linkiir.com/docs/catalogs/) |

---

## Subscribe

In Grid, open **Settings → Catalogs → Subscribe** and paste this URL:

```
https://github.com/Linkiir/linkiir-transport-adapters
```

| Field | Value |
|---|---|
| **URL** | the address above |
| **Ref** | `main` |
| **SSH private key** | leave blank — this is a public repository, cloned anonymously |
| **Install name** | `linkiir-transport-adapters` |

Use the install name exactly as given. Grid records it on every node built from this catalog, so a consistent name keeps a node's origin readable when you contact support.

Subscribing requires the **Manage catalogs** permission (Administration tier). Full instructions, including how to review an update before applying it, are in [the Catalogs documentation](https://help.linkiir.com/docs/catalogs/).

## Adapters

| Adapter | Type | Trigger | Version | Node type id |
|---|---|---|---|---|
| **S3 Adapter (Destination)** | destination | on message | 1.0.0 | `LKFLOW_S3_DESTINATION` |
| **S3 Adapter (Source)** | source | interval | 1.0.0 | `LKFLOW_S3_SOURCE` |

### S3 Adapter (Destination)

Uploads every message that reaches this node to an S3 bucket as its own object. Generates the object key from a prefix, a naming rule and an extension. Uses the aws_s3 library for signing and transport.

`LKFLOW_S3_DESTINATION` · destination node · version 1.0.0 · 11 configuration fields · library `aws_s3` 1.0.0

Credentials required: **Access Key**, **Secret Key**. These ship empty — see [Credentials](#credentials).

### S3 Adapter (Source)

Polls an S3 prefix on a timer, downloads objects older than a minimum age, pushes each one downstream, and optionally deletes it from the bucket. Uses the aws_s3 library for signing and transport.

`LKFLOW_S3_SOURCE` · source node · version 1.0.0 · 12 configuration fields · library `aws_s3` 1.0.0

Credentials required: **Access Key**, **Secret Key**. These ship empty — see [Credentials](#credentials).

## Libraries

Shared Lua modules the adapters above depend on. A node pins the exact version it uses, and published versions are immutable, so several can sit side by side.

| Library | Version | Used by |
|---|---|---|
| `aws_s3` | 1.0.0 | S3 Adapter (Destination), S3 Adapter (Source) |

### `aws_s3` 1.0.0

AWS S3 client for the native Linkiir scripting API. Signs requests with AWS Signature V4 using linkiir.sec, talks to S3 over linkiir.link.web, and parses ListObjectsV2 and error responses without an XML module. Exposes put/get/head/delete/list on a client object, each returning result or nil+err, with built-in retry and backoff.

Modules: `aws_s3.lua`, `aws_s3_config.lua`, `aws_s3_http.lua`, `aws_s3_sigv4.lua`, `aws_s3_xml.lua`

## Credentials

Every adapter here ships with its credential fields **empty**, by design. Password fields are encrypted with your own grid's key, so a value shipped from this repository could not be decrypted on your machine. Enter yours on the node after you build it.

Two fields appear on most adapters:

| Field | What it does |
|---|---|
| **Live Mode** | When off, requests are prepared and logged but never sent. Use it to confirm configuration and authentication before touching a live system. |
| **Verify TLS** | Verifies the server's certificate. Leave on. Turn it off only against a local service with a self-signed certificate. |

## Versions and updates

| | |
|---|---|
| **Adapters** | Versioned by the `version` field on each adapter. A change that does not move the version forward is rejected, so one version always means one specific set of files. |
| **Libraries** | Immutable. A published version is never edited; a fix ships as a new version. Nodes pinned to an older version are undisturbed by an update. |

Grid shows you the incoming commit and diff before applying an update. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Repository layout

```
catalog.json                              catalog manifest
nodes/<slug>/node_config.json             an adapter definition
nodes/<slug>/*.lua                        its scripts
nodes/<slug>/samples/                     de-identified test messages
libraries/<name>/<version>/library.json   a published library version
libraries/<name>/<version>/<name>/*.lua   its modules
```

The layout matches Grid's own on-disk layout, so a pull applies no transform.

## Other Linkiir catalogs

| Catalog | Covers |
|---|---|
| [linkiir-fhir-adapters](https://github.com/Linkiir/linkiir-fhir-adapters) | FHIR adapters and FHIR tooling |
| [linkiir-ehr-adapters](https://github.com/Linkiir/linkiir-ehr-adapters) | EHR and practice management over proprietary APIs, openEHR |
| [linkiir-interop-adapters](https://github.com/Linkiir/linkiir-interop-adapters) | HL7 v2, C-CDA, IHE, HIE, public health, engine migration |
| [linkiir-payer-adapters](https://github.com/Linkiir/linkiir-payer-adapters) | X12 EDI, clearinghouses, payer APIs, pharmacy |
| [linkiir-diagnostics-adapters](https://github.com/Linkiir/linkiir-diagnostics-adapters) | labs and LIS, imaging and PACS, devices |
| [linkiir-data-adapters](https://github.com/Linkiir/linkiir-data-adapters) | relational and NoSQL databases, warehouses, BI |
| **linkiir-transport-adapters** _(this one)_ | object storage, file transport, message brokers |
| [linkiir-ai-adapters](https://github.com/Linkiir/linkiir-ai-adapters) | AI and LLM services |
| [linkiir-notification-adapters](https://github.com/Linkiir/linkiir-notification-adapters) | chat, SMS, voice, email, paging |
| [linkiir-business-adapters](https://github.com/Linkiir/linkiir-business-adapters) | CRM, ERP, ITSM, HR, identity, scheduling |

## Documentation and support

Product documentation lives at **[help.linkiir.com](https://help.linkiir.com/docs/catalogs/)** — how catalogs work, subscribing and reviewing updates, building nodes from catalog adapters, and offline delivery. This repository holds the adapter content itself; it is not the documentation site.

For a question about a specific adapter, quote its node type id.

## License

Copyright © Linkiir Inc. All rights reserved.

This source is published so Linkiir Grid customers can read, audit and run it. It is **not** open source. See [LICENSE](LICENSE) for the terms that apply.

