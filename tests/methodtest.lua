-- Record and struct members, and multi-value return expansion.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagsOf(src, filename)
   filename = filename or "test.g.nupp"
   local result = parser.parse(src, filename)
   assertEq(#result.errors, 0, "syntax errors: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, filename, env)) do
      out[j] = d.code .. ":" .. d.line
   end
   return table.concat(out, " ")
end

local function assertClean(src)
   assertEq(diagsOf(src), "", "expected clean:\n" .. src)
end

local function generate(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test.g.nupp", env)
   assertEq(#diags, 0, "check: " .. (diags[1] and diags[1].msg or ""))
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
   return code
end

local function run(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test.g.nupp", env)
   assertEq(#diags, 0, "check: " .. (diags[1] and diags[1].msg or ""))
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@methodtest")
   if not chunk then
      error("generated code does not load: " .. tostring(err) .. "\n" .. code, 2)
   end
   return chunk()
end

local TASK = table.concat({
   "local record Task",
   "    title: string",
   "end",
   "function Task:describe(): string",
   "    return self.title",
   "end",
}, "\n")

local M = {}

function M.recordMethodsTypeAtCallSites()
   assertClean(TASK .. "\nlocal t: Task = new Task()\nlocal s: string = t:describe()")
   assertEq(diagsOf(TASK .. "\nlocal t: Task = new Task()\nlocal n: number = t:describe()"),
      "NUPP2001:8")
   assertEq(diagsOf(TASK .. "\nlocal t: Task = new Task()\nt:describe(1)"), "NUPP2007:8")
   assertEq(diagsOf(TASK .. "\nlocal t: Task = new Task()\nt:nosuch()"), "NUPP2004:8")
end

function M.selfIsBoundInsideMethods()
   assertClean(TASK)
   -- self carries the record's fields
   assertEq(diagsOf(table.concat({
      "local record R",
      "    n: number",
      "end",
      "function R:bad(): number",
      "    return self.nope",
      "end",
   }, "\n")), "NUPP2004:5")
end

function M.explicitSelfKeepsTheReceiverType()
   -- The leading `self` spelling is the method receiver, not an untyped
   -- ordinary parameter. In particular, member lookup must still see R.
   assertEq(diagsOf(table.concat({
      "local record R",
      "    n: number",
      "",
      "    function bad(self): number",
      "        return self.nope",
      "    end",
      "end",
   }, "\n")), "NUPP2004:5")
end

function M.inlineFunctionsNeedSelfToBeMethods()
   local declaration = table.concat({
      "local interface Greeter",
      "    name: string",
      "",
      "    function greet(): string",
      "        return 'hello, ' .. self.name",
      "    end",
      "end",
   }, "\n")
   assertEq(diagsOf(declaration, "test.nupp"), "NUPP2105:5")

   assertEq(run(table.concat({
      "local record Numbers",
      "    function answer(): integer",
      "        return 42",
      "    end",
      "end",
      "return Numbers.answer()",
   }, "\n")), 42)
   assertEq(diagsOf(table.concat({
      "local record Numbers",
      "    function answer(): integer return 42 end",
      "end",
      "local numbers = new Numbers()",
      "numbers:answer()",
   }, "\n")), "NUPP2004:5")
   assertEq(diagsOf(table.concat({
      "local record Numbers",
      "    function answer(): integer return 42 end",
      "end",
      "Numbers:answer()",
   }, "\n")), "NUPP2004:4")

   assertEq(run(table.concat({
      "local interface Greeter",
      "    function greet(name: string): string",
      "        return 'hello, ' .. name",
      "    end",
      "end",
      "return Greeter.greet('Ada')",
   }, "\n")), "hello, Ada")
end

function M.dottedMembersTakeNoReceiver()
   assertClean(table.concat({
      "local record R",
      "    n: number",
      "end",
      "function R.make(v: number): R",
      "    return {n = v} as R",
      "end",
      "local r: R = R.make(1)",
   }, "\n"))
end

function M.recordMethodsRunAtRuntime()
   assertEq(run(TASK .. table.concat({
      "",
      "local t = new Task(title = 'ok')",
      "return t:describe()",
   }, "\n")), "ok")
end

function M.structMethodsDispatchThroughMetatype()
   local src = table.concat({
      "local struct Vec2",
      "    x: float",
      "    y: float",
      "end",
      "function Vec2:len(): number",
      "    return (self.x * self.x + self.y * self.y) ^ 0.5",
      "end",
      "local v = new Vec2(3, 4)",
      "return v:len()",
   }, "\n")
   assertClean(src)
   assertEq(run(src), 5)
   -- the constructor still works after metatype
   assertEq(run(table.concat({
      "local struct P",
      "    n: float",
      "end",
      "function P:twice(): number",
      "    return self.n * 2",
      "end",
      "local p = new P(21)",
      "return p:twice()",
   }, "\n")), 42)
end

function M.multiValueReturnsExpandAcrossTargets()
   local two = table.concat({
      "local function two(): number, string",
      "    return 1, 'two'",
      "end",
   }, "\n")
   assertClean(two .. "\nlocal a, b = two()\nlocal n: number = a\nlocal s: string = b")
   assertEq(diagsOf(two .. "\nlocal a, b = two()\nlocal bad: number = b"),
      "NUPP2001:5")
   -- only the trailing expression expands
   assertClean(two .. "\nlocal x, y, z = 0, two()\nlocal n: number = y")
   assertEq(diagsOf(two .. "\nlocal x, y, z = 0, two()\nlocal bad: number = z"),
      "NUPP2001:5")
end

-- Only a call expands. Inferring anything else may still have left a call's
-- results behind — a function expression whose body calls something does — and
-- taking those for the expression's own type gave a function the type of
-- whatever it last called.
function M.onlyACallExpandsAcrossTargets()
   local two = table.concat({
      "local function two(): number, string",
      "    return 1, 'two'",
      "end",
   }, "\n")
   -- the value is the function, not what its body returns
   assertClean(two .. "\n" .. table.concat({
      "local f: function(): (number, string) = two",
      "local a, b = f()",
      "local n: number = a",
   }, "\n"))
   -- a function expression assigned to a declared field, whose body both
   -- recurses and returns a multi-value call
   assertClean(table.concat({
      "local m = {}",
      "record m.Box",
      "    one: function(n: string?): string?",
      "    two: function(n: string?): (string?, any)",
      "end",
      "local b = new m.Box()",
      "b.one = function(n)",
      "    if n == 'x' then return b.one(n) end",
      "    return b.two(n)",
      "end",
      "b.two = function(n)",
      "    return n, nil",
      "end",
      "return m",
   }, "\n"))
end

-- `new` is the construction, for both kinds of declaration. It lowers to the
-- stamp and the ctype call themselves, so what it costs at run time is nothing.
function M.newConstructsRecordsAndStructs()
   assertEq(run(table.concat({
      "local record Account",
      "    name: string",
      "    balance: number",
      "    function deposit(self, credit: number)",
      "        self.balance = self.balance + credit",
      "    end",
      "end",
      "local struct V2",
      "    x: float",
      "    y: float",
      "end",
      "local a = new Account(name = 'Hina', balance = 500)",
      "local named = new V2(3.0, 4.0)",
      "local positional = new V2(1.0, 2.0)",
      "a:deposit(20)",
      "return a.balance + named.x + named.y + positional.x + positional.y",
   }, "\n")), 530)
end

-- The keyword is contextual: `new` is a name everywhere a name can stand, and
-- only a name following it on the same line makes it a construction.
function M.newStaysAnOrdinaryNameElsewhere()
   assertEq(run(table.concat({
      "local record R",
      "    n: integer",
      "end",
      "local function id(x: any): any return x end",
      "local new = id",
      "local held = new",
      "id(R)",
      "local built = new R(n = 5)",
      "return built.n + (held == id and 1 or 0)",
   }, "\n")), 6)
end

-- What `new` names is a type, so an operand that is not one is answered as a
-- type rather than through whatever value stands under the name. An interface
-- binds no value at all, so going through the value would say `any`.
function M.newRefusesWhatCannotBeConstructed()
   assertEq(diagsOf(table.concat({
      "local interface I",
      "    n: integer",
      "end",
      "local iface = new I()",
   }, "\n")), "NUPP2206:4")
   assertEq(diagsOf("local prim = new string()"), "NUPP2206:1")
   -- a closed set of literals is a union, and a value of it is one of the
   -- literals, written directly
   assertEq(diagsOf(table.concat({
      "local type Color = 'red' | 'blue'",
      "local c = new Color()",
   }, "\n")), "NUPP2206:2")
end

-- A refinement is what `is` compiles to. The values here were never built by
-- this program, which is the case a stamped metatable cannot answer: a table
-- off a decoder, or anything an untyped library handed back.
function M.whereRefinementsDecideIsAtRuntime()
   assertEq(run(table.concat({
      "local interface Shape",
      "   kind: string",
      "end",
      "local interface Circle is Shape",
      "   kind: string",
      "   radius: number",
      "   satisfies |self| -> self.kind == 'circle'",
      "end",
      "local interface Square is Shape",
      "   kind: string",
      "   side: number",
      "   satisfies |self| -> self.kind == 'square'",
      "end",
      "local function area(s: Shape): number",
      "   if s is Circle then return 3 * s.radius * s.radius end",
      "   if s is Square then return s.side * s.side end",
      "   return 0",
      "end",
      "local decoded: Shape = {kind = 'circle', radius = 2} as Shape",
      "local other: Shape = {kind = 'square', side = 3} as Shape",
      "return area(decoded) + area(other)",
   }, "\n")), 21)
end

-- An interface has no runtime table to stamp, so `is` on one was NUPP3001 and
-- could not be compiled at all. A refinement is the answer it can give.
function M.whereRefinementsGiveAnInterfaceARuntimeIdentity()
   assertEq(run(table.concat({
      "local interface Tagged",
      "   tag: string",
      "   satisfies |self| -> type(self.tag) == 'string'",
      "end",
      "local function describe(v: any): string",
      "   if v is Tagged then return 'tagged ' .. v.tag end",
      "   return 'untagged'",
      "end",
      "return describe({tag = 'x'}) .. '/' .. describe(42)",
   }, "\n")), "tagged x/untagged")
end

-- A refinement may read the subject more than once, so a subject that is not a
-- name is evaluated once and handed to the test.
function M.aComputedSubjectIsEvaluatedOnce()
   assertEq(run(table.concat({
      "local interface Tagged",
      "   tag: string",
      "   satisfies |self| -> self.tag == 'x'",
      "end",
      "local calls = 0",
      "local function make(): any",
      "   calls = calls + 1",
      "   return {tag = 'x'}",
      "end",
      "local hit = make() is Tagged",
      "return (hit and 10 or 0) + calls",
   }, "\n")), 11)
end

-- Reaching through a field has to guard the step before it, because the test
-- runs against values that are not of the type yet. `?.` is the runtime's own
-- answer to that, and it reads each step once where a written-out guard read it
-- twice.
function M.aRefinementReachesThroughFieldsSafely()
   local decl = table.concat({
      "local record Inner",
      "   c: string",
      "end",
      "local record Mid",
      "   b: Inner",
      "end",
      "local interface Deep",
      "   a: Mid",
      "   satisfies |self| -> self.a.b.c == 'x'",
      "end",
   }, "\n")
   -- present, absent halfway, and not a table at all
   assertEq(run(decl .. table.concat({
      "",
      "local full: any = {a = {b = {c = 'x'}}}",
      "local partial: any = {a = {}}",
      "local n: any = 42",
      "return (full is Deep and 1 or 0) + (partial is Deep and 10 or 0)",
      "   + (n is Deep and 100 or 0)",
   }, "\n")), 1)
end

-- A record is nominal, and an instance is a value that came from the
-- declaration — not only one the declaration stamped itself. A constructor that
-- links back rather than stamping directly, which is how tecs builds its event
-- instances, produces instances too, and `is` has to say so.
function M.instancesAreRecognisedThroughTheirPrototype()
   assertEq(run(table.concat({
      "local interface Event",
      "   eventId: integer",
      "   init: function(instance: self, ...: any)",
      "end",
      "local record OnSpawn is Event",
      "   eventId: integer",
      "   entity: integer",
      "   metamethod __call: function(self, entity: integer): self",
      "end",
      "OnSpawn.init = function(instance: OnSpawn, entity: integer)",
      "   instance.entity = entity",
      "end",
      "local function newEvent<E is Event>(event: metatable<E>)",
      "   local instanceMt = {__index = event}",
      "   setmetatable(event, {__call = function(_self: E, ...: any): E",
      "      local instance = setmetatable({eventId = 7}, instanceMt) as E",
      "      event.init(instance, ...)",
      "      return instance",
      "   end})",
      "end",
      "newEvent(OnSpawn)",
      "local linked = OnSpawn(42)",
      "local stamped = new OnSpawn(eventId = 1, entity = 2)",
      "local foreign: any = {eventId = 1, entity = 2}",
      -- linked and stamped are both instances; a lookalike and the declaration's
      -- own table are not
      "return (linked is OnSpawn and 1 or 0) + (stamped is OnSpawn and 2 or 0)",
      "   + (foreign is OnSpawn and 100 or 0)",
      "   + ((OnSpawn as any) is OnSpawn and 100 or 0)",
   }, "\n")), 3)
end

-- `is` against an interface has no runtime test to run unless the interface
-- says what one is. When the subject's own type already declares the interface,
-- there is nothing to run: the declaration answered it.
function M.aProvenInterfaceNeedsNoTest()
   assertEq(run(table.concat({
      "local interface Shape",
      "   kind: string",
      "end",
      "local record Circle is Shape",
      "   kind: string",
      "   radius: number",
      "end",
      "local c = new Circle(kind = 'c', radius = 1)",
      "local maybe: Circle? = c",
      "local absent: Circle? = nil",
      "return (c is Shape and 1 or 0) + (maybe is Shape and 2 or 0)",
      "   + (absent is Shape and 100 or 0)",
   }, "\n")), 3)
end

-- An interface whose fields carry literal types has already said what its test
-- is: the field admits that value and nothing else. Reading it off is what lets
-- a tagged interface answer `is` for a value this program did not build, with
-- nothing written.
function M.aTaggedInterfaceDerivesItsOwnTest()
   local decl = table.concat({
      "local interface Circle",
      "   kind: 'circle'",
      "   radius: number",
      "end",
      "local interface Square",
      "   kind: 'square'",
      "   side: number",
      "end",
   }, "\n")
   assertEq(run(decl .. table.concat({
      "",
      -- values nothing here built
      "local c: any = {kind = 'circle', radius = 2}",
      "local s: any = {kind = 'square', side = 3}",
      "local neither: any = {kind = 'triangle'}",
      "return (c is Circle and 1 or 0) + (s is Square and 2 or 0)",
      "   + (c is Square and 100 or 0) + (neither is Circle and 100 or 0)",
      "   + ((42 as any) is Circle and 100 or 0)",
   }, "\n")), 3)
   -- an explicit block still wins over the tags
   assertEq(run(decl .. table.concat({
      "",
      "local interface Odd",
      "   kind: 'odd'",
      "   satisfies |self| -> self.kind == 'even'",
      "end",
      "local v: any = {kind = 'odd'}",
      "local w: any = {kind = 'even'}",
      "return (v is Odd and 1 or 0) + (w is Odd and 2 or 0)",
   }, "\n")), 2)
end

-- An interface may implement what it declares. The body is emitted once and
-- referenced by each declaration that takes it, so an implementor inherits the
-- behaviour rather than a copy of it, resolved where it is written rather than
-- looked up at run time.
function M.interfacesCarryDefaultBodies()
   assertEq(run(table.concat({
      "local interface Greeter",
      "   name: string",
      "   function greet(self): string",
      "      return 'hello, ' .. self.name",
      "   end",
      "end",
      "local record Person is Greeter",
      "   name: string",
      "end",
      "local p = new Person(name = 'Ada')",
      "return p:greet()",
   }, "\n")), "hello, Ada")
   -- a struct takes it through the metatype's index table
   assertEq(run(table.concat({
      "local interface Sized",
      "   w: float",
      "   h: float",
      "   function area(self): number",
      "      return self.w * self.h",
      "   end",
      "end",
      "local struct Box is Sized",
      "   w: float",
      "   h: float",
      "end",
      "return (new Box(3, 4)):area()",
   }, "\n")), 12)
   -- and a chain of interfaces passes it along
   assertEq(run(table.concat({
      "local interface Base",
      "   n: integer",
      "   function twice(self): number",
      "      return self.n * 2",
      "   end",
      "end",
      "local interface Mid is Base",
      "   n: integer",
      "end",
      "local record Leaf is Mid",
      "   n: integer",
      "end",
      "return (new Leaf(n = 21)):twice()",
   }, "\n")), 42)
end

-- Replacing a default has to be said, and saying it when nothing is replaced is
-- the same mistake from the other side. Java catches neither.
function M.overridingADefaultIsDeclared()
   local iface = table.concat({
      "local interface Greeter",
      "   name: string",
      "   function greet(self): string",
      "      return 'hi'",
      "   end",
      "end",
   }, "\n")
   -- silently shadowing is refused
   assertEq(diagsOf(iface .. table.concat({
      "",
      "local record Silent is Greeter",
      "   name: string",
      "   function greet(self): string",
      "      return '...'",
      "   end",
      "end",
   }, "\n")), "NUPP2118:9")
   -- saying it is fine, and the override runs
   assertEq(run(iface .. table.concat({
      "",
      "local record Loud is Greeter",
      "   name: string",
      "   @override",
      "   function greet(self): string",
      "      return 'LOUD'",
      "   end",
      "end",
      "return (new Loud(name = 'x')):greet()",
   }, "\n")), "LOUD")
   -- and claiming to override nothing is refused too
   assertEq(diagsOf(table.concat({
      "local record Bogus",
      "   n: integer",
      "   @override",
      "   function nope(self): integer",
      "      return 1",
      "   end",
      "end",
   }, "\n")), "NUPP2118:4")
end

-- Two interfaces providing the same name are two implementations and no reason
-- to prefer either, so the declaration has to say which behaviour it means.
function M.aDefaultInheritedTwiceMustBeChosen()
   local ifaces = table.concat({
      "local interface A",
      "   function tag(self): string",
      "      return 'a'",
      "   end",
      "end",
      "local interface B",
      "   function tag(self): string",
      "      return 'b'",
      "   end",
      "end",
   }, "\n")
   assertEq(diagsOf(ifaces .. table.concat({
      "",
      "local record Bad is A, B",
      "   n: integer",
      "end",
   }, "\n")), "NUPP2118:11")
   -- writing it settles the question
   assertEq(run(ifaces .. table.concat({
      "",
      "local record Good is A, B",
      "   n: integer",
      "   @override",
      "   function tag(self): string",
      "      return 'mine'",
      "   end",
      "end",
      "return (new Good(n = 1)):tag()",
   }, "\n")), "mine")
end

-- A constructor is the whole reason `new` is worth having over a literal: a
-- literal may leave a declared field out, and a constructor may not.
function M.constructorsRunAndFillEveryField()
   assertEq(run(table.concat({
      "local record Account",
      "    name: string",
      "    balance: number",
      "    constructor(self, name: string, opening: number)",
      "        self.name = name",
      "        self.balance = opening",
      "    end",
      "    function deposit(self, credit: number)",
      "        self.balance = self.balance + credit",
      "    end",
      "end",
      "local a = new Account('Hina', 500)",
      "a:deposit(20)",
      "return a.balance",
   }, "\n")), 520)
   -- the instance is a real one: `is` still answers through the metatable
   assertEq(run(table.concat({
      "local record R",
      "    n: integer",
      "    constructor(self, v: integer)",
      "        self.n = v",
      "    end",
      "end",
      "local r = new R(7)",
      "return (r is R) and r.n or 0",
   }, "\n")), 7)
end

function M.constructorsRefuseWhatTheyCannotGuarantee()
   -- a field that cannot hold nil has to be filled
   assertEq(diagsOf(table.concat({
      "local record A",
      "    name: string",
      "    balance: number",
      "    constructor(self, n: string)",
      "        self.name = n",
      "    end",
      "end",
   }, "\n")), "NUPP2208:4")
   -- an optional one need not be
   assertClean(table.concat({
      "local record B",
      "    name: string",
      "    note: string?",
      "    constructor(self, n: string)",
      "        self.name = n",
      "    end",
      "end",
   }, "\n"))
   -- a field taken from an interface is as much part of the value as one
   -- declared here, so leaving it out is the same nil
   assertEq(diagsOf(table.concat({
      "local interface Named",
      "   name: string",
      "end",
      "local record Person is Named",
      "   constructor(self)",
      "   end",
      "end",
   }, "\n")), "NUPP2208:5")
   assertClean(table.concat({
      "local interface Named",
      "   name: string",
      "end",
      "local record Person is Named",
      "   constructor(self, n: string)",
      "      self.name = n",
      "   end",
      "end",
   }, "\n"))
   -- an interface builds nothing
   assertEq(diagsOf(table.concat({
      "local interface I",
      "    n: integer",
      "    constructor(self, v: integer)",
      "        self.n = v",
      "    end",
      "end",
   }, "\n")), "NUPP2208:3")
   -- distinct constructor parameter packs form an overload set
   assertClean(table.concat({
      "local record T",
      "    n: integer",
      "    constructor(self, v: integer)",
      "        self.n = v",
      "    end",
      "    constructor(self, v: string)",
      "        self.n = #v",
      "    end",
      "end",
   }, "\n"))
end

function M.overloadedConstructorsSelectDistinctBodies()
   assertEq(run(table.concat({
      "local record Value",
      "    text: string",
      "    constructor(self, value: integer)",
      "        self.text = tostring(value)",
      "    end",
      "    constructor(self, value: string)",
      "        self.text = value",
      "    end",
      "end",
      "local numberValue = new Value(42)",
      "local stringValue = new Value('ready')",
      "return numberValue.text .. ':' .. stringValue.text",
   }, "\n")), "42:ready")
   assertEq(diagsOf(table.concat({
      "local record Duplicate",
      "    value: integer",
      "    constructor(self, value: integer)",
      "        self.value = value",
      "    end",
      "    constructor(self, other: integer)",
      "        self.value = other",
      "    end",
      "end",
   }, "\n")), "NUPP2208:6")
end

function M.genericConstructorsRemainOverloadedAfterInstantiation()
   assertEq(run(table.concat({
      "local record Box<T>",
      "    value: T",
      "    constructor(self, kind: 'value', value: T)",
      "        self.value = value",
      "    end",
      "    constructor(self, kind: 'converted', value: T, convert: boolean)",
      "        self.value = (convert and tostring(value) or value) as any",
      "    end",
      "end",
      "local text = new Box('value', 'ready')",
      "local number = new Box('converted', 42, true)",
      "local textValue: string = text.value",
      "local numberValue: integer = number.value",
      "return text.value .. ':' .. number.value",
   }, "\n")), "ready:42")
end

-- Declaring a constructor closes the literal form. Leaving it open beside one
-- would let every invariant the constructor establishes be walked around.
function M.aConstructorClosesTheLiteralForm()
   local decl = table.concat({
      "local record A",
      "    n: integer",
      "    constructor(self, v: integer)",
      "        self.n = v",
      "    end",
      "end",
   }, "\n")
   assertEq(diagsOf(decl .. "\nlocal a = new A {n = 1}"), "NUPP2208:7")
   assertClean(decl .. "\nlocal a = new A(1)")
   -- `constructor` is contextual: a field may still be called one
   assertClean(table.concat({
      "local record C",
      "    constructor: string",
      "end",
      "local c = new C(constructor = 'x')",
   }, "\n"))
end

-- A metamethod declaration is a contract, and a metatable literal is where the
-- value fulfilling it is written. Until it is checked there the contract is
-- rendered and never read.
function M.aContractIsHeldToTheValueThatFulfilsIt()
   local i64 = table.concat({
      "local record I64",
      "   v: integer",
      "   metamethod __add: function(self: I64, other: I64): I64",
      "end",
      "local x = new I64(v = 1)",
   }, "\n")
   assertEq(diagsOf(i64 .. "\nsetmetatable(x, {__add = 'not a function'})"),
      "NUPP2123:6")
   assertClean(i64 .. table.concat({
      "",
      "setmetatable(x, {__add = function(a: I64, b: I64): I64",
      "   return new I64(v = a.v + b.v)",
      "end})",
   }, "\n"))
end

-- Where a declaration contracts for nothing, LuaJIT still says what it will do
-- with the key it reads.
function M.aKeyWithNoContractIsHeldToWhatLuaJITDoesWithIt()
   local r = "local record R end\nlocal r = new R()\n"
   assertEq(diagsOf(r .. "setmetatable(r, {__mode = 42})"), "NUPP2123:3")
   assertEq(diagsOf(r .. "setmetatable(r, {__gc = 'soon'})"), "NUPP2123:3")
   assertEq(diagsOf(r .. "setmetatable(r, {__index = 42})"), "NUPP2123:3")
   assertClean(r .. "setmetatable(r, {__index = r, __mode = 'k'})")
   -- and an unknown key is still a broken contract rather than a field
   assertEq(diagsOf(r .. "setmetatable(r, {__tostirng = tostring})"),
      "NUPP2118:3")
end

-- The declaration's name holds its runtime table, and `new` builds instances of
-- it. They are different values and now different types, which is what stops
-- either standing where the other is wanted.
function M.aRecordsTableIsNotAnInstanceOfIt()
   local foo = "local record Foo\n   v: integer\nend\n"
   assertClean(foo .. table.concat({
      "local mt: metatable<Foo> = Foo",
      "local instance: Foo = new Foo(v = 1)",
      "return {mt, instance}",
   }, "\n"))
   -- the table is not an instance
   assertEq(diagsOf(foo .. "local wrong: Foo = Foo\nreturn wrong"),
      "NUPP2001:4")
   -- and an instance is not the table
   assertEq(diagsOf(foo .. table.concat({
      "local instance = new Foo(v = 1)",
      "local wrong: metatable<Foo> = instance",
      "return wrong",
   }, "\n")), "NUPP2001:5")
   -- construction, methods and nested reads still go through the table
   assertEq(run(table.concat({
      "local record Outer",
      "   record Inner",
      "      n: integer",
      "   end",
      "end",
      "local made = new Outer.Inner(n = 4)",
      "return made.n",
   }, "\n")), 4)
end

-- Now that the table and an instance are different types, `is` between them is
-- settled without running: a declaration's own table is not one of the values it
-- stamps, and the test would spend a metatable lookup to say so.
function M.aTableIsNotAnInstanceAndIsSaysSoWithoutAsking()
   local foo = table.concat({
      "local record Foo",
      "   v: integer",
      "end",
      "local instance = new Foo(v = 1)",
   }, "\n")
   assertEq(run(foo .. table.concat({
      "",
      "return (instance is Foo and 1 or 0) + (Foo is Foo and 100 or 0)",
   }, "\n")), 1)
   local code = generate(foo .. "\nlocal answer = Foo is Foo\nreturn answer")
   assert(code:find("( false )", 1, true),
      "the refuted test is not emitted: " .. code)
end

-- A metamethod written on an instance puts a function where the operator never
-- looks. The declaration's table is the metatable, so that is where it belongs.
function M.aMetamethodOnAnInstanceIsRefused()
   local i64 = table.concat({
      "local record I64",
      "   v: integer",
      "   metamethod __tostring: function(self): string",
      "end",
   }, "\n")
   assertEq(diagsOf(i64 .. table.concat({
      "",
      "local x = new I64(v = 1)",
      "x.__tostring = tostring",
   }, "\n")), "NUPP2004:6")
   -- and on the table it is the installation
   assertClean(i64 .. table.concat({
      "",
      "I64.__tostring = function(self: I64): string",
      "   return tostring(self.v)",
      "end",
   }, "\n"))
end

-- A record's runtime table is the metatable its instances carry, so it is a
-- `metatable<R>` and the oldest way to write a class in Lua checks. Reaching a
-- member through the wrapper reaches the record's.
function M.aRecordsTableSatisfiesItsOwnMetatableType()
   local foo = table.concat({
      "local record Foo",
      "   v: integer",
      "   function double(self): integer",
      "      return self.v * 2",
      "   end",
      "end",
   }, "\n")
   assertClean(foo .. table.concat({
      "",
      "local raw: table = {v = 1}",
      "local mt: metatable<Foo> = Foo",
      "setmetatable(raw, Foo)",
      "return mt",
   }, "\n"))
   -- and the members are reached through it
   assertClean(foo .. table.concat({
      "",
      "local mt: metatable<Foo> = Foo",
      "local f: function(self: Foo): integer = mt.double",
      "return f",
   }, "\n"))
   assertEq(diagsOf(foo .. table.concat({
      "",
      "local mt: metatable<Foo> = Foo",
      "return mt.nosuch",
   }, "\n")), "NUPP2004:8")
end

-- A record's runtime table is the metatable its instances carry, so writing a
-- declared metamethod on it is how a contract is fulfilled. It used to be
-- refused as a missing field, with the same message a typo got.
function M.aContractIsInstalledOnTheRecordsOwnTable()
   local i64 = table.concat({
      "local record I64",
      "   v: integer",
      "   metamethod __tostring: function(self): string",
      "end",
   }, "\n")
   assertEq(run(i64 .. table.concat({
      "",
      "I64.__tostring = function(self: I64): string",
      "   return 'I64(' .. tostring(self.v) .. ')'",
      "end",
      "return tostring(new I64(v = 7))",
   }, "\n")), "I64(7)")
   -- the value is held to the contract it fulfils
   assertEq(diagsOf(i64 .. "\nI64.__tostring = 42"), "NUPP2123:5")
   -- and a misspelled one is still absent, now with the spelling to reach for
   assertEq(diagsOf(i64 .. "\nI64.__totring = tostring"), "NUPP2004:5")
end

-- A `metatable<T>` annotation says whose metatable it is as readily as a
-- parameter does, so the literal under one is held to the same rules wherever
-- it is written.
function M.anAnnotatedMetatableIsHeldToTheSameRules()
   local i64 = table.concat({
      "local record I64",
      "   v: integer",
      "   metamethod __tostring: function(self): string",
      "end",
   }, "\n")
   assertEq(diagsOf(i64 .. "\nlocal mt: metatable<I64> = {__tostring = 42}"
      .. "\nreturn mt"), "NUPP2123:5")
   assertEq(diagsOf(i64 .. table.concat({
      "",
      "local mt: metatable<I64> = {}",
      "mt = {__tostirng = tostring}",
      "return mt",
   }, "\n")), "NUPP2118:6")
   assertClean(i64 .. table.concat({
      "",
      "local mt: metatable<I64> = {__tostring = function(self: I64): string",
      "   return tostring(self.v)",
      "end}",
      "return mt",
   }, "\n"))
end

-- An `__index` table is what instances read their members through, so a member
-- written into one has to be what the declaration said it is. A name the
-- declaration does not have is an ordinary helper, and one it has that the table
-- leaves out may still be assigned afterwards.
function M.anIndexTableIsHeldToTheMembersItStandsIn()
   local counter = table.concat({
      "local record Counter",
      "   value: integer",
      "   label: function(self: Counter): string",
      "end",
      "local c = new Counter(value = 1, label = tostring)",
   }, "\n")
   assertEq(diagsOf(counter .. table.concat({
      "",
      "setmetatable(c, {__index = {label = function(self: Counter): integer",
      "   return 1",
      "end}})",
   }, "\n")), "NUPP2123:6")
   assertClean(counter .. table.concat({
      "",
      "setmetatable(c, {__index = {helper = 42,",
      "   label = function(self: Counter): string",
      "      return 'c'",
      "   end}})",
   }, "\n"))
end

-- Nothing here can see what a function returns, so a computed metatable stays
-- gradual, which is what the documentation has always promised.
function M.aComputedMetatableStaysGradual()
   assertClean(table.concat({
      "local record R",
      "   metamethod __tostring: function(self): string",
      "end",
      "local r = new R()",
      "local function build(): table",
      "   return {__tostring = 42}",
      "end",
      "setmetatable(r, build())",
   }, "\n"))
end

-- A registrar takes its receiver through a bound, so the contract it has to
-- fulfil is the bound's. Checking it there is what lets the registrar's own body
-- be wrong rather than only its call sites.
function M.aBoundedReceiverCarriesItsContractIntoTheRegistrar()
   local event = table.concat({
      "local interface Event",
      "   eventId: integer",
      "   metamethod __call: function(self, ...: any): self",
      "end",
      "local record OnSpawn is Event",
      "   eventId: integer",
      "end",
   }, "\n")
   assertEq(diagsOf(event .. table.concat({
      "",
      "local function newEvent<E is Event>(event: metatable<E>)",
      "   setmetatable(event, {__call = 'not callable'})",
      "end",
      "return newEvent",
   }, "\n")), "NUPP2123:9")
   assertClean(event .. table.concat({
      "",
      "local function newEvent<E is Event>(event: metatable<E>)",
      "   local instanceMt = {__index = event}",
      "   setmetatable(event, {__call = function(_self: E, ...: any): E",
      "      return setmetatable({eventId = 7}, instanceMt) as E",
      "   end})",
      "end",
      "return newEvent",
   }, "\n"))
end

function M.multiValueReturnsInAssignments()
   local two = table.concat({
      "local function two(): number, string",
      "    return 1, 'two'",
      "end",
      "local a: number = 0",
      "local b: string = ''",
   }, "\n")
   assertClean(two .. "\na, b = two()")
   assertEq(diagsOf(two .. "\nb, a = two()"), "NUPP2001:6 NUPP2001:6")
end

-- A method's own type parameters are not free when `self` is rebound to the
-- receiver. Substituting a map that mentions only `self` replaced each with `any`,
-- so a generic method stopped inferring and its result fit wherever it was put --
-- silently, because `any` fits everything.
function M.aGenericMethodStillInfers()
   local mistyped = table.concat({
      "local record Box",
      "   function idOf<C>(self, value: C): C",
      "      return value",
      "   end",
      "end",
      "local box = new Box()",
      "local wrong: string = box:idOf(42)",
      "return wrong",
   }, "\n") .. "\n"
   assertEq(diagsOf(mistyped), "NUPP2001:7", "a generic method stopped inferring")
   assertClean(table.concat({
      "local record Box",
      "   function idOf<C>(self, value: C): C",
      "      return value",
      "   end",
      "end",
      "local box = new Box()",
      "local kept: integer = box:idOf(42)",
      "return kept",
   }, "\n") .. "\n")
end

return M
