-- The type-system features the compiler needed in order to describe itself.
-- Each of these came out of typing nupp.compiler.cst and nupp.compiler.lexer: what the CST and
-- the token stream actually are could not be said without them.
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

local function parse(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   return result
end

local function diagsOf(src, opts)
   local out = {}
   for j, d in ipairs(check.check(parse(src), "test", env, opts)) do
      out[j] = d.code
   end
   return table.concat(out, " ")
end

-- gen reads hints the checker leaves on type nodes (a record's runtime
-- table, a struct's ctype), so it runs after checking, as in a real build.
local function generate(src)
   local result = parse(src)
   check.check(result, "test.g.nupp", env)
   local code, diags = gen.generate(result, "test")
   assertEq(#diags, 0, "gen diagnostics: " .. (diags[1] and diags[1].msg or ""))
   return code
end

local M = {}

-- A field whose type admits nil need not be there at all: an absent field
-- reads as nil, which is what makes `missing: boolean?` optional.
function M.aNilAdmittingFieldIsOptional()
   local shape = "local type Tok = {kind: string, missing: boolean?}\n"
   assertEq(diagsOf(shape .. 'local t: Tok = {kind = "name"}'), "")
   assertEq(diagsOf(shape .. 'local t: Tok = {kind = "n", missing = true}'), "")
   -- a field that does not admit nil is still required
   assertEq(diagsOf("local type R = {kind: string, n: integer}\n"
      .. 'local r: R = {kind = "n"}'), "NUPP2001")
end

-- A record that is also a sequence declares `{T}` among its fields. The CST
-- needs this: a node's array part is the whole basis of the round trip.
function M.aRecordCanHaveAnArrayPart()
   local decl = table.concat({
      "local record Node",
      "    {Node}",
      "    kind: string",
      "end",
   }, "\n")
   assertEq(diagsOf(decl .. "\n" .. table.concat({
      'local n = new Node {kind = "if"}',
      'n[1] = new Node {kind = "x"}',
      "n[#n + 1] = n[1]",
      "local k: string = n[1].kind",
      "for _, child in ipairs(n) do print(child.kind) end",
   }, "\n")), "", "index, length, append and ipairs all work")
   -- and the element type is enforced
   assertEq(diagsOf(decl .. '\nlocal n = new Node {kind = "if"}\nn[1] = 5'),
      "NUPP2001")
end

function M.anArrayPartIsALuaThingSoAStructHasNone()
   assertEq(diagsOf("local struct P\n    {P}\n    x: float\nend"), "NUPP2204")
end

-- `x is T` as a return type says the function answers whether its parameter
-- is a T, which narrows the argument wherever the call is the condition.
function M.aPredicateNarrowsItsArgument()
   local decl = table.concat({
      "local record Tok",
      "    kind: string",
      "    text: string",
      "end",
      "local record Nd",
      "    kind: string",
      "end",
      "local type Child = Nd | Tok",
      "local function isTok(x: Child): x is Tok",
      "    return x is Tok",
      "end",
   }, "\n")
   assertEq(diagsOf(decl .. "\n" .. table.concat({
      "local function textOf(c: Child): string",
      "    if isTok(c) then",
      "        return c.text",
      "    end",
      "    return c.kind",
   }, "\n") .. "\nend"), "", "narrowed both ways")
   -- without the call there is no narrowing, and the field is not shared
   assertEq(diagsOf(decl .. "\nlocal function f(c: Child): string\n"
      .. "    return c.text\nend"), "NUPP2004")
end

function M.aPredicateMustNameAParameter()
   assertEq(diagsOf("local record R\n    x: integer\nend\n"
      .. "local function f(a: R): b is R\n    return true\nend"), "NUPP2109")
end

function M.aPredicateThatCanNeverHoldIsReported()
   assertEq(diagsOf("local record R\n    x: integer\nend\n"
      .. "local function f(a: string): a is R\n    return true\nend"),
      "NUPP2110")
end

-- Copying an integer into an inferred local keeps it an integer. Widening
-- there made `integer` unusable: every offset lost it on the first copy.
function M.anIntegerSurvivesAnInferredLocal()
   assertEq(diagsOf(table.concat({
      "local function f(pos: integer): integer",
      "    local start = pos",
      "    return start + 1",
      "end",
   }, "\n")), "")
   -- an integer *literal* still widens, so arithmetic on it stays open
   assertEq(diagsOf("local x = 1\nx = 1.5"), "")
end

-- A record's runtime table is its identity, so `is` compiles to a real test
-- rather than failing for want of one.
function M.recordIdentityCompiles()
   local code = generate(table.concat({
      "local record R",
      "    x: integer",
      "end",
      -- `any`, because a subject whose own type proves the answer is elided
      -- rather than tested, and it is the test being checked here
      "local v: any = new R {x = 1}",
      "print(v is R)",
   }, "\n"))
   assert(code:find("getmetatable", 1, true),
      "`is` on a record reaches the declaration through __index: " .. code)
end

-- A test the subject's own type already answers is not worth running, and an
-- optional's nil is the only part of that answer its declaration leaves open.
function M.aProvenIdentityIsNotTested()
   local code = generate(table.concat({
      "local record R",
      "    x: integer",
      "end",
      "local v = new R {x = 1}",
      "local maybe: R? = v",
      "print(v is R, maybe is R)",
   }, "\n"))
   assert(not code:find("getmetatable", 1, true),
      "neither test runs: " .. code)
   assert(code:find("maybe ~= nil", 1, true),
      "the optional still answers for its nil: " .. code)
end

-- The comma between two return types belongs to the annotation, so it has
-- to erase with it. Left behind it produced `function f ( ) ,`.
function M.multipleReturnAnnotationsErase()
   local code = generate(table.concat({
      "local function f(s: string): integer?, boolean",
      "    return #s, true",
      "end",
      "print(f('a'))",
   }, "\n"))
   assert(loadstring(code), "generated Lua parses: " .. code)
   assert(not code:find("%)%s*,"), "no orphan separator: " .. code)
end

-- A variable holds what was just written to it. Without this the common
-- `if not x then x = f() end` leaves x nilable forever.
function M.assignmentNarrowsToWhatWasWritten()
   assertEq(diagsOf(table.concat({
      "local function f(m: {[string]: integer}, k: string): integer",
      "    local hit = m[k]",
      "    if not hit then",
      "        hit = 0",
      "        return hit + 1",
      "    end",
      "    return hit",
      "end",
   }, "\n")), "", "hit is an integer once it has been written")
end

-- Truthiness of a field path is the same fact a plain name gives.
function M.aFieldPathNarrowsOnTruthiness()
   local decl = "local record R\n    xs: {integer}?\nend\n"
   assertEq(diagsOf(decl .. table.concat({
      "local function f(r: R): integer",
      "    if r.xs and #r.xs > 0 then",
      "        return r.xs[1]",
      "    end",
      "    return 0",
      "end",
   }, "\n")), "", "r.xs is not nil inside the guard")
   assertEq(diagsOf(decl .. "local function f(r: R): integer\n"
      .. "    return r.xs[1]\nend"), "NUPP2004", "and nilable without it")
end

-- Indexing a union indexes every member, which is what makes the `xs or {}`
-- default usable.
function M.aUnionIsIndexable()
   assertEq(diagsOf(table.concat({
      "local function f(xs: {integer}?): number",
      "    local all = xs or {}",
      "    return all[1] + 0",
      "end",
   }, "\n")), "")
end

-- A table written with string keys and one value type is a map of it.
function M.aStringKeyedTableIsAMap()
   assertEq(diagsOf("local m: {[string]: boolean} = {a = true, b = false}"), "")
   assertEq(diagsOf("local m: {[string]: boolean} = {a = true, b = 2}"),
      "NUPP2001", "a value of the wrong type still fails")
end

-- `local T = require("m")` makes T.Name mean a type from m, rather than
-- looking for a module actually called T.
function M.aModuleAliasResolvesTypes()
   local src = table.concat({
      'local L = require("nupp.compiler.lexer")',
      "local function kindOf(t: L.Token): string",
      "    return t.kind",
      "end",
      'print(kindOf({kind = "name", text = "x", offset = 1, line = 1,'
         .. " col = 1, trivia = {}}))",
   }, "\n")
   assertEq(diagsOf(src), "")
end

-- Writing nil to a table entry is how Lua removes it, so a container takes
-- nil whatever its element type says a present value holds. A record field
-- is not that: it is declared, and removing it would leave the type
-- describing something that is not there.
function M.writingNilRemovesAContainerEntry()
   assertEq(diagsOf(table.concat({
      "local xs: {integer} = {1, 2, 3}",
      "xs[3] = nil",
      "local m: {[string]: integer} = {}",
      'm["k"] = nil',
   }, "\n")), "")
   assertEq(diagsOf('local xs: {integer} = {1}\nxs[1] = "no"'), "NUPP2001",
      "a wrong type is still wrong")
   assertEq(diagsOf(table.concat({
      "local record R",
      "    x: integer",
      "end",
      "local r = new R {x = 1}",
      'r["x"] = nil',
   }, "\n")), "NUPP2004", "a record is not bracket-indexable to begin with")
   assertEq(diagsOf(table.concat({
      "local record R",
      "    x: integer",
      "end",
      "local r = new R {x = 1}",
      "r.x = nil",
   }, "\n")), "NUPP2001", "and a declared field cannot be removed")
end

-- Narrowing an assignment target has to happen after the assignment is
-- checked. Applied first, it compared the target against the very value
-- being written to it, and every field assignment passed.
function M.assignmentIsCheckedBeforeItNarrows()
   assertEq(diagsOf(table.concat({
      "local record R",
      "    x: integer",
      "end",
      "local r = new R {x = 1}",
      'r.x = "no"',
   }, "\n")), "NUPP2001")
   assertEq(diagsOf(table.concat({
      "local xs: {integer} = {}",
      'xs[1] = "no"',
   }, "\n")), "NUPP2001")
end

-- Narrowing survives the join. A variable assigned in one branch and ruled
-- out in the other is known afterwards to be neither nil nor unset.
function M.narrowingSurvivesABranchJoin()
   assertEq(diagsOf(table.concat({
      "local function f(m: {[string]: integer}, k: string): integer",
      "    local hit = m[k]",
      "    if not hit then",
      "        hit = 0",
      "    end",
      "    return hit",
      "end",
   }, "\n")), "", "the implicit else is a path like any other")
   assertEq(diagsOf(table.concat({
      "local function g(m: {[string]: integer}, k: string): integer",
      "    local hit = m[k]",
      "    if hit then",
      "        print(hit)",
      "    else",
      "        hit = 0",
      "    end",
      "    return hit",
      "end",
   }, "\n")), "", "both arms agree, so the join does too")
end

-- A branch that leaves does not reach the join, which is what makes a
-- guard clause narrow everything after it.
function M.aBranchThatLeavesDoesNotJoin()
   assertEq(diagsOf(table.concat({
      "local function f(m: {[string]: integer}, k: string): integer",
      "    local hit = m[k]",
      "    if not hit then return 0 end",
      "    return hit",
      "end",
   }, "\n")), "")
end

-- The join only knows what every path knows. A key one arm is silent
-- about could be anything there, so it stays at its declared type.
function M.theJoinIsConservative()
   assertEq(diagsOf(table.concat({
      "local function f(a: integer?, b: boolean): integer",
      "    if b then",
      "        a = 1",
      "    end",
      "    return a",
      "end",
   }, "\n")), "NUPP2002")
end

-- true and false are types. A function that returns a result or false is
-- a Lua idiom, and truth-testing one has to leave the result behind.
function M.falseIsAType()
   assertEq(diagsOf(table.concat({
      "local function find(s: string): integer | false",
      "    local at = s:find('b', 1, true)",
      "    if at then return at end",
      "    return false",
      "end",
      "local function use(s: string): integer",
      "    local at = find(s)",
      "    if at then",
      "        return at",
      "    end",
      "    return 0",
      "end",
   }, "\n")), "")
end

-- Falsy in Lua is nil or false and nothing else, so testing a boolean for
-- truth leaves the one value it can still be.
function M.truthNarrowsABoolean()
   assertEq(diagsOf(table.concat({
      "local function f(x: boolean): true",
      "    if x then",
      "        return x",
      "    end",
      "    return true",
      "end",
   }, "\n")), "")
   assertEq(diagsOf(table.concat({
      "local function f(x: boolean): false",
      "    if x then",
      "        return false",
      "    end",
      "    return x",
      "end",
   }, "\n")), "", "and the falsy side leaves the other")
end

-- add() gives back what it was given, so a named CST field keeps its own
-- type rather than widening to "node or token".
function M.aGenericFunctionPreservesItsArgumentType()
   assertEq(diagsOf(table.concat({
      "local record N",
      "    kind: string",
      "end",
      "local function keep<T>(x: T?): T?",
      "    return x",
      "end",
      "local n: N? = keep(new N {kind = 'a'})",
      "print(n and n.kind)",
   }, "\n")), "")
end

-- A type parameter fits everything while it is unsubstituted, so nothing
-- may quietly subtract it away: narrowing inside generic code has to leave
-- it standing.
function M.narrowingKeepsATypeParameter()
   assertEq(diagsOf(table.concat({
      "local record N",
      "    kind: string",
      "end",
      "local function first<T>(xs: {N}, x: T?): T?",
      "    if x ~= nil then",
      "        xs[#xs + 1] = new N {kind = 'a'}",
      "    end",
      "    return x",
      "end",
      "print(first({}, 1))",
   }, "\n")), "")
end

-- Dispatch loops are written by copying the discriminant out first. A test
-- on the copy has to narrow the value it came from, or per-kind types are
-- unusable in exactly the code that needs them.
function M.anAliasedDiscriminantNarrowsTheOriginal()
   local decl = table.concat({
      "local type IfStat = {kind: 'ifStat', cond: string}",
      "local type CallExpr = {kind: 'call', callee: string}",
      "local type Stat = IfStat | CallExpr",
   }, "\n")
   assertEq(diagsOf(decl .. "\n" .. table.concat({
      "local function describe(n: Stat): string",
      "    local kind = n.kind",
      "    if kind == 'ifStat' then",
      "        return n.cond",
      "    end",
      "    return n.callee",
      "end",
   }, "\n")), "", "narrowed through the copy, both ways")
   -- and the copy stops speaking for the value once either one moves
   assertEq(diagsOf(decl .. "\n" .. table.concat({
      "local function describe(n: Stat, other: Stat): string",
      "    local kind = n.kind",
      "    n = other",
      "    if kind == 'ifStat' then",
      "        return n.cond",
      "    end",
      "    return 'x'",
      "end",
   }, "\n")), "NUPP2107 NUPP2004",
      "a reassigned value is no longer described by it")
end

-- A named field keeps a string literal, which is the only way to build a
-- value of a discriminated union. Numbers widen: a counter initialized to
-- 1 is not a value of the type 1.
function M.aNamedFieldKeepsAStringDiscriminant()
   assertEq(diagsOf(table.concat({
      "local type Circle = {tag: 'circle', r: number}",
      "local type Square = {tag: 'square', side: number}",
      "local type Shape = Circle | Square",
      "local c: Shape = {tag = 'circle', r = 1}",
      "local q: Shape = {tag = 'square', side = 2}",
   }, "\n")), "")
   assertEq(diagsOf(table.concat({
      "local rec: {n: integer} = {n = 1}",
      "local function bump(r: {n: integer}, by: integer)",
      "    r.n = r.n + by",
      "end",
      "bump(rec, 2)",
   }, "\n")), "", "a number stays a number, not the one it started at")
end

-- An elseif chain over a copied discriminant has to keep narrowing past
-- the first arm: the narrowed copy still came from where it came from.
function M.anAliasedDiscriminantNarrowsThroughAChain()
   assertEq(diagsOf(table.concat({
      "local type A = {tag: 'a', x: string}",
      "local type B = {tag: 'b', y: string}",
      "local type C = {tag: 'c', z: string}",
      "local type U = A | B | C",
      "local function f(u: U): string",
      "    local tag = u.tag",
      "    if tag == 'a' then",
      "        return u.x",
      "    elseif tag == 'b' then",
      "        return u.y",
      "    end",
      "    return u.z",
      "end",
   }, "\n")), "")
end

-- Either side of an `or` may be the one that held, so the truthy side
-- knows the union of what each proves — and nothing about a reference
-- only one side mentions.
function M.orUnionsWhatBothSidesProve()
   assertEq(diagsOf(table.concat({
      "local type A = {tag: 'a', both: string}",
      "local type B = {tag: 'b', both: string}",
      "local type C = {tag: 'c', only: string}",
      "local type U = A | B | C",
      "local function f(u: U): string",
      "    if u.tag == 'a' or u.tag == 'b' then",
      "        return u.both",
      "    end",
      "    return u.only",
      "end",
   }, "\n")), "")
end

-- A sum type is mutually recursive by construction: each variant names the
-- union in its fields and the union names the variants, so neither can be
-- written first. Declarations are hoisted to the top of their block, which
-- is what makes one writable at all.
function M.declarationsAreHoisted()
   assertEq(diagsOf(table.concat({
      "local record Array",
      "    elem: Shape",
      "end",
      "local record Prim",
      "    name: string",
      "end",
      "local type Shape = Prim | Array",
      "local function describe(s: Shape): string",
      "    if s is Prim then",
      "        return s.name",
      "    end",
      "    return describe(s.elem)",
      "end",
   }, "\n")), "")
end

-- A declaration attached to a table answers to its simple name inside its own
-- body, so a recursive field does not have to repeat the table, and the name
-- does not leak out beside it.
function M.aQualifiedDeclarationNamesItselfInItsOwnBody()
   assertEq(diagsOf(table.concat({
      "local m = {}",
      "record m.Node",
      "    parent: Node?",
      "end",
      "return m",
   }, "\n")), "")
   assertEq(diagsOf(table.concat({
      "local m = {}",
      "record m.Node",
      "    kind: string",
      "end",
      "local stray: Node",
      "return m",
   }, "\n")), "NUPP2101")
end

-- A record body is where types nest, so it has to work through the table the
-- owner was attached to, `is` included: a nested record's runtime table hangs
-- off its owner's, and without that path `is` had no runtime identity at all.
function M.nestedTypesResolveThroughTheirOwnersTable()
   assertEq(diagsOf(table.concat({
      "local m = {}",
      "record m.Shapes",
      "    record Point",
      "        x: number",
      "    end",
      "    type Id = uint32",
      "end",
      "local p: m.Shapes.Point = new m.Shapes.Point {x = 1}",
      "local i: m.Shapes.Id = 1",
      "local ok: boolean = p is m.Shapes.Point",
      "return m",
   }, "\n")), "")
end

-- Hoisting reaches into a record namespace as well as hoisting the owner. This
-- matters when an earlier declaration describes a value using a nested type.
function M.nestedRecordsResolveBeforeTheirOwnersBody()
   assertEq(diagsOf(table.concat({
      "local m: {factory: m.Container.Factory}",
      "record m.Container",
      "    record Factory",
      "        create: function(): Container",
      "    end",
      "end",
   }, "\n")), "")
end

-- A declaration attaches to one table. A deeper path would bind the type under
-- one name and assign the runtime value to another, which silently stamped a
-- nil metatable.
function M.aDeclarationAttachesToOneTable()
   assertEq(diagsOf(table.concat({
      "local m = {}",
      "m.sub = {}",
      "record m.sub.Deep",
      "    id: uint32",
      "end",
      "return m",
   }, "\n")), "NUPP2119")
end

-- Methods attach through the whole path, the way the declaration was written.
function M.methodsAttachToAQualifiedRecord()
   assertEq(diagsOf(table.concat({
      "local m = {}",
      "record m.Counter",
      "    n: integer",
      "end",
      "function m.Counter:bump(): integer",
      "    return self.n + 1",
      "end",
      "local c: m.Counter = new m.Counter {n = 1}",
      "local got: integer = c:bump()",
      "return m",
   }, "\n")), "")
end

-- Hoisting must not make a self-referential alias loop forever.
function M.anAliasDefinedInTermsOfItselfIsReported()
   assertEq(diagsOf("local type A = B\nlocal type B = A\nlocal x: A = 1"),
      "NUPP2115")
end

-- Methods are hoisted too: their signatures are published before any body
-- is checked, so two that call each other can both be written plainly.
function M.methodsAreHoisted()
   assertEq(diagsOf(table.concat({
      "local record Walker",
      "    depth: integer",
      "end",
      "function Walker:enter(n: integer): integer",
      "    if n > 0 then",
      "        return self:leave(n - 1)",
      "    end",
      "    return self.depth",
      "end",
      "function Walker:leave(n: integer): integer",
      "    return self:enter(n)",
      "end",
   }, "\n")), "")
   -- and the signature published is the one the annotations give
   assertEq(diagsOf(table.concat({
      "local record W",
      "    n: integer",
      "end",
      "function W:a(): integer",
      "    return self:b('no')",
      "end",
      "function W:b(x: integer): integer",
      "    return x",
      "end",
   }, "\n")), "NUPP2006")
end

-- The CST is one record per production and `Node` is their union, so a pass
-- that dispatches on `kind` is checked against the vocabulary rather than
-- trusted with it: reading a field belonging to another kind is an error.
function M.perKindNodesAreADiscriminatedUnion()
   local cstModule = "local cst = require('nupp.compiler.cst')\n"
   assertEq(diagsOf(cstModule .. table.concat({
      "local function describe(n: cst.Node): string",
      "    local kind = n.kind",
      "    if kind == 'binop' then",
      "        local op = n.op",
      "        return op and op.text or '?'",
      "    elseif kind == 'name' then",
      "        local token = n.token",
      "        return token and token.text or '?'",
      "    end",
      "    return '?'",
      "end",
   }, "\n")), "", "each arm reaches the fields its own kind carries")
   -- a field that belongs to another kind is not there at all
   assertEq(diagsOf(cstModule .. table.concat({
      "local function describe(n: cst.Node): string",
      "    if n.kind == 'name' then",
      "        return n.lhs and 'x' or 'y'",
      "    end",
      "    return '?'",
      "end",
   }, "\n")), "NUPP2004", "a binop field is not readable on a name")
   -- and the array part is still every child, in source order
   assertEq(diagsOf(cstModule .. table.concat({
      "local function count(n: cst.Node): integer",
      "    local total: integer = 0",
      "    for _, child in ipairs(n) do",
      "        if not cst.isToken(child) then total = total + 1 end",
      "    end",
      "    return total",
      "end",
   }, "\n")), "")
end

return M
