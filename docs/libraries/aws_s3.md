# `aws_s3` 1.0.0

AWS S3 client for the native Linkiir scripting API. Signs requests with AWS Signature V4 using linkiir.sec, talks to S3 over linkiir.link.web, and parses ListObjectsV2 and error responses without an XML module. Exposes put/get/head/delete/list on a client object, each returning result or nil+err, with built-in retry and backoff.

| | |
|---|---|
| **Library** | `aws_s3` |
| **Version** | 1.0.0 |
| **Immutable** | yes — a fix ships as a new version directory |

## Modules

- `aws_s3/aws_s3.lua`
- `aws_s3/aws_s3_config.lua`
- `aws_s3/aws_s3_http.lua`
- `aws_s3/aws_s3_sigv4.lua`
- `aws_s3/aws_s3_xml.lua`

## Using it

A node that pins this library gets the `aws_s3/` folder copied in beside its script. Add it to `package.path` and require the entry module:

```lua
local aws_s3 = require("aws_s3.aws_s3")
```
