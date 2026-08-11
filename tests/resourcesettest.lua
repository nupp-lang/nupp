local sets = require("nupp.resource_set")

local M = {}

function M.closesRegistrationsInReverseAndAttemptsEveryOne()
   local seen = {}
   local resources = sets.new("test")
   resources:adopt("first", function(value)
      seen[#seen + 1] = value
      error("first failed")
   end)
   resources:adopt("second", function(value)
      seen[#seen + 1] = value
      error("second failed")
   end)
   resources:adopt("third", function(value)
      seen[#seen + 1] = value
   end)
   local ok, reason = pcall(resources.close, resources)
   assert(ok == false, "cleanup failures must be reported")
   assert(table.concat(seen, ",") == "third,second,first",
      "all registrations close in reverse: " .. table.concat(seen, ","))
   assert(tostring(reason):find("suppressed 1 cleanup failure", 1, true),
      "secondary failures are retained: " .. tostring(reason))
end

function M.removeTransfersOneRegistrationOut()
   local closed = 0
   local value = {}
   local resources = sets.new("test")
   resources:adopt(value, function() closed = closed + 1 end)
   assert(resources:remove(value) == value)
   resources:close()
   assert(closed == 0, "removed registration was not cleaned")
   local ok = pcall(resources.remove, resources, value)
   assert(ok == false, "one registration cannot be removed twice")
end

function M.closeIsIdempotent()
   local resources = sets.new("test")
   resources:close()
   resources:close()
end

return M
