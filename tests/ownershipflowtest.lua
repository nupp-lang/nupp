-- Table-driven capability laundering matrix. Each row is a language transport, not a
-- diagnostic spelling: accepted rows must keep the obligation usable exactly once;
-- rejected rows must stop weakening at the first unsafe boundary.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local T = require("nupp.compiler.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local RESOURCE = table.concat({
   "cdef struct flow_resource value: int32 end",
   "cdef function flow_open_c(): flow_resource*",
   "local function flow_open(): Owned<flow_resource*, flow_close>",
   "   return flow_open_c()",
   "end",
   "cdef function flow_close(takes value: flow_resource*)",
}, "\n")

local function diagnostics(source)
   local result = parser.parse(RESOURCE .. "\n" .. source, "ownership-flow.g.nupp")
   assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
   return check.check(result, "ownership-flow.g.nupp", env)
end

local ROWS = {
   {"local move", true, [[
local value = flow_open()
local forwarded = value
drop(forwarded)
]]},
   {"local duplication", false, [[
local value = flow_open()
local forwarded = value
print(value)
drop(forwarded)
]]},
   {"optional narrowing", true, [[
local value = assert(flow_open() as flow_resource*?)
drop(value)
]]},
   {"scalar generic", true, [[
local function id<T>(value: T): T preserves value return value end
local value = id(flow_open())
drop(value)
]]},
   {"inferred scalar generic", true, [[
local function id<T>(value: T): T return value end
local value = id(flow_open())
drop(value)
]]},
   {"parenthesized projection", true, [[
local value = (flow_open())
drop(value)
]]},
   {"anonymous table storage", false, [[
local value = flow_open()
local stored = {value}
]]},
   {"map write", false, [[
local value = flow_open()
local stored: {string: flow_resource*} = {}
stored.value = value
]]},
   {"borrowed closure capture", true, [[
local value = flow_open()
local function scoped() print(value.value) end
scoped()
drop(value)
]]},
   {"borrowed closure escape", false, [[
local function leak()
   local value = flow_open()
   return function() print(value.value) end
end
]]},
   {"unknown call", false, [[
local value = flow_open()
local sink: any = print
sink(value)
]]},
   {"raw coroutine", false, [[
local value = flow_open()
coroutine.yield()
drop(value)
]]},
   {"unsafe does not erase", false, [[
local value = flow_open()
unsafe do local raw: any = value end
]]},
   {"nominal affine field", true, [[
local record Box item: Owned<flow_resource*> end
local box = new Box(item = flow_open())
drop(box)
]]},
   {"partial move and residual cleanup", true, [[
local record Box item: Owned<flow_resource*> end
local box = new Box(item = flow_open())
local item = box.item
drop(item)
drop(box)
]]},
}

local M = {}

function M.everyTransportEitherPreservesOrRejectsCapability()
   for _, row in ipairs(ROWS) do
      local found = diagnostics(row[3])
      if row[2] then
         assert(#found == 0, row[1] .. " unexpectedly rejected: "
            .. tostring(found[1] and found[1].code))
      else
         assert(#found > 0, row[1] .. " laundered an obligation")
      end
   end
end

-- Stable test-only fixture shape for the semantic ValueSlot carrier. This deliberately
-- is not a reflection API available to programs.
function M.capabilityFixtureKeepsPayloadAndOrderedDischargeSeparate()
   local first = T.functionCleanup("flow:first", "first")
   local second = T.functionCleanup("flow:second", "second")
   local owner = T.owned(T.string, {first, second})
   local narrowed = T.withOwnershipPayload(owner, T.literal("ready"))
   local fixture = {
      payload = T.unwrapOwnership(narrowed),
      obligation = narrowed.tag,
      cleanup = {narrowed.cleanups[1].id, narrowed.cleanups[2].id},
      roots = {},
      retention = "unretained",
   }
   -- Interned identity rather than the payload's id spelled out: the same literal is
   -- the same object, which is the stronger claim and does not depend on how an id
   -- happens to read.
   assert(fixture.payload == T.literal("ready"))
   assert(fixture.obligation == "owned")
   assert(fixture.cleanup[1] == first.id and fixture.cleanup[2] == second.id)
end

return M
