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
   assertEq(found[1].msg, message)
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
      "@comptime",
      "local function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local yes: Optional(string) = 'yes'",
      "local no: Optional(string) = nil",
      "return yes, no",
   }, "\n"))
   assertEq(codes(table.concat({
      "@comptime",
      "local function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local bad: Optional(string) = 42",
      "return bad",
   }, "\n")), "NUPP2001")
end

function M.closedComptimeTypeFunctionsUseScalarControlFlowAndInspection()
   clean(table.concat({
      "@comptime",
      "local function Binary(source: string): type",
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
      "@comptime",
      "local function DeepElement(T: type): type",
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
      "@comptime",
      "local function Binary(source: string): type",
      "   return nupp.types.error('expected binary digits')",
      "end",
      "local bad: Binary('2')",
      "return bad",
   }, "\n")), "NUPP2420")
   assertEq(codes(table.concat({
      "@comptime",
      "local function Optional(T: type): type",
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
      "@comptime",
      "local function Optional(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local function choose<T>(value: T, fallback: Optional(T)): Optional(T)",
      "   return fallback",
      "end",
      "local answer: string? = choose('ready', nil)",
      "return answer",
   }, "\n"))
   assertEq(codes(table.concat({
      "@comptime",
      "local function Optional(T: type): type",
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
      "@comptime",
      "local function Literal(value: integer): type",
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
      "@comptime",
      "local function Maybe(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "local user: Maybe(User) = new User(name = 'Ada')",
      "return user",
   }, "\n"))
end

function M.constrainedOpenTypeCallsExposeOnlyTheirDeclaredBound()
   clean(table.concat({
      "@comptime",
      "local function ReadView(T: type): type<{readonly name: string}>",
      "   return nupp.types.shape({{name = 'name', read = nupp.types.string}})",
      "end",
      "local function nameOf<T>(value: ReadView(T)): string",
      "   return value.name",
      "end",
      "return nameOf",
   }, "\n"))
   assertEq(codes(table.concat({
      "@comptime",
      "local function Bad(T: type): type<{readonly name: string}>",
      "   return nupp.types.integer",
      "end",
      "local value: Bad(string)",
      "return value",
   }, "\n")), "NUPP2421")
end

function M.comptimeTypePackResultsExpandThroughUnpackof()
   clean(table.concat({
      "@comptime",
      "local function Pair(T: type): typepack",
      "   return nupp.types.pack({T, nupp.types.string})",
      "end",
      "local function closed(...: unpackof Pair(integer)): nil end",
      "local function inferred<T>(value: T, ...: unpackof Pair(T)): nil end",
      "closed(1, 'one')",
      "inferred(true, true, 'yes')",
      "return closed, inferred",
   }, "\n"))
   assertEq(codes(table.concat({
      "@comptime",
      "local function Pair(T: type): typepack",
      "   return nupp.types.pack({T, nupp.types.string})",
      "end",
      "local function inferred<T>(value: T, ...: unpackof Pair(T)): nil end",
      "inferred(true, 1, 'yes')",
      "return inferred",
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
   dump = typeDump("typeerror<'broken'>")
   assertEq(dump, "(ttypeerror typeerror < (tliteral 'broken') >)")
end

function M.computedPackSyntaxFormatsIdempotently()
   local source = table.concat({
      "local function apply<F is string>(...:unpackof Args<F>):nil",
      "end",
      "local value:{string,}",
      "local type More<T> = {string,unpackof T}",
      "local type Failure = typeerror<\"broken\">",
   }, "\n")
   local once, errors = fmt.format(source)
   assertEq(#errors, 0)
   assertEq(once, table.concat({
      "local function apply<F is string>(...: unpackof Args<F>): nil",
      "end",
      "",
      "local value: {string,}",
      "local type More<T> = {string, unpackof T}",
      "local type Failure = typeerror<\"broken\">",
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

function M.recursiveAliasesMustBeGuardedByAMatchArm()
   assertEq(codes("local type Loop<T> = Loop<T>"), "NUPP2133")
   local scrutinee = diagnostics(table.concat({
      "local type Loop<T> = match Loop<T>",
      "   when infer X then X else T end",
   }, "\n"))
   assertEq(scrutinee[1] and scrutinee[1].code, "NUPP2133")
   local mappedKey = diagnostics(table.concat({
      "local type Loop<T> = match T when infer X then",
      "   {readonly [K in Loop<X>]: string} else T end",
   }, "\n"))
   local foundRecursive = false
   for _, diagnostic in ipairs(mappedKey) do
      foundRecursive = foundRecursive or diagnostic.code == "NUPP2133"
   end
   assert(foundRecursive, "a recursive mapped key reports the recursive rule")
end

function M.guardedRecursiveAliasesParseRoutesAndNestedContainers()
   clean(table.concat({
      "local type Segment<S> = match S",
      "   when `:${infer Name}` then {readonly [K in Name]: string}",
      "   else {readonly [K in never]: string} end",
      "local type RouteParameters<Path> = match Path",
      "   when `${infer Head}/${infer Tail}` then",
      "      Segment<Head> & RouteParameters<Tail>",
      "   else Segment<Path> end",
      "local params: RouteParameters<'users/:user/posts/:post'> =",
      "   {user = 'ada', post = 'hello'}",
      "local user: string = params.user",
      "local post: string = params.post",
      "local type DeepElement<T> = match T",
      "   when {infer Item} then DeepElement<Item>",
      "   else T end",
      "local element: DeepElement<{{{integer}}}> = 42",
   }, "\n"))
end

function M.recursiveAliasCyclesAndMutualRecursionReportDedicatedErrors()
   local cycleSource = table.concat({
      "local type Loop<T> = match T when infer X then Loop<X> end",
      "local value: Loop<string>",
   }, "\n")
   assertEq(codes(cycleSource), "NUPP2133")
   local cycle = diagnostics(cycleSource)[1]
   assert(cycle.msg:find("expansion:", 1, true), "cycle carries a bounded expansion trace")
   assertEq(codes(table.concat({
      "local type Left<T> = match T when infer X then Right<X> end",
      "local type Right<T> = match T when infer X then Left<X> end",
   }, "\n")), "NUPP2133")
end

function M.recursiveAliasDepthAndReducerCancellationAreBounded()
   local nested = "integer"
   for _ = 1, 130 do nested = "{" .. nested .. "}" end
   assertEq(codes(table.concat({
      "local type DeepElement<T> = match T",
      "   when {infer Item} then DeepElement<Item> else T end",
      "local value: DeepElement<" .. nested .. ">",
   }, "\n")), "NUPP2133")

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

function M.finiteMatchesInferStructureAndDistributeOnlyExplicitly()
   clean(table.concat({
      "local type Element<T> = match T when {infer Item} then Item else T end",
      "local item: Element<{string}> = 'value'",
      "local type NonNil<T> = match each T when nil then never else T end",
      "local present: NonNil<string | nil> = 'yes'",
      "local type Whole<T> = match T when nil then never else T end",
      "local whole: Whole<string | nil> = nil",
   }, "\n"))
end

function M.tupleTailPatternsDestructureComputedSequences()
   clean(table.concat({
      "local type Concat<Left, Right> = match Left",
      "   when {infer Head, unpackof infer Tail} then",
      "      {Head, unpackof Concat<Tail, Right>}",
      "   when {never} then Right",
      "   else any end",
      "local type Tail<Tuple> = match Tuple",
      "   when {infer _, unpackof infer Rest} then Rest",
      "   else never end",
      "local type HasTwo<Tuple> = match Tuple",
      "   when {infer _, infer _, unpackof infer _} then true",
      "   else false end",
      "local joined: Concat<{string, integer}, {boolean,}> =",
      "   nil as {string, integer, boolean}",
      "local rest: Tail<{string, integer, boolean}> = nil as {integer, boolean}",
      "local empty: Tail<{string,}> = {}",
      "local enough: HasTwo<{string, integer}> = true",
      "local short: HasTwo<{string,}> = false",
      "print(joined, rest, empty, enough, short)",
   }, "\n"))
   assertEq(codes(table.concat({
      "local type Tail<Tuple> = match Tuple",
      "   when {infer _, unpackof infer Rest} then Rest else never end",
      "local wrong: Tail<{string, integer, boolean}> = {true}",
   }, "\n")), "NUPP2001")
end

function M.finitePatternsCoverThePublicStructuralForms()
   clean(table.concat({
      "local record Box<T> value: T end",
      "local type First<T> = match T when {infer A, infer B} then A end",
      "local type Value<T> = match T when {[infer K]: infer V} then V end",
      "local type Pointee<T> = match T when infer Item* then Item end",
      "local type Fixed<T> = match T when infer Item[16] then Item end",
      "local type Mutable<T> = match T when const infer Item then Item end",
      "local type Unbox<T> = match T when Box<infer Item> then Item end",
      "local type Result<T> = match T when function(infer A): infer R then R end",
      "local first: First<{string, integer}> = 'x'",
      "local value: Value<{[string]: integer}> = 1",
      "local pointee: Pointee<float*> = 1.0",
      "local fixed: Fixed<float[16]> = 1.0",
      "local mutable: Mutable<const {name: string}> = {name = 'x'}",
      "local unboxed: Unbox<Box<string>> = 'x'",
      "local result: Result<function(string): integer> = 1",
   }, "\n"))
   assertEq(codes(table.concat({
      "local type Same<T> = match T when {infer X, infer X} then X end",
      "local impossible: Same<{string, integer}> = 'x'",
   }, "\n")), "NUPP2001")
end

function M.functionPatternsInferParameterAndResultPacks()
   clean(table.concat({
      "local type Signature<T> = match T",
      "   when function(infer A...): infer R... then function(A...): R... end",
      "local mirrored: Signature<function(string, integer): (boolean, string)> = nil as any",
      "local expected: function(string, integer): (boolean, string) = mirrored",
      "local type SamePacks<T> = match T",
      "   when function(infer A...): infer A... then true else false end",
      "local different: SamePacks<function(string): integer> = false",
   }, "\n"))
   assertEq(codes(table.concat({
      "local type Signature<T> = match T",
      "   when function(infer A...): infer R... then function(A...): R... end",
      "local wrong: function(boolean): nil = nil as any",
      "local bad: Signature<function(string): integer> = wrong",
   }, "\n")), "NUPP2001")
end

function M.computedTypesExpandIntoCallablePacks()
   clean(table.concat({
      "local type Args<F> = match F",
      "   when 'pair' then {string, number}",
      "   when 'one' then {boolean,}",
      "   when 'many' then {integer}",
      "   else any end",
      "local function apply<F is string>(kind: F, ...: unpackof Args<F>): string",
      "   return kind end",
      "local pair: string = apply('pair', 'x', 1)",
      "local one: string = apply('one', true)",
      "local many: string = apply('many', 1, 2, 3)",
      "local dynamic: string = 'dynamic'",
      "local gradual: string = apply(dynamic, {}, false, 3)",
      "print(pair, one, many, gradual)",
   }, "\n"))
   assertEq(codes(table.concat({
      "local type Args<F> = match F when 'pair' then {string, number} else any end",
      "local function apply<F is string>(kind: F, ...: unpackof Args<F>): nil end",
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
   oneDiagnostic(table.concat({
      "local function apply(...: unpackof typeerror<'computed contract failed'>): nil end",
      "apply()",
   }, "\n"), "NUPP2006", "computed contract failed")
end

function M.stringFormatDerivesArgumentsFromLiteralFormats()
   clean(table.concat({
      "local name = 'Ada'",
      "local count = string.format('%s has %d messages', name, 3)",
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
      "print(count, percent, decimal, method, extended, flags, many, gradual)",
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
end

function M.templateConstructionAndOneSegmentExtractionAreFinite()
   clean(table.concat({
      "local type Event<const Name: string> = `${Name}Changed`",
      "local event: Event<'ready'> = 'readyChanged'",
      "local type Parameter<Path> =",
      "   match Path when `${infer _}:${infer Name}` then Name else never end",
      "local parameter: Parameter<'users:id'> = 'id'",
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
      "local type Public<T> = {readonly [K in keyof T as",
      "   match K when 'password' then never else K end]: T.[K]}",
      "local public: Public<{name: string, password: string}> = {name = 'Ada'}",
      "local name: string = public.name",
   }, "\n"))
end

function M.templateAmbiguityAndRemapCollisionsReportAtTheOperator()
   assertEq(codes(table.concat({
      "local type Split<T> = match T",
      "   when `${infer A}${infer B}` then A else never end",
   }, "\n")), "NUPP2132")
   assertEq(codes(table.concat({
      "local type Collision<T> = {readonly [K in keyof T as 'same']: T.[K]}",
      "local collision: Collision<{a: string, b: integer}> = nil as any",
   }, "\n")), "NUPP2130")
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

return M
