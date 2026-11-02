local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local cst = require("nupp.compiler.syntax.cst")
local gen = require("nupp.compiler.lua.gen")
local fmt = require("nupp.tools.fmt")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local types = require("nupp.compiler.types")
local generics = require("nupp.compiler.types.generics")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local diagnosticRun = 0

local function diagnostics(source)
    diagnosticRun = diagnosticRun + 1
    env.loaded = {}
    local filename = ("typelevel-%d.nupp"):format(diagnosticRun)
    local parsed = parser.parse(source, filename)
    testAssert.eq(#parsed.errors, 0, "syntax: " .. (parsed.errors[1] and parsed.errors[1].msg or ""))

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
    testAssert.eq(codes(source), "", "expected clean check for:\n" .. source)
end

local function oneDiagnostic(source, code, message)
    local found = diagnostics(source)
    testAssert.eq(#found, 1, "one diagnostic for:\n" .. source)
    testAssert.eq(found[1].code, code)
    if found[1].msg ~= message and not found[1].msg:match("^" .. message:gsub("([^%w])", "%%%1") .. "\n  called ") then
        testAssert.eq(found[1].msg, message)
    end
end

local function typeDump(typeSource)
    local parsed = parser.parse("local value: " .. typeSource, "test.nupp")
    testAssert.eq(#parsed.errors, 0)
    local declaration = parsed.root.blocks[1].stats[1]
    assert(declaration.kind == "localStmt")
    local annotation = declaration.types[1]

    return cst.dump(annotation), cst.textOf(parsed.root)
end

local M = {}

function M.closedComptimeTypeFunctionsConstructTypes()
    clean(
        table.concat(
            {
                "@comptime local function Optional(T: type): type",
                "   return types.optional(T)",
                "end",
                "local yes: Optional(string) = 'yes'",
                "local no: Optional(string) = nil",
                "return yes, no",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Optional(T: type): type",
                    "   return types.optional(T)",
                    "end",
                    "local bad: Optional(string) = 42",
                    "return bad",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )
end

function M.closedComptimeTypeFunctionsUseScalarControlFlowAndInspection()
    clean(
        table.concat(
            {
                "@comptime local function Binary(source: string): type",
                "   local elements = {}",
                "   for index = 1, #source do",
                "      local digit = source:sub(index, index)",
                "      if digit == '0' then",
                "         elements[#elements + 1] = types.literal(0)",
                "      elseif digit == '1' then",
                "         elements[#elements + 1] = types.literal(1)",
                "      else",
                "         return types.error('expected binary digits')",
                "      end",
                "   end",
                "   return types.tuple(elements)",
                "end",
                "@comptime local function DeepElement(T: type): type",
                "   while types.kind(T) == 'array' do",
                "      T = types.elements(T)[1]",
                "   end",
                "   return T",
                "end",
                "local bits: Binary('101') = nil as any",
                "local leaf: DeepElement({{{integer}}}) = 42",
                "return bits, leaf",
            },
            "\n"
        )
    )
end

function M.closedComptimeTypeFunctionsReportApplicationFailures()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Binary(source: string): type",
                    "   return types.error('expected binary digits')",
                    "end",
                    "local bad: Binary('2')",
                },
                "\n"
            )
        ),
        "NUPP2420"
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Optional(T: type): type",
                    "   return types.optional(T)",
                    "end",
                    "local bad: Optional(string, number)",
                },
                "\n"
            )
        ),
        "NUPP2421"
    )
    testAssert.eq(
        codes(table.concat({"local function Runtime(T: any): any return T end", "local bad: Runtime(string)",}, "\n")),
        "NUPP2421"
    )
end

function M.compilerOnlyTypeHandlesCannotEnterRuntimeSignatures()
    testAssert.eq(codes("local function identity(T: type): type return T end"), "NUPP2421 NUPP2421")
    testAssert.eq(codes("local value: type = nil as any"), "NUPP2421")
end

