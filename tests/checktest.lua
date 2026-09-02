local parser = require("nupp.compiler.parser")
local check = require("fragment")
local T = require("nupp.compiler.types")
local relations = require("nupp.compiler.relations")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Runs the checker; returns the list of "CODE:line" strings.
local function diagsOf(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "test.g.nupp")
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
   local packVar = T.packvar("A", "test-pack")
   local pack = T.pack({}, {kind = "generic", var = packVar})
   assertEq(T.tostring(T.func({}, {}, true, nil, nil, nil, nil, nil,
      nil, nil, nil, nil, nil, pack, pack, {packVar})),
      "function<A...>(A...): (A...)")
   assertEq(T.tostring(T.indexer(T.string, T.string, T.string, T.number)),
      "{readonly [string]: string, writeonly [string]: number}")
   assertEq(T.tostring(T.shape({{name = "value", read = T.string,
      write = T.number}})),
      "{readonly value: string, writeonly value: number}")
   assertEq(T.tostring(T.tuple({T.string})), "{string,}")
   assertEq(T.tostring(T.array(T.string)), "{string}")
end

-- A string literal's type is the string it denotes, not the source that spells
-- it, so a spelling is only ever a way of writing bytes: the annotation and the
-- initializer below are the same type because they are the same one byte. A type
-- is also printed -- into a diagnostic, into --json, into a hover -- so it is
-- rendered back as a spelling that stays on one line and in ASCII.
function M.aStringLiteralTypeIsTheBytesItDenotes()
   assertClean([[local a: "\65" = "A"]] .. "\nprint(a)")
   assertClean([[local b: "A" = "\65"]] .. "\nprint(b)")
   assertEq(diagsOf([[local c: "\65" = "\\65"]] .. "\nprint(c)"), "NUPP2001:1",
      "three characters are not the one byte they spell")
   assertEq(T.tostring(T.literal("\1\255a\nb", T.string)), '"\\1\\255a\\nb"')
   assertEq(T.tostring(T.literal("\0" .. "12", T.string)), '"\\00012"',
      "a numeric escape is padded where a digit follows it")
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
   rec.writeByname = { x = T.number, y = T.number }
   assert(isA(rec, narrow))
   assert(not isA(narrow, rec))
   -- functions: contravariant params, covariant returns
   local takesNum = T.func({ T.number }, { T.integer }, false)
   local takesInt = T.func({ T.integer }, { T.number }, false)
   assert(isA(takesNum, takesInt))
   assert(not isA(takesInt, takesNum))
end

function M.arrayCovarianceCannotLaunderFunctionEffects()
   assertEq(diagsOf(table.concat({
      "local safe: {nosuspend function(number): number} = {math.floor}",
      "local calls: {function(number): number} = safe",
      "return calls",
   }, "\n")), "NUPP2001:2")
end

function M.unboundGenericParametersAreNotGradual()
   assertEq(diagsOf(table.concat({
      "local function readAsString<T>(value: T): string",
      "   local text: string = value",
      "   return text",
      "end",
      "local function invent<T>(): T",
      "   return 5",
      "end",
      "return readAsString, invent",
   }, "\n")), "NUPP2001:2 NUPP2002:6")

   assertEq(diagsOf(table.concat({
      "local function id<T>(value: T): T return value end",
      "local number: number = id(nil)",
      "return number",
   }, "\n")), "NUPP2001:2")
end

function M.logicalOperatorsKeepTheSelectedFalsyValue()
   assertEq(diagsOf(table.concat({
      "local flag: boolean = nil as any",
      "local text: string = flag and 'ready'",
      "return text",
   }, "\n")), "NUPP2001:2")
end

function M.assertRemovesFalseFromItsResult()
   assertClean(table.concat({
      "local impossible: never = assert(false)",
      "return impossible",
   }, "\n"))
end

function M.callsInvalidateNarrowingThroughMutationAndCapture()
   assertEq(diagsOf(table.concat({
      "local record Box",
      "   name: string?",
      "end",
      "local function clear(box: Box): nil box.name = nil end",
      "local box = new Box(name = 'ready')",
      "if box.name then",
      "   clear(box)",
      "   local text: string = box.name",
      "end",
      "return box",
   }, "\n")), "NUPP2001:8")

   assertEq(diagsOf(table.concat({
      "local value: string? = 'ready'",
      "local function clear(): nil value = nil end",
      "if value then",
      "   clear()",
      "   local text: string = value",
      "end",
      "return value",
   }, "\n")), "NUPP2001:5")

   assertEq(diagsOf(table.concat({
      "local value: string? = 'ready'",
      "local clear = function(): nil value = nil end",
      "if value then",
      "   clear()",
      "   local text: string = value",
      "end",
      "return value",
   }, "\n")), "NUPP2001:5")

   assertEq(diagsOf(table.concat({
      "local record Box",
      "   name: string?",
      "end",
      "function Box:clear(): nil self.name = nil end",
      "local box = new Box(name = 'ready')",
      "if box.name then",
      "   box:clear()",
      "   local text: string = box.name",
      "end",
      "return box",
   }, "\n")), "NUPP2001:8")
