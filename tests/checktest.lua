local parser = require("nupp.parser")
local check = require("nupp.check")
local T = require("nupp.types")
local relations = require("nupp.relations")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Runs the checker; returns the list of "CODE:line" strings.
local function diagsOf(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "test")
   local out = {}
   for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
   return table.concat(out, " "), diags
end

local function assertClean(src)
   local got, diags = diagsOf(src)
   assertEq(got, "", "expected clean check for:\n" .. src
      .. (diags[1] and ("\nfirst: " .. diags[1].msg) or ""))
end

local function applyFix(source, fix)
   local edits = {}
   for _, edit in ipairs(fix.edits or {}) do edits[#edits + 1] = edit end
   table.sort(edits, function(a, b) return a.offset > b.offset end)
   for _, edit in ipairs(edits) do
      source = source:sub(1, edit.offset - 1) .. edit.newText
         .. source:sub(edit.offset + edit.length)
   end
   return source
end

local M = {}

---------------------------------------------------------------------------
-- types.lua interning
---------------------------------------------------------------------------

function M.interningIdentity()
   assert(T.array(T.number) == T.array(T.number), "arrays interned")
   assert(T.optional(T.string) == T.union({ T.nil_, T.string }),
      "optional is canonical union")
   assert(T.union({ T.number, T.string }) == T.union({ T.string, T.number }),
      "unions canonicalized by order")
   assert(T.union({ T.number }) == T.number, "singleton union unwraps")
   assert(T.union({ T.number, T.union({ T.string, T.number }) })
      == T.union({ T.string, T.number }), "nested unions flatten+dedup")
   assert(T.shape({ { name = "x", type = T.number }, { name = "y", type = T.number } })
      == T.shape({ { name = "y", type = T.number }, { name = "x", type = T.number } }),
      "shapes canonicalized by field name")
   assert(T.nominal("A", "record") ~= T.nominal("A", "record"),
      "nominals get fresh identity")
end

function M.typeTostring()
   assertEq(T.tostring(T.optional(T.number)), "number?")
   assertEq(T.tostring(T.map(T.string, T.array(T.integer))),
      "{[string]: {integer}}")
   assertEq(T.tostring(T.func({ T.number }, { T.boolean }, false)),
      "function(number): boolean")
end

---------------------------------------------------------------------------
-- relations.lua
---------------------------------------------------------------------------

function M.subtypingRules()
   local isA = relations.isA
   assert(isA(T.integer, T.number))
   assert(isA(T.int64, T.integer))
   assert(not isA(T.number, T.integer))
   assert(isA(T.string, T.optional(T.string)))
   assert(isA(T.nil_, T.optional(T.string)))
   assert(not isA(T.optional(T.string), T.string))
   assert(isA(T.array(T.integer), T.array(T.number)))
   assert(isA(T.array(T.number), T.table_))
   -- width subtyping: wider shape fits narrower
   local wide = T.shape({ { name = "x", type = T.number },
      { name = "y", type = T.number } })
   local narrow = T.shape({ { name = "x", type = T.number } })
   assert(isA(wide, narrow))
   assert(not isA(narrow, wide))
   -- nominal-to-shape erosion, never the reverse
   local rec = T.nominal("P", "record")
   rec.byname = { x = T.number, y = T.number }
   assert(isA(rec, narrow))
   assert(not isA(narrow, rec))
   -- functions: contravariant params, covariant returns
   local takesNum = T.func({ T.number }, { T.integer }, false)
   local takesInt = T.func({ T.integer }, { T.number }, false)
   assert(isA(takesNum, takesInt))
   assert(not isA(takesInt, takesNum))
end

-- `unknown` is the top type: everything fits into it, but -- unlike `any` --
-- it does not fit anywhere else on its own. It is not gradual in `any`'s
-- sense; only the one direction is free.
function M.unknownIsTheTopType()
   local isA = relations.isA
   assert(isA(T.integer, T.unknown))
   assert(isA(T.string, T.unknown))
   assert(isA(T.nil_, T.unknown))
   assert(isA(T.func({ T.number }, { T.boolean }, false), T.unknown))
   assert(not isA(T.unknown, T.integer))
   assert(not isA(T.unknown, T.string))
   assert(isA(T.unknown, T.unknown))
   -- any remains bidirectional, including against unknown
   assert(isA(T.any, T.unknown))
   assert(isA(T.unknown, T.any))
end

-- `never` is the bottom type: uninhabited, so it fits anywhere any type is
-- wanted, and nothing but itself fits into it.
function M.neverIsTheBottomType()
   local isA = relations.isA
   assert(isA(T.never, T.integer))
   assert(isA(T.never, T.string))
   assert(isA(T.never, T.unknown))
   assert(isA(T.never, T.never))
   assert(not isA(T.integer, T.never))
   assert(not isA(T.string, T.never))
   assert(not isA(T.nil_, T.never))
end

---------------------------------------------------------------------------
-- checker
---------------------------------------------------------------------------

function M.andOrIdioms()
   assertClean("local flag: boolean\nlocal n: number = flag and 1 or 2")
   assertClean("local m: number?\nlocal n: number = m or 0")
   -- NOTE: "s and s .. '!' or 'none'" with s: string? needs narrowing to
   -- check cleanly; restored when the facts engine lands.
end

function M.cleanPrograms()
   assertClean("local x: number = 1 + 2")
   assertClean("local s: string = 'a' .. 1")
   assertClean("local n: integer = 7 // 2")
   assertClean("local b: boolean = 1 < 2")
   assertClean("local o: number? = nil")
   assertClean("local u: number | string = 'hi'")
   assertClean("local f = function(x: number): number return x * 2 end\nlocal y: number = f(3)")
   assertClean("local t: {number} = {1, 2, 3}")
   assertClean("local m: {[string]: number} = {}")
   assertClean("local p: {x: number, y: number} = {x = 1, y = 2}")
   assertClean("local a: any = 'whatever'\nlocal n: number = a")
   assertClean("local big: int64 = 10LL\nlocal n: number = big")
end

function M.inheritedContractsBoundsAndSelf()
   local src = table.concat({
      "local interface Component",
      "   componentName: string",
      "   metamethod __call: function(self, ...: any): self",
      "end",
      "local interface Tagged",
      "   tag: string",
      "end",
      "local record Position is Component, Tagged",
      "   x: number",
      "end",
      "local function construct<C is Component>(c: C): C",
      "   local name: string = c.componentName",
      "   return c()",
      "end",
      "local made: Position = construct(Position)",
      "local tag: string = made.tag",
   }, "\n")
   assertClean(src)
   assertEq((diagsOf(src .. table.concat({
      "",
      "local record Plain end",
      "local bad = construct(Plain)",
   }, "\n"))), "NUPP2116:18")
end

function M.genericIndexContracts()
   assertClean(table.concat({
      "local record Key<T> end",
      "local record Store",
      "   metamethod __index: function<T>(self, key: Key<T>): T",
      "   metamethod __newindex: function<T>(self, key: Key<T>, value: T)",
      "end",
      "local store: Store",
      "local key: Key<string>",
      "local value: string = store[key]",
      "store[key] = 'saved'",
   }, "\n"))
end

function M.arithmeticAndLengthContracts()
   assertClean(table.concat({
      "local record I64",
      "   metamethod __add: function(self: I64, other: I64): I64",
      "end",
      "local a, b: I64, I64",
      "local c: I64 = a + b",
   }, "\n"))
   assertEq((diagsOf("local n = #true")), "NUPP2003:1")
   assertEq((diagsOf("local record A end\nlocal record B end\nlocal x: A\nlocal y: B\nprint(x < y)")),
      "NUPP2003:5")
end

function M.metatableTypeIsACompilerKnownPhantom()
   assertClean(table.concat({
      "local record R end",
      "local mt: metatable<R> = {__index = {}}",
      "local r: R",
      "setmetatable(r, mt)",
      "setmetatable(r, nil)",
   }, "\n"))
end

function M.inlineMethodsAreHoistedAndNestedAliasesAreQualified()
   assertClean(table.concat({
      "local record Types",
      "   type Id = integer",
      "   record Counter",
      "      value: Types.Id",
      "      function even(n: integer): boolean",
      "         if n == 0 then return true end",
      "         return self:odd(n - 1)",
      "      end",
      "      function odd(n: integer): boolean",
      "         if n == 0 then return false end",
      "         return self:even(n - 1)",
      "      end",
      "   end",
      "end",
      "local id: Types.Id = 1",
      "local counter: Types.Counter",
      "local yes: boolean = counter:even(id)",
   }, "\n"))
end

function M.recordsWorkWithPairsAndMetatableTyposAreRejected()
   assertClean(table.concat({
      "local record R",
      "   value: number",
      "end",
      "local r: R",
      "for key, value in pairs(r) do print(key, value) end",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local record R end",
      "local r: R",
      "setmetatable(r, {__cal = function() end})",
   }, "\n"))), "NUPP2118:3")
