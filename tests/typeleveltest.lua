local parser = require("nupp.compiler.parser")
local cst = require("nupp.compiler.cst")
local gen = require("nupp.compiler.gen")
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

local function typeDump(typeSource)
   local parsed = parser.parse("local value: " .. typeSource, "test.g.nupp")
   assertEq(#parsed.errors, 0)
   local annotation = parsed.root.blocks[1].stats[1].types[1]
   return cst.dump(annotation), cst.textOf(parsed.root)
end

local M = {}

function M.finiteTypeOperatorSyntaxRoundTrips()
   local dump, text = typeDump("writeof Cell.[\"value\"]")
   assertEq(dump,
      "(twriteof writeof (tmember (tname Cell) . [ (tliteral \"value\") ]))")
   assertEq(text, "local value: writeof Cell.[\"value\"]")
   dump = typeDump("keyof Cell")
   assertEq(dump, "(tkeyof keyof (tname Cell))")
   dump = typeDump("writekeyof Cell")
   assertEq(dump, "(tkeyof writekeyof (tname Cell))")
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

function M.recursiveAliasesRemainForbiddenBeforeTheRecursiveGate()
   assertEq(codes("local type Loop<T> = Loop<T>"), "NUPP2115")
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
