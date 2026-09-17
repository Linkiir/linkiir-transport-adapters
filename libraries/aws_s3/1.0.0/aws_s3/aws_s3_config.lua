-- aws_s3_config.lua — bridge from a node's config to an S3 client, so all four
-- scripted adapter nodes share one construction path.
--
--   local client, cfg = require('aws_s3_config').fromNodeConfig()
--
-- cfg is the raw linkiir.config.node() map, returned too because each node
-- needs its own extra fields (Prefix, Minimum Object Age, Key Naming, ...).

local S3 = require 'aws_s3'

local M = {}

-- Normalize a config value that may be a bool, a string, or nil into a bool.
-- Storage of bools is native, but be forgiving of "true"/"false" strings.
local function toBool(v, default)
   if v == nil then return default end
   if type(v) == 'boolean' then return v end
   if type(v) == 'string' then return v:lower() == 'true' end
   return default
end

function M.fromNodeConfig()
   local cfg = linkiir.config.node()
   local client = S3.client{
      accessKey = cfg['Access Key'],
      secretKey = cfg['Secret Key'],
      region    = cfg['Region'],
      bucket    = cfg['Bucket Name'],
      endpoint  = cfg['Endpoint Override'],
      live      = toBool(cfg['Live Mode'], false),
      verifyTls = toBool(cfg['Verify TLS'], true),
   }
   return client, cfg
end

return M