end

function M.metamethodTyposCarrySafeFixes()
   local literal = table.concat({
      "local record R end",
      "local r: R",
      "setmetatable(r, {__cal = function() end})",
   }, "\n")
   local _, literalDiags = diagsOf(literal)
   local literalFixes = literalDiags[1] and literalDiags[1].fixes
   assertEq(literalFixes and #literalFixes or 0, 1,
      "one runtime metamethod spelling is uniquely closest")
   assertEq(literalFixes[1].title, "change to `__call`")
   assertClean(applyFix(literal, literalFixes[1]))

   local contract = table.concat({
      "local record R",
      "   metamethod __idnex: function(self, key: any): any",
      "end",
   }, "\n")
   local _, contractDiags = diagsOf(contract)
   local contractFixes = contractDiags[1] and contractDiags[1].fixes
   assertEq(contractFixes and #contractFixes or 0, 1,
      "an adjacent transposition has one contract fix")
   assertEq(contractFixes[1].title, "change to `__index`")
   assertClean(applyFix(contract, contractFixes[1]))

   local missingPrefix = table.concat({
      "local record R",
      "   metamethod index: function(self, key: any): any",
      "end",
   }, "\n")
   local _, prefixDiags = diagsOf(missingPrefix)
   local prefixFixes = prefixDiags[1] and prefixDiags[1].fixes
   assertEq(prefixFixes and #prefixFixes or 0, 1,
      "a known contract missing its prefix has one fix")
   assertClean(applyFix(missingPrefix, prefixFixes[1]))

   local runtimeOnly = table.concat({
      "local record R",
      "   metamethod __mode: function(self): string",
      "end",
   }, "\n")
   local _, unsupported = diagsOf(runtimeOnly)
   assert(not unsupported[1].fixes,
      "a valid runtime-only key is unsupported, not misspelled")
