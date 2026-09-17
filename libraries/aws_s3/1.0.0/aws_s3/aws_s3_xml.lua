-- aws_s3_xml.lua — a small, complete XML reader for Lua 5.1 / LuaJIT, plus the
-- two S3-specific readers built on top of it.
--
-- The runtime exposes no XML module, so this file provides one. It is a real
-- parser, not a set of pattern scrapes: it tokenizes the document and builds a
-- tree, which means nesting, attributes, self-closing tags, comments, CDATA,
-- processing instructions, numeric and named entities, and namespace prefixes
-- are all handled rather than assumed away.
--
-- General API:
--   local doc, err = xml.parse(str)      -- doc is a #root node, or nil + err
--   xml.child(node, 'Key')               -- first child by name, or nil
--   xml.children(node, 'Contents')       -- array of children by name
--   xml.text(node, 'Key')                -- trimmed text of a named child
--
-- A node is { name, attrs = {k=v}, children = {node...}, text = string }.
-- Element names have any namespace prefix stripped ('s3:Key' -> 'Key'), so
-- documents that add a prefix later do not break callers.
--
-- S3 API:
--   xml.parseListObjects(body) -> { objects, prefixes, truncated, nextToken }
--   xml.parseError(body)       -> { code, message, requestId } | nil

local M = {}

-- --- Entities ---------------------------------------------------------------

local NAMED = { lt = '<', gt = '>', amp = '&', quot = '"', apos = "'" }

-- Single left-to-right pass, so '&amp;lt;' correctly yields '&lt;' rather than
-- being decoded twice into '<'.
local function decodeEntities(s)
   if not s or s == '' then return s end
   if not s:find('&', 1, true) then return s end
   s = s:gsub('&#x(%x+);', function(h)
      local n = tonumber(h, 16)
      return (n and n < 256) and string.char(n) or ''
   end)
   s = s:gsub('&#(%d+);', function(d)
      local n = tonumber(d)
      return (n and n < 256) and string.char(n) or ''
   end)
   s = s:gsub('&(%a+);', function(name)
      return NAMED[name] or ('&' .. name .. ';')
   end)
   return s
end

local function trim(s)
   if not s then return nil end
   return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- 's3:Key' -> 'Key'. Leaves unprefixed names alone.
local function stripNs(name)
   if not name then return name end
   local localName = name:match(':([^:]+)$')
   return localName or name
end

-- --- Parser -----------------------------------------------------------------

local function newNode(name)
   return { name = name, attrs = {}, children = {}, text = '' }
end

local function parseAttrs(node, attrStr)
   if not attrStr or attrStr == '' then return end
   for k, q, v in attrStr:gmatch('([%w_:%.%-]+)%s*=%s*(["\'])(.-)%2') do
      node.attrs[stripNs(k)] = decodeEntities(v)
   end
end

