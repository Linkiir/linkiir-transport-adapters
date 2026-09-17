-- S3 Adapter (Source) — polls an S3 prefix and pushes objects downstream.
--
-- main() runs every Interval milliseconds. Each poll:
--   1. lists the prefix
--   2. keeps objects at least Minimum Object Age old
--   3. downloads each one, pushes it downstream, then deletes it
--
-- Ordering is deliberate: the delete happens strictly after a successful
-- linkiir.flow.push. push is the one runtime call that raises on failure, so if
-- the queue is unavailable the script aborts with the object still in S3 and
-- the next poll retries it. Deleting first would lose the message. The trade is
-- at-least-once delivery: a crash between push and delete replays that object.

package.path = linkiir.sys.nodeDir() .. '/aws_s3/?.lua;' .. package.path
local S3config = require 'aws_s3_config'

function main()
   local client, cfg = S3config.fromNodeConfig()

   local prefix  = cfg['Prefix'] or ''
   local minAge  = tonumber(cfg['Minimum Object Age']) or 0
   local maxObjs = tonumber(cfg['Max Objects Per Poll']) or 10
   local doDelete = cfg['Delete After Download']
   if doDelete == nil then doDelete = true end

   local listing, err = client:list{ prefix = prefix, maxKeys = maxObjs }
   if not listing then
      -- Logged, not raised: a transient S3 problem must not stop the node.
      -- The next interval retries, and nothing has been deleted.
      linkiir.log.error(string.format(
         'S3 source: list failed [%s] %s', tostring(err.code), tostring(err.message)))
      return
   end

   if listing.simulated then
      linkiir.log.info('S3 source: Live Mode is off, no request was sent.')
      return
   end

   -- Age gate. Skip zero-byte keys and keys ending in '/', which are the
   -- folder markers the S3 console creates and carry no payload.
   --
   -- The age is clamped at zero. S3 rounds LastModified to the second and the
   -- local clock can sit slightly behind AWS, so an object written moments ago
   -- can report a timestamp up to a second in the future. Left unclamped that
   -- yields a negative age, and a Minimum Object Age of 0 would then skip the
   -- very object the poll just listed.
   local now = os.time()
   local eligible = {}
   for _, obj in ipairs(listing.objects) do
      local isFolder = obj.key:sub(-1) == '/'
      local age = obj.epoch and math.max(0, now - obj.epoch) or nil
      if not isFolder and obj.size > 0 and age and age >= minAge then
         eligible[#eligible + 1] = obj
      end
   end

   -- Oldest first, so a backlog drains in arrival order.
   table.sort(eligible, function(a, b)
      return (a.epoch or 0) < (b.epoch or 0)
   end)

   local pushed, deleted = 0, 0
   for _, obj in ipairs(eligible) do
      local body, getErr = client:get{ key = obj.key }
      if not body then
         -- One bad object must not block the rest of the batch.
         linkiir.log.error(string.format(
            'S3 source: download failed for %s [%s] %s',
            obj.key, tostring(getErr.code), tostring(getErr.message)))
      else
         -- Raises on failure, which is what we want: the object is still in S3.
         linkiir.flow.push{ data = body }
         pushed = pushed + 1

         if doDelete then
            local ok, delErr = client:delete{ key = obj.key }
            if ok then
               deleted = deleted + 1
            else
               -- The message is already downstream, so this is not fatal. The
               -- object will be seen again next poll and re-pushed, which is
               -- the at-least-once behaviour noted above.
               linkiir.log.error(string.format(
                  'S3 source: delete failed for %s [%s] %s',
                  obj.key, tostring(delErr.code), tostring(delErr.message)))
            end
         end
      end
   end

   linkiir.log.info(string.format(
      'S3 source: listed %d, eligible %d, pushed %d, deleted %d (prefix %s, min age %ds)',
      #listing.objects, #eligible, pushed, deleted, prefix, minAge))
end