end

function M.aliasWritesInvalidateFieldNarrowing()
   assertEq(diagsOf(table.concat({
      "local record Box",
      "   name: string?",
      "end",
      "local box = new Box(name = 'ready')",
      "local alias = box",
      "if box.name then",
      "   alias.name = nil",
      "   local text: string = box.name",
      "end",
      "return box",
   }, "\n")), "NUPP2001:8")
end

function M.unreifiedInterfaceTestsFailDuringCheck()
   assertEq(diagsOf(table.concat({
      "local interface Drawable",
      "   width: number",
      "end",
      "local value: any = nil",
      "return value is Drawable",
   }, "\n")), "NUPP3001:5")
end

function M.constArraysRemainReadableViews()
   assertClean(table.concat({
      "local values: const {string} = {'a', 'b'}",
      "local lookup: const {[string]: integer} = {a = 1}",
      "local count: integer = #values",
      "local first: string = values[1]",
      "for index, value in ipairs(values) do",
      "   local i: integer = index",
      "   local s: string = value",
      "end",
      "for key, value in pairs(lookup) do",
      "   local k: string = key",
      "   local n: integer = value",
      "end",
      "local found: integer? = lookup['a']",
      "return count, first, found",
   }, "\n"))
   assertEq(diagsOf(table.concat({
      "local values: const {string} = {'a'}",
      "values[1] = 'b'",
   }, "\n")), "NUPP2009:2")
end

function M.propertyCapabilities()
   assertClean(table.concat({
      "local type Animal = string | integer",
      "local record Cell",
      "   readonly value: string",
      "   writeonly value: Animal",
      "   readonly [string]: string",
      "   writeonly [string]: Animal",
      "end",
      "local cell = new Cell(value = 'ready')",
      "cell.value = 1",
      "local value: string = cell.value",
      "cell['answer'] = 42",
      "local indexed: string? = cell['answer']",
      "local readView: {readonly value: Animal} = cell",
      "local writeView: {writeonly value: string} = cell",
      "return {value, indexed, readView, writeView}",
   }, "\n"))

   local denied, details = diagsOf(table.concat({
      "local readView: {readonly value: string} = {value = 'x'}",
      "local writeView: {writeonly value: string} = {}",
      "readView.value = 'y'",
      "local value = writeView.value",
      "readView.value ..= 'z'",
   }, "\n"))
   assertEq(denied, "NUPP2009:3 NUPP2009:4 NUPP2009:5")
   assert(details[1].help and details[1].help:match("write access"))

   local variance = diagsOf(table.concat({
      "local type Animal = string | integer",
      "local readString: {readonly value: string} = {value = 'x'}",
      "local readAnimal: {readonly value: Animal} = {value = 'x'}",
      "local writeString: {writeonly value: string} = {}",
      "local writeAnimal: {writeonly value: Animal} = {}",
      "local ordinaryString: {value: string} = {value = 'x'}",
      "local okRead: {readonly value: Animal} = readString",
      "local okWrite: {writeonly value: string} = writeAnimal",
      "local badRead: {readonly value: string} = readAnimal",
      "local badWrite: {writeonly value: Animal} = writeString",
      "local badOrdinary: {value: Animal} = ordinaryString",
   }, "\n"))
   assertEq(variance, "NUPP2001:9 NUPP2001:10 NUPP2001:11")

   assertClean(table.concat({
      "local type Animal = string | integer",
      "local readIndex: {readonly [string]: string} = {}",
      "local writeIndex: {writeonly [string]: Animal} = {}",
      "local widerRead: {readonly [string]: Animal} = readIndex",
      "local narrowerWrite: {writeonly [string]: string} = writeIndex",
      "return {widerRead, narrowerWrite}",
   }, "\n"))

   assertEq(diagsOf(table.concat({
      "local record Bad",
      "   readonly value: string",
      "   readonly value: integer",
      "end",
   }, "\n")), "NUPP2118:3")
   assertEq(diagsOf(table.concat({
      "local struct Bad",
      "   readonly value: int32",
      "end",
   }, "\n")), "NUPP2118:2")

   assertClean(table.concat({
      "local out: {writeonly value: string} | {writeonly value: string | integer}",
      "out.value = 'ready'",
   }, "\n"))
   assertEq(diagsOf(table.concat({
      "local out: {writeonly value: string} | {writeonly value: string | integer}",
      "out.value = 42",
   }, "\n")), "NUPP2001:2")