end

function M.unsupportedAndDuplicateContractsAreRejected()
   assertEq((diagsOf(table.concat({
      "local record R",
      "   metamethod __band: function(self, other: self): self",
      "end",
   }, "\n"))), "NUPP2118:2")
   assertEq((diagsOf(table.concat({
      "local record R",
      "   value: number",
      "   function value(): number return 1 end",
      "end",
   }, "\n"))), "NUPP2118:3")
end

function M.mismatchDiagnostics()
   assertEq((diagsOf("local x: number = 'oops'")), "NUPP2001:1")
   assertEq((diagsOf("local x: string\nx = 42")), "NUPP2001:2")
   assertEq((diagsOf("local x: integer = 1.5")), "NUPP2001:1")
   assertEq((diagsOf("local o: number? = 'no'")), "NUPP2001:1")
end

function M.constBindings()
   assertClean("const x: number = 1\nlocal y: number = x")
   assertClean("const t = {}\nt.value = 1")
   assertClean("local x = 1\ndo const x = 2 end")
   assertClean("const function f(n: number): number return n end\nf(1)")

   assertEq((diagsOf("const x = 1\nx = 2")), "NUPP2008:2")
   assertEq((diagsOf("const x = 1\nx += 2")), "NUPP2008:2")
   assertEq((diagsOf("const x\nx ??= 2")), "NUPP2008:2")
   assertEq((diagsOf("const x = 1\nlocal x = 2")), "NUPP2008:2")
   assertEq((diagsOf("const x = 1\ndo local x = 2 end")), "NUPP2008:2")
   assertEq((diagsOf("const x = 1\nlocal function f(x) end")),
      "NUPP2008:2")
   assertEq((diagsOf("const x = 1\nfor x = 1, 2 do end")), "NUPP2008:2")
   assertEq((diagsOf("const x = 1\nlocal f = x -> x")), "NUPP2008:2")
   assertEq((diagsOf("const function f() end\nf = nil")), "NUPP2008:2")
end

function M.namedVarargsAreConst()
   assertClean("local function f(...args) return args.n, args[1], ... end")
   assertClean("local f = |...args| -> args.n")
   assertEq((diagsOf("local function f(...args) args = {} end")),
      "NUPP2008:1")
   assertEq((diagsOf("local f = |...args| -> do\nlocal args = {}\nend")),
      "NUPP2008:2")
end

