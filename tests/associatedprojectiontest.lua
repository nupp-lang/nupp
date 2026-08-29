-- Projection member lookup, and the regressions the feature exists for.
--
-- A projection that answers concretely is that type. One that stays opaque reads its
-- effective bound's members, and reads them as itself: a `self`-returning member of
-- the bound answers the projection, not the contract.
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

local function codes(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(parsed, "test.g.nupp", env)) do
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

local CONTRACTS = src(
   "local interface Named",
   "   name: string",
   "end",
   "local interface Counted",
   "   name: string",
   "   count: integer",
   "end",
   "local interface Cloneable",
   "   clone: function(self): self",
   "end")

local M = {}

function M.aProjectionThatClosesAMultiMemberCycleReportsOnce()
   reports(src(
      "local interface Pair",
      "   associated type First",
      "   associated type Second",
      "end",
      "local record Loop is Pair",
      "   associated type First = Loop.Second",
      "   associated type Second = Loop.First",
      "end",
      "return Loop"), "NUPP2135")
end

function M.aBoundFieldIsReadableAndWritable()
   clean(CONTRACTS .. src(
      "local interface Reader",
      "   associated type Item is Named",
      "end",
      "local function label<T is Reader>(item: T.Item): string",
      "   return item.name",
      "end",
      "local function rename<T is Reader>(item: T.Item): nil",
      "   item.name = 'x'",
      "end",
      "return label, rename"))
   reports(CONTRACTS .. src(
      "local interface Reader",
      "   associated type Item is Named",
      "end",
      "local function wrong<T is Reader>(item: T.Item): integer",
      "   return item.name",
      "end",
      "return wrong"), "NUPP2002")
end

-- The receiver override: `clone` answers the projection, not the contract.
function M.aSelfReturningBoundMemberAnswersTheProjection()
   clean(CONTRACTS .. src(
      "local interface Copies",
      "   associated type Item is Cloneable",
      "end",
      "local function twice<T is Copies>(item: T.Item): T.Item",
      "   return item:clone():clone()",
      "end",
      "return twice"))
   -- A projection fits its bound, so answering `Cloneable` with one is fine. What
   -- must fail is the reverse: an upper bound cannot manufacture the answer.
   clean(CONTRACTS .. src(
      "local interface Copies",
      "   associated type Item is Cloneable",
      "end",
      "local function widens<T is Copies>(item: T.Item): Cloneable",
      "   return item:clone()",
      "end",
      "return widens"))
   reports(CONTRACTS .. src(
      "local interface Copies",
      "   associated type Item is Cloneable",
      "end",
      "local function narrows<T is Copies>(c: Cloneable): T.Item",
      "   return c",
      "end",
      "return narrows"), "NUPP2002")
end

function M.anIntersectionBoundExposesBothMemberSets()
   clean(CONTRACTS .. src(
      "local interface Both",
      "   associated type Item is Named & Counted",
      "end",
      "local function describe<T is Both>(item: T.Item): string",
      "   return item.name .. tostring(item.count)",
      "end",
      "return describe"))
end

function M.aUnionBoundExposesOnlyCommonMembers()
   local either = src(
      "local interface Either",
      "   associated type Item is Named | Counted",
      "end")
   clean(CONTRACTS .. either .. src(
      "local function common<T is Either>(item: T.Item): string",
      "   return item.name",
      "end",
      "return common"))
   reports(CONTRACTS .. either .. src(
      "local function uncommon<T is Either>(item: T.Item): integer",
      "   return item.count",
      "end",
      "return uncommon"), "NUPP2004")
end

function M.anUnboundedAssociatedTypeHasNoMembers()
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "end",
      "local function nothing<T is Reader>(item: T.Item): string",
      "   return item.name",
      "end",
      "return nothing"), "NUPP2004")
end

-- A concrete answer bypasses the bound and uses what it actually carries.
function M.aConcreteAnswerUsesItsOwnMembers()
   clean(CONTRACTS .. src(
      "local record Tag is Named",
      "   name: string",
      "   extra: integer",
      "end",
      "local interface Reader",
      "   associated type Item is Named",
      "end",
      "local record Lines is Reader",
      "   associated type Item = Tag",
      "end",
      "local function extra(item: Lines.Item): integer",
      "   return item.extra",
      "end",
      "return extra"))
end

function M.aChainedProjectionReachesItsMembers()
   clean(CONTRACTS .. src(
      "local interface Inner",
      "   associated type Leaf is Named",
      "end",
      "local interface Outer",
      "   associated type Step is Inner",
      "end",
      "local function reach<T is Outer>(leaf: T.Step.Leaf): string",
      "   return leaf.name",
      "end",
      "return reach"))
end