end

function M.constTableFieldsAreReadOnly()
   assertClean(table.concat({
      "local M = {}",
      "const M.bar = {",
      "   const BAZ = 123,",
      "   const nested = {const name = 'nupp'},",
      "}",
      "return M",
   }, "\n"))

   assertEq(diagsOf(table.concat({
      "local M = {}",
      "const M.bar = {",
      "   const BAZ = 123,",
      "   const nested = {const name = 'nupp'},",
      "}",
      "M.bar.BAZ = 456",
      "M.bar.nested.name = 'lua'",
      "M.bar.BAZ += 1",
      "return M",
   }, "\n")), "NUPP2008:6 NUPP2008:7 NUPP2008:8")

   assertEq(diagsOf(table.concat({
      "local M = {}",
      "const... M.bar = {BAZ = 123, nested = {name = 'nupp'}}",
      "M.bar.BAZ = 456",
      "M.bar.nested.name = 'lua'",
      "return M",
   }, "\n")), "NUPP2008:3 NUPP2008:4")
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

-- A computed key settles what a table constructor's type is -- a generic table --
-- and says nothing about the entries standing after it. Those used to go
-- unvisited, so anything wrong in one went unreported and anything the generator
-- needed the checker to resolve was never resolved.
function M.entriesAfterAComputedKeyAreStillChecked()
   assertEq((diagsOf("local t = {['a'] = 1, ['b'] = 'no' + 1}")), "NUPP2003:1")
   assertEq((diagsOf("local t = {['a'] = 1, b = 'no' + 1}")), "NUPP2003:1")
   assertEq((diagsOf("local t = {['a'] = 1, 'no' + 1}")), "NUPP2003:1")
   -- Every entry, not only the one after the first computed key.
   assertEq((diagsOf("local t = {['a'] = 1, ['b'] = 'no' + 1, ['c'] = 'no' + 1}")),
      "NUPP2003:1 NUPP2003:1")
   assertClean("local t = {['a'] = 1, ['b'] = 2}")
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
      -- the argument is the declaration's visible Type<C> witness;
      -- calling it runs the __call the bound declares and yields an instance
      "local function construct<C is Component>(c: Type<C>): C",
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
      "local store: Store = new Store()",
      "local key: Key<string> = new Key()",
      "local value: string = store[key]",
      "store[key] = 'saved'",
   }, "\n"))
end

function M.operatorContracts()
   local function binaryContract(metamethod, operator)
      assertClean(table.concat({
         "local record Result end",
         "local record Right end",
         "local record Left",
         ("   metamethod %s: function(left: Left, right: Right): Result")
            :format(metamethod),
         "end",
         "local left, right: Left, Right = new Left(), new Right()",
         ("local result: Result = left %s right"):format(operator),
      }, "\n"))
   end

   binaryContract("__add", "+")
   binaryContract("__sub", "-")
   binaryContract("__mul", "*")
   binaryContract("__div", "/")
   binaryContract("__mod", "%")
   binaryContract("__pow", "^")
   binaryContract("__concat", "..")

   assertClean(table.concat({
      "local record Result end",
      "local record Operand",
      "   metamethod __unm: function(operand: Operand): Result",
      "end",
      "local operand: Operand = new Operand()",
      "local result: Result = -operand",
   }, "\n"))

   -- Lua consults the right operand when the left has no matching contract,
   -- but the contract still receives operands in source order.
   assertClean(table.concat({
      "local record Result end",
      "local record Scale",
      "   metamethod __mul: function(left: number, right: Scale): Result",
      "end",
      "local scale: Scale = new Scale()",
      "local result: Result = 2 * scale",
   }, "\n"))

   local function comparisonContract(metamethod, operator, contractOnRight)
      local contract = ("   metamethod %s: function(left: %s, right: %s): boolean")
         :format(metamethod,
            contractOnRight and "Right" or "Left",
            contractOnRight and "Left" or "Right")
      local left = contractOnRight and "local record Left end" or table.concat({
         "local record Left",
         contract,
         "end",
      }, "\n")
      local right = contractOnRight and table.concat({
         "local record Right",
         contract,
         "end",
      }, "\n") or "local record Right end"
      assertClean(table.concat({
         left,
         right,
         "local left, right: Left, Right = new Left(), new Right()",
         ("local result: boolean = left %s right"):format(operator),
      }, "\n"))
   end

   comparisonContract("__lt", "<", false)
   comparisonContract("__lt", ">", true)
   comparisonContract("__le", "<=", false)
   comparisonContract("__le", ">=", true)

   -- Lua implements <= without __le as not (right < left), including the
   -- corresponding operand reversal.
   comparisonContract("__lt", "<=", true)

   assertEq((diagsOf("local n = #true")), "NUPP2003:1")
   assertEq((diagsOf("local record A end\nlocal record B end\nlocal x: A = new A()\nlocal y: B = new B()\nprint(x < y)")),
      "NUPP2003:5")
