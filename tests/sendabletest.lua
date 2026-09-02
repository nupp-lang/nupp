-- S1: `sendable function(...)`.
--
-- The guarantee that another isolated Lua state can reproduce a callable. Asserted
-- here: module members, contextual literals, effectively-final captures, capture
-- copyability, and the ordinary function relation.
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

local function diagnoseDeclared(body)
   local env = envMod.new(HERE)
   local result = parser.parse("module test\n\n" .. body, "test.nupp")
   assertEq(#result.errors, 0, "syntax errors in declared module")
   local errors = {}
   for _, diag in ipairs(check.check(result, "test.nupp", env)) do
      if diag.severity ~= "warning" then errors[#errors + 1] = diag end
   end
   return errors
end

-- A module table and one member on it, which is the shape every module has once its
-- exports are written, whichever spelling put them there.
local MODULE = "local m = {}\n"
   .. "function m.hash(value: string): string\n    return value\nend\n"
local PRIVATE = "local function priv(value: string): string\n    return value\nend\n"
local WANT = "local slot: sendable function(string): string = "

local M = {}

function M.acceptsAMemberOfAModule()
   assertEq(#diagnose(MODULE .. WANT .. "m.hash"), 0, "a module member is sendable")
end

function M.refusesAPrivateFunction()
   local errors = diagnose(MODULE .. PRIVATE .. WANT .. "priv")
   assertEq(#errors, 1, "one refusal")
   assertTrue(errors[1].msg:find("another Lua state cannot reproduce it", 1, true) ~= nil,
      "it says why: " .. errors[1].msg)
end

function M.acceptsAContextualLiteral()
   local errors = diagnoseDeclared([[
export function apply(prefix: string, value: string): string
    const slot: sendable function(string): string = |item: string| -> prefix .. item
    return slot(value)
end
]])
   assertEq(#errors, 0, "a literal with an immutable capture is sendable")
end

function M.acceptsAnEffectivelyFinalCapture()
   local errors = diagnoseDeclared([[
export function apply(value: string): string
    local prefix: string
    prefix = "nupp:"
    const slot: sendable function(string): string = |item: string| -> prefix .. item
    return slot(value)
end
]])
   assertEq(#errors, 0, "one initialization assignment is effectively final")
end

function M.refusesAReassignedCapture()
   local errors = diagnoseDeclared([[
export function apply(prefix: string, value: string): string
    const slot: sendable function(string): string = |item: string| -> prefix .. item
    prefix = "changed:"
    return slot(value)
end
]])
   assertEq(#errors, 1, "a reassigned capture is refused once")
   assertTrue(errors[1].msg:find("capture \"prefix\" is reassigned", 1, true) ~= nil,
      "the capture is named: " .. errors[1].msg)
end

function M.refusesAnUncopyableCapture()
   local errors = diagnoseDeclared([[
export function hold(value: thread): sendable function(): thread
    return || -> value
end
]])
   assertEq(#errors, 1, "an uncopyable capture is refused once")
   assertTrue(errors[1].msg:find("capture \"value\" is a thread", 1, true) ~= nil,
      "the capture type is named: " .. errors[1].msg)
end

function M.ridesOnABinding()
   -- The fact is minted at the read and carried by the type, so a value that reached
   -- the slot through a local is as sendable as one written there directly.
   local src = MODULE .. "const held = m.hash\n" .. WANT .. "held"
   assertEq(#diagnose(src), 0, "a binding keeps the guarantee")
end

function M.satisfiesAPlainSlot()
   -- One-directional: a guarantee is spare where none was asked for.
   local src = MODULE .. "local plain: function(string): string = m.hash\n"
   assertEq(#diagnose(src), 0, "a sendable function is still a function")
end

function M.staysCallableAcrossABranch()
   -- `a or b` over the two readings of one function must join to something callable.
   -- Keying the merge on the sendable variant would leave an uncallable union.
   local src = MODULE .. PRIVATE
      .. "local selected: boolean = nil as any\n"
      .. "local chosen = selected and m.hash or priv\nlocal out = chosen(\"a\")\n"
   assertEq(#diagnose(src), 0, "the join is callable")
end

function M.dropsTheGuaranteeAcrossABranch()
   -- ...and the choice promises only what both readings did.
   local src = MODULE .. PRIVATE
      .. "local selected: boolean = nil as any\n"
      .. "local chosen = selected and m.hash or priv\n" .. WANT .. "chosen"
   assertEq(#diagnose(src), 1, "an unnamed alternative loses the guarantee")
end

function M.composesWithNosuspend()
   local both = "local a: sendable nosuspend function(string): string = m.hash\n"
      .. "local b: nosuspend sendable function(string): string = m.hash\n"
   local errors = diagnose(MODULE .. both)
   -- `m.hash` is not proved quiet here, so both slots refuse it for that reason and
   -- neither refuses it for its address: the modifiers parsed in either order.
   assertEq(#errors, 2, "two suspension refusals")
   for _, diag in ipairs(errors) do
      assertTrue(diag.msg:find("may suspend", 1, true) ~= nil,
         "refused for suspension only: " .. diag.msg)
   end
end

-- Instantiating a generic member closes its binders and nothing else: the guarantee
-- a module member carries survives into the specialized signature.
function M.survivesGenericInstantiation()
   local generic = "local m = {}\n"
      .. "function m.first<T>(xs: {T}): T?\n    return xs[1]\nend\n"
   assertEq(#diagnose(generic
      .. "local slot: sendable function(xs: {integer}): integer? = m.first"), 0,
      "a generic module member is sendable once instantiated")
end

-- An interface that promises a member is reproducible holds every implementor to it.
-- Conformance drops the receiver to compare the rest of a member's signature, and the
-- guarantee has to survive that.
function M.anInterfaceMemberHoldsImplementorsToIt()
   local contract = "local m = {}\n"
      .. "interface m.Job\n    run: sendable function(self: m.Job): nil\nend\n"
   local good = contract
      .. "record m.Good\n    run: sendable function(self: m.Good): nil\nend\n"
      .. "local job: m.Job = new m.Good(run = nil as any)\nprint(job)"
   assertEq(#diagnose(good), 0, "a sendable member conforms")
   local bad = contract
      .. "record m.Bad\n    run: function(self: m.Bad): nil\nend\n"
      .. "local job: m.Job = new m.Bad(run = nil as any)\nprint(job)"
   local errors = diagnose(bad)
   assertEq(#errors, 1, "one refusal")
   assertTrue(errors[1].msg:find('read member "run" does not match', 1, true) ~= nil,
      "refused on the member: " .. errors[1].msg)
end

return M
