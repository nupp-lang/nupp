local set = require("nupp.owners.set")

local M = {}

function M.closesRegistrationsInReverseAndAttemptsEveryOne()
   local seen = {}
   local group = set.new("test")
   group:adopt("first", function(value)
      seen[#seen + 1] = value
      error("first failed")
   end)
   group:adopt("second", function(value)
      seen[#seen + 1] = value
      error("second failed")
   end)
   group:adopt("third", function(value)
      seen[#seen + 1] = value
   end)
   local ok, reason = pcall(group.close, group)
   assert(ok == false, "cleanup failures must be reported")
   assert(table.concat(seen, ",") == "third,second,first",
      "all registrations close in reverse: " .. table.concat(seen, ","))
   assert(tostring(reason):find("suppressed 1 cleanup failure", 1, true),
      "secondary failures are retained: " .. tostring(reason))
end

function M.removeTransfersOneRegistrationOut()
   local closed = 0
   local value = {}
   local group = set.new("test")
   group:adopt(value, function() closed = closed + 1 end)
   assert(group:remove(value) == value)
   group:close()
   assert(closed == 0, "removed registration was not cleaned")
   local ok = pcall(group.remove, group, value)
   assert(ok == false, "one registration cannot be removed twice")
end

function M.closeIsIdempotent()
   local group = set.new("test")
   group:close()
   group:close()
end

return M
