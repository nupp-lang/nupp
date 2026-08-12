-- Associated projections composed with type-level computation.
--
-- One evaluator runs both, because they nest: an indexed member over a projection
-- needs the projection reduced first, an answer may itself be a computed type, a
-- cycle may run through a neutral operation, and a projection erased to `any` may
-- then be consumed by one.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagnose(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   return check.check(parsed, "test.g.nupp", env)
end

local function codes(source)
   local out = {}
   for j, d in ipairs(diagnose(source)) do
      out[j] = d.code
   end
   return table.concat(out, " ")
end

local function src(...)
   return table.concat({...}, "\n") .. "\n"
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function reports(source, want)
   assertEq(codes(source), want, "for:\n" .. source)
end

local ROW = src(
   "local interface Holds",
   "   associated type Item",
   "end",
   "local record Row is Holds",
   "   associated type Item = {name: string, count: integer}",
   "end")

local M = {}

function M.indexedMemberAndKeyofOverAConcreteProjection()
   clean(ROW .. src(
      "local held: string = nil as Row.Item.[\"name\"]",
      "local key: keyof Row.Item = \"name\"",
      "return held, key"))
   reports(ROW .. src(
      "local wrong: integer = nil as Row.Item.[\"name\"]",
      "return wrong"), "NUPP2001")
end

-- A surviving projection blocks the operation rather than failing it: it is an
-- operand nothing can read yet, not an invalid structural type.
function M.indexedMemberOverAnOpaqueProjectionStaysBlocked()
   clean(src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local function opaque<T is Holds>(x: T.Item.[\"name\"]): nil",
      "end",
      "return opaque"))
end

function M.anAnswerMayBeAComputedType()
   clean(ROW .. src(
      "local record Derived is Holds",
      "   associated type Item = Row.Item.[\"name\"]",
      "end",
      "local held: string = nil as Derived.Item",
      "return held"))
end

-- The cycle owns its diagnostic. The operation over it manufactures nothing.
function M.aCycleThroughANeutralOperationReportsOnlyTheCycle()
   reports(src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local record Loop is Holds",
      "   associated type Item = Loop.Item.[\"name\"]",
      "end",
      "return Loop"), "NUPP2135")
end

-- The erasure survives being consumed: `keyof` of a projection that lost its head
-- is still an erasure, and the call is still checked as `any`.
function M.aGradualProjectionConsumedByANeutralOperationStillWarns()
   reports(src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local function held<T is Holds>(x: T): keyof T.Item",
      "   return nil as any",
      "end",
      "local erased = held(nil as any)",
      "return erased"), "NUPP2511")
end

-- Eager evaluation names the concrete type in the message itself, so nothing has to
-- explain a projection that is no longer there.
function M.aMismatchNamesTheConcreteType()
   local diags = diagnose(src(
      "local interface Component",
      "   componentId: integer",
      "   associated type Value = self",
      "end",
      "local interface ScalarComponent<E> is Component",
      "   componentId: integer",
      "   associated type Value == E",
      "end",
      "local record Archetype",
      "   function column<C is Component>(self, component: C): {C.Value}",
      "      return nil as any",
      "   end",
      "end",
      "local archetype = new Archetype()",
      "local health: ScalarComponent<number> = nil as any",
      "local wrong: {string} = archetype:column(health)",
      "return wrong"))
   assertEq(#diags, 1, "expected one mismatch")
   assertEq(diags[1].code, "NUPP2001")
   assert(diags[1].msg:find("{number} is not a {string}", 1, true),
      "the message did not name the concrete type: " .. diags[1].msg)
   assertEq(diags[1].help, nil, "nothing is left to explain")
end

-- Computed callable packs and associated members in one signature.
function M.computedPacksComposeWithAssociatedMembers()
   local signature = src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local record Row is Holds",
      "   associated type Item = string",
      "end",
      "@comptime",
      "local function Arguments(Kind: type): typepack",
      "   local info = nupp.types.describe(Kind)",
      "   if info.kind == 'literal' and info.value == 'pair' then",
      "      return nupp.types.pack({nupp.types.string, nupp.types.number})",
      "   end",
      "   return nupp.types.pack({}, nupp.types.any)",
      "end",
      "local function apply<Kind is string, T is Holds>(",
      "   kind: Kind,",
      "   held: T,",
      "   ...: unpackof Arguments(Kind)",
      "): T.Item",
      "   return nil as any",
      "end",
      "local row = new Row()")
   clean(signature .. src(
      "local out: string = apply('pair', row, 'x', 1)",
      "return out"))
   reports(signature .. src(
      "local wrong: integer = apply('pair', row, 'x', 1)",
      "return wrong"), "NUPP2001")
end

return M
