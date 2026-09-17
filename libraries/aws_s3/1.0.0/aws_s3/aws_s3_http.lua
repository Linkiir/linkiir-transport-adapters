-- aws_s3_http.lua — the transport layer between the client and
-- linkiir.link.web: retry, backoff, and turning HTTP outcomes into the
-- library's uniform result-or-error contract.
--
-- Never raises. Returns resp, nil on success (2xx) or nil, err on failure,
-- where err = { kind, code, message, retryable }.

local xml = require 'aws_s3_xml'

local M = {}

-- HTTP codes worth retrying. Everything else in the 4xx/5xx range is a
-- permanent condition a retry will not fix.
local RETRYABLE_CODES = { [429] = true, [500] = true, [502] = true,
                          [503] = true, [504] = true }

local function isSuccess(code)
   return code >= 200 and code < 300
end

-- One attempt. Returns resp, nil | nil, err. verb is 'get'/'put'/etc.
local function attempt(client, verb, url, headers, body)
   local resp, err = linkiir.link.web[verb]{
      url       = url,
      headers   = headers,
      body      = body,
      timeout   = client.timeout,
      verifyTls = client.verifyTls,
      live      = client.live,
   }

   -- Transport failure: link.web returned nil, err.
   if not resp then
      return nil, {
         kind = 'transport', code = (err and err.code) or 'transport',
         message = (err and err.message) or 'HTTP transport error',
         retryable = true,
      }
   end

   -- Live Mode off: the runtime simulated the call. Treat as success so the
   -- rest of the pipeline runs, and let the caller notice resp.simulated.
   if resp.simulated then
      return resp, nil
   end

   if isSuccess(resp.code) then
      return resp, nil
   end

   -- Non-2xx: lift the S3 <Error> document into a named code when present.
   local awsErr = xml.parseError(resp.body)
   return nil, {
      kind = awsErr and 'aws' or 'http',
      code = (awsErr and awsErr.code) or resp.code,
      message = (awsErr and awsErr.message)
                or ('HTTP ' .. tostring(resp.code)),
      retryable = RETRYABLE_CODES[resp.code] == true,
   }
end

-- request{ verb, url, headers, body } with retry/backoff.
-- Backoff is pause * 2^(n-1) seconds, capped at 30s, on retryable failures.
function M.request(client, T)
   local maxAttempts = 1 + (client.retry or 0)
   local pause = client.pause or 2
   local resp, err

   for n = 1, maxAttempts do
      resp, err = attempt(client, T.verb, T.url, T.headers, T.body)
      if resp then return resp, nil end
      if not err.retryable or n == maxAttempts then
         return nil, err
      end
      local delay = pause * (2 ^ (n - 1))
      if delay > 30 then delay = 30 end
      linkiir.log.info(string.format(
         'aws_s3: %s %s failed (%s), retry %d/%d in %ds',
         T.verb, T.url, tostring(err.code), n, maxAttempts - 1, delay))
      linkiir.sys.sleep(math.floor(delay * 1000))
   end

   return nil, err
end

return M
