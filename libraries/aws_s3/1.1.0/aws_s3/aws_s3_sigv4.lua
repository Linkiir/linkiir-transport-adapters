-- aws_s3_sigv4.lua — AWS Signature Version 4 for S3.
--
-- One public function, sigv4.sign, returns the request headers with
-- x-amz-date, x-amz-content-sha256 and Authorization added. Everything is
-- expressed against the Linkiir API:
--   linkiir.sec.hash{algorithm="sha256", ...}   for SHA-256
--   linkiir.sec.hmac{algorithm="sha256", ...}   for HMAC-SHA256
--
-- Three runtime facts shape this file:
--   * linkiir.sec.hash raises on empty input, so SHA256("") is returned as the
--     well-known constant instead of calling sec.hash.
--   * linkiir.codec.uri.encode encodes space as '+' and is not SigV4-safe, so
--     uriEncode is implemented here from the RFC 3986 unreserved set.
--   * sec.hmac with hex=false returns raw digest bytes and accepts a binary
--     key, which is what chaining the signing key requires.

local M = {}

-- SHA-256 of the empty string. SigV4 needs this for every GET/DELETE (no body),
-- which is exactly the input linkiir.sec.hash refuses.
local EMPTY_SHA256 =
   'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'

-- RFC 3986 unreserved: A-Z a-z 0-9 - _ . ~  (everything else percent-encoded).
-- encodeSlash=false leaves '/' alone, for the canonical URI path where slashes
-- are segment separators; true encodes it, for query values and key segments.
function M.uriEncode(s, encodeSlash)
   if s == nil then return '' end
   return (s:gsub('[^%w%-%_%.%~]', function(c)
      if c == '/' and not encodeSlash then
         return '/'
      end
      return string.format('%%%02X', string.byte(c))
   end))
end

-- SHA-256, lowercase hex. Short-circuits the empty case.
function M.sha256Hex(data)
   if data == nil or #data == 0 then
      return EMPTY_SHA256
   end
   return linkiir.sec.hash{ algorithm = 'sha256', data = data, hex = true }
end

-- HMAC-SHA256 returning raw bytes (hex=false), so results chain as keys.
local function hmacRaw(key, data)
   return linkiir.sec.hmac{ algorithm = 'sha256', key = key, data = data, hex = false }
end

-- HMAC-SHA256 returning lowercase hex, for the final signature.
local function hmacHex(key, data)
   return linkiir.sec.hmac{ algorithm = 'sha256', key = key, data = data, hex = true }
end

-- kDate -> kRegion -> kService -> kSigning, all raw bytes.
local function signingKey(secretKey, dateStamp, region, service)
   local kDate    = hmacRaw('AWS4' .. secretKey, dateStamp)
   local kRegion  = hmacRaw(kDate, region)
   local kService = hmacRaw(kRegion, service)
   return hmacRaw(kService, 'aws4_request')
end

-- Build the canonical query string from an ordered array of {name, value}
-- pairs. Both sides are encoded (slashes too), then sorted by name, then value.
local function canonicalQuery(query)
   if not query or #query == 0 then return '' end
   local parts = {}
   for _, kv in ipairs(query) do
      parts[#parts + 1] = {
         M.uriEncode(kv[1], true),
         M.uriEncode(kv[2], true),
      }
   end
   table.sort(parts, function(a, b)
      if a[1] == b[1] then return a[2] < b[2] end
      return a[1] < b[1]
   end)
   local out = {}
   for _, p in ipairs(parts) do
      out[#out + 1] = p[1] .. '=' .. p[2]
   end
   return table.concat(out, '&')
end

-- Assemble the canonical request and the string-to-sign. Split out from sign()
-- so debug() can show exactly what was hashed when a signature is rejected.
local function build(T)
   local now       = T.now or os.time()
   local amzDate   = os.date('!%Y%m%dT%H%M%SZ', now)
   local dateStamp = os.date('!%Y%m%d', now)
   local service   = T.service or 's3'
   local payloadHash = M.sha256Hex(T.payload)

   local canonicalHeaders =
      'host:' .. T.host .. '\n' ..
      'x-amz-content-sha256:' .. payloadHash .. '\n' ..
      'x-amz-date:' .. amzDate .. '\n'
   local signedHeaders = 'host;x-amz-content-sha256;x-amz-date'

   local canonicalRequest = table.concat({
      T.method,
      T.path,
      canonicalQuery(T.query),
      canonicalHeaders,
      signedHeaders,
      payloadHash,
   }, '\n')

   local scope = dateStamp .. '/' .. T.region .. '/' .. service .. '/aws4_request'
   local stringToSign = table.concat({
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      M.sha256Hex(canonicalRequest),
   }, '\n')

   return {
      amzDate = amzDate, dateStamp = dateStamp, service = service,
      scope = scope, signedHeaders = signedHeaders, payloadHash = payloadHash,
      canonicalRequest = canonicalRequest, stringToSign = stringToSign,
   }
end

-- sign{ method, host, path, query, payload, headers,
--       accessKey, secretKey, region, service, now }
--   -> headers  (a copy of T.headers plus the three signing headers)
function M.sign(T)
   local b = build(T)
   local key = signingKey(T.secretKey, b.dateStamp, T.region, b.service)
   local signature = hmacHex(key, b.stringToSign)

   local authorization = 'AWS4-HMAC-SHA256 ' ..
      'Credential=' .. T.accessKey .. '/' .. b.scope .. ', ' ..
      'SignedHeaders=' .. b.signedHeaders .. ', ' ..
      'Signature=' .. signature

   local headers = {}
   for k, v in pairs(T.headers or {}) do headers[k] = v end
   headers['x-amz-date'] = b.amzDate
   headers['x-amz-content-sha256'] = b.payloadHash
   headers['Authorization'] = authorization
   return headers
end

-- debug(T) -> canonicalRequest, stringToSign
-- For linkiir.log.debug when S3 returns SignatureDoesNotMatch with no detail.
function M.debug(T)
   local b = build(T)
   return b.canonicalRequest, b.stringToSign
end

return M