function M.openComptimeTypeCallsCloseAfterGenericInference()
    clean(
        table.concat(
            {
                "@comptime local function Optional(T: type): type",
                "   return types.optional(T)",
                "end",
                "local function choose<T>(value: T, fallback: Optional(T)): Optional(T)",
                "   return fallback",
                "end",
                "local answer: string? = choose('ready', nil)",
                "return answer",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Optional(T: type): type",
                    "   return types.optional(T)",
                    "end",
                    "local function choose<T>(value: T, fallback: Optional(T)): Optional(T)",
                    "   return fallback",
                    "end",
                    "return choose('ready', 42)",
                },
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.openScalarTypeCallsCloseAfterConstInference()
    clean(
        table.concat(
            {
                "@comptime local function Literal(value: integer): type",
                "   return types.literal(value)",
                "end",
                "local function preserve<const N: integer>(value: N): Literal(N)",
                "   return value as any",
                "end",
                "local one: 1 = preserve(1)",
                "return one",
            },
            "\n"
        )
    )
end

function M.comptimeTypeFunctionsPreserveExistingNominalIdentity()
    clean(
        table.concat(
            {
                "local record User name: string end",
                "@comptime local function Maybe(T: type): type",
                "   return types.optional(T)",
                "end",
                "local user: Maybe(User) = new User(name = 'Ada')",
                "return user",
            },
            "\n"
        )
    )
end

function M.comptimeTypeFunctionsPreserveNestedNominalReferences()
    clean(
        table.concat(
            {
                "local record User name: string end",
                "@comptime local function Element(T: type): type",
                "   return types.elements(T)[1]",
                "end",
                "local user: Element({User}) = new User(name = 'Ada')",
                "return user",
            },
            "\n"
        )
    )
end

function M.comptimeTypeAliasesNameReusableDescriptorShapes()
    clean(
        table.concat(
            {
                "@comptime local type Field = {name: string, read: type?}",
                "@comptime local function ReadView(T: type): type",
                "   local fields: {Field} = {{name = 'value', read = T}}",
                "   return types.shape(fields)",
                "end",
                "local view: ReadView(string) = {value = 'ready'}",
                "return view.value",
            },
            "\n"
        )
    )
    oneDiagnostic(
        table.concat(
            {"@comptime local type Field = {name: string, read: type?}", "local value: Field = nil as any",},
            "\n"
        ),
        "NUPP2421",
        'comptime type alias "Field" is available only inside comptime'
    )
end

function M.comptimeReadsNominalFieldsThroughTheTypesAPI()
    clean(
        table.concat(
            {
                "local record User",
                "   name: string",
                "   age: integer",
                "end",
                "@comptime local function Structural(T: type): type",
                "   const direct = types.fields(T)",
                "   const described = types.describe(T).fields",
                "   if not described or #direct ~= 2 or #described ~= #direct then",
                "      return types.error('nominal fields were not described')",
                "   end",
                "   return types.shape(direct)",
                "end",
                "local user: Structural(User) = {name = 'Ada', age = 37}",
                "return user.name, user.age",
            },
            "\n"
        )
    )
end

function M.constrainedOpenTypeCallsExposeOnlyTheirDeclaredBound()
    clean(
        table.concat(
            {
                "@comptime local function ReadView(T: type): type<{@readonly name: string}>",
                "   return types.shape({{name = 'name', read = types.string}})",
                "end",
                "local function nameOf<T>(value: ReadView(T)): string",
                "   return value.name",
                "end",
                "return nameOf",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Bad(T: type): type<{@readonly name: string}>",
                    "   return types.integer",
                    "end",
                    "local value: Bad(string)",
                },
                "\n"
            )
        ),
        "NUPP2421"
    )
end

function M.comptimeTypePackResultsExpandThroughUnpackof()
    clean(
        table.concat(
            {
                "@comptime local function Pair(T: type): typepack",
                "   return types.pack({T, types.string})",
                "end",
                "local function closed(...: unpackof Pair(integer)): nil end",
                "local function inferred<T>(value: T, ...: unpackof Pair(T)): nil end",
                "closed(1, 'one')",
                "inferred(true, true, 'yes')",
                "return closed, inferred",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Pair(T: type): typepack",
                    "   return types.pack({T, types.string})",
                    "end",
                    "local function inferred<T>(value: T, ...: unpackof Pair(T)): nil end",
                    "inferred(true, 1, 'yes')",
                    "return inferred",
                },
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.comptimeTypeFunctionsAcceptTypePackArguments()
    clean(
        table.concat(
            {
                "@comptime local function Identity(P: typepack): typepack",
                "   return P",
                "end",
                "local function takes(...: unpackof Identity((string, integer))): nil end",
                "takes('one', 1)",
                "return takes",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Identity(P: typepack): typepack",
                    "   return P",
                    "end",
                    "local function takes(...: unpackof Identity((string, integer))): nil end",
                    "takes('one', false)",
                    "return takes",
                },
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.finiteTypeOperatorSyntaxRoundTrips()
    local dump, text = typeDump("writeof Cell.[\"value\"]")
    testAssert.eq(dump, "(twriteof writeof (tmember (tname Cell) . [ (tliteral \"value\") ]))")
    testAssert.eq(text, "local value: writeof Cell.[\"value\"]")
    dump = typeDump("keyof Cell")
    testAssert.eq(dump, "(tkeyof keyof (tname Cell))")
    dump = typeDump("writekeyof Cell")
    testAssert.eq(dump, "(tkeyof writekeyof (tname Cell))")
    dump = typeDump("{string,}")
    testAssert.eq(dump, "(ttuple { (tname string) , })")
    dump = typeDump("function<F is string>(fmt: F, ...: unpackof Args<F>): string")
    testAssert.eq(
        dump,
        "(tfunc function (generics < F is (tname string) >) ( "
        .. "(tfuncParam fmt : (tname F)) , (tfuncParam ... : "
        .. "(tpack unpackof (tname Args < (tname F) >))) ) : (tname string))"
    )
    dump = typeDump("{string, unpackof Tail}")
    testAssert.eq(dump, "(ttuple { (tname string) , unpackof (tname Tail) })")
end

function M.computedPackSyntaxFormatsIdempotently()
    local source = table.concat(
        {
            "local function apply<F is string>(...:unpackof Args<F>):nil",
            "end",
            "local value:{string,}",
            "local type More<T> = {string,unpackof T}",
        },
        "\n"
    )
    local once, errors = fmt.format(source)
    testAssert.eq(#errors, 0)
    testAssert.eq(
        once,
        table.concat(
            {
                "local function apply<F is string>(...: unpackof Args<F>): nil",
                "end",
                "",
                "local value: {string,}",
                "local type More<T> = {string, unpackof T}",
            },
            "\n"
        ) .. "\n"
    )
    local twice, again = fmt.format(once)
    testAssert.eq(#again, 0)
    testAssert.eq(twice, once)
end

function M.keyAndIndexedMemberOperatorsRespectCapabilities()
    clean(
        table.concat(
            {
                "local type Cell = {@readonly value: string, @writeonly value: string | integer}",
                "local readKey: keyof Cell = 'value'",
                "local writeKey: writekeyof Cell = 'value'",
                "local readValue: Cell.['value'] = 'ready'",
                "local writeValue: writeof Cell.['value'] = 4",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat({"local type Cell = {@readonly value: string}", "local bad: writekeyof Cell = 'value'",}, "\n")
        ),
        "NUPP2001"
    )
end

function M.propertyCapabilityAnnotationsWorkInStructuralShapes()
    clean(
        table.concat(
            {
                "local type Cell = {@readonly value: string, @writeonly value: string | integer}",
                "local readKey: keyof Cell = 'value'",
                "local writeKey: writekeyof Cell = 'value'",
                "local readValue: Cell.['value'] = 'ready'",
                "local writeValue: writeof Cell.['value'] = 4",
                "local type ReadonlyView<T> = {@readonly [K in keyof T]: T.[K]}",
                "local type Sink<T> = {@writeonly [K in writekeyof T]: writeof T.[K]}",
                "local source: ReadonlyView<{name: string}> = {name = 'Ada'}",
                "local sink: Sink<{name: string}> = nil as any",
                "sink.name = 'Grace'",
                "print(source.name)",
            },
            "\n"
        )
    )
end

function M.mappedShapesReduceAfterGenericSubstitution()
    clean(
        table.concat(
            {
                "local type ReadonlyView<T> = {@readonly [K in keyof T]: T.[K]}",
                "local type Sink<T> = {@writeonly [K in writekeyof T]: writeof T.[K]}",
                "local source: ReadonlyView<{name: string, age: integer}> = {name = 'Ada', age = 37}",
                "local sink: Sink<{name: string, age: integer}> = nil as any",
                "sink.name = 'Grace'",
                "sink.age = 42",
                "local name: string = source.name",
            },
            "\n"
        )
    )
end

function M.broadAndMissingMemberReductionsReportLocally()
    testAssert.eq(codes("local value: {@readonly [K in string]: K}"), "NUPP2130")
    testAssert.eq(codes("local value: {name: string}.['missing']"), "NUPP2130")
end

function M.finiteReducerCancellationIsBounded()
    local deep = types.string
    for _ = 1, 40 do
        deep = types.array(deep)
    end
    local polls = 0
    local _, err = generics.reduce(deep, nil, nil, {
        cancelled = function()
            polls = polls + 1
            return true
        end
    })
    testAssert.eq(err, "type reduction cancelled")
    testAssert.eq(polls, 1, "the finite reducer polls its cancellation control")
end

function M.constParametersSizeArraysWithoutRuntimeSpecialization()
    clean(
        table.concat(
            {
                "local record Matrix<T, const Rows: integer, const Columns: integer>",
                "   values: T[Rows * Columns]",
                "end",
                "local matrix: Matrix<float, 4, 4> = nil as any",
                "local values: float[16] = matrix.values",
            },
            "\n"
        )
    )
end

function M.constFunctionInferenceRequiresIdenticalKnownValues()
    clean(
        table.concat(
            {
                "local record Field<const Name: string> end",
                "local function field<const Name: string>(name: Name): Field<Name>",
                "   return nil as any",
                "end",
                "local named: Field<'name'> = field('name')",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat({"local function same<const S: string>(left: S, right: S): nil end", "same('x', 'y')",}, "\n")
        ),
        "NUPP2131"
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local function field<const S: string>(name: S): nil end",
                    "local dynamic: string = 'x'",
                    "field(dynamic)",
                },
                "\n"
            )
        ),
        "NUPP2131"
    )
end

function M.constInferenceSeparatesIntegersThatShareADecimalSpelling()
    -- `tostring` on a LuaJIT number is %.14g, so these two admitted integers
    -- share a spelling. Interning a literal under that spelling gave them one
    -- type, and a const parameter then agreed with itself across both.
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local function same<const N: integer>(left: N, right: N): nil end",
                    "same(1000000000000000, 1000000000000001)",
                },
                "\n"
            )
        ),
        "NUPP2131"
    )
    clean(
        table.concat(
            {
                "local function same<const N: integer>(left: N, right: N): nil end",
                "same(1000000000000001, 1000000000000001)",
            },
            "\n"
        )
    )
end

function M.numericLiteralAndMemberIndexSyntaxStayDistinct()
    clean(
        table.concat(
            {
                "local type Sixteen = 16",
                "local fixed: float[4 * 4] = nil as any",
                "local exact: float[16] = fixed",
                "local type Numeric = {[integer]: string}",
                "local type Indexed = Numeric.[16]",
                "local indexed: Indexed = 'value'",
            },
            "\n"
        )
    )
end

function M.computedTypesExpandIntoCallablePacks()
    clean(
        table.concat(
            {
                "@comptime local function Args(F: type): typepack",
                "   local info = types.describe(F)",
                "   if info.kind ~= 'literal' then return types.pack({}, types.any) end",
                "   if info.value == 'pair' then return types.pack({types.string, types.number}) end",
                "   if info.value == 'one' then return types.pack({types.bool}) end",
                "   if info.value == 'many' then return types.pack({}, types.integer) end",
                "   return types.pack({}, types.any)",
                "end",
                "local function apply<F is string>(kind: F, ...: unpackof Args(F)): string",
                "   return kind end",
                "local pair: string = apply('pair', 'x', 1)",
                "local one: string = apply('one', true)",
                "local many: string = apply('many', 1, 2, 3)",
                "local dynamic: string = 'dynamic'",
                "local gradual: string = apply(dynamic, {}, false, 3)",
                "print(pair, one, many, gradual)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@comptime local function Args(F: type): typepack",
                    "   local info = types.describe(F)",
                    "   if info.kind == 'literal' and info.value == 'pair' then",
                    "      return types.pack({types.string, types.number})",
                    "   end",
                    "   return types.pack({}, types.any)",
                    "end",
                    "local function apply<F is string>(kind: F, ...: unpackof Args(F)): nil end",
                    "apply('pair', 'x', 'wrong')",
                },
                "\n"
            )
        ),
        "NUPP2006"
    )
    testAssert.eq(
        codes(table.concat({"local function apply(...: unpackof {string,}): nil end", "apply(1)",}, "\n")),
        "NUPP2006"
    )
    clean(
        table.concat(
            {
                "local type AddHead<Tail> = {string, unpackof Tail}",
                "local function apply(...: unpackof AddHead<{number, boolean}>): nil end",
                "apply('x', 1, true)",
            },
            "\n"
        )
    )
    local failure = diagnostics(
        table.concat(
            {
                "@comptime local function Failure(): typepack",
                "   return types.error('computed contract failed')",
                "end",
                "local function apply(...: unpackof Failure()): nil end",
                "apply()",
            },
            "\n"
        )
    )
    testAssert.eq(#failure, 1, "one authored type-function diagnostic")
    testAssert.eq(failure[1].code, "NUPP2420")
    assert(failure[1].msg:match("^computed contract failed"), "the authored message begins the diagnostic")
end

function M.stringFormatDerivesArgumentsFromLiteralFormats()
    clean(
        table.concat(
            {
                "@derive(types.debug)",
                "local record User name: string end",
                "local user = new User(name = 'Ada')",
                "local name = 'Ada'",
                "local count = string.format('%s has %d messages', name, 3)",
                "local debug = string.format('user=%?', user)",
                "local debugMethod = ('user=%?'):format(user)",
                "local percent = string.format('100%% ready')",
                "local decimal = string.format('%.2f', 1.5)",
                "local method = ('%d'):format(3)",
                "local extended = string.format("
                .. "'%a %A %c %d %i %o %u %x %X %e %E %f %g %G %p %q %s', "
                .. "1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, {}, true, 'text')",
                "local flags = string.format('%-+#09.2f', 1.5)",
                "local many = string.format('%d%d%d%d%d%d%d%d%d', 1, 2, 3, 4, 5, 6, 7, 8, 9)",
                "local dynamic: string = '%s'",
                "local gradual = string.format(dynamic, {}, false, 3)",
                "print(count, debug, debugMethod, percent, decimal, method, extended, flags, many, gradual)",
            },
            "\n"
        )
    )
    oneDiagnostic(
        "local bad = string.format('%d', 'three')\nprint(bad)",
        "NUPP2006",
        "argument 2: string is not a number"
    )
    oneDiagnostic(
        "local bad = string.format('%d')\nprint(bad)",
        "NUPP2006",
        "omitted argument 2 supplies nil, not number"
    )
    oneDiagnostic(
        "local bad = string.format('%d', 1, 2)\nprint(bad)",
        "NUPP2007",
        "too many arguments (expected 2, got 3)"
    )
    oneDiagnostic(
        "local bad = string.format('plain', 1)\nprint(bad)",
        "NUPP2007",
        "too many arguments (expected 1, got 2)"
    )
    oneDiagnostic(
        "local bad = string.format('%z', 1)\nprint(bad)",
        "NUPP2006",
        'invalid string.format directive starting at "%z"'
    )
    oneDiagnostic(
        "local bad = string.format('%..f', 1)\nprint(bad)",
        "NUPP2006",
        'invalid string.format directive starting at "%..f"'
    )
    oneDiagnostic(
        "local bad = string.format('%100d', 1)\nprint(bad)",
        "NUPP2006",
        'invalid string.format directive starting at "%100"'
    )
    oneDiagnostic(
        "local bad = string.format('%*d', 1)\nprint(bad)",
        "NUPP2006",
        'invalid string.format directive starting at "%*d"'
    )
    oneDiagnostic(
        "local bad = string.format('%F', 1)\nprint(bad)",
        "NUPP2006",
        'invalid string.format directive starting at "%F"'
    )
    oneDiagnostic(
        "local bad = string.format('%.100f', 1)\nprint(bad)",
        "NUPP2006",
        'invalid string.format directive starting at "%.100"'
    )
    oneDiagnostic("local bad = ('%d'):format('three')\nprint(bad)", "NUPP2006", "argument 1: string is not a number")
    oneDiagnostic(
        "local bad = string.format('%?', 'wrong')\nprint(bad)",
        "NUPP2006",
        "argument 2: string is not a Debug"
    )
end

function M.formatArgumentsIsReusableByUserFormattingWrappers()
    clean(
        table.concat(
            {
                "local function format<F is string>(fmt: F, ...: unpackof types.formatarguments(F)): string",
                "   return string.format(fmt, ...)",
                "end",
                "local value = format('%s=%d', 'count', 3)",
                "print(value)",
            },
            "\n"
        )
    )
    oneDiagnostic(
        table.concat(
            {
                "local function format<F is string>(fmt: F, ...: unpackof types.formatarguments(F)): string",
                "   return string.format(fmt, ...)",
                "end",
                "local value = format('%d', 'wrong')",
                "print(value)",
            },
            "\n"
        ),
        "NUPP2006",
        "argument 2: string is not a number"
    )
    oneDiagnostic(
        table.concat(
            {
                "local function format<F is string>(fmt: F, ...: unpackof types.formatarguments(F)): string",
                "   return string.format(fmt, ...)",
                "end",
                "local value = format('%?', {})",
                "print(value)",
            },
            "\n"
        ),
        "NUPP2006",
        "%? is available only to compiler-lowered formatting APIs"
    )
end

function M.luaDebugFormatLoweringUsesTheDirectiveScanner()
    local luaFormat = require("nupp.compiler.lua.luaformat")
    local parsed, why = luaFormat.analyze("%-+#09.2f %q %% %d %?")
    testAssert.eq(why, nil)
    testAssert.eq(parsed and parsed.format, "%-+#09.2f %q %% %d %s")
    testAssert.eq(parsed and parsed.debugArguments[1], false)
    testAssert.eq(parsed and parsed.debugArguments[4], true)
    local missing, invalid = luaFormat.analyze("%..f")
    testAssert.eq(missing, nil)
    testAssert.eq(invalid, 'invalid string.format directive starting at "%..f"')
end

function M.osDateDerivesItsResultFromALiteralFormat()
    clean(
        table.concat(
            {
                "local stamp: string = os.date('%Y-%m-%dT%H:%M:%S')",
                "local default: string = os.date()",
                "local fields = os.date('*t')",
                "local utc = os.date('!*t')",
                "const storedFormat = '*t'",
                "local stored = os.date(storedFormat)",
                "local chosen: os.DateFields | string = os.date(...)",
                "local at: number = os.time(os.date('*t'))",
                "local year: integer, dst: boolean = fields.year, fields.isdst",
                "return stamp, default, utc.yday, stored.wday, chosen, at, year, dst",
            },
            "\n"
        )
    )
    oneDiagnostic(
        "local held: string = os.date('*t')\nprint(held)",
        "NUPP2001",
        "cannot initialize held: DateFields is not a string"
    )
    oneDiagnostic("local fields = os.date('*t')\nprint(fields.mnoth)", "NUPP2004", 'no field "mnoth" in DateFields')
    oneDiagnostic(
        "local bad = os.date('*t and more')\nprint(bad)",
        "NUPP2006",
        'os.date reads "*t" and ignores the rest of "*t and more"'
    )
    oneDiagnostic(
        "local bad = os.date('%Y-%m-%')\nprint(bad)",
        "NUPP2006",
        'os.date format "%Y-%m-%" ends in a lone "%"'
    )
end

function M.luaPatternsDeriveLiteralCaptureResults()
    clean(
        table.concat(
            {
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
            },
            "\n"
        )
    )
    oneDiagnostic(
        "local value: integer? = string.match('name', '([a-z]+)')\nprint(value)",
        "NUPP2001",
        "cannot initialize value: string? is not a integer? (member string does not fit)"
    )
    oneDiagnostic(
        "local bad = string.match('name', '[abc')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: malformed pattern"
    )
    oneDiagnostic(
        "local bad = string.gmatch('name', '%')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: malformed pattern"
    )
    oneDiagnostic(
        "local bad = string.match('name', '%b(')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: malformed pattern"
    )
    oneDiagnostic(
        "local bad = string.match('name', '%fabc')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: malformed pattern"
    )
    oneDiagnostic(
        "local bad = string.match('name', ')')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: unexpected ')'"
    )
    oneDiagnostic(
        "local bad = string.match('name', '(')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: unfinished capture"
    )
    oneDiagnostic(
        "local bad = string.gsub('name', '[abc', '#')\nprint(bad)",
        "NUPP2006",
        "invalid Lua pattern: malformed pattern"
    )
end

function M.comptimeTypeLibraryDoesNotLeakIntoRuntimeCode()
    clean(
        table.concat(
            {
                "local type TypeLibrary = {",
                "   @readonly string: @comptime type,",
                "   @readonly optional: @comptime function(value: type): type,",
                "}",
                "@comptime local function Maybe(T: type): type",
                "   return types.optional(T)",
                "end",
                "local value: Maybe(string) = nil",
                "return value",
            },
            "\n"
        )
    )
    oneDiagnostic(
        "local leaked = types.string",
        "NUPP2421",
        'compiler-only member "string" is available only inside comptime'
    )
    oneDiagnostic(
        "local leaked = types.optional",
        "NUPP2421",
        'compiler-only member "optional" is available only inside comptime'
    )
    oneDiagnostic(
        "local leaked = types.error",
        "NUPP2421",
        'compiler-only member "error" is available only inside comptime'
    )
    oneDiagnostic(
        table.concat(
            {
                "local type ScalarLibrary = {@readonly step: @comptime function(integer): integer}",
                "local library: ScalarLibrary = nil as any",
                "local leaked = library.step",
            },
            "\n"
        ),
        "NUPP2421",
        'compiler-only member "step" is available only inside comptime'
    )
end

function M.compilerOnlyNamespaceAliasesKeepRuntimeRefusals()
    oneDiagnostic(
        "local library = require('types')\nlocal leaked = library.string",
        "NUPP2421",
        'compiler-only member "string" is available only inside comptime'
    )
    clean("local types: {string: string} = {string = 'runtime'}\nreturn types.string")
end

function M.templateConstructionAndOneSegmentExtractionAreFinite()
    clean(
        table.concat(
            {
                "local type Event<const Name: string> = `${Name}Changed`",
                "local event: Event<'ready'> = 'readyChanged'",
                "@comptime local function Parameter(Path: type): type",
                "   local info = types.describe(Path)",
                "   local name = info.kind == 'literal' and (info.value as string):match(':(.+)$') or nil",
                "   if name then return types.literal(name) end",
                "   return types.never",
                "end",
                "local parameter: Parameter('users:id') = 'id'",
            },
            "\n"
        )
    )
end

function M.mappedRemappingBuildsDependentEventAdapters()
    clean(
        table.concat(
            {
                "local type Events<T> = {",
                "   @readonly [K in keyof T as `${K}Changed`]: function(value: T.[K]): nil",
                "}",
                "local events: Events<{name: string, age: integer}> = nil as any",
                "local onName: function(value: string): nil = events.nameChanged",
                "local onAge: function(value: integer): nil = events.ageChanged",
                "@comptime local function PublicKey(K: type): type",
                "   local info = types.describe(K)",
                "   if info.kind == 'literal' and info.value == 'password' then return types.never end",
                "   return K",
                "end",
                "local type Public<T> = {@readonly [K in keyof T as PublicKey(K)]: T.[K]}",
                "local public: Public<{name: string, password: string}> = {name = 'Ada'}",
                "local name: string = public.name",
            },
            "\n"
        )
    )
end

function M.remapCollisionsReportAtTheOperator()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local type Collision<T> = {@readonly [K in keyof T as 'same']: T.[K]}",
                    "local collision: Collision<{a: string, b: integer}> = nil as any",
                },
                "\n"
            )
        ),
        "NUPP2130"
    )