end

function M.metatableTypeIsACompilerKnownPhantom()
   assertClean(table.concat({
      "local record R end",
      "local mt: metatable<R> = {__index = {}}",
      "local r: R = new R()",
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
      "      function even(self, n: integer): boolean",
      "         if n == 0 then return true end",
      "         return self:odd(n - 1)",
      "      end",
      "      function odd(self, n: integer): boolean",
      "         if n == 0 then return false end",
      "         return self:even(n - 1)",
      "      end",
      "   end",
      "end",
      "local id: Types.Id = 1",
      "local counter: Types.Counter = new Types.Counter()",
      "local yes: boolean = counter:even(id)",
   }, "\n"))
end

function M.recordsWorkWithPairsAndMetatableTyposAreRejected()
   assertClean(table.concat({
      "local record R",
      "   value: number",
      "end",
      "local r: R = new R()",
      "for key, value in pairs(r) do print(key, value) end",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local record R end",
      "local r: R = new R()",
      "setmetatable(r, {__cal = function() end})",
   }, "\n"))), "NUPP2118:3")
end

function M.metamethodTyposCarrySafeFixes()
   local literal = table.concat({
      "local record R end",
      "local r: R = new R()",
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
      "local p: Point = new Point()",
      "local n: number? = p?.x",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local record Point",
      "   x: number",
      "end",
      "local p: Point = new Point()",
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
      "local a: A = new A()",
      "local b: B = a",
   }, "\n"))), "NUPP2001:8")
   -- but a record erodes to a matching structural shape
   assertClean(table.concat({
      "local record A",
      "   v: number",
      "end",
      "local a: A = new A()",
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

function M.shortFunctionsInferCallbackParameters()
   local src = table.concat({
      "local type Event = {name: string}",
      "local function observe<E is Event>(eventType: E, observer: function(E))",
      "end",
      "local event: Event = {name = 'ready'}",
      "observe(event, e -> do",
      "    local name: string = e.name",
      "end)",
   }, "\n")
   assertClean(src)
   assertEq((diagsOf(src:gsub("e.name", "e.missing"))), "NUPP2004:6")
   local longSrc = src:gsub("e %-%> do", "function(e)")
   assertClean(longSrc)
   assertEq((diagsOf(longSrc:gsub("e.name", "e.missing"))), "NUPP2004:6")
end

function M.shortFunctionReturnsCompleteGenericInference()
   local prefix = table.concat({
      "local function map<T, U>(xs: {T}, f: function(T): U): {U}",
      "   error('not run')",
      "end",
   }, "\n")
   assertClean(prefix .. "\nlocal values: {number} = map({1, 2}, |x| -> x + 1)")
   assertEq(diagsOf(prefix
      .. "\nlocal values: {string} = map({1, 2}, |x| -> x + 1)"),
      "NUPP2001:4")
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
      "local a: unknown = new P(x = 1)",
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
-- A refinement is the runtime test that decides whether a value is one of
-- these. An interface has no table to stamp, so it is the only identity one can
-- have; a record and a struct already answer `is` exactly, so they may not
-- carry one.
function M.refinementsAreEnforced()
   assertClean(table.concat({
      "local interface Circle",
      "   kind: string",
      "   radius: number",
      "   satisfies |self| -> self.kind == 'circle'",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "local interface Tagged",
      "   tag: string",
      "   satisfies |self| -> type(self.tag) == 'string'",
      "end",
   }, "\n"))
   -- and it composes the way a test does
   assertClean(table.concat({
      "local interface Both",
      "   a: integer",
      "   b: boolean",
      "   c: boolean",
      "   satisfies |self| -> self.a == 1 and (self.b or not self.c)",
      "end",
   }, "\n"))
   assertClean("local record Even\n   n: integer\nend")
   -- `matches` stays contextual: a field may still be called one
   assertClean("local record F\n   matches: string\nend")
end

-- A record's identity is the metatable `new` stamps and a struct's is its
-- ctype. A refinement beside either would be a second answer to a settled
-- question, and which answer `is R` gave would depend on whether a body
-- happened to carry one.
function M.onlyAnInterfaceCarriesARefinement()
   assertEq((diagsOf(table.concat({
      "local record R",
      "   kind: string",
      "   satisfies |self| -> self.kind == 'r'",
      "end",
   }, "\n"))), "NUPP2122:3")
   assertEq((diagsOf(table.concat({
      "local struct S",
      "   n: int32",
      "   satisfies |self| -> self.n == 1",
      "end",
   }, "\n"))), "NUPP2122:3")
   -- one per declaration
   assertEq((diagsOf(table.concat({
      "local interface J",
      "   n: integer",
      "   satisfies |self| -> self.n == 1",
      "   satisfies |self| -> self.n == 2",
      "end",
   }, "\n"))), "NUPP2122:4")
   -- and the clause that used to sit in the head says where it went
   assertEq((diagsOf(table.concat({
      "local interface I where self.n == 1",
      "   n: integer",
      "end",
   }, "\n"))), "NUPP2122:1")
end

-- Each rejection names what was written rather than pointing at a list of what
-- is allowed. The subset exists so the test can run wherever `is` is written,
-- which rules out calls, arithmetic, and anything outside the subject.
-- `record C is Shape` is a claim the checker proves, and Shape's refinement is
-- what `is Shape` runs. When C's own fields make that test fail, the two
-- disagree about the same value and nothing at either site shows it.
function M.aDeclarationIsHeldToTheRefinementsItInherits()
   assertEq((diagsOf(table.concat({
      "local interface Shape",
      "   kind: string",
      "   satisfies |self| -> self.kind == 'shape'",
      "end",
      "local record Circle is Shape",
      "   kind: 'circle'",
      "   radius: number",
      "end",
   }, "\n"))), "NUPP2122:5")
   -- a tag that agrees is fine
   assertClean(table.concat({
      "local interface Shape",
      "   kind: string",
      "   satisfies |self| -> self.kind == 'circle'",
      "end",
      "local record Circle is Shape",
      "   kind: 'circle'",
      "end",
   }, "\n"))
   -- so is a type test the declared field satisfies
   assertClean(table.concat({
      "local interface Shape",
      "   kind: string",
      "   satisfies |self| -> type(self.kind) == 'string'",
      "end",
      "local record Circle is Shape",
      "   kind: 'circle'",
      "end",
   }, "\n"))
   -- and a field no declaration settles decides nothing either way
   assertClean(table.concat({
      "local interface Open",
      "   n: integer",
      "   satisfies |self| -> self.n == 1",
      "end",
      "local record Any is Open",
      "   n: integer",
      "end",
   }, "\n"))
end

function M.refinementsRejectWhatCannotBeEnforced()
   local function refuses(test)
      return (diagsOf(table.concat({
         "local interface I",
         "   n: integer",
         "   satisfies |self| -> " .. test,
         "end",
      }, "\n")))
   end
   -- arithmetic reaches nothing about the value
   assertEq(refuses("1 + 1 == 3"), "NUPP2122:3")
   -- a constant decides nothing: this one says yes to every value
   assertEq(refuses("true"), "NUPP2122:3")
   -- and this one says no to all of them
   assertEq(refuses("false"), "NUPP2122:3")
   -- a field the declaration does not have compiles to a test never true
   assertEq(refuses("self.nope == 'x'"), "NUPP2122:3")
   -- a call cannot be made where `is` is written
   assertEq(refuses("tostring(self.n) == '1'"), "NUPP2122:3")
   -- nor can anything outside the subject be read
   assertEq(refuses("other == 1"), "NUPP2122:3")
end

function M.constructionWidensAnInferredLiteral()
   -- A field is a slot the value can be replaced in, so the type argument
   -- construction infers from a literal is the literal's type: `Box<integer>`,
   -- not `Box<1>`, the way `{1}` is an `{integer}`.
   assertClean(table.concat({
      "local record Box<T>",
      "    value: T",
      "end",
      "local b: Box<integer> = new Box(value = 1)",
      "local s: Box<string> = new Box(value = 'a')",
      "b.value = 2",
      "s.value = 'b'",
      "return b, s",
   }, "\n"))
   assertClean(table.concat({
      "local record Pair<T>",
      "    first: T",
      "    second: T",
      "end",
      "local p: Pair<integer> = new Pair(first = 1, second = 2)",
      "return p",
   }, "\n"))
end

return M
