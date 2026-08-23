-- S1: `addressable function(...)`.
--
-- The guarantee that a callable can be named by module and member, which is what an
-- isolated Lua state has to be given instead of the value. Asserted here: where the
-- fact is minted, that it rides on a binding afterwards, that it is one-directional,
-- and that a choice between a named and an unnamed reading stays callable.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- The fragment returns its table, which is what makes it a module: `m` is then the
-- name this file's exports are reachable under, rather than an ordinary local holding
-- an ordinary table.
local function diagnose(body)
   local env = envMod.new(HERE)
   local result = parser.parse(body .. "\nreturn m\n", "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local errors = {}
   for _, diag in ipairs(check.check(result, "test.g.nupp", env)) do
      if diag.severity ~= "warning" then errors[#errors + 1] = diag end
   end
   return errors
end

-- A module table and one member on it, which is the shape every module has once its
-- exports are written, whichever spelling put them there.
local MODULE = "local m = {}\n"
   .. "function m.hash(value: string): string\n    return value\nend\n"
local PRIVATE = "local function priv(value: string): string\n    return value\nend\n"
local WANT = "local slot: addressable function(string): string = "

local M = {}

function M.acceptsAMemberOfAModule()
   assertEq(#diagnose(MODULE .. WANT .. "m.hash"), 0, "a module member is nameable")
end

function M.refusesAPrivateFunction()
   local errors = diagnose(MODULE .. PRIVATE .. WANT .. "priv")
   assertEq(#errors, 1, "one refusal")
   assertTrue(errors[1].msg:find("module address", 1, true) ~= nil,
      "it says why: " .. errors[1].msg)
end

function M.refusesALambda()
   local errors = diagnose(MODULE .. WANT .. "|value: string| -> value")
   assertEq(#errors, 1, "a lambda has no address")
end

function M.ridesOnABinding()
   -- The fact is minted at the read and carried by the type, so a value that reached
   -- the slot through a local is as nameable as one written there directly.
   local src = MODULE .. "const held = m.hash\n" .. WANT .. "held"
   assertEq(#diagnose(src), 0, "a binding keeps the guarantee")
end

function M.satisfiesAPlainSlot()
   -- One-directional: a guarantee is spare where none was asked for.
   local src = MODULE .. "local plain: function(string): string = m.hash\n"
   assertEq(#diagnose(src), 0, "an addressable function is still a function")
end

function M.staysCallableAcrossABranch()
   -- `a or b` over the two readings of one function must join to something callable.
   -- Keying the merge on the addressable variant would leave an uncallable union.
   local src = MODULE .. PRIVATE
      .. "local chosen = m.hash or priv\nlocal out = chosen(\"a\")\n"
   assertEq(#diagnose(src), 0, "the join is callable")
end

function M.dropsTheGuaranteeAcrossABranch()
   -- ...and the choice promises only what both readings did.
   local src = MODULE .. PRIVATE
      .. "local chosen = m.hash or priv\n" .. WANT .. "chosen"
   assertEq(#diagnose(src), 1, "an unnamed alternative loses the guarantee")
end

function M.composesWithNosuspend()
   local both = "local a: addressable nosuspend function(string): string = m.hash\n"
      .. "local b: nosuspend addressable function(string): string = m.hash\n"
   local errors = diagnose(MODULE .. both)
   -- `m.hash` is not proved quiet here, so both slots refuse it for that reason and
   -- neither refuses it for its address: the modifiers parsed in either order.
   assertEq(#errors, 2, "two suspension refusals")
   for _, diag in ipairs(errors) do
      assertTrue(diag.msg:find("may suspend", 1, true) ~= nil,
         "refused for suspension, not address: " .. diag.msg)
   end
end

return M