end

function M.removedTypeProgrammingSyntaxHasNoSpecialCst()
    local parsed = parser.parse("local value: typeerror<'broken'>", "removed.nupp")
    testAssert.eq(#parsed.errors, 0)
    assert(not cst.dump(parsed.root):find("ttypeerror", 1, true), "typeerror is now an ordinary generic type name")
    local matched = parser.parse("local type Old<T> = match T when infer X then X end", "removed.nupp")
    assert(#matched.errors > 0, "type-level match and infer are no longer grammar")
end

function M.templateProductsHaveABoundedDiagnostic()
    local left, right = {}, {}
    for j = 1, 17 do
        left[j] = ("'l%d'"):format(j)
        right[j] = ("'r%d'"):format(j)
    end
    local source = table.concat(
        {
            "local type Left = " .. table.concat(left, " | "),
            "local type Right = " .. table.concat(right, " | "),
            "local value: `${Left}${Right}`",
        },
        "\n"
    )
    testAssert.eq(codes(source), "NUPP2132")
end

function M.boundsIntersectionsAndIndexersShareTheMemberVocabulary()
    clean(
        table.concat(
            {
                "local type NamedKeys<T is {@readonly name: string}> = keyof T",
                "local named: NamedKeys<{@readonly name: string, @readonly age: integer}> = 'name'",
                "local both: keyof ({@readonly left: string} & {@readonly right: integer}) = 'right'",
                "local indexed: keyof {@readonly [string]: integer} = 'arbitrary'",
            },
            "\n"
        )
    )
end

function M.constArithmeticErrorsStayAtTheTypeBoundary()
    testAssert.eq(codes("local huge: float[9007199254740991 + 1]"), "NUPP2131")
    testAssert.eq(codes("local divided: float[4 // 0]"), "NUPP2131")
end

function M.constExpressionsAcceptNumericSeparators()
    clean(
        table.concat(
            {
                "local grouped: float[1_0 + 6] = nil as any",
                "local signed: float[-1_0 + 26] = grouped",
                "local hexadecimal: float[0x1_0] = signed",
            },
            "\n"
        )
    )
end

function M.constArgumentsParticipateInNominalIdentity()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Field<const Name: string> end",
                    "local left: Field<'left'> = nil as any",
                    "local right: Field<'right'> = left",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )
end

function M.emptyGenericMemberMapsLearnTheirFirstDeclaration()
    local declaration = types.nominal("InitiallyEmptySurface", "record")
    local parameter = types.typevar("T", "initially-empty-surface")
    declaration.typeParams = {parameter}
    local bindings = {[parameter] = types.string}
    local instance = generics.instantiate(declaration, bindings)
    local surfaces = {"byname", "writeByname", "staticByname", "staticWriteByname", "metamethods"}
    for _, name in ipairs(surfaces) do
        testAssert.eq(next(instance[name]), nil)
        declaration[name].late = parameter
    end
    testAssert.eq(generics.instantiate(declaration, bindings), instance)
    for _, name in ipairs(surfaces) do
        testAssert.eq(instance[name].late, types.string)
    end
end

function M.concreteSubgraphsAreRecognizedOncePerRefresh()
    local child = types.nominal("ConcreteMemberChild", "record")
    local element = types.typevar("T", "concrete-member-child")
    child.typeParams = {element}
    local closed = types.tuple({types.string, types.number})
    child.byname.value, child.byname.element = closed, element
    local parent = types.nominal("ConcreteMemberParent", "record")
    local left = types.typevar("Left", "concrete-member-parent:left")
    local right = types.typevar("Right", "concrete-member-parent:right")
    parent.typeParams = {left, right}
    parent.byname.left = generics.instantiate(child, {[element] = left})
    parent.byname.right = generics.instantiate(child, {[element] = right})
    local original, visits = types.hasTypevar, 0
    types.hasTypevar = function(value)
        if value == closed then
            visits = visits + 1
        end
        return original(value)
    end
    local ok, problem = pcall(function()
        local bindings = {[left] = types.string, [right] = types.number}
        local instance = generics.instantiate(parent, bindings)
        testAssert.eq(visits, 1, "a concrete subgraph is independent of the two binding maps")
        testAssert.eq(instance.byname.left.byname.value, closed)
        testAssert.eq(instance.byname.right.byname.value, closed)
        testAssert.eq(instance.byname.left.byname.element, types.string)
        testAssert.eq(instance.byname.right.byname.element, types.number)
        child.byname.late = element
        testAssert.eq(generics.instantiate(parent, bindings), instance)
        testAssert.eq(instance.byname.left.byname.late, types.string)
        testAssert.eq(instance.byname.right.byname.late, types.number)
        testAssert.eq(visits, 2, "a changed child starts a fresh containment walk")
    end)
    types.hasTypevar = original
    assert(ok, problem)
end

function M.sharedGenericSubstitutionsCompleteOncePerRefresh()
    local declaration = types.nominal("SharedSubstitutionSurface", "record")
    local parameter = types.typevar("T", "shared-substitution-surface")
    declaration.typeParams = {parameter}
    local leaf = types.func({parameter}, {parameter})
    local shared = types.func({leaf, leaf}, {leaf})
    local surfaces = {"byname", "writeByname", "staticByname", "staticWriteByname", "metamethods"}
    for _, name in ipairs(surfaces) do
        for index = 1, 6 do
            declaration[name]["member" .. index] = shared
        end
    end
    local bindings = {[parameter] = types.string}
    local original, visits = types.funcWith, 0
    types.funcWith = function(source, changes)
        if source == leaf or source == shared then
            visits = visits + 1
        end
        return original(source, changes)
    end
    local ok, problem = pcall(function()
        local first = generics.instantiate(declaration, bindings)
        testAssert.eq(visits, 2, "shared function graphs are substituted once in one refresh")
        local expected = first.byname.member1
        testAssert.eq(expected.params[1].params[1], types.string)
        for _, name in ipairs(surfaces) do
            testAssert.eq(first[name].member6, expected)
        end
        declaration.byname.late = shared
        local again = generics.instantiate(declaration, bindings)
        testAssert.eq(again, first)
        testAssert.eq(again.byname.late, expected)
        testAssert.eq(visits, 4, "a later explicit refresh gets a fresh substitution walk")
    end)
    types.funcWith = original
    assert(ok, problem)
end

function M.distinctGenericFunctionsShareTheirSubstitutedPacks()
    local declaration = types.nominal("SharedPackSurface", "record")
    local parameter = types.typevar("T", "shared-pack-surface")
    declaration.typeParams = {parameter}
    local ordinary = types.func({parameter, parameter}, {parameter}, false, {"borrows", "plain"})
    declaration.byname.ordinary = ordinary
    declaration.byname.never = types.funcWith(ordinary, {noreturn = true})
    declaration.byname.noYield = types.funcWith(ordinary, {noYield = true})
    declaration.byname.foreign = types.funcWith(ordinary, {foreign = true})
    local original, heads = types.pack, {}
    types.pack = function(head, tail, modes, names)
        if #head == 2 and head[1] == types.string and head[2] == types.string then
            heads[head] = true
        end
        return original(head, tail, modes, names)
    end
    local ok, instance = pcall(generics.instantiate, declaration, {[parameter] = types.string})
    types.pack = original
    assert(ok, instance)
    local count = 0
    for _ in pairs(heads) do
        count = count + 1
    end
    testAssert.eq(count, 1, "distinct functions sharing a pack substitute one head sequence")
    local pack = instance.byname.ordinary.paramPack
    testAssert.eq(pack.modes[1], "borrows")
    testAssert.eq(instance.byname.noYield.paramPack, pack)
    assert(instance.byname.noYield.noYield and instance.byname.never.noreturn and instance.byname.foreign.foreign)
end

function M.oneGenericRefreshKeepsDistinctArgumentMapsSeparate()
    local child = types.nominal("DistinctMapChild", "record")
    local element = types.typevar("T", "distinct-map-child")
    child.typeParams = {element}
    child.byname.get = types.func({}, {element})
    local parent = types.nominal("DistinctMapParent", "record")
    local left = types.typevar("Left", "distinct-map-parent:left")
    local right = types.typevar("Right", "distinct-map-parent:right")
    parent.typeParams = {left, right}
    parent.byname.left = generics.instantiate(child, {[element] = left})
    parent.byname.right = generics.instantiate(child, {[element] = right})
    local instance = generics.instantiate(parent, {[left] = types.string, [right] = types.number})
    testAssert.eq(instance.byname.left.byname.get.rets[1], types.string)
    testAssert.eq(instance.byname.right.byname.get.rets[1], types.number)
    assert(instance.byname.left ~= instance.byname.right, "one walk must preserve distinct nominal arguments")
end

function M.unrelatedSubstitutionKeepsOpenNominalArgumentsUnchanged()
    local declaration = types.nominal("UnchangedApplication", "record")
    local element = types.typevar("Element", "unchanged-application:element")
    element.default = types.string
    local rest = types.packvar("Rest", "unchanged-application")
    local size = types.constvar("Size", "integer", "unchanged-application")
    local unrelated = types.typevar("Other", "unchanged-application:other")
    declaration.typeParams, declaration.packParams, declaration.constParams = {element}, {rest}, {size}
    local openPack = types.pack({}, {kind = "generic", var = rest})
    declaration.byname.value = element
    declaration.byname.values = types.packResult(openPack)
    declaration.byname.storage = types.carray(types.uint8, nil, size)
    local bindings = {[element] = element, [rest] = openPack, [size] = size}
    local open = generics.instantiate(declaration, bindings)
    declaration.byname.next = types.optional(open)
    open = generics.instantiate(declaration, bindings)

    local instantiate, visits = generics.instantiate, 0
    generics.instantiate = function(owner, bindings)
        visits = visits + 1
        return instantiate(owner, bindings)
    end
    local ok, rebound = pcall(generics.rebind, open, {[unrelated] = types.number})
    generics.instantiate = instantiate
    assert(ok, rebound)
    testAssert.eq(rebound, open, "unrelated substitution preserves the exact nominal")
    testAssert.eq(visits, 0, "an unrelated binder must not expand a recursive member graph")

    local answers = types.pack({types.string}, {kind = "homogeneous", type = types.integer}, {"borrows"})
    local closed = generics.rebind(open, {
        [element] = types.integer,
        [rest] = answers,
        [size] = types.constLiteral("integer", 4),
    })
    assert(closed ~= open, "changed arguments produce their own application")
    testAssert.eq(closed.byname.value, types.integer)
    testAssert.eq(closed.byname.values.pack.head[1], types.string)
    testAssert.eq(closed.byname.values.pack.modes[1], "borrows")
    testAssert.eq(closed.byname.values.pack.tail.type, types.integer)
    testAssert.eq(closed.byname.storage.count, 4)
    local recursive = false
    for _, member in ipairs(closed.byname.next.members) do
        recursive = recursive or member == closed
    end
    assert(recursive, "changed arguments preserve the recursive application")

    local materialized = generics.materialize(open, {})
    testAssert.eq(materialized.typeArgs[1], types.string, "materialization still applies the declared default")
    testAssert.eq(materialized.packArgs[1].tail.kind, "unknown", "unmapped pack arguments still materialize")
end

function M.explicitRefreshReachesAnUnchangedOpenChild()
    local parent = types.nominal("UnchangedChildParent", "record")
    local child = types.nominal("UnchangedChild", "record")
    local parentParameter = types.typevar("T", "unchanged-child-parent")
    local childParameter = types.typevar("T", "unchanged-child")
    parent.typeParams, child.typeParams = {parentParameter}, {childParameter}
    child.byname.value = childParameter
    local openChild = generics.instantiate(child, {[childParameter] = childParameter})
    parent.byname.child = openChild
    local first = generics.instantiate(parent, {[parentParameter] = types.string})

    child.byname.value = types.integer
    child.byname.get = types.func({}, {childParameter})
    local refreshed = generics.instantiate(parent, {[parentParameter] = types.string})
    testAssert.eq(refreshed, first)
    testAssert.eq(refreshed.byname.child, openChild)
    testAssert.eq(openChild.byname.value, types.integer, "explicit refresh visits an unrelated open child")
    testAssert.eq(openChild.byname.get.rets[1], childParameter)
end

function M.unchangedReservedApplicationsStillComplete()
    for _, nested in ipairs({false, true}) do
        local child = types.nominal("ReservedUnchangedChild", "record")
        local parameter = types.typevar("T", "reserved-unchanged-child:" .. tostring(nested))
        child.typeParams = {parameter}
        local reserved = generics.reserveInstantiation(child, {[parameter] = parameter})
        child.byname.value = parameter
        child.byname.get = types.func({}, {parameter})
        local unrelated = types.typevar("Other", "reserved-unchanged-parent:" .. tostring(nested))
        local completed
        if nested then
            local parent = types.nominal("ReservedUnchangedParent", "record")
            parent.typeParams, parent.byname.child = {unrelated}, reserved
            completed = generics.instantiate(parent, {[unrelated] = types.string}).byname.child
        else
            completed = generics.rebind(reserved, {[unrelated] = types.string})
        end
        testAssert.eq(completed, reserved, "completion preserves the reserved nominal")
        testAssert.eq(completed.byname.value, parameter)
        testAssert.eq(completed.byname.get.rets[1], parameter)
    end
end

function M.cachedGenericInstantiationsLearnLateDeclaredMembers()
    local declaration = types.nominal("LateSurface", "record")
    local parameter = types.typevar("T", "late-surface-test")
    declaration.typeParams = {parameter}

    local first = generics.instantiate(declaration, {[parameter] = types.string})
    testAssert.eq(first.byname.get, nil, "the early instance starts incomplete")

    declaration.byname.get = types.func({declaration}, {parameter})
    declaration.metamethods.__tostring = types.func({declaration}, {types.string})
    local refreshed = generics.instantiate(declaration, {[parameter] = types.string})

    testAssert.eq(refreshed, first, "refreshing preserves nominal identity")
    local getter = refreshed.byname.get
    local stringify = refreshed.metamethods.__tostring
    assert(getter and getter.tag == "func")
    assert(stringify and stringify.tag == "func")
    testAssert.eq(getter.rets[1], types.string, "late members are specialized onto the cached instance")
    testAssert.eq(stringify.rets[1], types.string, "late metamethods are copied onto the cached instance")
end

function M.genericMemberIdentitiesIgnoreHashIterationOrder()
    local declaration = types.nominal("OrderedSurface", "record")
    local argument = types.nominal("OrderedArgument", "record")
    local parameter = types.typevar("T", "ordered-surface-test")
    declaration.typeParams = {parameter}
    local surfaces = {"byname", "writeByname", "staticByname", "staticWriteByname", "metamethods"}
    local watched = {}
    for index, surface in ipairs(surfaces) do
        local members = declaration[surface]
        members.alpha = types.tuple({parameter, types.literal(index, types.number)})
        members.zeta = types.tuple({parameter, types.literal(index + #surfaces, types.number)})
        watched[members] = true
    end

    -- Force the source maps to enumerate backwards; relying on one process's
    -- hash seed would let a nondeterministic compiler pass this regression.
    local originalPairs = pairs
    _G.pairs = function(value)
        if not watched[value] then
            return originalPairs(value)
        end
        local names, index = {"zeta", "alpha"}, 0

        return function()
            index = index + 1
            local name = names[index]
            if name then
                return name, value[name]
            end
        end
    end
    local ok, instance = pcall(generics.instantiate, declaration, {[parameter] = argument})
    _G.pairs = originalPairs
    assert(ok, instance)
    for _, surface in ipairs(surfaces) do
        local members = instance[surface]
        testAssert.eq(members.alpha.elems[1], argument, surface .. " alpha argument")
        testAssert.eq(members.zeta.elems[1], argument, surface .. " zeta argument")
        local alpha = assert(tonumber(members.alpha.id:match("(%d+)$")))
        local zeta = assert(tonumber(members.zeta.id:match("(%d+)$")))
        assert(alpha < zeta, surface .. " identities depend on member map enumeration")
    end
end

function M.recursiveGenericMethodsRefreshEachInstanceOncePerWalk()
    -- Issue #15: each separately bound method contributes another open Handle<T>.
    -- A stack-only recursion guard expands every path between those instances.
    local source = {"local record Handle<T>", "    id: integer"}
    for index = 1, 6 do
        source[#source + 1] = ("    method%d: function(self: Handle<T>): nil"):format(index)
    end
    source[#source + 1] = "end"
    for index = 1, 6 do
        source[#source + 1] = ("function Handle.method%d<T>(self: Handle<T>): nil end"):format(index)
    end

    -- Count work rather than wall time, and stop a regression before it can stall
    -- the suite for minutes. Restore the entry point even when the check fails.
    local instantiate, visits = generics.instantiate, 0
    generics.instantiate = function(declaration, bindings)
        visits = visits + 1
        assert(visits <= 10000, "recursive generic member refresh revisits completed instances")
        return instantiate(declaration, bindings)
    end
    local ok, problem = pcall(clean, table.concat(source, "\n"))
    generics.instantiate = instantiate
    assert(ok, problem)
end

function M.sharedGenericMembersRefreshAgainAfterDeclarationChanges()
    local parent = types.nominal("SharedParent", "record")
    local child = types.nominal("SharedChild", "record")
    local parentParameter = types.typevar("T", "shared-parent-test")
    local childParameter = types.typevar("T", "shared-child-test")
    parent.typeParams, child.typeParams = {parentParameter}, {childParameter}
    child.byname.value = childParameter
    local openChild = generics.instantiate(child, {[childParameter] = parentParameter})
    parent.byname.left, parent.byname.right = openChild, openChild

    local first = generics.instantiate(parent, {[parentParameter] = types.string})
    local shared = first.byname.left
    testAssert.eq(first.byname.right, shared, "both paths retain one nominal identity")
    testAssert.eq(shared.byname.value, types.string, "the nested argument is substituted")

    child.byname.value = types.integer
    child.byname.get = types.func({}, {childParameter})
    child.writeByname.value = types.integer
    child.staticByname.get = types.func({}, {childParameter})
    child.staticWriteByname.value = childParameter
    child.metamethods.__tostring = types.func({}, {types.string})
    local refreshed = generics.instantiate(parent, {[parentParameter] = types.string})
    testAssert.eq(refreshed, first, "a later walk preserves the parent")
    testAssert.eq(refreshed.byname.left, shared, "a later walk preserves the child")
    testAssert.eq(shared.byname.value, types.integer, "a replaced nested member is refreshed")
    testAssert.eq(shared.byname.get.rets[1], types.string, "a late nested member is specialized")
    testAssert.eq(shared.writeByname.value, types.integer)
    testAssert.eq(shared.staticByname.get.rets[1], types.string)
    testAssert.eq(shared.staticWriteByname.value, types.string)
    testAssert.eq(shared.metamethods.__tostring.rets[1], types.string)

    local other = generics.instantiate(parent, {[parentParameter] = types.number})
    assert(other ~= first, "different arguments retain distinct parent identities")
    assert(other.byname.left ~= shared, "different arguments retain distinct child identities")
    testAssert.eq(other.byname.left.byname.get.rets[1], types.number)
end

function M.typeComputationAndConstBindersEraseFromGeneratedLua()
    local source = table.concat(
        {
            "local function field<const Name: string>(name: Name): Name",
            "   return name",
            "end",
            "local type View<T> = {@readonly [K in keyof T]: T.[K]}",
            "local value: View<{name: string}> = {name = field('ok')}",
            "return value.name",
        },
        "\n"
    )
    clean(source)
    local parsed = parser.parse(source, "erase.nupp")
    local lua, emitted = gen.generate(parsed, "erase")
    testAssert.eq(#emitted, 0, "code generation diagnostics")
    assert(not lua:find("const Name", 1, true), "const binder reached runtime Lua")
    assert(not lua:find("keyof", 1, true), "type operator reached runtime Lua")
    local chunk = assert(loadstring(lua))
    testAssert.eq(chunk(), "ok")
end

function M.comptimeCallsInAnnotationPositionEraseFromGeneratedLua()
    local source = table.concat(
        {
            "@comptime local function Optional(T: type): type",
            "   return types.optional(T)",
            "end",
            "local value: Optional(string) = 'ok'",
            "return value",
        },
        "\n"
    )
    clean(source)
    local parsed = parser.parse(source, "annotation.nupp")
    local lua, emitted = gen.generate(parsed, "annotation")
    testAssert.eq(#emitted, 0, "code generation diagnostics")
    -- The call is type material, so its parentheses erase with the annotation
    -- rather than reaching the statement as `local value ( ) = 'ok'`, which is
    -- not Lua and so fails to load rather than to type-check.
    assert(lua:find("local value = 'ok'", 1, true), "annotation reached runtime Lua:\n" .. lua)
    local chunk = assert(loadstring(lua))
    testAssert.eq(chunk(), "ok")
end

-- A parameter with a default may be left out of an application, and the
-- declaration is what says what it then means.
function M.aDefaultedTypeParameterMayBeLeftOut()
    clean(
        table.concat(
            {
                "local record Pair<A, B = string>",
                "   left: A",
                "   right: B",
                "end",
                "local function same(p: Pair<integer>): Pair<integer, string>",
                "   return p",
                "end",
                "print(same)",
            },
            "\n"
        )
    )
end

function M.aDefaultedConstParameterMayBeLeftOut()
    clean(
        table.concat(
            {
                "local record Box<T, const N: integer = 0>",
                "   value: T",
                "end",
                "local function same(b: Box<integer>): Box<integer, 0>",
                "   return b",
                "end",
                "print(same)",
            },
            "\n"
        )
    )
end

-- A written argument still decides the position, so a default changes nothing
-- about an application that supplies one.
function M.aWrittenArgumentOverridesTheDefault()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Box<T, const N: integer = 0>",
                    "   value: T",
                    "end",
                    "local function seven(b: Box<integer, 7>): Box<integer, 0>",
                    "   return b",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2002"
    )
end

-- Leaving an argument out has to mean the last position, or it would say
-- nothing about which one was left out.
function M.aParameterWithoutADefaultCannotFollowOneWithIt()
    testAssert.eq(
        codes(table.concat({"local record Bad<A = string, B>", "   left: A", "   right: B", "end",}, "\n")),
        "NUPP2121"
    )
end

function M.aGenericPackParameterCannotHaveADefault()
    testAssert.eq(
        codes(table.concat({"local record Bad<A... = string>", "   value: integer", "end",}, "\n")),
        "NUPP2121"
    )
end

-- A `function` const parameter names a declaration rather than carrying a value.
-- It is what lets a terminal travel in the type that carries it instead of being
-- restated at every producer of one.
local FUNCTION_CONST = table.concat(
    {
        "cdef function free_a(takes value: voidptr)",
        "cdef function free_b(takes value: voidptr)",
        "local record Handle<T, const cleanup: function>",
        "   value: T",
        "end",
    },
    "\n"
)

function M.aConstFunctionParameterNamesADeclaration()
    clean(
        FUNCTION_CONST .. table.concat(
            {
                "",
                "local function same(h: Handle<integer, free_a>): Handle<integer, free_a>",
                "   return h",
                "end",
                "print(same)",
            },
            "\n"
        )
    )
end

-- The whole point of putting it in the type: two applications naming different
-- functions are different types, so a terminal cannot be swapped silently.
function M.constFunctionArgumentsDistinguishTypes()
    testAssert.eq(
        codes(
            FUNCTION_CONST .. table.concat(
                {
                    "",
                    "local function mismatch(h: Handle<integer, free_a>): Handle<integer, free_b>",
                    "   return h",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2002"
    )
end

function M.aConstFunctionArgumentMustNameAFunction()
    testAssert.eq(
        codes(
            FUNCTION_CONST .. table.concat(
                {
                    "",
                    "local notAFunction = 7",
                    "local function bad(h: Handle<integer, notAFunction>): integer",
                    "   return h.value",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2131"
    )
end

function M.aConstFunctionArgumentMustBeDeclared()
    testAssert.eq(
        codes(
            FUNCTION_CONST .. table.concat(
                {"", "local function missing(h: Handle<integer, nosuchthing>): integer", "   return h.value", "end",},
                "\n"
            )
        ),
        "NUPP2131"
    )
end

-- Hoisting builds the binder and binding reuses that same object, so a domain only
-- one of them knew was silently replaced by whatever the other settled on.
function M.aConstFunctionDomainSurvivesHoisting()
    clean(
        table.concat(
            {
                "cdef function free(takes value: voidptr)",
                "local record Later<T, const cleanup: function>",
                "   value: T",
                "end",
                "local held: Later<integer, free> = nil as any",
                "print(held)",
            },
            "\n"
        )
    )
end

local AFFINE_TYPES = table.concat(
    {
        "local record Resource",
        "   value: integer",
        "end",
        "local function closeA(takes value: Resource): nil end",
        "local function closeB(takes value: Resource): nil end",
        "local type Owner<T, const cleanup: function> = affine(T, cleanup)",
    },
    "\n"
)

-- A borrowed parameter names the representation it borrows, whether it spells a
-- closeable generic declaration directly or through an alias of it, so one fits
-- wherever the other is wanted.
function M.anAliasOfACloseableGenericBorrowsTheSameRepresentation()
    clean(
        [[
local m = {}
interface m.Gen<T> is own.Closeable
    _w: T?
    close: function(takes self: m.Gen<T>): nil
end
interface m.User
    @readonly
    useGen: function<T>(borrows self: m.User, borrows item: m.Gen<T>): nil
    @readonly
    useFixed: function(borrows self: m.User, borrows item: m.Gen<integer>): nil
end
local type GenAlias<T> = m.Gen<T>
local function viaAlias(borrows user: m.User, borrows gen: GenAlias<integer>): nil
    user:useGen(gen)
    user:useFixed(gen)
end
local function direct(borrows user: m.User, borrows gen: m.Gen<integer>): nil
    viaAlias(user, gen)
end
return m, direct
]]
    )
end

function M.usersCanDeclareGenericAffineTypes()
    clean(
        AFFINE_TYPES .. table.concat(
            {
                "",
                "local function open(): Owner<Resource, closeA>",
                "   return new Resource(value = 1)",
                "end",
                "local resource = open()",
                "own.drop(resource)",
            },
            "\n"
        )
    )
end

function M.transparentAffineAliasesWithTheSameTerminalInterchange()
    clean(
        AFFINE_TYPES .. table.concat(
            {
                "",
                "local type Other<T, const cleanup: function> = affine(T, cleanup)",
                "local function rename(takes value: Owner<Resource, closeA>): Other<Resource, closeA>",
                "   return value",
                "end",
            },
            "\n"
        )
    )
end

function M.transparentAffineAliasesRetainTerminalIdentity()
    testAssert.eq(
        codes(
            AFFINE_TYPES .. table.concat(
                {
                    "",
                    "local function mismatch(takes value: Owner<Resource, closeA>): Owner<Resource, closeB>",
                    "   return value",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2002"
    )
end

function M.terminalLessAffineTypesAreExplicitAndCannotBeDropped()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local type Forward<T> = affine(T)",
                    "local function make(): Forward<integer> return 1 end",
                    "local value = make()",
                    "own.drop(value)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.comptimeCanConstructAffineTypesFromFunctionIdentity()
    clean(
        table.concat(
            {
                "local function close(takes value: string): nil end",
                "@comptime local function MakeOwner(T: type, const cleanup: function): type",
                "   return types.affine(T, cleanup)",
                "end",
                "local function make(): MakeOwner(string, close) return 'value' end",
                "local value = make()",
                "own.drop(value)",
            },
            "\n"
        )
    )
end

function M.affineConstructorAddsNoRuntimeRepresentation()
    local source = table.concat(
        {
            "local calls = 0",
            "local function close(takes value: integer): nil calls = calls + value end",
            "local type Counter = affine(integer, close)",
            "local function make(): Counter return 2 end",
            "local value = make()",
            "own.drop(value)",
            "return calls",
        },
        "\n"
    )
    local parsed = parser.parse(source, "affine-erasure.nupp")
    local found = check.check(parsed, "affine-erasure.nupp", env)
    testAssert.eq(#found, 0, found[1] and found[1].msg or "check")
    local lua, emitted = gen.generate(parsed, "affine-erasure")
    testAssert.eq(#emitted, 0, "code generation diagnostics")
    assert(not lua:find("Counter = {}", 1, true), "affine constructor allocated a runtime type")
    local chunk = assert(loadstring(lua))
    testAssert.eq(chunk(), 2)
end

local TUPLE_QUERY = table.concat(
    {
        "local record Position",
        "   x: number",
        "end",
        "local record Velocity",
        "   dx: number",
        "end",
        "@comptime local function Values(Q: type): typepack",
        "   return types.pack(types.elements(Q))",
        "end",
        "local function each(body: function(integer, ...: unpackof Values({Position, Velocity})): nil): nil",
        "end",
    },
    "\n"
)

function M.aComputedTailTypesAnUnannotatedCallbackParameter()
    clean(
        TUPLE_QUERY .. table.concat(
            {"", "each(function(entity, position, velocity): nil", "   position.x = position.x + velocity.dx", "end)",},
            "\n"
        )
    )
end

function M.aComputedTailCarriesFieldsIntoTheCallbackBody()
    testAssert.eq(
        codes(
            TUPLE_QUERY .. table.concat(
                {"", "each(function(entity, position, velocity): nil", "   position.missing = 1", "end)",},
                "\n"
            )
        ),
        "NUPP2004"
    )
end

-- The count is compared once the tail has reduced, under the same rule a written
-- parameter list is held to: an extra parameter is refused unless nil is what its
-- type already admits, so one left untyped passes where one written as a string
-- does not.
function M.aComputedTailCountsTheCallbackParameters()
    testAssert.eq(
        codes(TUPLE_QUERY .. table.concat({"", "each(function(entity, a, b, c: string, d): nil", "end)",}, "\n")),
        "NUPP2006"
    )
    clean(TUPLE_QUERY .. table.concat({"", "each(function(entity, a, b, c, d): nil", "end)",}, "\n"))
end

function M.aComputedTailComparesAWrittenCallbackParameter()
    testAssert.eq(
        codes(
            TUPLE_QUERY .. table.concat(
                {"", "each(function(entity: integer, position: Position, velocity: Position): nil", "end)",},
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.comptimeReadsTheHeadOfAPack()
    clean(
        table.concat(
            {
                "@comptime local function FirstParameter(F: type): type",
                "   const supplied = types.elements(types.parameters(F))",
                "   if #supplied ~= 2 then",
                "      return types.error('this one takes two')",
                "   end",
                "   return supplied[2]",
                "end",
                "local type Pair = function(left: integer, right: string): nil",
                "local second: FirstParameter(Pair) = 'value'",
            },
            "\n"
        )
    )
end

function M.comptimeReadsTheArgumentsOfAGenericApplication()
    clean(
        table.concat(
            {
                "local record Cell<T>",
                "   value: T",
                "end",
                "@comptime local function Held(C: type): type",
                "   const supplied = types.arguments(C)",
                "   if #supplied ~= 1 then",
                "      return types.error('a cell holds one type')",
                "   end",
                "   return supplied[1]",
                "end",
                "local held: Held(Cell<string>) = 'value'",
            },
            "\n"
        )
    )
end

function M.aTypeWithNoArgumentsHasNone()
    oneDiagnostic(
        table.concat(
            {
                "@comptime local function Held(C: type): type",
                "   const supplied = types.arguments(C)",
                "   if #supplied ~= 1 then",
                "      return types.error('a cell holds one type')",
                "   end",
                "   return supplied[1]",
                "end",
                "local held: Held(string) = 'value'",
            },
            "\n"
        ),
        "NUPP2420",
        "a cell holds one type"
    )
end

function M.comptimeComparesNominalDeclarationFamilies()
    clean(
        table.concat(
            {
                "local record Cell<T>",
                "   value: T",
                "end",
                "local record Other<T>",
                "   value: T",
                "end",
                "@comptime local function Same(A: type, B: type): type",
                "   return types.literal(types.samenominal(A, B))",
                "end",
                "@comptime local function Borrowed(T: type): type",
                "   return types.borrowed(T)",
                "end",
                "local type TextCell = Cell<string>",
                "local sameApplication: Same(Cell<string>, Cell<number>) = true",
                "local throughAlias: Same(TextCell, Cell<integer>) = true",
                "local throughBorrow: Same(Borrowed(Cell<string>), Cell<boolean>) = true",
                "local otherDeclaration: Same(Cell<string>, Other<string>) = false",
                "local structural: Same({value: string}, {value: string}) = false",
            },
            "\n"
        )
    )
end

function M.lowercaseFormatargumentsKeepsItsExistingCheckedSignature()
    local member = env.globals.types.t.byname.formatarguments
    testAssert.eq(member.tag, "func")
    testAssert.eq(#member.params, 1)
    testAssert.eq(types.tostring(member.params[1]), "type")
    testAssert.eq(member.comptimeOnly, true)
    testAssert.eq(#member.retPack.head, 1)
    testAssert.eq(types.tostring(member.retPack.head[1]), "typepack")
    testAssert.eq(env.globals.types.t.byname.formatArguments, nil, "the old public name is absent")
end

function M.retiredComptimeModuleNamesAreNotAliases()
    local state, values = {}, {}
    require("nupp.compiler.comptime.materialize.providers").installEvaluator(state, values)
    for _, names in ipairs({
        {"nonExhaustive", "nonexhaustive"},
        {"sameNominal", "samenominal"},
        {"readAt", "readat"},
        {"writeAt", "writeat"},
        {"readKeys", "readkeys"},
        {"writeKeys", "writekeys"},
    }) do
        testAssert.eq(values.types[names[1]], nil)
        testAssert.eq(type(state.intrinsics[values.types[names[2]]]), "function")
    end
    testAssert.eq(values.types.reflect.fieldCodec, nil)
    testAssert.eq(type(state.intrinsics[values.types.reflect.fieldcodec]), "function")
    clean('local type Status = "ready" | types.nonexhaustive()')
    testAssert.ne(codes('local type Status = "ready" | types.nonExhaustive()'), "")
end

function M.lowercaseBuilderNamesPreserveTypeIdentityDuringBootstrap()
    clean(
        [[
local record Cell<T>
    value: T
end
@comptime local function Checked(T: type, Other: type): type
    const nominal = types.samenominal
    if nominal(T, Other) ~= types.samenominal(T, Other) then
        return types.error("lowercase nominal identity changed")
    end
    const key = types.literal("value")
    const shape = types.shape({{name = "value", read = types.string, write = types.string}})
    if types.readat(shape, key) ~= types.readat(shape, key) then
        return types.error("lowercase read projection changed")
    end
    if types.writeat(shape, key) ~= types.writeat(shape, key) then
        return types.error("lowercase write projection changed")
    end
    if #types.readkeys(shape) ~= #types.readkeys(shape) or #types.writekeys(shape) ~= #types.writekeys(shape) then
        return types.error("lowercase key projection changed")
    end
    return T
end
local cell: Checked(Cell<string>, Cell<number>) = new Cell(value = "same")
local type Open = "ready" | types.nonexhaustive()
local state: Open = "ready"
local text = switch state do
    case "ready" -> "ready"
    else -> "other"
end
return cell, text
]]
    )
end

function M.comptimeTypeCachesPreserveNominalIdentity()
    clean(
        table.concat(
            {
                "@comptime local function Identity(T: type): type return T end",
                "@comptime local function Exact(A: type, B: type): type",
                "   return types.literal(A == B)",
                "end",
                "@comptime local function Same(A: type, B: type): type",
                "   return types.literal(types.samenominal(A, B))",
                "end",
                "local record Shared value: string end",
                "local exact: Exact(Shared, Shared) = true",
                "local same: Same(Shared, Shared) = true",
                "local record Item value: string end",
                "local sameIdentity: Same(Item, Item) = true",
                "local function first(): nil",
                "   local record Item value: string end",
                "   local item: Identity(Item) = new Item(value = 'first')",
                "end",
                "local function second(): nil",
                "   local record Item value: string end",
                "   local item: Identity(Item) = new Item(value = 'second')",
                "end",
                "first()",
                "second()",
                "return exact, same, sameIdentity",
            },
            "\n"
        )
    )
end

local PACK_QUERY = table.concat(
    {
        "local record Position",
        "   x: number",
        "end",
        "local record Velocity",
        "   dx: number",
        "end",
        "local record Component<T>",
        "   id: integer",
        "end",
        "@comptime local function Values(C: typepack): typepack",
        "   const members = types.elements(C)",
        "   const out = {}",
        "   for index = 1, #members do",
        "      const supplied = types.arguments(members[index])",
        "      if #supplied ~= 1 then",
        "         return types.error('a query argument must be a component handle')",
        "      end",
        "      out[index] = supplied[1]",
        "   end",
        "   return types.pack(out)",
        "end",
        "local record World",
        "   each: function<C...>(self, body: function(integer, ...: unpackof Values(C...)): nil, ...: C...): nil",
        "end",
        "local world: World = nil as any",
        "local position: Component<Position> = nil as any",
        "local velocity: Component<Velocity> = nil as any",
    },
    "\n"
)

function M.aTypeFunctionTakesAGenericPackArgument()
    clean(
        PACK_QUERY .. table.concat(
            {
                "",
                "world:each(function(entity, position, velocity): nil",
                "   position.x = position.x + velocity.dx",
                "end, position, velocity)",
            },
            "\n"
        )
    )
end

function M.aPackDerivedFromTheArgumentsReachesTheCallbackBody()
    testAssert.eq(
        codes(
            PACK_QUERY .. table.concat(
                {
                    "",
                    "world:each(function(entity, position, velocity): nil",
                    "   position.missing = 1",
                    "end, position, velocity)",
                },
                "\n"
            )
        ),
        "NUPP2004"
    )
end

function M.aComputedIteratorResultPackTypesGenericForBindings()
    clean(
        PACK_QUERY .. table.concat(
            {
                "",
                "local record Query<C...>",
                "   matches: function(): (integer, unpackof Values(C...))",
                "end",
                "local query: Query<(Component<Position>, Component<Velocity>)> = nil as any",
                "for count, position, velocity in query.matches do",
                "   local n: integer = count",
                "   local x: number = position.x",
                "   local dx: number = velocity.dx",
                "end",
            },
            "\n"
        )
    )
end

function M.aComputedIteratorResultPackReachesTheLoopBody()
    testAssert.eq(
        codes(
            PACK_QUERY .. table.concat(
                {
                    "",
                    "local record Query<C...>",
                    "   matches: function(): (integer, unpackof Values(C...))",
                    "end",
                    "local query: Query<(Component<Position>, Component<Velocity>)> = nil as any",
                    "for count, position, velocity in query.matches do",
                    "   position.missing = count + velocity.dx",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2004"
    )
end

function M.computedIteratorModesMakeBindingsIterationScopedBorrows()
    testAssert.eq(
        codes(
            PACK_QUERY .. table.concat(
                {
                    "",
                    "@comptime local function BorrowedValues(C: typepack): typepack",
                    "   const members = types.elements(C)",
                    "   const out = {}",
                    "   const modes = {}",
                    "   for index = 1, #members do",
                    "      out[index] = types.arguments(members[index])[1]",
                    "      modes[index] = index == 1 and 'exclusive' or 'borrowed'",
                    "   end",
                    "   return types.pack(out, nil, modes)",
                    "end",
                    "local record Query<C...>",
                    "   matches: function(): (integer, unpackof BorrowedValues(C...))",
                    "end",
                    "local query: Query<(Component<Position>, Component<Velocity>)> = nil as any",
                    "local escaped: Position = nil as any",
                    "for count, position, velocity in query.matches do",
                    "   escaped = position",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

function M.comptimeCountsThePackItWasPassed()
    clean(
        table.concat(
            {
                "@comptime local function Count(C: typepack): type",
                "   return types.literal(#types.elements(C))",
                "end",
                "local record Counter",
                "   width: function<C...>(self, ...: C...): Count(C...)",
                "end",
                "local counter: Counter = nil as any",
                "local counted: 2 = counter:width('a', 'b')",
            },
            "\n"
        )
    )
end

-- A type argument that is itself a type parameter satisfies a bound only when its own
-- bound implies it. An unbounded one stands for anything, and the old permissive
-- typevar relation used to let it through, so `wrap(3)` built a `Reg<integer>` whose
-- method then read a field no integer has.
function M.aTypeParameterArgumentNeedsABoundThatImpliesTheBound()
    local body = table.concat(
        {
            "local interface Named",
            "   name: string",
            "end",
            "local interface Titled",
            "   name: string",
            "   title: string",
            "end",
            "local record Reg<T is Named>",
            "   item: T",
            "end",
        },
        "\n"
    ) .. "\n"
    testAssert.eq(
        codes(
            body .. table.concat(
                {"local function wrap<U>(x: U): Reg<U>", "   return new Reg(item = x)", "end", "return wrap",},
                "\n"
            )
        ),
        "NUPP2116 NUPP2116"
    )
    testAssert.eq(codes(body .. "local type Also<U> = Reg<U>\n"), "NUPP2116")
    clean(
        body .. table.concat(
            {
                "local function wrap<U is Named>(x: U): Reg<U>",
                "   return new Reg(item = x)",
                "end",
                "local function narrow<U is Titled>(x: U): Reg<U>",
                "   return new Reg(item = x)",
                "end",
                "local type Also<U is Named> = Reg<U>",
                "return wrap, narrow",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local interface Named",
                    "   name: string",
                    "end",
                    "local interface Titled",
                    "   name: string",
                    "   title: string",
                    "end",
                    "local record Reg<T is Titled>",
                    "   item: T",
                    "end",
                    "local function wrap<U is Named>(x: U): Reg<U>",
                    "   return new Reg(item = x)",
                    "end",
                    "return wrap",
                },
                "\n"
            )
        ),
        "NUPP2116 NUPP2116"
    )
end

-- A default is checked against the bound beside it where it is declared, since
-- every application relying on it would otherwise be refused instead.
function M.aDefaultTypeArgumentIsCheckedAgainstItsBoundWhereDeclared()
    local body = table.concat(
        {"local interface Named", "   name: string", "end", "local record P is Named", "   name: string", "end",},
        "\n"
    ) .. "\n"
    testAssert.eq(codes(body .. "local record Reg<T is Named = integer>\n   item: T\nend\nreturn Reg\n"), "NUPP2116")
    clean(body .. "local record Reg<T is Named = P>\n   item: T\nend\nreturn Reg\n")
    testAssert.eq(
        codes(body .. "local function make<T is Named = integer>(): T?\n   return nil\nend\nreturn make\n"),
        "NUPP2116"
    )
end

function M.expectedResultInfersANullaryGenericConstructor()
    clean(
        table.concat(
            {
                "local interface Token<T>",
                "end",
                "local function make<T>(): Token<T>",
                "   error('not executed')",
                "end",
                "local value: Token<number> = make()",
                "return value",
            },
            "\n"
        )
    )
end

function M.simdSpeciesIdentityIsInvariantAndComparisonsReturnMasks()
    clean(
        table.concat(
            {
                'local array = require("nupp.mem.array")',
                'local simd = require("simd")',
                "local species = assert(simd.species(array.float))",
                "local fixed = assert(simd.species(array.float, 8))",
                "local left: simd.Vector<float, simd.Preferred> = nil as any",
                "local right: simd.Vector<float, simd.Preferred> = nil as any",
                "local selected: simd.Mask<float, simd.Preferred> = (left < right) & (left <= right)",
                "local positive: simd.Mask<float, simd.Preferred> = left > 0.0",
                "return species, fixed, selected, positive",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    'local simd = require("simd")',
                    "local function wrong(value: simd.Vector<number, simd.Fixed<4>>): simd.Vector<number, simd.Fixed<8>>",
                    "   return value",
                    "end",
                    "return wrong",
                },
                "\n"
            )
        ),
        "NUPP2002"
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    'local simd = require("simd")',
                    "local left: simd.Vector<float, simd.Preferred> = nil as any",
                    "local right: simd.Vector<float, simd.Preferred> = nil as any",
                    "return left & right",
                },
                "\n"
            )
        ),
        "NUPP2003"
    )
end

function M.simdMaskEqualityReturnsLaneMasksAndRejectsOrdering()
    local prefix = [[
local simd = require("simd")
local left: simd.Mask<uint8, simd.Fixed<3>> = nil as any
local right: simd.Mask<uint8, simd.Fixed<3>> = nil as any
]]
    clean(
        prefix
        .. [[
local same: simd.Mask<uint8, simd.Fixed<3>> = left == right
local different: simd.Mask<uint8, simd.Fixed<3>> = left ~= right
return same:select(4, 2), different:any()
]]
    )
    testAssert.eq(codes(prefix .. "local result = left < right"), "NUPP2003")
    testAssert.eq(codes(prefix .. "local result = left == true"), "NUPP2003")
    testAssert.eq(
        codes(prefix .. [[
local other: simd.Mask<uint8, simd.Fixed<4>> = nil as any
local result = left == other
]]),
        "NUPP2006"
    )
end

function M.narrowStorageWidthsAreValidOnlyInsideCompilerOwnedSimdFamilies()
    clean(
        table.concat(
            {
                'local array = require("nupp.mem.array")',
                'local simd = require("simd")',
                "local species = assert(simd.species(array.uint8))",
                "local vector: simd.Vector<uint8, simd.Preferred> = nil as any",
                "local mask: simd.Mask<uint8, simd.Preferred> = vector == vector",
                "local lane: uint32 = vector:extract(1)",
                "local bits = mask:bits()",
                "local shift: uint32 = 1",
                "local changed: uint64 = ~(bits | bits) << shift",
                "local same: boolean = changed == bits",
                "return species, mask, lane, same",
            },
            "\n"
        )
    )
    testAssert.eq(codes("local value: uint8 = 1\nreturn value\n"), "NUPP2012")
end

function M.simdHorizontalContractsPreserveTheirNestedIntrinsicIdentity()
    clean(
        table.concat(
            {
                'local simd = require("simd")',
                "local horizontal = simd.horizontal",
                "local ordered = horizontal.orderedsum",
                "local value: simd.Vector<float, simd.Fixed<8>> = nil as any",
                "local result: float = ordered(value)",
                "return result",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    'local simd = require("simd")',
                    "local value: simd.Vector<uint32, simd.Fixed<8>> = nil as any",
                    "return simd.horizontal.orderedsum(value)",
                },
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.exactReducerLifecycleAndTypesAreChecked()
    local source = [[
local simd = require("simd")
@aot
local function total(seed: uint32): uint32
    local fold = simd.reducer.wrappingsum(nupp.mem.array.uint32, seed)
    for i = 1, 4 do
        fold:add(seed)
    end
    return fold:value()
end
return total
]]
    clean(source)
    local bad = source:gsub("fold:add%(seed%)", "if i > 2 then fold:add(seed) end")
    clean(bad)
    testAssert.eq(codes(source:gsub("fold:add%(seed%)", "fold:add(true)")), "NUPP2006")
    clean(
        [[
local simd = require("simd")
local minimum: simd.IntegerArgMin<uint64> = simd.reducer.integerargmin(nupp.mem.array.uint64)
local flag: boolean = simd.reducer.any():value()
local count: uint64 = simd.reducer.count():value()
return minimum, flag, count
]]
    )
end

function M.floatingReducerStateIsPrivateToTheSimdModule()
    testAssert.eq(
        codes([[
local simd = require("simd")
local sum = simd.reducer.orderedsum(0.0)
local total = sum.total
]]),
        "NUPP2209"
    )
    testAssert.eq(
        codes(
            [[
local simd = require("simd")
local sum = simd.reducer.compensatedsum(0.0)
sum.compensation = 1.0
return sum:value()
]]
        ),
        "NUPP2209"
    )
end

-- Every reducer a constructor answers is a type the caller can write down.
function M.everyFloatingReducerNamesItsType()
    local lines = {'local simd = require("simd")'}
    for _, name in ipairs({
        "OrderedSum",
        "PairwiseSum",
        "CompensatedSum",
        "AlgebraicSum",
        "OrderedProduct",
        "PairwiseProduct",
        "AlgebraicProduct",
        "OrderedDot",
        "PairwiseDot",
        "AlgebraicDot",
    }) do
        local constructor = name:sub(1, 1):lower() .. name:sub(2)
        lines[
            #lines + 1
        ] = ("local %s: simd.%s<number> = simd.reducer.%s(0.0)"):format(constructor, name, constructor:lower())
    end
    lines[#lines + 1] = "return orderedSum, algebraicDot"
    clean(table.concat(lines, "\n"))
end

-- One verb contributes to every reducer, and each one is a `simd.Reducer` of
-- what it answers.
function M.everyReducerContributesThroughAddAndIsAReducer()
    clean(
        [[
local simd = require("simd")
local function finish<T>(reducer: simd.Reducer<T>): T
    return reducer:value()
end
local product: simd.Reducer<number> = simd.reducer.orderedproduct(1.0)
local pairwise = simd.reducer.pairwiseproduct(1.0)
local algebraic = simd.reducer.algebraicproduct(1.0)
local dot: simd.Reducer<number> = simd.reducer.pairwisedot(0.0)
local count: simd.Reducer<uint64> = simd.reducer.count()
local any: simd.Reducer<boolean> = simd.reducer.any()
local position: simd.Reducer<integer> = simd.reducer.numberargmin()
local least: simd.Reducer<number> = simd.reducer.propagatingmin(0.0)
pairwise:add(2.0)
algebraic:add(2.0)
local ordered = simd.reducer.orderedproduct(1.0)
ordered:add(3.0)
return finish(product), finish(pairwise), finish(algebraic), finish(ordered), finish(dot), finish(count),
    finish(any), finish(position), finish(least)
]]
    )
    testAssert.eq(
        codes(
            [[
local simd = require("simd")
local product = simd.reducer.orderedproduct(1.0)
product:multiply(2.0)
return product:value()
]]
        ),
        "NUPP2004"
    )
end

-- An integer reducer is selected by its element's type, which its array witness
-- names; a written type argument and the witness have to agree.
function M.integerReducersAreSelectedByTheirElementType()
    clean(
        [[
local array = require("nupp.mem.array")
local simd = require("simd")
local sum: simd.WrappingSum<int32> = simd.reducer.wrappingsum<int32>(array.int32, 0)
local product: simd.Reducer<uint64> = simd.reducer.wrappingproduct(array.uint64, 1ULL)
local bits: simd.AndBits<uint32> = simd.reducer.andbits(array.uint32, math.u32.wrap(7))
local least: simd.IntegerMin<int64> = simd.reducer.integermin(array.int64, 0LL)
local position: simd.IntegerArgMax<uint32> = simd.reducer.integerargmax(array.uint32)
return sum, product, bits, least, position
]]
    )
    testAssert.eq(
        codes(
            [[
local array = require("nupp.mem.array")
local simd = require("simd")
return simd.reducer.wrappingsum<uint32>(array.int32, 0)
]]
        )
            :match("NUPP%d+"),
        "NUPP2006"
    )
    testAssert.eq(
        codes(
            [[
local array = require("nupp.mem.array")
local simd = require("simd")
return simd.reducer.xorbits(array.float, 0)
]]
        )
            :match("NUPP%d+"),
        "NUPP2116"
    )
end

-- The ordering policy leads the name, as it does in `orderedSum`.
function M.theOrderedPrefixSumNamesItsPolicyFirst()
    local source = [[
local simd = require("simd")
local value: simd.Vector<float, simd.Fixed<4>> = nil as any
local prefix: simd.Vector<float, simd.Fixed<4>> = value:NAME()
return prefix
]]
    clean((source:gsub("NAME", "orderedprefixsum")))
    testAssert.eq(codes((source:gsub("NAME", "prefixSumOrdered"))), "NUPP2004")
end

function M.reducerLifecyclesAreCheckedWithoutTargetLowering()
    clean(
        table.concat(
            {
                'local simd = require("simd")',
                "@aot",
                "local function total(): number",
                "   local sum = simd.reducer.orderedsum(0.0)",
                "   for i = 1, 4 do",
                "      sum:add(i)",
                "   end",
                "   return sum:value()",
                "end",
                "return total",
            },
            "\n"
        )
    )

    local found = diagnostics(
        table.concat(
            {
                'local simd = require("simd")',
                "@aot",
                "local function total(): number",
                "   local sum = simd.reducer.orderedsum(0.0)",
                "   local copy = sum",
                "   for i = 1, 4 do",
                "      copy:add(i)",
                "   end",
                "   return copy:value()",
                "end",
                "return total",
            },
            "\n"
        )
    )
    local lifecycle = false
    for _, diagnostic in ipairs(found) do
        lifecycle = lifecycle
            or diagnostic.msg:find("a reducer cannot be copied or passed through another value", 1, true) ~= nil
    end
    assert(lifecycle, "nupp check did not enforce reducer ownership")
end

-- A default body lives on the interface's table and reaches only a declaration
-- that names the interface with `is`, so a shape has to carry the member itself:
-- one that does not is refused, wherever the interface is wanted.
function M.aShapeMustCarryAnInterfacesDefaultMember()
    local body = table.concat(
        {
            "local interface Named",
            "   name: string",
            "   function greet(self): string",
            '      return "hi " .. self.name',
            "   end",
            "end",
            "local function greet(v: Named): string",
            "   return v:greet()",
            "end",
        },
        "\n"
    ) .. "\n"
    testAssert.eq(codes(body .. 'local n: Named = {name = "x"}\nreturn n\n'), "NUPP2001")
    testAssert.eq(codes(body .. 'print(greet({name = "y"}))\n'), "NUPP2006")
    testAssert.eq(codes(body .. 'local t: {name: string} = {name = "z"}\nprint(greet(t))\n'), "NUPP2006")
    clean(
        body .. table.concat(
            {
                'local n: Named = {name = "x", greet = function(self: Named): string return "yo" end}',
                "print(greet(n))",
            },
            "\n"
        )
    )
end

-- A value the checker cannot prove is refused where it would enter a constrained
-- type, and `types.admit` is how the source says it meant it. The destination
-- supplies the type, so nothing names it twice.
function M.admissionIsWrittenWhereProofRunsOut()
    local alias = "local type Small = types.range(integer, 0, 10)\n"
    clean(alias .. "local function of(v: integer): Small\n    return types.admit(v)\nend\nprint(of(1))")
    clean(alias .. "local v: integer = 1\nlocal x: Small = types.admit(v)\nprint(x)")
    -- a proved value may be admitted too: a bound can move, and the source that
    -- says what it meant should keep compiling when it does
    clean(alias .. "local function of(): Small\n    return types.admit(7)\nend\nprint(of())")
    -- the destination has to be constrained
    testAssert.eq(
        codes(alias .. "local function of(v: integer): integer\n    return types.admit(v)\nend\nprint(of(1))"),
        "NUPP2013"
    )
    -- and the value has to be the constraint's base: this admits, it does not convert
    testAssert.eq(
        codes(alias .. "local function of(v: string): Small\n    return types.admit(v)\nend\nprint(of('x'))"),
        "NUPP2013"
    )
end

-- Proof decides what is emitted: an unprovable value gets one shared test, a proved
-- one gets nothing at all, and the value is read exactly once either way.
function M.admissionEmitsOnlyWhatProofLeaves()
    local alias = "local type Small = types.range(integer, 0, 10)\n"

    local function lua(source)
        local parsed = parser.parse(source, "admit.nupp")
        testAssert.eq(#parsed.errors, 0, "syntax: " .. (parsed.errors[1] and parsed.errors[1].msg or ""))
        env.loaded = {}
        check.check(parsed, "admit.nupp", env)

        return gen.generate(parsed, "admit.nupp")
    end

    local unproved = lua(alias .. "local function of(v: integer): Small\n    return types.admit(v)\nend\nprint(of(1))")
    assert(unproved:find("__nuppAdmit", 1, true), "an unprovable admission emits its test")
    assert(unproved:find("__nuppV <= 10", 1, true), "the test carries the upper bound")
    assert(unproved:find("__nuppV %% 1 == 0"), "an integer base tests integrality")
    local proved = lua(alias .. "local function of(): Small\n    return types.admit(7)\nend\nprint(of())")
    assert(not proved:find("__nuppAdmit", 1, true), "a proved admission emits nothing")
end

function M.admissionUsesTheTypesBindingAndRejectsRetiredNames()
    clean(
        [[
local types = {admit = function(value: integer): string return tostring(value) end}
local result: string = types.admit(7)
return result
]]
    )
    clean(
        [[
local type Small = types.range(integer, 0, 10)
local query = types
local function checked(value: integer): Small return query.admit(value) end
return checked
]]
    )
    for _, name in ipairs({"admit", "sizeof", "alignof", "offsetof"}) do
        assert(codes("return nupp." .. name) ~= "", "retired nupp." .. name .. " must be refused")
    end
end

function M.admissionChecksOnceAndKeepsItsRuntimeFailure()
    local parsed = parser.parse(
        [[
local type Small = types.range(integer, 0, 10)
local reads: integer = 0
local function read(value: integer): integer
    reads += 1
    return value
end
local function checked(value: integer): Small return types.admit(read(value)) end
return checked, function(): integer return reads end
]],
        "admission-runtime.nupp"
    )
    testAssert.eq(#parsed.errors, 0)
    for _, diagnostic in ipairs(check.check(parsed, "admission-runtime.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local code = gen.generate(parsed, "admission_runtime")
    local chunk = assert(loadstring(code))
    local admit, reads = chunk()
    testAssert.eq(admit(5), 5)
    local accepted, failure = pcall(admit, 11)
    testAssert.eq(accepted, false)
    assert(tostring(failure):find("Small", 1, true), tostring(failure))
    testAssert.eq(pcall(admit, 1.5), false)
    testAssert.eq(reads(), 3, "each admission evaluates its argument once")
end

-- One constraint is one type however it was reached: written in a type, returned
-- from a @comptime function, or substituted into a generic alias. That is the whole
-- reason the builder and the resolver share a constructor.
function M.aConstraintBuiltAtComptimeIsTheOneWrittenInAType()
    local built = table.concat(
        {
            "@comptime local function Between(T: type, low: integer, high: integer): type",
            "    return types.range(T, low, high)",
            "end",
            "local type Range<T, const Low: integer, const High: integer> = Between(T, Low, High)",
            "local type Made = Range<integer, 0, 31>",
            "local type Written = types.range(integer, 0, 31)",
        },
        "\n"
    ) .. "\n"
    -- each is the other, in both directions, which only holds if they interned alike
    clean(built .. "local function pass(v: Made): Written\n    return v\nend\nprint(pass(1))")
    clean(built .. "local function pass(v: Written): Made\n    return v\nend\nprint(pass(1))")
    clean(built .. "local ok: Made = 7\nprint(ok)")
    testAssert.eq(codes(built .. "local no: Made = 32\nprint(no)"), "NUPP2001")
    -- and a wider interval still takes a narrower one
    local percent = built .. "local type Percent = Range<integer, 0, 100>\n"
    clean(percent .. "local function widen(v: Made): Percent\n    return v\nend\nprint(widen(1))")
    testAssert.eq(
        codes(percent .. "local function narrow(v: Percent): Made\n    return v\nend\nprint(narrow(1))"),
        "NUPP2002"
    )
end

function M.computedConstraintsKeepExactIntegerBounds()
    local function generated(kind, base)
        return table.concat(
            {
                "@comptime local function Wide(): type",
                ("    return types.%s(types.%s, 0, 4503599627370496 * 2)"):format(kind, base),
                "end",
                "local type Value = Wide()",
            },
            "\n"
        )
    end

    testAssert.eq(codes(generated("range", "integer")), "NUPP2415")
    testAssert.eq(codes(generated("len", "string")), "NUPP2415")
end

-- `pairs` takes a read-only indexer, and an array and a record shape both satisfy
-- one: `{T}` assigns to `{@readonly [integer]: T}` and `{a: A, b: B}` to
-- `{@readonly [string]: A | B}`. Unification did not follow, so iterating either
-- bound neither key nor value and the loop variables were `any`.
function M.pairsBindsItsKeyAndValueOverAnArrayOrAShape()
    clean(
        table.concat(
            {
                "local arr: {string} = {\"a\"}",
                "for k, v in pairs(arr) do",
                "    local key: integer = k",
                "    local value: string = v",
                "    print(key, value)",
                "end",
            },
            "\n"
        ) .. "\n"
    )
    clean(
        table.concat(
            {
                "local rec: {a: string, b: integer} = {a = \"x\", b = 1}",
                "for k, v in pairs(rec) do",
                "    local key: string = k",
                "    local value: string | integer = v",
                "    print(key, value)",
                "end",
            },
            "\n"
        ) .. "\n"
    )
    -- the binding is the argument's own element type, not a widening to `any`
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local arr: {string} = {\"a\"}",
                    "for _, v in pairs(arr) do",
                    "    local wrong: integer = v",
                    "    print(wrong)",
                    "end",
                },
                "\n"
            ) .. "\n"
        ),
        "NUPP2001"
    )
end

-- A type parameter inference cannot reach is written instead. The `<` alone cannot
-- say whether a generic call or a comparison pair was meant, so the reading commits
-- only when the list closes with `>` immediately followed by `(`.
function M.aCallMaySupplyItsTypeArgumentsInWriting()
    local pick = "local function pick<T>(): T?\n    return nil\nend\n"
    clean(pick .. "local a: integer? = pick<integer>()\nprint(a)")
    clean(pick .. "local b: string? = pick<string>()\nprint(b)")
    -- the written argument is what the result is, not whatever the destination says
    testAssert.eq(codes(pick .. "local c: string? = pick<integer>()\nprint(c)"), "NUPP2001")
    -- more arguments than the callee declares is refused
    testAssert.eq(codes(pick .. "local d = pick<integer, string>()\nprint(d)"), "NUPP2007")
    -- a comparison pair still reads as one wherever the list does not close into a call
    clean("local x, y, z = 1, 2, 3\nlocal cmp = x < y or x > (z)\nprint(cmp)")
    clean("local x, y = 1, 2\nlocal cmp = (x < y) == (y > x)\nprint(cmp)")
end

-- The parser already recorded a method call's type arguments and nothing read them,
-- so writing one type-checked and still produced `any`.
function M.aMethodCallMaySupplyItsTypeArgumentsInWriting()
    local holder = table.concat(
        {
            "local record Holder",
            "    v: integer",
            "end",
            "function Holder:pick<T>(): T?",
            "    return nil",
            "end",
            "local h = new Holder(v = 1)",
        },
        "\n"
    ) .. "\n"
    clean(holder .. "local a: integer? = h:pick<integer>()\nprint(a)")
    testAssert.eq(codes(holder .. "local b: string? = h:pick<integer>()\nprint(b)"), "NUPP2001")
end

-- `as` is erased, so it may say a value is one of these but cannot make it one. A
-- constraint is exactly the claim that has to be established.
function M.anErasedCastCannotManufactureAConstraint()
    local alias = "local type Small = types.range(integer, 0, 10)\n"
    testAssert.eq(
        codes(alias .. "local function of(v: integer): Small\n    return v as Small\nend\nprint(of(1))"),
        "NUPP2013"
    )
    -- casting something already established is not a claim, so it stays allowed
    clean(alias .. "local function of(v: Small): Small\n    return v as Small\nend\nprint(of(1))")
end

-- A written admission is a comparison and a raise, so a noraise region forbids one
-- and a noalloc region does not mind it. A proved admission is erased and so is
-- neither. Constrained positions a write reaches are refused rather than erased.
function M.admissionCarriesExactlyTheEffectsItLeft()
    local alias = "local type Small = types.range(integer, 0, 10)\n"

    local function body(region, value)
        return alias .. table.concat(
            {
                "local function of(v: integer): Small",
                "    local out: Small = types.admit(0)",
                "    " .. region .. " do",
                "        out = types.admit(" .. value .. ")",
                "    end",
                "    return out",
                "end",
                "print(of(1))",
            },
            "\n"
        )
    end

    clean(body("@noraise", "7"))
    testAssert.eq(codes(body("@noraise", "v")), "NUPP2711")
    clean(body("@noalloc", "v"))

    -- a field, an element and a constructor are admission positions too
    local box = alias .. "local record Box\n    n: Small\nend\n"
    testAssert.eq(codes(box .. "local function put(b: Box, v: integer): nil\n    b.n = v\nend\nprint(put)"), "NUPP2001")
    testAssert.eq(
        codes(box .. "local function make(v: integer): Box\n    return new Box(n = v)\nend\nprint(make)"),
        "NUPP2202"
    )
    testAssert.eq(
        codes(alias .. "local function list(v: integer): {Small}\n    return {v}\nend\nprint(list)"),
        "NUPP2002"
    )
end

-- A constrained type is a union member like any other, so it has to be seen as
-- itself where a union is expected rather than widened to its base first. `is`
-- narrowing a base-typed value is the shape that asks: `Short` reaching `Short?`.
function M.aConstrainedTypeReachesAUnionAsItself()
    local alias = "local type Short = types.len(string, 1, 4)\n"
    clean(
        alias .. table.concat(
            {
                "local function named(text: string): Short?",
                "    if text is Short then",
                "        return text",
                "    end",
                "    return nil",
                "end",
                "print(named('ab'))",
            },
            "\n"
        )
    )
    clean(alias .. "local function pass(v: Short): Short?\n    return v\nend\nprint(pass('ab'))")
    -- and an assignment into a field resolves what it admits into, like a binding
    local box = alias .. "local record Box\n    text: Short\nend\n"
    clean(box .. "local function put(b: Box, v: string): nil\n    b.text = types.admit(v)\nend\nprint(put)")
end

function M.sharedGenericSignatureSubstitutionUsesOneRefreshWalk()
    local count = 16
    local parameter = types.typevar("Element", "shared-signature-refresh")
    local declarations, open = {}, {}
    for index = 1, count do
        local declaration = types.nominal("Signature" .. index, "record")
        declaration.typeParams = {parameter}
        declarations[index] = declaration
        open[index] = generics.reserveInstantiation(declaration, {[parameter] = parameter})
    end
    for index, declaration in ipairs(declarations) do
        declaration.byname = {
            value = parameter,
            next = open[index % count + 1],
            method = types.func({parameter}, {
                parameter
            }),
        }
        declaration.writeByname = {value = parameter, next = open[index % count + 1]}
    end
    local signature = types.func(open, open)
    local bindings = {[parameter] = types.integer}
    local operations = {
        function()
            return generics.rebind(signature, bindings)
        end,
        function()
            return generics.materialize(signature, bindings)
        end,
        function()
            return generics.materializePack(signature.paramPack, bindings)
        end,
        function()
            return generics.evaluate(signature, bindings).type
        end,
        function()
            return generics.reduce(signature, bindings)
        end,
        function()
            return generics.instantiateFunction(signature, bindings)
        end,
    }
    for index, operation in ipairs(operations) do
        local instantiate, visits = generics.instantiate, 0
        generics.instantiate = function(declaration, map)
            visits = visits + 1
            assert(visits <= count * 8, "signature substitution repeats shared nominal walks")
            return instantiate(declaration, map)
        end
        local ok, result = pcall(operation)
        generics.instantiate = instantiate
        assert(ok, tostring(result))
        local parameters = result.tag == "pack" and result.head or result.params
        for position = 1, count do
            testAssert.eq(parameters[position].byname.value, types.integer)
            testAssert.eq(parameters[position].byname.next, parameters[position % count + 1])
            if result.tag ~= "pack" then
                testAssert.eq(parameters[position], result.rets[position])
            end
        end
        declarations[1].byname.late = types.literal(index, types.number)
        testAssert.eq(
            generics.rebind(signature, bindings).params[1].byname.late,
            declarations[1].byname.late,
            "later declaration changes remain visible"
        )
    end
end

function M.failedSubstitutionsRestoreEnclosingRefreshScope()
    local parameter = types.typevar("Element", "failed-substitution-refresh")
    local first, nested = types.nominal("SubstitutionOuter", "record"), types.nominal("SubstitutionInner", "record")
    local trigger, failure = types.nominal(
        "SubstitutionTrigger",
        "record"
    ), types.nominal("SubstitutionFailure", "record")
    local open = {}
    for _, declaration in ipairs({first, nested, trigger, failure}) do
        declaration.typeParams = {parameter}
        open[declaration] = generics.reserveInstantiation(declaration, {[parameter] = parameter})
    end
    first.byname.method = types.func({parameter}, {parameter})
    nested.byname.value = parameter
    local bindings = {[parameter] = types.integer}
    local inner = types.func({open[nested], open[failure]}, {})
    local outer = types.func({open[first], open[trigger], open[first], open[failure]}, {})
    local instantiate, funcWith, outerRefreshes = generics.instantiate, types.funcWith, 0
    types.funcWith = function(fn, overrides)
        if fn == first.byname.method then
            outerRefreshes = outerRefreshes + 1
        end
        return funcWith(fn, overrides)
    end
    generics.instantiate = function(declaration, map)
        if declaration == failure then
            error("substitution failure", 0)
        elseif declaration == trigger then
            local ok, problem = pcall(generics.rebind, inner, bindings)
            assert(not ok and tostring(problem):find("substitution failure", 1, true))
            nested.byname.late = types.string
            testAssert.eq(generics.rebind(open[nested], bindings).byname.late, types.string)
        end

        return instantiate(declaration, map)
    end
    local ok, problem = pcall(generics.rebind, outer, bindings)
    generics.instantiate, types.funcWith = instantiate, funcWith
    assert(not ok and tostring(problem):find("substitution failure", 1, true))
    testAssert.eq(outerRefreshes, 1, "failed nested substitution preserves enclosing visits")
    first.byname.afterFailure = types.boolean
    testAssert.eq(generics.rebind(open[first], bindings).byname.afterFailure, types.boolean)
end

function M.completedGenericRefreshValidatesSourceTargetAndAllBindings()
    local declaration = types.nominal("ValidatedRefresh", "record")
    local parameter = types.typevar("T", "validated-refresh:parameter")
    local free = types.typevar("Free", "validated-refresh:free")
    declaration.typeParams = {parameter}
    local method = types.func({parameter}, {free})
    declaration.byname.method = method
    declaration.byname.removable = parameter
    local bindings = {[parameter] = types.string, [free] = types.number}
    local original, visits = types.funcWith, 0
    types.funcWith = function(source, changes)
        if source == method then
            visits = visits + 1
        end
        return original(source, changes)
    end
    local ok, problem = pcall(function()
        local instance = generics.instantiate(declaration, bindings)
        testAssert.eq(visits, 1)
        testAssert.eq(generics.instantiate(declaration, bindings), instance)
        testAssert.eq(visits, 1, "unchanged completed applications reuse their fill")

        local function changed(mutate)
            local before = visits
            mutate(instance)
            testAssert.eq(generics.instantiate(declaration, bindings), instance)
            testAssert.eq(visits, before + 1, "a changed snapshot must refill")
        end

        changed(function()
            declaration.byname.added = parameter
        end)
        testAssert.eq(instance.byname.added, types.string)
        changed(function()
            declaration.byname.added = types.boolean
        end)
        testAssert.eq(instance.byname.added, types.boolean)
        changed(function()
            declaration.byname.removable = nil
        end)
        changed(function()
            declaration.byname = {method = method, added = types.boolean}
        end)
        changed(function(value)
            value.byname = {}
        end)
        testAssert.eq(instance.byname.method.rets[1], types.number)
        changed(function(value)
            value.byname.method = types.any
        end)
        testAssert.eq(instance.byname.method.rets[1], types.number)
        changed(function()
            bindings[free] = types.boolean
        end)
        testAssert.eq(instance.byname.method.rets[1], types.boolean)
        local unrelated = {}
        changed(function()
            bindings[unrelated] = types.string
        end)
        changed(function()
            bindings[unrelated] = nil
        end)
        for _, name in ipairs({"writeByname", "staticByname", "staticWriteByname", "metamethods"}) do
            changed(function()
                declaration[name].added = parameter
            end)
            testAssert.eq(instance[name].added, types.string)
            changed(function(value)
                value[name].added = types.number
            end)
            testAssert.eq(instance[name].added, types.string)
            changed(function()
                declaration[name] = {added = types.boolean}
            end)
            testAssert.eq(instance[name].added, types.boolean)
            changed(function(value)
                value[name] = {}
            end)
            testAssert.eq(instance[name].added, types.boolean)
        end
    end)
    types.funcWith = original
    assert(ok, problem)
end

function M.completedGenericRefreshValidatesTransitiveAndSupertypeDependencies()
    local parameter = types.typevar("T", "validated-transitive-refresh")
    local leaf = types.nominal("ValidatedLeaf", "interface")
    local middle = types.nominal("ValidatedMiddle", "interface")
    local outer = types.nominal("ValidatedOuter", "record")
    for _, declaration in ipairs({leaf, middle, outer}) do
        declaration.typeParams = {parameter}
    end
    leaf.byname.value = parameter
    middle.supertypes = {generics.reserveInstantiation(leaf, {[parameter] = parameter})}
    outer.byname.middle = generics.reserveInstantiation(middle, {[parameter] = parameter})
    local bindings = {[parameter] = types.string}
    local instance = generics.instantiate(outer, bindings)
    local concreteMiddle = instance.byname.middle
    local concreteLeaf = concreteMiddle.supertypes[1]
    testAssert.eq(concreteLeaf.byname.value, types.string)
    leaf.byname.late = types.number
    testAssert.eq(generics.instantiate(outer, bindings), instance)
    testAssert.eq(concreteLeaf.byname.late, types.number)
    middle.supertypes = {}
    generics.instantiate(outer, bindings)
    testAssert.eq(#concreteMiddle.supertypes, 0)
    middle.supertypes[1] = generics.reserveInstantiation(leaf, {[parameter] = parameter})
    generics.instantiate(outer, bindings)
    testAssert.eq(concreteMiddle.supertypes[1], concreteLeaf)
    concreteMiddle.supertypes[1] = types.any
    generics.instantiate(outer, bindings)
    testAssert.eq(concreteMiddle.supertypes[1], concreteLeaf)
    concreteMiddle.supertypes = {}
    generics.instantiate(outer, bindings)
    testAssert.eq(concreteMiddle.supertypes[1], concreteLeaf)
end

function M.aMidFillFailureRestoresTheEnclosingDependencyCollector()
    local parameter = types.typevar("T", "mid-fill-failure")
    local parent, child, bad = types.nominal(
        "MidFillParent",
        "record"
    ), types.nominal("MidFillChild", "record"), types.nominal("MidFillBad", "record")
    for _, declaration in ipairs({parent, child, bad}) do
        declaration.typeParams = {parameter}
    end
    child.byname.value = parameter
    bad.byname.broken = types.func({parameter}, {parameter})
    local openBad = generics.reserveInstantiation(bad, {[parameter] = parameter})
    parent.byname.aTrigger = types.func({parameter}, {})
    parent.byname.zChild = generics.reserveInstantiation(child, {[parameter] = parameter})
    local original, attempts = types.funcWith, 0
    types.funcWith = function(source, changes)
        if source == bad.byname.broken then
            error("mid-fill failure", 0)
        elseif source == parent.byname.aTrigger then
            attempts = attempts + 1
            local ok, problem = pcall(generics.rebind, openBad, {[parameter] = types.string})
            assert(not ok and tostring(problem):find("mid-fill failure", 1, true))
        end

        return original(source, changes)
    end
    local bindings = {[parameter] = types.string}
    local ok, instance = pcall(generics.instantiate, parent, bindings)
    types.funcWith = original
    assert(ok, instance)
    testAssert.eq(attempts, 1)
    testAssert.eq(instance.byname.zChild.byname.value, types.string)
    child.byname.late = types.boolean
    testAssert.eq(generics.instantiate(parent, bindings), instance)
    testAssert.eq(
        instance.byname.zChild.byname.late,
        types.boolean,
        "a failed nested fill must not steal the successful parent's later dependencies"
    )
    testAssert.eq(generics.instantiate(bad, bindings).byname.broken.params[1], types.string)
end

function M.lowercaseFormatargumentsEvaluatesTheExistingCheckedBody()
    for _, member in ipairs({"formatarguments"}) do
        local source = [[
local function format<F is string>(fmt: F, ...: unpackof types.MEMBER(F)): string
    return string.format(fmt, ...)
end
local value = format("%s=%d", "count", 3)
print(value)
]]
        source = source:gsub("MEMBER", member)
        clean(source)
        assert(
            codes(source:gsub("types.formatarguments", "types.formatArguments")) ~= "",
            "the retired public name must be refused"
        )
        oneDiagnostic(source:gsub('"count", 3', '"count", "wrong"'), "NUPP2006", "argument 3: string is not a number")
    end
    testAssert.eq(
        codes(
            [[
local types = {formatarguments = function(value: string): string return value end}
local value: types.formatarguments("%d")
]]
        ),
        "NUPP2421"
    )
end

function M.canonicalTypeNamesWorkInRealTypePositions()
    clean(
        [[
@comptime local function Bool(): type return types.bool end
@comptime local function Nil(): type return types.niltype end
@comptime local function Table(): type return types.tabletype end
@comptime local function Callable(): type
    return types.functiontype(types.pack({types.string}), types.pack({types.bool, types.niltype}))
end
local type Short = types.len(string, 1, 4)
local flag: Bool() = true
local nothing: Nil() = nil
local object: Table() = {}
local word: Short = "word"
local predicate: Callable() = function(value: string): (boolean, nil) return value ~= "", nil end
return flag, nothing, object, word, predicate
]]
    )
    testAssert.eq(codes('local type Bad = types.len(string, 4, 1)'), "NUPP2422")
    assert(
        codes('local type Bad = types.length(string, 1, 4)') ~= "",
        "the preceding constrained type builder is retired"
    )
end

function M.canonicalMetadataKeysAreDeclaredAndPrecedingKeysAreRefused()
    clean(
        [[
@comptime local function Recipe(info: types.derive.Info, field: types.derive.Field): string
    local a, b, c = info.provideridentity, info.owneridentity, info.hasconstructor
    local d, e = info.ownertype, info.interfacetype
    local f, g, h, i = field.readtype, field.writetype, field.hasdefault, field.defaultvalue
    return info.qualifiedname
end
@comptime local function Reflected(info: types.reflect.Info, field: types.reflect.Field, edge: types.reflect.Entry, node: types.reflect.Node): string
    local a, b, c = field.typename, field.hasdefault, field.defaultvalue
    local d, e = edge.hasdefault, edge.defaultvalue
    local f, g, h = node.staticfields, node.nestedtypes, node.associatedtypes
    local i, j, k = node.typeparameters, node.typebounds, node.packparameters
    local l, m, n = node.constparameters, node.parameterkinds, node.typearguments
    local o, p, q, r = node.packarguments, node.constarguments, node.noreturn, node.noyield
    local s, t, u = node.modulename, node.derivekey, node.arrayof
    local v, w, x = node.varargtype, node.borrowedfrom, node.borrowedfrommany
    local y, z = node.borrowedresult, node.parameterpack
    local aa, ab, ac = node.returnpack, node.yieldpack, node.resumepack
    local ad, ae, af, ag = node.startpack, node.resultkind, node.transferonly, node.countterm
    local ah, ai, aj, ak = node.readkey, node.readvalue, node.writekey, node.writevalue
    return info.qualifiedname
end
@comptime local function Described(T: type): type
    local info = types.describe(T)
    local a, b = info.sourcekind, info.declarationkind
    local c, d, e, f = info.readkey, info.readvalue, info.writekey, info.writevalue
    return T
end
local value: Described(string) = "checked"
return value
]]
    )
    for _, reference in ipairs({"info.qualifiedName", "field.readType", "field.hasDefault"}) do
        assert(
            codes(
                "@comptime local function Bad(info: types.derive.Info, field: types.derive.Field): any return "
                .. reference
                .. " end"
            ) ~= "",
            reference .. " is retired"
        )
    end
    -- Node keeps its readonly string indexer for extension metadata. Its actual
    -- output keys are checked by reflectionnamestest rather than typed refusal.
    for _, reference in ipairs({"info.qualifiedName", "field.typeName"}) do
        assert(
            codes(
                "@comptime local function Bad(info: types.reflect.Info, field: types.reflect.Field, node: types.reflect.Node): any return "
                .. reference
                .. " end"
            ) ~= "",
            reference .. " is retired"
        )
    end
end

function M.canonicalAliasMemberKeepsItsExclusiveCallbackContract()
    clean(
        [[
local record Value
    count: integer
end
local function inspect(handle: alias(Value)): nil
    handle:withexclusive(function(exclusive value: Value): integer return value.count end)
end
]]
    )
    assert(
        codes(
            [[
local record Value count: integer end
local function inspect(handle: alias(Value)): nil
    handle:withExclusive(function(exclusive value: Value): integer return value.count end)
end
]]
        ) ~= "",
        "the preceding alias callback member is retired"
    )
end

return M
