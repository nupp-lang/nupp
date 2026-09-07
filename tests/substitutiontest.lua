-- Substitution has two jobs. Rebinding `self` over a member must preserve every
-- other binder; specializing a call must materialize the ones inference never
-- reached, as `any`. One operation did both, and the preserving callers silently
-- got the materializing behaviour: a generic method's own binder became `any`,
-- so the result fit wherever it was put and nothing reported.
--
-- These characterize both directions at every path that substitutes a partial map.
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

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function reports(source, want)
   assertEq(codes(source), want, "for:\n" .. source)
end

local M = {}

-- 1. Direct specialization: the method is declared where it is called from.
function M.aGenericMethodPreservesItsOwnBinder()
   local body = table.concat({
      "local record Box",
      "   function idOf<C>(self, value: C): C",
      "      return value",
      "   end",
      "end",
      "local box = new Box()",
   }, "\n") .. "\n"
   reports(body .. "local wrong: string = box:idOf(42)\nreturn wrong\n", "NUPP2001")
   clean(body .. "local kept: integer = box:idOf(42)\nreturn kept\n")
end

-- 2. Inherited default: declaration inheritance substitutes a self-only map too,
-- so it has the same erasure to answer for.
function M.aGenericDefaultMethodPreservesItsOwnBinder()
   local body = table.concat({
      "local interface Source",
      "   function idOf<C>(self, value: C): C",
      "      return value",
      "   end",
      "end",
      "local record Box is Source",
      "end",
      "local box = new Box()",
   }, "\n") .. "\n"
   reports(body .. "local wrong: string = box:idOf(42)\nreturn wrong\n", "NUPP2001")
   clean(body .. "local kept: integer = box:idOf(42)\nreturn kept\n")
end

-- 3. Both at once: an instantiated generic record whose method mentions the
-- declaration's parameter and its own.
function M.anInstantiatedRecordKeepsBothBinders()
   local body = table.concat({
      "local record Cell<T>",
      "   held: T",
      "   function get(self): T",
      "      return self.held",
      "   end",
      "   function swap<U>(self, other: U): U",
      "      return other",
      "   end",
      "end",
      "local cell: Cell<string> = nil as any",
   }, "\n") .. "\n"
   clean(body .. "local held: string = cell:get()\nreturn held\n")
   reports(body .. "local wrong: integer = cell:get()\nreturn wrong\n", "NUPP2001")
   clean(body .. "local swapped: integer = cell:swap(1)\nreturn swapped\n")
   reports(body .. "local wrong: string = cell:swap(1)\nreturn wrong\n", "NUPP2001")
end

-- 4. The job the self-only map exists for: `self` follows the receiver.
function M.anInheritedSelfFollowsTheReceiver()
   local body = table.concat({
      "local interface Chainable",
      "   function chain(self): self",
      "      return self",
      "   end",
      "end",
      "local record Node is Chainable",
      "   value: integer",
      "end",
      "local node = new Node(value = 1)",
   }, "\n") .. "\n"
   clean(body .. "local same: Node = node:chain()\nreturn same\n")
   reports(body .. "local wrong: string = node:chain()\nreturn wrong\n", "NUPP2001")
end

-- 5. The other direction, which the split must not break: a binder inference
-- genuinely never reached materializes as `any`, keeping the call gradual rather
-- than leaking an unbound binder into the caller.
function M.anUninferredBinderMaterializesAsAny()
   local body = table.concat({
      "local function pick<T>(): T?",
      "   return nil",
      "end",
   }, "\n") .. "\n"
   clean(body .. "local anything: string? = pick()\nreturn anything\n")
   clean(body .. "local other: integer? = pick()\nreturn other\n")
end

-- A type-level operation over an instantiated nominal -- `Box<T>.["value"]`, `keyof
-- Box<T>` -- carries no binder mark in its id, because the nominal's id carries none.
-- Substitution has to walk it to find `T`, or the call site keeps the blocked term.
function M.anOperationOverAnInstantiatedNominalIsSubstitutedAtTheCall()
   clean(table.concat({
      "local m = {}",
      "record m.Box<T>",
      "   value: T",
      "end",
      'function m.get<T>(b: m.Box<T>): m.Box<T>.["value"]',
      "   return b.value as any",
      "end",
      "function m.key<T>(b: m.Box<T>): keyof m.Box<T>",
      '   return "value" as any',
      "end",
      "local one: integer = 1",
      "local b = new m.Box(value = one)",
      "local n: integer = m.get(b)",
      'local k: "value" = m.key(b)',
      "print(n, k)",
   }, "\n"))
end

-- A bound says what a T can do, not what may stand in for one. Answering a
-- `T is Named` result with some record that is Named hands whoever passed a
-- different record the wrong type, so only the binder itself fits a result of T,
-- an argument of T, or a field of T, however the bound is satisfied.
function M.aBoundedBinderAcceptsOnlyItself()
   local body = table.concat({
      "local interface Named",
      "   name: string",
      "end",
      "local record P is Named",
      "   name: string",
      "end",
      "local record Cell<T is Named>",
      "   item: T",
      "end",
   }, "\n") .. "\n"
   reports(body .. table.concat({
      "local function same<T is Named>(x: T): T",
      '   return new P(name = "p")',
      "end",
      "return same",
   }, "\n"), "NUPP2002")
   reports(body .. table.concat({
      "local function store<T is Named>(cell: Cell<T>): nil",
      '   cell.item = new P(name = "p")',
      "end",
      "return store",
   }, "\n"), "NUPP2001")
   reports(body .. table.concat({
      "local function keep<T is Named>(x: T): nil",
      "   local held: T = x",
      '   held = new P(name = "p")',
      "end",
      "return keep",
   }, "\n"), "NUPP2001")
   reports(body .. table.concat({
      "local function fill<T is Named>(cell: Cell<T>, x: P): nil",
      "   local function put(item: T) cell.item = item end",
      "   put(x)",
      "end",
      "return fill",
   }, "\n"), "NUPP2006")
   clean(body .. table.concat({
      "local function same<T is Named>(x: T): T",
      "   local held: T = x",
      "   return held",
      "end",
      "local function other<T is Named, U is T>(x: T, y: U): T",
      "   local function put(item: T) print(item.name) end",
      "   put(y)",
      "   return y",
      "end",
      "local function stop<T is Named>(x: T): T",
      '   error("never")',
      "end",
      "return same, other, stop",
   }, "\n"))
end

-- Passing a T where a concrete parameter is wanted is the same mistake in the
-- other direction: a bound satisfies the parameter, an absent bound does not.
function M.aBinderReachesOnlyWhatItsBoundAllows()
   reports(table.concat({
      "local function label(x: string): string return x end",
      "local function show<T>(x: T): string",
      "   return label(x)",
      "end",
      "return show",
   }, "\n"), "NUPP2006")
   clean(table.concat({
      "local function label(x: string): string return x end",
      "local function show<T is string>(x: T): string",
      "   return label(x)",
      "end",
      "local function optional<T>(x: T): T",
      "   if x ~= nil then print(x) end",
      "   return x",
      "end",
      "return show, optional",
   }, "\n"))
end

return M
