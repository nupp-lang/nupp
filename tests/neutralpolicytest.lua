local policy = require("nupp.compiler.neutralpolicy")

local M = {}

function M.everyAuditedBoundaryHasAnExplicitNeutralPolicy()
   for _, name in ipairs(policy.required) do
      local decision = policy[name]
      assert(type(decision) == "string" and decision ~= "", name .. " has no neutral policy")
      assert(decision:find("reduce", 1, true)
         or decision:find("preserve", 1, true)
         or decision:find("reject", 1, true), name .. " has no boundary decision")
   end
end

return M