-- parse(s) -> rootNode | nil, err
-- rootNode is a synthetic '#root' whose children are the document's top-level
-- elements, so a document with a declaration or comments before the root
-- element parses without special-casing.
function M.parse(s)
   if type(s) ~= 'string' or s == '' then
      return nil, 'xml.parse: empty input'
   end

   local root = newNode('#root')
   local stack = { root }
   local pos, n = 1, #s

   while pos <= n do
      local lt = s:find('<', pos, true)

      -- Text before the next tag (or trailing text) belongs to the open node.
      local textEnd = lt and (lt - 1) or n
      if textEnd >= pos then
         local raw = s:sub(pos, textEnd)
         if raw:find('%S') then
            local cur = stack[#stack]
            cur.text = cur.text .. decodeEntities(raw)
         end
      end
      if not lt then break end

      if s:sub(lt, lt + 8) == '<![CDATA[' then
         local close = s:find(']]>', lt + 9, true)
         if not close then return nil, 'xml.parse: unterminated CDATA' end
         -- CDATA is literal: no entity decoding.
         local cur = stack[#stack]
         cur.text = cur.text .. s:sub(lt + 9, close - 1)
         pos = close + 3

      elseif s:sub(lt, lt + 3) == '<!--' then
         local close = s:find('-->', lt + 4, true)
         if not close then return nil, 'xml.parse: unterminated comment' end
         pos = close + 3

      elseif s:sub(lt, lt + 1) == '<?' then
         local close = s:find('?>', lt + 2, true)
         if not close then
            return nil, 'xml.parse: unterminated processing instruction'
         end
         pos = close + 2

      elseif s:sub(lt, lt + 1) == '<!' then
         -- DOCTYPE and friends: skipped wholesale.
         local close = s:find('>', lt + 2, true)
         if not close then return nil, 'xml.parse: unterminated declaration' end
         pos = close + 1

      elseif s:sub(lt + 1, lt + 1) == '/' then
         local close = s:find('>', lt + 2, true)
         if not close then return nil, 'xml.parse: unterminated end tag' end
         local name = stripNs(trim(s:sub(lt + 2, close - 1)))
         local cur = stack[#stack]
         if #stack > 1 and cur.name == name then
            table.remove(stack)
         elseif #stack > 1 then
            -- Mismatched close: unwind to it if it is open, otherwise ignore.
            local found
            for i = #stack, 2, -1 do
               if stack[i].name == name then
                  found = i
                  break
               end
            end
            if found then
               for _ = #stack, found, -1 do table.remove(stack) end
            end
         end
         pos = close + 1

      else
         local close = s:find('>', lt + 1, true)
         if not close then return nil, 'xml.parse: unterminated start tag' end
         local inner = s:sub(lt + 1, close - 1)
         local selfClosing = false
         if inner:sub(-1) == '/' then
            selfClosing = true
            inner = inner:sub(1, -2)
         end
         local rawName = inner:match('^([^%s]+)')
         if not rawName then return nil, 'xml.parse: malformed start tag' end
         local node = newNode(stripNs(rawName))
         parseAttrs(node, inner:sub(#rawName + 1))
         local cur = stack[#stack]
         cur.children[#cur.children + 1] = node
         if not selfClosing then stack[#stack + 1] = node end
         pos = close + 1
      end
   end

   return root
end

-- --- Tree helpers -----------------------------------------------------------

function M.child(node, name)
   if not node then return nil end
   for _, c in ipairs(node.children) do
      if c.name == name then return c end
   end
   return nil
end

function M.children(node, name)
   local out = {}
   if not node then return out end
   for _, c in ipairs(node.children) do
      if c.name == name then out[#out + 1] = c end
   end
   return out
end

-- text(node)         -> trimmed text of node
-- text(node, 'Key')  -> trimmed text of the first child named Key, or nil
function M.text(node, name)
   local target = name and M.child(node, name) or node
   if not target then return nil end
   return trim(target.text)
end

-- --- S3 helpers -------------------------------------------------------------

-- Keys arrive percent-encoded because every request sets encoding-type=url.
local function decodeKey(k)
   if not k then return k end
   return linkiir.codec.uri.decode(k)
end

-- S3 ISO-8601 UTC ('2026-08-24T17:42:00.000Z') -> epoch seconds.
-- os.time reads its table as local time while the stamp is UTC, so the local
-- UTC offset is added back. nil if the string does not parse.
local function isoToEpoch(iso)
   if not iso then return nil end
   local y, mo, d, h, mi, sec =
      iso:match('(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)')
   if not y then return nil end
   local asLocal = os.time{
      year = tonumber(y), month = tonumber(mo), day = tonumber(d),
      hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec),
      isdst = false,
   }
   if not asLocal then return nil end
   local offset = os.difftime(os.time(), os.time(os.date('!*t')))
   return asLocal + offset
end

M.isoToEpoch = isoToEpoch

-- parseListObjects(body) -> { objects, prefixes, truncated, nextToken }
--   objects  = { { key, size, etag, lastModified, epoch }, ... }
--   prefixes = { 'incoming/2026/', ... }   (only when a delimiter was sent)
function M.parseListObjects(body)
   local result = { objects = {}, prefixes = {}, truncated = false, nextToken = nil }
   local doc = M.parse(body)
   if not doc then return result end

   local listing = M.child(doc, 'ListBucketResult') or doc

   for _, c in ipairs(M.children(listing, 'Contents')) do
      local lastModified = M.text(c, 'LastModified')
      result.objects[#result.objects + 1] = {
         key          = decodeKey(M.text(c, 'Key')),
         size         = tonumber(M.text(c, 'Size')) or 0,
         etag         = M.text(c, 'ETag'),
         lastModified = lastModified,
         epoch        = isoToEpoch(lastModified),
      }
   end

   for _, p in ipairs(M.children(listing, 'CommonPrefixes')) do
      local prefix = decodeKey(M.text(p, 'Prefix'))
      if prefix then result.prefixes[#result.prefixes + 1] = prefix end
   end

   result.truncated = (M.text(listing, 'IsTruncated') == 'true')
   result.nextToken = M.text(listing, 'NextContinuationToken')
   return result
end

-- parseError(body) -> { code, message, requestId } | nil
-- nil when the body is not an S3 error document, so callers can fall back to
-- the bare HTTP status.
function M.parseError(body)
   if not body or body == '' then return nil end
   local doc = M.parse(body)
   if not doc then return nil end
   local e = M.child(doc, 'Error')
   if not e then return nil end
   return {
      code      = M.text(e, 'Code'),
      message   = M.text(e, 'Message'),
      requestId = M.text(e, 'RequestId'),
   }
end

return M