function M.operatorDiagnostics()
   assertEq((diagsOf("local x = 'a' + 1")), "NUPP2003:1")
   assertEq((diagsOf("local x = {} .. 'b'")), "NUPP2003:1")
   -- Lua would coerce '1' + 1 at runtime; the checker still flags it
   assertEq((diagsOf("local x = '1' + 1")), "NUPP2003:1")
end

function M.returnChecking()
   assertEq((diagsOf("local function f(): number return 'no' end")),
      "NUPP2002:1")
   assertEq((diagsOf("local function f(): number return 1, 2 end")),
      "NUPP2002:1")
   assertClean("local function f(): number, string return 1, 'ok' end")
   -- missing return value against an annotation
   assertEq((diagsOf("local function f(): number return end")),
      "NUPP2002:1")
end

function M.callChecking()
   local callSource = "local f = function(n: number) end\nf('x')"
   local code, callDiags = diagsOf(callSource)
   assertEq(code, "NUPP2006:2")
   assertEq(#(callDiags[1].related or {}), 1,
      "bad argument points back to the callable declaration")
   assert(callDiags[1].help:find("parameter list", 1, true),
      "bad call says what to compare")
   assertEq((diagsOf(
      "local f = function(n: number) end\nf(1, 2)")), "NUPP2007:2")
   assertEq((diagsOf("local n: number = 1\nn(2)")), "NUPP2005:2")
   assertClean("local f = function(...: number): number return 0 end\nf(1, 2, 3)")
end

function M.fieldChecking()
   assertEq((diagsOf(
      "local p: {x: number} = {x = 1}\nlocal y = p.nope")), "NUPP2004:2")
   assertClean("local p: {x: number} = {x = 1}\nlocal y: number = p.x")
   assertClean("local m: {[string]: number} = {}\nlocal v: number? = m['k']")
   assertEq((diagsOf(
      "local a: {number} = {}\nlocal v = a['k']")), "NUPP2004:2")
end

function M.identifierTyposCarryUnambiguousFixes()
   local fieldSource = table.concat({
      "local p: {horizontal: number} = {horizontal = 1}",
      "local value = p.horizonal",
   }, "\n")
   local _, fieldDiags = diagsOf(fieldSource)
   local fieldFix = fieldDiags[1] and fieldDiags[1].fixes
      and fieldDiags[1].fixes[1]
   assert(fieldFix, "field typo has a fix")
   assertEq(fieldFix.title, "change to `horizontal`")
   assertClean(applyFix(fieldSource, fieldFix))
   assertEq(fieldDiags[1].col, 17, "diagnostic points at the member")
   assertEq(fieldDiags[1].length, #"horizonal", "member span")

   local typeSource = "local value: stirng = 'x'"
   local _, typeDiags = diagsOf(typeSource)
   local typeFix = typeDiags[1] and typeDiags[1].fixes
      and typeDiags[1].fixes[1]
   assert(typeFix, "type typo has a fix")
   assertClean(applyFix(typeSource, typeFix))
end

function M.recordDeclarationsCheck()
   assertClean(table.concat({
      "local record Point",
      "   x: number",
      "   y: number",
      "end",
      "local p: Point",
      "local n: number? = p?.x",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local record Point",
      "   x: number",
      "end",
      "local p: Point",
      "local v = p.z",
   }, "\n"))), "NUPP2004:5")
end

function M.nominalProvenance()
   -- same shape, different declarations: not interchangeable
   assertEq((diagsOf(table.concat({
      "local record A",
      "   v: number",
      "end",
      "local record B",
      "   v: number",
      "end",
      "local a: A",
      "local b: B = a",
   }, "\n"))), "NUPP2001:8")
   -- but a record erodes to a matching structural shape
   assertClean(table.concat({
      "local record A",
      "   v: number",
      "end",
      "local a: A",
      "local s: {v: number} = a",
   }, "\n"))
end

function M.typeAliasAndLiteralUnionCheck()
   assertClean(
      "local type Id = uint32\nlocal i: Id = 7\nlocal n: number = i")
   assertClean(
      "local type Color = 'red' | 'green'\nlocal c: Color\nlocal s: string = c")
end

function M.unknownTypeNames()
   assertEq((diagsOf("local x: Wat = 1")), "NUPP2101:1")
end

