-- S3 Adapter (Destination) — uploads each message to S3 as its own object.
--
-- main(Data) is called once for every message delivered to this node.
--
-- On failure this logs and returns rather than raising. With stop_on_error
-- false that skips the message instead of halting the node, which is the right
-- default for a demo: one unwritable object should not take the flow down.
-- Raise here instead if a delivery failure must stop everything.

package.path = linkiir.sys.nodeDir() .. '/aws_s3/?.lua;' .. package.path
local S3config = require 'aws_s3_config'

-- A short random hex token for object keys. linkiir.sys.guid requires at least
-- 128 bits, so ask for 128 and keep the first 12 hex chars -- enough to avoid
-- collisions within a demo and short enough to read.
local function shortId()
   return (linkiir.sys.guid(128):gsub('%-', '')):sub(1, 12)
end

-- Build the unique part of the object key.
--   Timestamp        -> 20260824T174200Z
--   GUID             -> a short random hex string
--   Timestamp + GUID -> both, so keys sort chronologically and never collide
local function keyBody(naming)
   local stamp = os.date('!%Y%m%dT%H%M%SZ')
   if naming == 'GUID' then
      return shortId()
   elseif naming == 'Timestamp' then
      return stamp
   end
   return stamp .. '-' .. shortId()
end

function main(Data)
   local client, cfg = S3config.fromNodeConfig()

   local prefix = cfg['Key Prefix'] or ''
   local ext    = cfg['Key Extension']
   local key    = prefix .. keyBody(cfg['Key Naming'])
   if ext and ext ~= '' then
      key = key .. '.' .. ext
   end

   local ok, err = client:put{
      key         = key,
      body        = Data,
      contentType = cfg['Content Type'] or 'application/octet-stream',
   }

   if not ok then
      linkiir.log.error(string.format(
         'S3 destination: upload failed for %s [%s] %s',
         key, tostring(err.code), tostring(err.message)))
      return
   end

   if cfg['Live Mode'] == false then
      linkiir.log.info(string.format(
         'S3 destination: Live Mode is off. Would have uploaded %d bytes to s3://%s/%s',
         #Data, tostring(cfg['Bucket Name']), key))
      return
   end

   linkiir.log.info(string.format(
      'S3 destination: uploaded %d bytes to s3://%s/%s',
      #Data, tostring(cfg['Bucket Name']), key))
end