-- The motivating case, both directions. `= self` explicitly.
function M.selfAnsweredExplicitlyResolvesToTheImplementor()
   local contract = src(
      "local interface Holds",
      "   associated type Value",
      "end")
   clean(contract .. src(
      "local record Node is Holds",
      "   associated type Value = self",
      "   tag: string",
      "end",
      "local function tagOf(n: Node): Node.Value",
      "   return n",
      "end",
      "return tagOf"))
   reports(contract .. src(
      "local record Node is Holds",
      "   associated type Value = self",
      "   tag: string",
      "end",
      "local function wrong(n: Node): Node.Value",
      "   return 'not a node'",
      "end",
      "return wrong"), "NUPP2002")
end

-- The same through an inherited default, which is the copy-down.
function M.selfInheritedAsADefaultResolvesToTheImplementor()
   local contract = src(
      "local interface Holds",
      "   associated type Value = self",
      "end")
   clean(contract .. src(
      "local record Node is Holds",
      "   tag: string",
      "end",
      "local function itself(n: Node): Node.Value",
      "   return n",
      "end",
      "return itself"))
   reports(contract .. src(
      "local record Node is Holds",
      "   tag: string",
      "end",
      "local function wrong(n: Node): Node.Value",
      "   return 'not a node'",
      "end",
      "return wrong"), "NUPP2002")
end

-- An interface's default stays opaque through the interface itself, so an
-- implementor that answers otherwise is not shadowed by it.
function M.anInterfaceDefaultStaysOpaqueThroughTheInterface()
   reports(src(
      "local interface Holds",
      "   associated type Value = string",
      "end",
      "local function assumed(v: Holds.Value): string",
      "   return v",
      "end",
      "return assumed"), "NUPP2002")
end

-- The Tecs shape, in both directions. The components answering are records, because
-- an interface's `=` is a default its implementors may override, so a value known
-- only as the interface cannot be said to answer it.
function M.theMotivatingShapeResolvesThroughConcreteComponents()
   local world = src(
      "local interface Component",
      "   componentId: integer",
      "   associated type Value = self",
      "end",
      "local record Health is Component",
      "   componentId: integer",
      "   associated type Value = number",
      "end",
      "local record Position is Component",
      "   componentId: integer",
      "   x: number",
      "end",
      "local record Archetype",
      "   function get<C is Component>(self, component: C): {C.Value}",
      "      return nil as any",
      "   end",
      "end",
      "local arch = new Archetype()",
      "local health = new Health(componentId = 2)",
      "local position = new Position(componentId = 1, x = 0)")
   clean(world .. src(
      "local held: {Position} = arch:get(position)",
      "local raw: {number} = arch:get(health)",
      "return held, raw"))
   -- The lie the feature exists to stop: the column holds numbers, not components.
   reports(world .. src(
      "local wrong: {Health} = arch:get(health)",
      "return wrong"), "NUPP2001")
   reports(world .. src(
      "local wrong: {string} = arch:get(position)",
      "return wrong"), "NUPP2001")
end

-- And the consequence of interface opacity, stated outright: a component known only
-- as the interface that defaults it does not expose the default.
function M.anInterfaceTypedComponentStaysOpaque()
   reports(src(
      "local interface Component",
      "   componentId: integer",
      "   associated type Value = self",
      "end",
      "local interface ScalarComponent<E> is Component",
      "   componentId: integer",
      "   associated type Value = E",
      "end",
      "local record Archetype",
      "   function get<C is Component>(self, component: C): {C.Value}",
      "      return nil as any",
      "   end",
      "end",
      "local arch = new Archetype()",
      "local health: ScalarComponent<number> = nil as any",
      "local raw: {number} = arch:get(health)",
      "return raw"), "NUPP2001")
end

-- `T is ConcreteRecord` has one inhabitant, so its projections reduce.
function M.aBinderBoundedByARecordReduces()
   local contract = src(
      "local interface Holds",
      "   associated type Value",
      "end",
      "local record Node is Holds",
      "   associated type Value = string",
      "end")
   clean(contract .. src(
      "local function held<T is Node>(n: T): T.Value",
      "   return 'x'",
      "end",
      "return held"))
   reports(contract .. src(
      "local function wrong<T is Node>(n: T): T.Value",
      "   return 42",
      "end",
      "return wrong"), "NUPP2002")
end

-- A fixed equality is a promise the contract makes, so it resolves through the
-- contract. This is what a default cannot do: an implementor may answer otherwise,
-- so a value known only as the interface cannot rely on one.
local SCALAR = src(
   "local interface Component",
   "   componentId: integer",
   "   associated type Value = self",
   "end",
   "local interface ScalarComponent<E> is Component",
   "   componentId: integer",
   "   associated type Value == E",
   "end",
   "local record Position is Component",
   "   componentId: integer",
   "   x: number",
   "end",
   "local record Archetype",
   "   function get<C is Component>(self, component: C): {C.Value}",
   "      return nil as any",
   "   end",
   "end",
   "local arch = new Archetype()",
   "local health: ScalarComponent<number> = nil as any",
   "local position = new Position(componentId = 1, x = 0)")