function M.shortFunctionsTyped()
   assertClean("local dbl = |x: number| -> x * 2\nlocal n: number = dbl(3)")
   assertEq((diagsOf(
      "local dbl = |x: number| -> x * 2\ndbl('a')")), "NUPP2006:2")
   assertClean("local always = || -> true\nlocal b: boolean = always()")
   assertClean("local blocky = |x: number| -> do return x end\nblocky(1)")
   -- single-parameter sugar; the return type is inferred from the body
   assertClean("local neg = n -> -n\nneg(5)")
end

function M.interpolatedStringsTyped()
   assertClean("local n = 3\nlocal s: string = `n is ${n}, twice is ${n * 2}`")
   assertEq((diagsOf("local x: number = `just text ${1}`")), "NUPP2001:1")
   -- errors inside interpolations are still found
   assertEq((diagsOf("local s = `bad: ${'a' + 1}`")), "NUPP2003:1")
end

function M.castsAreTrusted()
   assertClean("local a: any\nlocal n: number = a as number")
   assertClean("local x: number = ('5' as any) as number")
end

function M.gradualDefaults()
   -- unannotated and unknown things check silently
   assertClean("print(unknown_global.deep.chain(1, 2))")
   assertClean("local x = some_global\nx = 5\nx = 'string'")
   -- inferred table literals stay open (module-table idiom);
   -- annotated shapes are closed
   assertClean("local M = {a = 1}\nM.b = 2\nlocal x = M.b")
   assertEq((diagsOf(
      "local M: {a: number} = {a = 1}\nlocal x = M.b")), "NUPP2004:2")
   -- inferred bindings widen; annotated bindings stay exact
   assertClean("local i = 1\ni = i / 2")
   assertClean("local x = nil\nx = {}\nlocal v = x.field")
   assertEq((diagsOf("local i: integer\ni = 1.5")), "NUPP2001:2")
   -- disabling an inferred local function is legal; an annotated one is not
   assertClean("local function f() end\nf = nil")
   assertEq((diagsOf(
      "local f: function() = function() end\nf = nil")), "NUPP2001:2")
end

-- `unknown` accepts anything, but using one without narrowing or casting
-- first is an ordinary type error -- the same one any other mismatched type
-- would get, since nothing in the checker gives `unknown` a pass the way it
-- does `any`.
function M.unknownNeedsNarrowingOrACast()
   assertClean("local a: unknown = 5")
   assertClean("local b: unknown = 'text'")
   assertEq((diagsOf("local a: unknown = 5\nlocal s: string = a")),
      "NUPP2001:2")
   assertEq((diagsOf("local a: unknown = 5\nprint(a.field)")), "NUPP2004:2")
   assertEq((diagsOf("local a: unknown = 5\nprint(a + 1)")), "NUPP2003:2")
   assertClean("local a: unknown = 5\nlocal s = a as string\nprint(s)")
   assertClean(table.concat({
      "local record P",
      "   x: integer",
      "end",
      "local a: unknown = P{x = 1}",
      "if a is P then print(a.x) end",
   }, "\n"))
end

-- `never` is what a function that always raises returns; declaring it lets
-- the checker catch a path that returns after all, the same way any other
-- return-type mismatch is caught.
function M.neverAsAReturnType()
   assertClean(table.concat({
      "local function bail(msg: string): never",
      "   error(msg)",
      "end",
      "print(bail)",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local function bail(x: integer): never",
      "   if x > 0 then return end",
      "   error('no')",
      "end",
      "print(bail)",
   }, "\n"))), "NUPP2002:2")
   -- a never-returning call leaves the block, narrowing what follows
   assertClean(table.concat({
      "local function bail(msg: string): never",
      "   error(msg)",
      "end",
      "local function use(s: string?)",
      "   if not s then bail('missing') end",
      "   print(#s)",
      "end",
      "print(use)",
   }, "\n"))
end

-- The grammar carries `where`, the formatter keeps it and `nupp doc` renders it
-- into a signature, and no checker code reads the expression. A constraint that
-- constrains nothing is worth a diagnostic rather than a footnote.
function M.whereRefinementsReportThatTheyAreUnchecked()
   assertEq((diagsOf("local record Odd where 1 + 1 == 3\n   n: integer\nend")),
      "NUPP2122:1")
   assertEq((diagsOf("local struct S where false\n   x: float\nend")),
      "NUPP2122:1")
   assertEq((diagsOf("local interface I where true\n   n: integer\nend")),
      "NUPP2122:1")
   assertClean("local record Even\n   n: integer\nend")
end

return M
