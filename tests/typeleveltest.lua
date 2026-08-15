local parser = require("nupp.compiler.parser")
local cst = require("nupp.compiler.cst")
local gen = require("nupp.compiler.gen")
local fmt = require("nupp.compiler.fmt")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local types = require("nupp.compiler.types")
local generics = require("nupp.compiler.generics")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local diagnosticRun = 0
local function diagnostics(source)
   diagnosticRun = diagnosticRun + 1
   env.loaded = {}
   local filename = ("typelevel-%d.g.nupp"):format(diagnosticRun)
   local parsed = parser.parse(source, filename)
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   return check.check(parsed, filename, env)
end

local function codes(source)
   local out = {}
   for j, diagnostic in ipairs(diagnostics(source)) do
      out[j] = diagnostic.code
   end
   return table.concat(out, " ")
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function oneDiagnostic(source, code, message)
   local found = diagnostics(source)
   assertEq(#found, 1, "one diagnostic for:\n" .. source)
   assertEq(found[1].code, code)
   if found[1].msg ~= message
      and not found[1].msg:match("^" .. message:gsub("([^%w])", "%%%1") .. "\n  called ") then
      assertEq(found[1].msg, message)
   end
end

local function typeDump(typeSource)
   local parsed = parser.parse("local value: " .. typeSource, "test.g.nupp")
   assertEq(#parsed.errors, 0)
   local declaration = parsed.root.blocks[1].stats[1]
   assert(declaration.kind == "localStmt")
   local annotation = declaration.types[1]
   return cst.dump(annotation), cst.textOf(parsed.root)
end

local M = {}

function M.closedComptimeTypeFunctionsConstructTypes()
   clean(table.concat({
      "local comptime function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local yes: Optional(string) = 'yes'",
      "local no: Optional(string) = nil",
      "return yes, no",
   }, "\n"))
   assertEq(codes(table.concat({
      "local comptime function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local bad: Optional(string) = 42",
      "return bad",
   }, "\n")), "NUPP2001")
end

function M.closedComptimeTypeFunctionsUseScalarControlFlowAndInspection()
   clean(table.concat({
      "local comptime function Binary(source: string): type",
      "   local elements = {}",
      "   for index = 1, #source do",
      "      local digit = source:sub(index, index)",
      "      if digit == '0' then",
      "         elements[#elements + 1] = nupp.types.literal(0)",
      "      elseif digit == '1' then",
      "         elements[#elements + 1] = nupp.types.literal(1)",
      "      else",
      "         return nupp.types.error('expected binary digits')",
      "      end",
      "   end",
      "   return nupp.types.tuple(elements)",
      "end",
      "local comptime function DeepElement(T: type): type",
      "   while nupp.types.kind(T) == 'array' do",
      "      T = nupp.types.elements(T)[1]",
      "   end",
      "   return T",
      "end",
      "local bits: Binary('101') = nil as any",
      "local leaf: DeepElement({{{integer}}}) = 42",
      "return bits, leaf",
   }, "\n"))
end

function M.closedComptimeTypeFunctionsReportApplicationFailures()
   assertEq(codes(table.concat({
      "local comptime function Binary(source: string): type",
      "   return nupp.types.error('expected binary digits')",
      "end",
      "local bad: Binary('2')",
      "return bad",
   }, "\n")), "NUPP2420")
   assertEq(codes(table.concat({
      "local comptime function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local bad: Optional(string, number)",
      "return bad",
   }, "\n")), "NUPP2421")
   assertEq(codes(table.concat({
      "local function Runtime(T: any): any return T end",
      "local bad: Runtime(string)",
      "return Runtime(1), bad",
   }, "\n")), "NUPP2421")
end

function M.compilerOnlyTypeHandlesCannotEnterRuntimeSignatures()
   assertEq(codes(table.concat({
      "local function identity(T: type): type return T end",
      "return identity",
   }, "\n")), "NUPP2421 NUPP2421")
   assertEq(codes(table.concat({
      "local value: type = nil as any",
      "return value",
   }, "\n")), "NUPP2421")
end

function M.openComptimeTypeCallsCloseAfterGenericInference()
   clean(table.concat({
      "local comptime function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local function choose<T>(value: T, fallback: Optional(T)): Optional(T)",
      "   return fallback",
      "end",
      "local answer: string? = choose('ready', nil)",
      "return answer",
   }, "\n"))
   assertEq(codes(table.concat({
      "local comptime function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local function choose<T>(value: T, fallback: Optional(T)): Optional(T)",
      "   return fallback",
      "end",
      "return choose('ready', 42)",
   }, "\n")), "NUPP2006")
end

function M.openScalarTypeCallsCloseAfterConstInference()
   clean(table.concat({
      "local comptime function Literal(value: integer): type",
      "   return nupp.types.literal(value)",
      "end",
      "local function preserve<const N: integer>(value: N): Literal(N)",
      "   return value as any",
      "end",
      "local one: 1 = preserve(1)",
      "return one",
   }, "\n"))
end

function M.comptimeTypeFunctionsPreserveExistingNominalIdentity()
   clean(table.concat({
      "local record User name: string end",
      "local comptime function Maybe(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local user: Maybe(User) = new User(name = 'Ada')",
      "return user",
   }, "\n"))
end

function M.comptimeTypeFunctionsPreserveNestedNominalReferences()
   clean(table.concat({
      "local record User name: string end",
      "local comptime function Element(T: type): type",
      "   return nupp.types.elements(T)[1]",
      "end",
      "local user: Element({User}) = new User(name = 'Ada')",
      "return user",
   }, "\n"))
end

function M.constrainedOpenTypeCallsExposeOnlyTheirDeclaredBound()
   clean(table.concat({
      "local comptime function ReadView(T: type): type<{readonly name: string}>",
      "   return nupp.types.shape({{name = 'name', read = nupp.types.string}})",
      "end",
      "local function nameOf<T>(value: ReadView(T)): string",
      "   return value.name",
      "end",
      "return nameOf",
   }, "\n"))
   assertEq(codes(table.concat({
      "local comptime function Bad(T: type): type<{readonly name: string}>",
      "   return nupp.types.integer",
      "end",
      "local value: Bad(string)",
      "return value",
   }, "\n")), "NUPP2421")
end

function M.comptimeTypePackResultsExpandThroughUnpackof()
   clean(table.concat({
      "local comptime function Pair(T: type): typepack",
      "   return nupp.types.pack({T, nupp.types.string})",
      "end",
      "local function closed(...: unpackof Pair(integer)): nil end",
      "local function inferred<T>(value: T, ...: unpackof Pair(T)): nil end",
      "closed(1, 'one')",
      "inferred(true, true, 'yes')",
      "return closed, inferred",
   }, "\n"))
   assertEq(codes(table.concat({
      "local comptime function Pair(T: type): typepack",
      "   return nupp.types.pack({T, nupp.types.string})",
      "end",
      "local function inferred<T>(value: T, ...: unpackof Pair(T)): nil end",
      "inferred(true, 1, 'yes')",
      "return inferred",
   }, "\n")), "NUPP2006")
end

function M.comptimeTypeFunctionsAcceptTypePackArguments()
   clean(table.concat({
      "local comptime function Identity(P: typepack): typepack",
      "   return P",
      "end",
      "local function takes(...: unpackof Identity((string, integer))): nil end",
      "takes('one', 1)",
      "return takes",
   }, "\n"))
   assertEq(codes(table.concat({
      "local comptime function Identity(P: typepack): typepack",
      "   return P",
      "end",
      "local function takes(...: unpackof Identity((string, integer))): nil end",
      "takes('one', false)",
      "return takes",
   }, "\n")), "NUPP2006")
end

function M.finiteTypeOperatorSyntaxRoundTrips()
   local dump, text = typeDump("writeof Cell.[\"value\"]")
   assertEq(dump,
      "(twriteof writeof (tmember (tname Cell) . [ (tliteral \"value\") ]))")
   assertEq(text, "local value: writeof Cell.[\"value\"]")
   dump = typeDump("keyof Cell")
   assertEq(dump, "(tkeyof keyof (tname Cell))")
   dump = typeDump("writekeyof Cell")
   assertEq(dump, "(tkeyof writekeyof (tname Cell))")
   dump = typeDump("{string,}")
   assertEq(dump, "(ttuple { (tname string) , })")
   dump = typeDump("function<F is string>(fmt: F, ...: unpackof Args<F>): string")
   assertEq(dump,
      "(tfunc function (generics < F is (tname string) >) ( "
         .. "(tfuncParam fmt : (tname F)) , (tfuncParam ... : "
         .. "(tpack unpackof (tname Args < (tname F) >))) ) : (tname string))")
   dump = typeDump("{string, unpackof Tail}")
   assertEq(dump, "(ttuple { (tname string) , unpackof (tname Tail) })")
end

function M.computedPackSyntaxFormatsIdempotently()
   local source = table.concat({
      "local function apply<F is string>(...:unpackof Args<F>):nil",
      "end",
      "local value:{string,}",
      "local type More<T> = {string,unpackof T}",
   }, "\n")
   local once, errors = fmt.format(source)
   assertEq(#errors, 0)
   assertEq(once, table.concat({
      "local function apply<F is string>(...: unpackof Args<F>): nil",
      "end",
      "",
      "local value: {string,}",
      "local type More<T> = {string, unpackof T}",
   }, "\n") .. "\n")
   local twice, again = fmt.format(once)
   assertEq(#again, 0)
   assertEq(twice, once)
end

function M.keyAndIndexedMemberOperatorsRespectCapabilities()
   clean(table.concat({
      "local type Cell = {readonly value: string, writeonly value: string | integer}",
      "local readKey: keyof Cell = 'value'",
      "local writeKey: writekeyof Cell = 'value'",
      "local readValue: Cell.['value'] = 'ready'",
      "local writeValue: writeof Cell.['value'] = 4",
   }, "\n"))
   assertEq(codes(table.concat({
      "local type Cell = {readonly value: string}",
      "local bad: writekeyof Cell = 'value'",
   }, "\n")), "NUPP2001")
end

function M.mappedShapesReduceAfterGenericSubstitution()
   clean(table.concat({
      "local type ReadonlyView<T> = {readonly [K in keyof T]: T.[K]}",
      "local type Sink<T> = {writeonly [K in writekeyof T]: writeof T.[K]}",
      "local source: ReadonlyView<{name: string, age: integer}> = {name = 'Ada', age = 37}",
      "local sink: Sink<{name: string, age: integer}> = nil as any",
      "sink.name = 'Grace'",
      "sink.age = 42",
      "local name: string = source.name",
   }, "\n"))
end

function M.broadAndMissingMemberReductionsReportLocally()
   assertEq(codes("local value: {readonly [K in string]: K}"), "NUPP2130")
   assertEq(codes("local value: {name: string}.['missing']"), "NUPP2130")
end

function M.finiteReducerCancellationIsBounded()
   local deep = types.string
   for _ = 1, 40 do deep = types.array(deep) end
   local polls = 0
   local _, err = generics.reduce(deep, nil, nil, {cancelled = function()
      polls = polls + 1
      return true
   end})
   assertEq(err, "type reduction cancelled")
   assertEq(polls, 1, "the finite reducer polls its cancellation control")
end

function M.constParametersSizeArraysWithoutRuntimeSpecialization()
   clean(table.concat({
      "local record Matrix<T, const Rows: integer, const Columns: integer>",
      "   values: T[Rows * Columns]",
      "end",
      "local matrix: Matrix<float, 4, 4> = nil as any",
      "local values: float[16] = matrix.values",
   }, "\n"))
end

function M.constFunctionInferenceRequiresIdenticalKnownValues()
   clean(table.concat({
      "local record Field<const Name: string> end",
      "local function field<const Name: string>(name: Name): Field<Name>",
      "   return nil as any",
      "end",
      "local named: Field<'name'> = field('name')",
   }, "\n"))
   assertEq(codes(table.concat({
      "local function same<const S: string>(left: S, right: S): nil end",
      "same('x', 'y')",
   }, "\n")), "NUPP2131")
   assertEq(codes(table.concat({
      "local function field<const S: string>(name: S): nil end",
      "local dynamic: string = 'x'",
      "field(dynamic)",
   }, "\n")), "NUPP2131")
end

function M.numericLiteralAndMemberIndexSyntaxStayDistinct()
   clean(table.concat({
      "local type Sixteen = 16",
      "local fixed: float[4 * 4] = nil as any",
      "local exact: float[16] = fixed",
      "local type Numeric = {[integer]: string}",
      "local type Indexed = Numeric.[16]",
      "local indexed: Indexed = 'value'",
   }, "\n"))
end

function M.computedTypesExpandIntoCallablePacks()
   clean(table.concat({
      "local comptime function Args(F: type): typepack",
      "   local info = nupp.types.describe(F)",
      "   if info.kind ~= 'literal' then return nupp.types.pack({}, nupp.types.any) end",
      "   if info.value == 'pair' then return nupp.types.pack({nupp.types.string, nupp.types.number}) end",
      "   if info.value == 'one' then return nupp.types.pack({nupp.types.boolean}) end",
      "   if info.value == 'many' then return nupp.types.pack({}, nupp.types.integer) end",
      "   return nupp.types.pack({}, nupp.types.any)",
      "end",
      "local function apply<F is string>(kind: F, ...: unpackof Args(F)): string",
      "   return kind end",
      "local pair: string = apply('pair', 'x', 1)",
      "local one: string = apply('one', true)",
      "local many: string = apply('many', 1, 2, 3)",
      "local dynamic: string = 'dynamic'",
      "local gradual: string = apply(dynamic, {}, false, 3)",
      "print(pair, one, many, gradual)",
   }, "\n"))
   assertEq(codes(table.concat({
      "local comptime function Args(F: type): typepack",
      "   local info = nupp.types.describe(F)",
      "   if info.kind == 'literal' and info.value == 'pair' then",
      "      return nupp.types.pack({nupp.types.string, nupp.types.number})",
      "   end",
      "   return nupp.types.pack({}, nupp.types.any)",
      "end",
      "local function apply<F is string>(kind: F, ...: unpackof Args(F)): nil end",
      "apply('pair', 'x', 'wrong')",
   }, "\n")), "NUPP2006")
   assertEq(codes(table.concat({
      "local function apply(...: unpackof {string,}): nil end",
      "apply(1)",
   }, "\n")), "NUPP2006")
   clean(table.concat({
      "local type AddHead<Tail> = {string, unpackof Tail}",
      "local function apply(...: unpackof AddHead<{number, boolean}>): nil end",
      "apply('x', 1, true)",
   }, "\n"))
   local failure = diagnostics(table.concat({
      "local comptime function Failure(): typepack",
      "   return nupp.types.error('computed contract failed')",
      "end",
      "local function apply(...: unpackof Failure()): nil end",
      "apply()",
   }, "\n"))
   assertEq(#failure, 1, "one authored type-function diagnostic")
   assertEq(failure[1].code, "NUPP2420")
   assert(failure[1].msg:match("^computed contract failed"),
      "the authored message begins the diagnostic")
end

function M.stringFormatDerivesArgumentsFromLiteralFormats()
   clean(table.concat({
      "@derive(nupp.derive.Debug)",
      "local record User name: string end",
      "local user = new User(name = 'Ada')",
      "local name = 'Ada'",
      "local count = string.format('%s has %d messages', name, 3)",
      "local debug = string.format('user=%?', user)",
      "local debugMethod = ('user=%?'):format(user)",
      "local percent = string.format('100%% ready')",
      "local decimal = string.format('%.2f', 1.5)",
      "local method = ('%d'):format(3)",
      "local extended = string.format(" ..
         "'%a %A %c %d %i %o %u %x %X %e %E %f %g %G %p %q %s', " ..
         "1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, {}, true, 'text')",
      "local flags = string.format('%-+#09.2f', 1.5)",
      "local many = string.format('%d%d%d%d%d%d%d%d%d', 1, 2, 3, 4, 5, 6, 7, 8, 9)",
      "local dynamic: string = '%s'",
      "local gradual = string.format(dynamic, {}, false, 3)",
      "print(count, debug, debugMethod, percent, decimal, method, extended, flags, many, gradual)",
   }, "\n"))
   oneDiagnostic("local bad = string.format('%d', 'three')\nprint(bad)",
      "NUPP2006", "argument 2: string is not a number")
   oneDiagnostic("local bad = string.format('%d')\nprint(bad)",
      "NUPP2006", "omitted argument 2 supplies nil, not number")
   oneDiagnostic("local bad = string.format('%d', 1, 2)\nprint(bad)",
      "NUPP2007", "too many arguments (expected 2, got 3)")
   oneDiagnostic("local bad = string.format('plain', 1)\nprint(bad)",
      "NUPP2007", "too many arguments (expected 1, got 2)")
   oneDiagnostic("local bad = string.format('%z', 1)\nprint(bad)",
      "NUPP2006", 'invalid string.format directive starting at "%z"')
   oneDiagnostic("local bad = string.format('%..f', 1)\nprint(bad)",
      "NUPP2006", 'invalid string.format directive starting at "%..f"')
   oneDiagnostic("local bad = string.format('%100d', 1)\nprint(bad)",
      "NUPP2006", 'invalid string.format directive starting at "%100"')
   oneDiagnostic("local bad = string.format('%*d', 1)\nprint(bad)",
      "NUPP2006", 'invalid string.format directive starting at "%*d"')
   oneDiagnostic("local bad = string.format('%F', 1)\nprint(bad)",
      "NUPP2006", 'invalid string.format directive starting at "%F"')
   oneDiagnostic("local bad = string.format('%.100f', 1)\nprint(bad)",
      "NUPP2006", 'invalid string.format directive starting at "%.100"')
   oneDiagnostic("local bad = ('%d'):format('three')\nprint(bad)",
      "NUPP2006", "argument 1: string is not a number")
   oneDiagnostic("local bad = string.format('%?', 'wrong')\nprint(bad)",
      "NUPP2006", "argument 2: string is not a Debug")
end

function M.stringFormatSyntaxIsReusableByUserFormattingWrappers()
   clean(table.concat({
      "local function format<F is string>(fmt: F, ...: unpackof nupp.format.StringFormatSyntax(F)): string",
      "   return string.format(fmt, ...)",
      "end",
      "local value = format('%s=%d', 'count', 3)",
      "print(value)",
   }, "\n"))
   oneDiagnostic(table.concat({
      "local function format<F is string>(fmt: F, ...: unpackof nupp.format.StringFormatSyntax(F)): string",
      "   return string.format(fmt, ...)",
      "end",
      "local value = format('%d', 'wrong')",
      "print(value)",
   }, "\n"), "NUPP2006", "argument 2: string is not a number")
   oneDiagnostic(table.concat({
      "local function format<F is string>(fmt: F, ...: unpackof nupp.format.StringFormatSyntax(F)): string",
      "   return string.format(fmt, ...)",
      "end",
      "local value = format('%?', {})",
      "print(value)",
   }, "\n"), "NUPP2006", table.concat({
      "%? is available only to compiler-lowered formatting APIs",
      "  called StringFormatSyntax at 5:1; defined at 5:1",
   }, "\n"))
end

function M.luaFormatParserUsesThePegRuntime()
   local luaFormat = require("nupp.compiler.LuaFormat")
   local kinds, why = luaFormat.argumentKinds("%-+#09.2f %q %% %d %?")
   assertEq(why, nil)
   assertEq(table.concat(kinds or {}, ","), "number,any,number,debug")
   local parsed = assert(luaFormat.analyze("100%%: %? %04d"))
   assertEq(parsed.format, "100%%: %s %04d")
   assertEq(parsed.debugArguments[1], true)
   assertEq(parsed.debugArguments[2], false)
   local missing, invalid = luaFormat.argumentKinds("%..f")
   assertEq(missing, nil)
   assertEq(invalid, 'invalid string.format directive starting at "%..f"')
end

function M.luaPatternParserUsesThePegRuntime()
   local luaPattern = require("nupp.compiler.LuaPattern")
   local captures, why = luaPattern.captureKinds("([a-z]+)()")
   assertEq(why, nil)
   assertEq(table.concat(captures or {}, ","), "string,position")
   local missing, invalid = luaPattern.captureKinds("[abc")
   assertEq(missing, nil)
   assertEq(invalid, "malformed pattern")
end

function M.luaPatternsDeriveLiteralCaptureResults()
   clean(table.concat({
      "local whole: string? = string.match('name=42', '[a-z]+=%d+')",
      "local name: string?, count: string? = string.match('name=42', '([a-z]+)=(%d+)')",
      "local value: string?, at: integer? = string.match('name', '([a-z]+)()')",
      "local storedPattern = '([a-z]+)()'",
      "local storedValue: string?, storedAt: integer? = string.match('name', storedPattern)",
      "local first: integer?, last: integer?, word: string?, position: integer? = string.find('name', '([a-z]+)()')",
      "local words: function(): (string?) = string.gmatch('one two', '[a-z]+')",
      "local pairs: function(): (string?, string?) = string.gmatch('one=1', '([a-z]+)=(%d+)')",
      "local method: string?, methodAt: integer? = ('name'):match('([a-z]+)()')",
      "local methodFirst: integer?, methodLast: integer?, methodWord: string?, methodPosition: integer? = ('name'):find('([a-z]+)()')",
      "local methodWords: function(): (string?) = ('one two'):gmatch('[a-z]+')",
      "local replaced: string, replacements: integer = ('name'):gsub('[a-z]+', '#')",
      "local literalFirst, literalLast = string.find('[', '[', 1, true)",
      "return whole, name, count, value, at, storedValue, storedAt, first, last, word, position, words, pairs, method, methodAt, methodFirst, methodLast, methodWord, methodPosition, methodWords, replaced, replacements, literalFirst, literalLast",
   }, "\n"))
   oneDiagnostic("local value: integer? = string.match('name', '([a-z]+)')\nprint(value)",
      "NUPP2001", "cannot initialize value: string? is not a integer? (member string does not fit)")
   oneDiagnostic("local bad = string.match('name', '[abc')\nprint(bad)",
      "NUPP2006", "invalid Lua pattern: malformed pattern")
   oneDiagnostic("local bad = string.gmatch('name', '%')\nprint(bad)",
      "NUPP2006", "invalid Lua pattern: malformed pattern")
   oneDiagnostic("local bad = string.gsub('name', '[abc', '#')\nprint(bad)",
      "NUPP2006", "invalid Lua pattern: malformed pattern")
end

function M.templateConstructionAndOneSegmentExtractionAreFinite()
   clean(table.concat({
      "local type Event<const Name: string> = `${Name}Changed`",
      "local event: Event<'ready'> = 'readyChanged'",
      "local comptime function Parameter(Path: type): type",
      "   local info = nupp.types.describe(Path)",
      "   local name = info.kind == 'literal' and info.value:match(':(.+)$') or nil",
      "   if name then return nupp.types.literal(name) end",
      "   return nupp.types.never",
      "end",
      "local parameter: Parameter('users:id') = 'id'",
   }, "\n"))
end

function M.mappedRemappingBuildsDependentEventAdapters()
   clean(table.concat({
      "local type Events<T> = {",
      "   readonly [K in keyof T as `${K}Changed`]: function(value: T.[K]): nil",
      "}",
      "local events: Events<{name: string, age: integer}> = nil as any",
      "local onName: function(value: string): nil = events.nameChanged",
      "local onAge: function(value: integer): nil = events.ageChanged",
      "local comptime function PublicKey(K: type): type",
      "   local info = nupp.types.describe(K)",
      "   if info.kind == 'literal' and info.value == 'password' then return nupp.types.never end",
      "   return K",
      "end",
      "local type Public<T> = {readonly [K in keyof T as PublicKey(K)]: T.[K]}",
      "local public: Public<{name: string, password: string}> = {name = 'Ada'}",
      "local name: string = public.name",
   }, "\n"))
end

function M.remapCollisionsReportAtTheOperator()
   assertEq(codes(table.concat({
      "local type Collision<T> = {readonly [K in keyof T as 'same']: T.[K]}",
      "local collision: Collision<{a: string, b: integer}> = nil as any",
   }, "\n")), "NUPP2130")
end

function M.removedTypeProgrammingSyntaxHasNoSpecialCst()
   local parsed = parser.parse("local value: typeerror<'broken'>", "removed.g.nupp")
   assertEq(#parsed.errors, 0)
   assert(not cst.dump(parsed.root):find("ttypeerror", 1, true),
      "typeerror is now an ordinary generic type name")
   local matched = parser.parse(
      "local type Old<T> = match T when infer X then X end",
      "removed.g.nupp")
   assert(#matched.errors > 0, "type-level match and infer are no longer grammar")
end

function M.templateProductsHaveABoundedDiagnostic()
   local left, right = {}, {}
   for j = 1, 17 do
      left[j] = ("'l%d'"):format(j)
      right[j] = ("'r%d'"):format(j)
   end
   local source = table.concat({
      "local type Left = " .. table.concat(left, " | "),
      "local type Right = " .. table.concat(right, " | "),
      "local value: `${Left}${Right}`",
   }, "\n")
   assertEq(codes(source), "NUPP2132")
end

function M.boundsIntersectionsAndIndexersShareTheMemberVocabulary()
   clean(table.concat({
      "local type NamedKeys<T is {readonly name: string}> = keyof T",
      "local named: NamedKeys<{readonly name: string, readonly age: integer}> = 'name'",
      "local both: keyof ({readonly left: string} & {readonly right: integer}) = 'right'",
      "local indexed: keyof {readonly [string]: integer} = 'arbitrary'",
   }, "\n"))
end

function M.constArithmeticErrorsStayAtTheTypeBoundary()
   assertEq(codes("local huge: float[9007199254740991 + 1]"), "NUPP2131")
   assertEq(codes("local divided: float[4 // 0]"), "NUPP2131")
end

function M.constArgumentsParticipateInNominalIdentity()
   assertEq(codes(table.concat({
      "local record Field<const Name: string> end",
      "local left: Field<'left'> = nil as any",
      "local right: Field<'right'> = left",
   }, "\n")), "NUPP2001")
end

function M.cachedGenericInstantiationsLearnLateDeclaredMembers()
   local declaration = types.nominal("LateSurface", "record")
   local parameter = types.typevar("T", "late-surface-test")
   declaration.typeParams = {parameter}

   local first = generics.instantiate(declaration, {[parameter] = types.string})
   assertEq(first.byname.get, nil, "the early instance starts incomplete")

   declaration.byname.get = types.func({declaration}, {parameter})
   declaration.metamethods.__tostring = types.func({declaration}, {types.string})
   local refreshed = generics.instantiate(declaration, {[parameter] = types.string})

   assertEq(refreshed, first, "refreshing preserves nominal identity")
   local getter = refreshed.byname.get
   local stringify = refreshed.metamethods.__tostring
   assert(getter and getter.tag == "func")
   assert(stringify and stringify.tag == "func")
   assertEq(getter.rets[1], types.string,
      "late members are specialized onto the cached instance")
   assertEq(stringify.rets[1], types.string,
      "late metamethods are copied onto the cached instance")
end

function M.typeComputationAndConstBindersEraseFromGeneratedLua()
   local source = table.concat({
      "local function field<const Name: string>(name: Name): Name",
      "   return name",
      "end",
      "local type View<T> = {readonly [K in keyof T]: T.[K]}",
      "local value: View<{name: string}> = {name = field('ok')}",
      "return value.name",
   }, "\n")
   clean(source)
   local parsed = parser.parse(source, "erase.g.nupp")
   local lua, emitted = gen.generate(parsed, "erase")
   assertEq(#emitted, 0, "code generation diagnostics")
   assert(not lua:find("const Name", 1, true), "const binder reached runtime Lua")
   assert(not lua:find("keyof", 1, true), "type operator reached runtime Lua")
   local chunk = assert(loadstring(lua))
   assertEq(chunk(), "ok")
end

function M.comptimeCallsInAnnotationPositionEraseFromGeneratedLua()
   local source = table.concat({
      "local comptime function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local value: Optional(string) = 'ok'",
      "return value",
   }, "\n")
   clean(source)
   local parsed = parser.parse(source, "annotation.g.nupp")
   local lua, emitted = gen.generate(parsed, "annotation")
   assertEq(#emitted, 0, "code generation diagnostics")
   -- The call is type material, so its parentheses erase with the annotation
   -- rather than reaching the statement as `local value ( ) = 'ok'`, which is
   -- not Lua and so fails to load rather than to type-check.
   assert(lua:find("local value = 'ok'", 1, true), "annotation reached runtime Lua:\n" .. lua)
   local chunk = assert(loadstring(lua))
   assertEq(chunk(), "ok")
end

-- A parameter with a default may be left out of an application, and the
-- declaration is what says what it then means.
function M.aDefaultedTypeParameterMayBeLeftOut()
   clean(table.concat({
      "local record Pair<A, B = string>",
      "   left: A",
      "   right: B",
      "end",
      "local function same(p: Pair<integer>): Pair<integer, string>",
      "   return p",
      "end",
      "print(same)",
   }, "\n"))
end

function M.aDefaultedConstParameterMayBeLeftOut()
   clean(table.concat({
      "local record Box<T, const N: integer = 0>",
      "   value: T",
      "end",
      "local function same(b: Box<integer>): Box<integer, 0>",
      "   return b",
      "end",
      "print(same)",
   }, "\n"))
end

-- A written argument still decides the position, so a default changes nothing
-- about an application that supplies one.
function M.aWrittenArgumentOverridesTheDefault()
   assertEq(codes(table.concat({
      "local record Box<T, const N: integer = 0>",
      "   value: T",
      "end",
      "local function seven(b: Box<integer, 7>): Box<integer, 0>",
      "   return b",
      "end",
   }, "\n")), "NUPP2002")
end

-- Leaving an argument out has to mean the last position, or it would say
-- nothing about which one was left out.
function M.aParameterWithoutADefaultCannotFollowOneWithIt()
   assertEq(codes(table.concat({
      "local record Bad<A = string, B>",
      "   left: A",
      "   right: B",
      "end",
   }, "\n")), "NUPP2121")
end

function M.aGenericPackParameterCannotHaveADefault()
   assertEq(codes(table.concat({
      "local record Bad<A... = string>",
      "   value: integer",
      "end",
   }, "\n")), "NUPP2121")
end

-- A `function` const parameter names a declaration rather than carrying a value.
-- It is what lets a terminal travel in the type that carries it instead of being
-- restated at every producer of one.
local FUNCTION_CONST = table.concat({
   "cdef function free_a(takes value: voidptr)",
   "cdef function free_b(takes value: voidptr)",
   "local record Handle<T, const cleanup: function>",
   "   value: T",
   "end",
}, "\n")

function M.aConstFunctionParameterNamesADeclaration()
   clean(FUNCTION_CONST .. table.concat({
      "",
      "local function same(h: Handle<integer, free_a>): Handle<integer, free_a>",
      "   return h",
      "end",
      "print(same)",
   }, "\n"))
end

-- The whole point of putting it in the type: two applications naming different
-- functions are different types, so a terminal cannot be swapped silently.
function M.constFunctionArgumentsDistinguishTypes()
   assertEq(codes(FUNCTION_CONST .. table.concat({
      "",
      "local function mismatch(h: Handle<integer, free_a>): Handle<integer, free_b>",
      "   return h",
      "end",
   }, "\n")), "NUPP2002")
end

function M.aConstFunctionArgumentMustNameAFunction()
   assertEq(codes(FUNCTION_CONST .. table.concat({
      "",
      "local notAFunction = 7",
      "local function bad(h: Handle<integer, notAFunction>): integer",
      "   return h.value",
      "end",
   }, "\n")), "NUPP2131")
end

function M.aConstFunctionArgumentMustBeDeclared()
   assertEq(codes(FUNCTION_CONST .. table.concat({
      "",
      "local function missing(h: Handle<integer, nosuchthing>): integer",
      "   return h.value",
      "end",
   }, "\n")), "NUPP2131")
end

-- Hoisting builds the binder and binding reuses that same object, so a domain only
-- one of them knew was silently replaced by whatever the other settled on.
function M.aConstFunctionDomainSurvivesHoisting()
   clean(table.concat({
      "cdef function free(takes value: voidptr)",
      "local record Later<T, const cleanup: function>",
      "   value: T",
      "end",
      "local held: Later<integer, free> = nil as any",
      "print(held)",
   }, "\n"))
end

local AFFINE_TYPES = table.concat({
   "local record Resource",
   "   value: integer",
   "end",
   "local function closeA(takes value: Resource): nil end",
   "local function closeB(takes value: Resource): nil end",
   "local affine type Owner<T, const cleanup: function> = T",
   "   terminal cleanup",
   "end",
}, "\n")

function M.usersCanDeclareGenericAffineTypes()
   clean(AFFINE_TYPES .. table.concat({
      "",
      "local function open(): Owner<Resource, closeA>",
      "   return new Resource(value = 1)",
      "end",
      "local resource = open()",
      "drop resource",
   }, "\n"))
end

function M.transparentAffineAliasesWithTheSameTerminalInterchange()
   clean(AFFINE_TYPES .. table.concat({
      "",
      "local affine type Other<T, const cleanup: function> = T",
      "   terminal cleanup",
      "end",
      "local function rename(takes value: Owner<Resource, closeA>): Other<Resource, closeA>",
      "   return value",
      "end",
   }, "\n"))
end

function M.transparentAffineAliasesRetainTerminalIdentity()
   assertEq(codes(AFFINE_TYPES .. table.concat({
      "",
      "local function mismatch(takes value: Owner<Resource, closeA>): Owner<Resource, closeB>",
      "   return value",
      "end",
   }, "\n")), "NUPP2002")
end

function M.terminalLessAffineTypesAreExplicitAndCannotBeDropped()
   assertEq(codes(table.concat({
      "local affine type Forward<T> = T end",
      "local function make(): Forward<integer> return 1 end",
      "local value = make()",
      "drop value",
   }, "\n")), "NUPP2602")
end

function M.comptimeCanConstructAffineTypesFromFunctionIdentity()
   clean(table.concat({
      "local function close(takes value: string): nil end",
      "local comptime function MakeOwner(T: type, const cleanup: function): type",
      "   return nupp.types.affine(T, cleanup)",
      "end",
      "local function make(): MakeOwner(string, close) return 'value' end",
      "local value = make()",
      "drop value",
   }, "\n"))
end

function M.affineDeclarationsAddNoRuntimeRepresentation()
   local source = table.concat({
      "local calls = 0",
      "local function close(takes value: integer): nil calls = calls + value end",
      "local affine type Counter = integer terminal close end",
      "local function make(): Counter return 2 end",
      "local value = make()",
      "drop value",
      "return calls",
   }, "\n")
   local parsed = parser.parse(source, "affine-erasure.g.nupp")
   local found = check.check(parsed, "affine-erasure.g.nupp", env)
   assertEq(#found, 0, found[1] and found[1].msg or "check")
   local lua, emitted = gen.generate(parsed, "affine-erasure")
   assertEq(#emitted, 0, "code generation diagnostics")
   assert(not lua:find("Counter = {}", 1, true), "affine declaration allocated a runtime type")
   local chunk = assert(loadstring(lua))
   assertEq(chunk(), 2)
end

return M
