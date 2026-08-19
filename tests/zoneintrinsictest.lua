-- The nupp.profile.zone push/pop intrinsic: a call in statement position on a receiver
-- statically known to be the module nupp.profile.zone returns is generated inline against
-- its private fields rather than called. pop additionally needs its popped name
-- discarded, since a captured value has nowhere to go but an ordinary call.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local zone = require("nupp.profile.zone")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

local function compile(source)
   local parsed = parser.parse(source, "zone_intrinsic_test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, "zone_intrinsic_test.g.nupp", env)
   local code, generated = gen.generate(parsed, "zone_intrinsic_test")
   for _, diagnostic in ipairs(generated) do diagnostics[#diagnostics + 1] = diagnostic end
   return code, diagnostics
end

local function run(source, ...)
   local code, diagnostics = compile(source)
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code,
            diagnostic.msg, code), 2)
      end
   end
   local chunk, why = loadstring(code, "@zone_intrinsic_test")
   assert(chunk, why and (why .. "\n---\n" .. code))
   return chunk(...)
end

local M = {}

function M.lowersPushAndADiscardedPopButNotACapturedPop()
   local code = compile([[
local zone = require("nupp.profile.zone")
zone.push("render")
local kept = zone.pop()
zone.pop()
]])
   assertTrue(code:find("__nuppActive", 1, true) ~= nil, "push lowers against the private fields\n" .. code)
   -- Every reference to `zone` that survives as a call is the one captured pop; the
   -- pushed and discarded-popped sites never call at all.
   local calls = 0
   for _ in code:gmatch("zone%s*%.%s*p[uo][sp][hp]?%s*%(") do calls = calls + 1 end
   assertEq(calls, 1, "exactly the captured pop keeps an ordinary call\n" .. code)
end

function M.lowersPushOnlyOnAReceiverStaticallyKnownToBeTheZoneModule()
   local code = compile([[
local other = {push = function(_: {any}, _: string): nil end}
other.push("x")
]])
   assertTrue(code:find("other%s*%.%s*push%s*%(") ~= nil, "an unrelated push keeps its call\n" .. code)
   assertTrue(code:find("__nuppActive", 1, true) == nil, "an unrelated push does not touch zone internals\n" .. code)
end

function M.lowersPushOnlyOnABareNameReceiver()
   local code = compile([[
local holder = {zone = require("nupp.profile.zone")}
holder.zone.push("x")
]])
   assertTrue(code:find("push%s*%(") ~= nil, "a non-name receiver keeps its call\n" .. code)
end

function M.matchesTheOrdinaryApiAtRunTime()
   local outer, inner, poppedCount, depthAfter, depthWhileInactive = run([[
local zone = require("nupp.profile.zone")
zone.acquire()
zone.push("outer")
zone.push("inner")
local path = zone.path()
local kept = zone.pop()
zone.pop()
local afterBoth = zone.depth()
zone.release()
zone.push("ignored")
local whileInactive = zone.depth()
return path, kept, afterBoth, whileInactive
]])
   assertEq(outer, "outer/inner", "path sees both pushes")
   assertEq(inner, "inner", "the captured pop returns the innermost name")
   assertEq(poppedCount, 0, "the lowered pop empties what the lowered push filled")
   assertEq(depthAfter, 0, "a lowered push while inactive is still a no-op")
end

function M.staysCorrectAlongsideAnUnrelatedLiveSession()
   -- The lowered site and the ordinary API write the same fields, so a session
   -- started outside the compiled unit still sees what it pushed.
   zone.acquire()
   local depth = run([[
local zone = require("nupp.profile.zone")
zone.push("compiled")
return zone.depth()
]])
   assertEq(depth, zone.depth(), "the lowered push landed on the live session's own stack")
   assertEq(zone.current(), "compiled", "the live session reads back what the lowered push wrote")
   zone.pop()
   zone.release()
end

return M