function M.theInterfaceTypedMotivatingCaseResolves()
   clean(SCALAR .. src(
      "local raw: {number} = arch:get(health)",
      "local held: {Position} = arch:get(position)",
      "return raw, held"))
   reports(SCALAR .. src(
      "local wrong: {string} = arch:get(health)",
      "return wrong"), "NUPP2001")
   reports(SCALAR .. src(
      "local wrong: {ScalarComponent<number>} = arch:get(health)",
      "return wrong"), "NUPP2001")
end

function M.aFixedEqualityFollowsGenericInstantiation()
   clean(SCALAR .. src(
      "local text: ScalarComponent<string> = nil as any",
      "local raw: {string} = arch:get(text)",
      "return raw"))
   reports(SCALAR .. src(
      "local text: ScalarComponent<string> = nil as any",
      "local raw: {number} = arch:get(text)",
      "return raw"), "NUPP2001")
end

function M.aDefaultStaysOpaqueAndOverridable()
   -- opaque through the interface that defaults it
   reports(src(
      "local interface Holds",
      "   associated type Value = string",
      "end",
      "local function assumed(v: Holds.Value): string",
      "   return v",
      "end",
      "return assumed"), "NUPP2002")
   -- and an implementor may still answer otherwise
   clean(src(
      "local interface Holds",
      "   associated type Value = string",
      "end",
      "local record Otherwise is Holds",
      "   associated type Value = integer",
      "end",
      "local function held(n: Otherwise.Value): integer",
      "   return n",
      "end",
      "return held"))
end

function M.aConcreteAnswerMustEqualAFixedConstraint()
   local contract = src(
      "local interface Fixes",
      "   associated type Value == string",
      "end")
   clean(contract .. src(
      "local record Agrees is Fixes",
      "   associated type Value = string",
      "end",
      "return Agrees"))
   reports(contract .. src(
      "local record Differs is Fixes",
      "   associated type Value = integer",
      "end",
      "return Differs"), "NUPP2127")
end

function M.aDerivedFixedConstraintRefinesABaseDefault()
   clean(src(
      "local interface Base",
      "   associated type Value = string",
      "end",
      "local interface Derived is Base",
      "   associated type Value == integer",
      "end",
      "local function held(v: Derived.Value): integer",
      "   return v",
      "end",
      "return held"))
end

function M.conflictingFixedConstraintsReport()
   reports(src(
      "local interface A",
      "   associated type Value == string",
      "end",
      "local interface B",
      "   associated type Value == integer",
      "end",
      "local record Taker is A, B",
      "   associated type Value = string",
      "end",
      "return Taker"), "NUPP2127")
end

function M.aFixedValueMustSatisfyItsOwnBound()
   reports(CONTRACTS .. src(
      "local interface Fixes",
      "   associated type Value is Named == integer",
      "end",
      "return Fixes"), "NUPP2116")
end

function M.unionsDistributeAcrossFixedAlternatives()
   clean(SCALAR .. src(
      "local either: ScalarComponent<number> | ScalarComponent<number> = nil as any",
      "local raw: {number} = arch:get(either)",
      "return raw"))
end

function M.fixedEqualityIsInterfaceOnly()
   reports(src(
      "local interface Holds",
      "   associated type Value",
      "end",
      "local record Node is Holds",
      "   associated type Value == string",
      "end",
      "return Node"), "NUPP2128")
end

-- A smoke test for the documented pattern, because it is the motivating distinction
-- and the easiest one for a later prose edit to reverse: a base contract keeps an
-- overridable default while a derived one fixes it, and both halves have to hold at
-- once for an interface-typed value.
function M.theDocumentedBaseDefaultAndDerivedFixedPatternHolds()
   local pattern = src(
      "local interface Component",
      "   componentId: integer",
      "   associated type Value = self",
      "end",
      "local interface ScalarComponent<E> is Component",
      "   componentId: integer",
      "   associated type Value == E",
      "end",
      "local record Position is Component",
      "   componentId: integer",
      "   x: number",
      "end",
      "local record Archetype",
      "   function column<C is Component>(self, component: C): {C.Value}",
      "      return nil as any",
      "   end",
      "end",
      "local archetype = new Archetype()",
      "local health: ScalarComponent<number> = nil as any",
      "local position = new Position(componentId = 1, x = 0)")
   -- the default hands a container component itself, without it being edited
   clean(pattern .. src(
      "local held: {Position} = archetype:column(position)",
      "return held"))
   -- and the derived fixed equality resolves through the interface-typed value
   clean(pattern .. src(
      "local raw: {number} = archetype:column(health)",
      "return raw"))
   -- both directions, so accepting the right answer is not the whole test
   reports(pattern .. src(
      "local wrong: {string} = archetype:column(position)",
      "return wrong"), "NUPP2001")
   reports(pattern .. src(
      "local wrong: {ScalarComponent<number>} = archetype:column(health)",
      "return wrong"), "NUPP2001")
   -- and a default alone stays opaque, which is what the fixed form is for
   reports(src(
      "local interface Holds",
      "   associated type Value = string",
      "end",
      "local assumed: string = nil as Holds.Value",
      "return assumed"), "NUPP2001")
end

return M
