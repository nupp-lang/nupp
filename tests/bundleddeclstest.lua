-- The declarations shipped with the compiler have to survive the consumer's
-- opinions about its own source.
--
-- `loadBundled` discards a declaration that produces any diagnostic, and
-- strictness was inherited from the project's manifest -- so `strict = true`, which
-- is the setting a careful project turns on, made every consumer re-judge nupp's
-- own declarations under a rule they were not written to. `string.buffer` fails
-- it: `put` takes `...: any`, which strict reports on an exported function. The
-- module then resolved to `unknown`, every use of it was silently untyped, and
-- nothing was reported about any of it.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local T = require("nupp.compiler.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- An environment standing in for a project that turned strict on.
local function strictEnv()
   return envMod.new(ROOT, {config = {strict = true, include = {"src"}}})
end

-- Every module the compiler ships a declaration for.
local BUNDLED = {
   "ffi", "string.buffer", "cjson", "cjson.safe",
   "jit.util", "jit.profile", "jit.zone", "jit.vmdef",
   "nupp.resources", "nupp.resources.native", "nupp.span",
   "nupp.zone", "nupp.profile",
}

local M = {}

function M.everyBundledDeclarationResolvesUnderStrict()
   local env = strictEnv()
   local lost = {}
   for _, name in ipairs(BUNDLED) do
      local t = env.resolveModule(env, name)
      if not t or t == T.any or t.tag == "unknown" then
         lost[#lost + 1] = name
      end
   end
   assertEq(#lost, 0,
      "a project's strictness must not discard the compiler's own declarations; "
      .. "lost: " .. table.concat(lost, ", "))
end

function M.stringBufferKeepsItsMembersUnderStrict()
   -- The one that actually failed, checked through a program rather than through
   -- the module type, because the symptom was at the use site.
   local env = strictEnv()
   local result = parser.parse([[
const sb = require("string.buffer")
const b = sb.new()
b:put("x")
return b:tostring()
]], "test")
   assertEq(#result.errors, 0, "syntax errors")
   for _, d in ipairs(check.check(result, "test", env, {strict = true}) or {}) do
      if d.severity == "error" then
         error(("%s: %s"):format(d.code, d.msg), 2)
      end
   end
end

function M.aStrictProjectStillJudgesItsOwnSource()
   -- The fix must not turn strictness off for the project itself.
   local env = strictEnv()
   local result = parser.parse([[
local m = {}

function m.leaky(x: any): any
    return x
end

return m
]], "test")
   assertEq(#result.errors, 0, "syntax errors")
   local found = false
   for _, d in ipairs(check.check(result, "test", env, {strict = true}) or {}) do
      if d.severity == "error" then found = true end
   end
   assertEq(found, true, "an exported signature mentioning any is still reported")
end

return M
