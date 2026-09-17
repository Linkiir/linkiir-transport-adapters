-- aws_s3.lua — public facade for the S3 client.
--
--   local S3 = require 'aws_s3'
--   local client = S3.client{ accessKey=, secretKey=, region=, bucket=, ... }
--   client:put{ key=, body=, contentType= }
--   client:get{ key= }          -> body, meta
--   client:head{ key= }         -> meta
--   client:delete{ key= }       -> true
--   client:list{ prefix=, maxKeys=, delimiter=, continuationToken= }
--
-- Every method returns result, nil on success or nil, err on failure. Nothing
-- here raises: raising is the node script's call, since only it knows whether
-- a failure should stop the flow.

local sigv4 = require 'aws_s3_sigv4'
local http  = require 'aws_s3_http'
local xml   = require 'aws_s3_xml'

local M = {}

local Client = {}
Client.__index = Client

-- Split an S3 endpoint URL into scheme+host (for signing and URL building).
-- host is what SigV4 signs; base is 'https://host'.
local function splitEndpoint(url)
   local scheme, host = url:match('^(%w+)://([^/]+)')
   return scheme or 'https', host
end

-- Encode a key into a URL path: each '/'-separated segment is percent-encoded
-- individually so slashes survive as separators. Leading '/' guaranteed.
local function keyToPath(key)
   local segments = {}
   for seg in (key or ''):gmatch('[^/]+') do
      segments[#segments + 1] = sigv4.uriEncode(seg, true)
   end
   local path = '/' .. table.concat(segments, '/')
   -- Preserve a trailing slash if the key had one (folder-style keys).
   if key and key:sub(-1) == '/' and path:sub(-1) ~= '/' then
      path = path .. '/'
   end
   return path
end

-- S3.client{ accessKey, secretKey, region, bucket,
--            endpoint, live, timeout, retry, pause, verifyTls }
function M.client(T)
   assert(T.accessKey and T.accessKey ~= '', 'aws_s3: accessKey is required')
   assert(T.secretKey and T.secretKey ~= '', 'aws_s3: secretKey is required')
   assert(T.region and T.region ~= '', 'aws_s3: region is required')
   assert(T.bucket and T.bucket ~= '', 'aws_s3: bucket is required')

   local endpoint = T.endpoint
   if not endpoint or endpoint == '' then
      -- Virtual-hosted style with the region in the host. Region-in-host avoids
      -- the 307 redirect S3 issues for non-us-east-1 buckets.
      endpoint = 'https://' .. T.bucket .. '.s3.' .. T.region .. '.amazonaws.com'
   end
   local scheme, host = splitEndpoint(endpoint)

   local c = setmetatable({}, Client)
   c.accessKey = T.accessKey
   c.secretKey = T.secretKey
   c.region    = T.region
   c.bucket    = T.bucket
   c.endpoint  = endpoint
   c.scheme    = scheme
   c.host      = host
   c.live      = (T.live == nil) and true or T.live
   c.timeout   = T.timeout or 30
   c.retry     = T.retry or 2
   c.pause     = T.pause or 2
   c.verifyTls = (T.verifyTls == nil) and true or T.verifyTls
   return c
end

-- Sign and send one request. path is the canonical URI, query an ordered array
-- of {name,value} pairs. Returns resp, nil | nil, err.
function Client:_send(method, path, query, body, extraHeaders)
   local verb = method:lower()
   local headers = sigv4.sign{
      method    = method,
      host      = self.host,
      path      = path,
      query     = query,
      payload   = body,
      headers   = extraHeaders,
      accessKey = self.accessKey,
      secretKey = self.secretKey,
      region    = self.region,
      service   = 's3',
   }

   -- Build the request URL: endpoint + path + optional query string.
   local url = self.endpoint .. path
   if query and #query > 0 then
      local parts = {}
      for _, kv in ipairs(query) do
         parts[#parts + 1] =
            sigv4.uriEncode(kv[1], true) .. '=' .. sigv4.uriEncode(kv[2], true)
      end
      url = url .. '?' .. table.concat(parts, '&')
   end

   return http.request(self, { verb = verb, url = url, headers = headers, body = body })
end

-- put{ key, body, contentType } -> true, nil | nil, err
function Client:put(T)
   local extra = {}
   if T.contentType then extra['Content-Type'] = T.contentType end
   local resp, err = self:_send('PUT', keyToPath(T.key), nil, T.body or '', extra)
   if not resp then return nil, err end
   return true, nil
end

-- get{ key } -> body, meta | nil, err
function Client:get(T)
   local resp, err = self:_send('GET', keyToPath(T.key), nil, '', nil)
   if not resp then return nil, err end
   local h = resp.headers or {}
   return resp.body, {
      size = tonumber(h['content-length'] or h['Content-Length']),
      etag = h['etag'] or h['ETag'],
      lastModified = h['last-modified'] or h['Last-Modified'],
      simulated = resp.simulated,
   }
end

-- head{ key } -> meta | nil, err
function Client:head(T)
   local resp, err = self:_send('HEAD', keyToPath(T.key), nil, '', nil)
   if not resp then return nil, err end
   local h = resp.headers or {}
   return {
      size = tonumber(h['content-length'] or h['Content-Length']),
      etag = h['etag'] or h['ETag'],
      lastModified = h['last-modified'] or h['Last-Modified'],
      simulated = resp.simulated,
   }
end

-- delete{ key } -> true | nil, err
function Client:delete(T)
   local resp, err = self:_send('DELETE', keyToPath(T.key), nil, '', nil)
   if not resp then return nil, err end
   return true, nil
end

-- list{ prefix, maxKeys, delimiter, continuationToken }
--   -> { objects, prefixes, truncated, nextToken }, nil | nil, err
-- ListObjectsV2 is a GET on the bucket root with list-type=2 in the query.
function Client:list(T)
   T = T or {}
   local query = {
      { 'list-type', '2' },
      { 'encoding-type', 'url' },
   }
   if T.prefix and T.prefix ~= '' then
      query[#query + 1] = { 'prefix', T.prefix }
   end
   if T.delimiter and T.delimiter ~= '' then
      query[#query + 1] = { 'delimiter', T.delimiter }
   end
   if T.maxKeys then
      query[#query + 1] = { 'max-keys', tostring(T.maxKeys) }
   end
   if T.continuationToken and T.continuationToken ~= '' then
      query[#query + 1] = { 'continuation-token', T.continuationToken }
   end

   local resp, err = self:_send('GET', '/', query, '', nil)
   if not resp then return nil, err end
   if resp.simulated then
      return { objects = {}, prefixes = {}, truncated = false, simulated = true }, nil
   end
   return xml.parseListObjects(resp.body), nil
end

return M
