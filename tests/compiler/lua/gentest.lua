local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function generate(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local code, diags = gen.generate(result, "test")
    -- These generate from a bare parse, where `gen.generate` documents a checked one. A
    -- construct whose lowering reads the checker's annotations -- `new R(field = v)` is
    -- one -- then lowers to Lua that does not parse, which is what NUPP3005 reports and
    -- is not what any of these are about. Every other diagnostic still has to be
    -- absent.
    local lowering = {}
    for _, d in ipairs(diags) do
        if d.code ~= "NUPP3005" then
            lowering[#lowering + 1] = d
        end
    end
    testAssert.eq(#lowering, 0, "gen diagnostics for " .. src)

    return code
end

local function generateCoverage(src)
    local result = parser.parse(src, "coverage-test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in coverage test source")
    local code, diags, metadata = gen.generate(result, "coverage-test.nupp", {path = "coverage-test.nupp"})
    testAssert.eq(#diags, 0, "coverage gen diagnostics for " .. src)

    return code, metadata
end

local function withFreshCoverage(run)
    local outer = rawget(_G, "__nuppCoverage")
    local previous = outer and outer.hits["coverage-test.nupp"] or nil
    if outer then
        outer.hits["coverage-test.nupp"] = nil
    else
        rawset(_G, "__nuppCoverage", nil)
    end
    local ok, problem = pcall(run)
    if outer then
        outer.hits["coverage-test.nupp"] = previous
    else
        rawset(_G, "__nuppCoverage", nil)
    end
    if not ok then
        error(problem, 0)
    end
end

local function generateChecked(src)
    local result = parser.parse(src, "prepared_worker.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in checked generator source")
    local diagnostics = check.check(result, "prepared_worker.nupp", env)
    testAssert.eq(#diagnostics, 0, "check diagnostics for " .. src)
    local code, generated = gen.generate(result, "prepared_worker")
    testAssert.eq(#generated, 0, "generation diagnostics for " .. src)

    return code
end

-- Compile and execute; returns the chunk's results.
local function run(src, ...)
    local code = generate(src)
    local chunk, err = loadstring(code, "@gen_test")
    if not chunk then
        error("generated code does not load: " .. tostring(err) .. "\n---\n" .. code, 2)
    end

    return chunk(...)
end

local function countLines(s)
    local _, n = s:gsub("\n", "")
    return n
end

local M = {}

function M.indexedProviderAnnotationsEraseAndPreserveCallableIdentity()
    local code = generateChecked(
        [[
module forwarding
local type Provider = {create: function(value: string): string}
local implementation = {create = function(value: string): string return value end}
export const create: Provider.["create"] = implementation.create
export const original: function(value: string): string = implementation.create
]]
    )
    local exported = assert(loadstring(code, "@indexed-provider"))()
    testAssert.eq(exported.create, exported.original)
    testAssert.eq(exported.create("kept"), "kept")
end

function M.semanticTypeOperatorsEraseFromRuntimeAnnotations()
    local code = generateChecked(
        [[
local type Row = {name: string}
local key: keyof Row = "name"
local value: writeof Row.["name"] = "kept"
local row: {@readonly [K in keyof Row]: Row.[K]} = {name = value}
local function identity(value: Row.["name"]): Row.["name"] return value end
local optional: Row.["name"]? = value
return key, identity(row.name), optional, "cast" as Row.["name"]
]]
    )
    local key, value, optional, cast = assert(loadstring(code, "@semantic-types"))()
    testAssert.eq(key, "name")
    testAssert.eq(value, "kept")
    testAssert.eq(optional, "kept")
    testAssert.eq(cast, "cast")
end

-- A comparison whose field is on the right has to reverse its ordered operator
-- when the refinement is normalized to put that field on the left. Equality hid
-- this because it is symmetric; `64 >= self.n` otherwise became `self.n >= 64`.
function M.refinementsReverseOrderedComparisonsWrittenLiteralFirst()
    local source = [[
local interface Small
    n: integer
    satisfies |self| -> 64 >= self.n
end
local function isSmall(value: unknown): boolean
    return value is Small
end
return isSmall
]]
    local code = generateChecked(source)
    local isSmall = assert(loadstring(code))()
    testAssert.eq(isSmall({n = 63}), true, "the reversed comparison admits a smaller value")
    testAssert.eq(isSmall({n = 65}), false, "the reversed comparison rejects a larger value")
    testAssert.eq(isSmall({n = "63"}), false, "an ordered comparison with the wrong runtime type is false")
end

function M.lengthRefinementsAreFalseForTheWrongRuntimeType()
    local source = [[
local interface Short
    name: string
    satisfies |self| -> #self.name <= 4
end
local function isShort(value: unknown): boolean
    return value is Short
end
return isShort
]]
    local code = generateChecked(source)
    local isShort = assert(loadstring(code))()
    testAssert.eq(isShort({name = "four"}), true, "a short string passes")
    testAssert.eq(isShort({name = "longer"}), false, "a long string fails")
    testAssert.eq(isShort({name = 4}), false, "a non-string field does not make `is` raise")
end

function M.refinementsRenderOrdinaryNumericLiteralForms()
    local source = [[
local interface Bounded
    n: number
    satisfies |self| -> self.n >= -1_000 and self.n < 0x10
end
local function isBounded(value: unknown): boolean
    return value is Bounded
end
return isBounded
]]
    local isBounded = assert(loadstring(generateChecked(source)))()
    testAssert.eq(isBounded({n = -1000}), true, "negative separated literal")
    testAssert.eq(isBounded({n = 15}), true, "hexadecimal upper bound")
    testAssert.eq(isBounded({n = 16}), false, "exclusive upper bound")
end

function M.targetFactsResolveTheHostFromTheEnvironment()
    local environments = {{value = env}}
    for _, host in ipairs({"native", "browser"}) do
        environments[#environments + 1] = {
            value = envMod.new(HERE .. "/..", {
                cache = false,
                config = {build = {host = host}}
            }),
            host = host,
        }
    end
    for _, environment in ipairs(environments) do
        local expectedHost = environment.host or "native"
        local parsed = parser.parse("return true", "target-facts.nupp")
        local diagnostics = check.check(parsed, "target-facts.nupp", environment.value, {
            moduleName = "nupp.runtime.target",
        })
        testAssert.eq(#diagnostics, 0, "target fact checking")
        local code, generated = gen.generate(parsed, "target-facts.nupp")
        testAssert.eq(#generated, 0, "target fact generation")
        local facts = assert(loadstring(code))()
        testAssert.eq(facts.dialect, "luajit", "every artifact runs on LuaJIT")
        testAssert.eq(facts.host, expectedHost, "only an explicit host overrides the native default")

        local imported = parser.parse('return require("nupp.runtime.browser.time")', "host-import.nupp")
        local admission = check.check(imported, "host-import.nupp", environment.value, {
            moduleName = "nupp.fixture.host",
        })
        local rejected = false
        for _, diagnostic in ipairs(admission) do
            if diagnostic.code == "NUPP3006" then
                rejected = true
            else
                assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
            end
        end
        testAssert.eq(rejected, expectedHost ~= "browser", "browser module admission follows the resolved host")
    end
end

function M.returnedRecordsKeepTheCallersTraceFrame()
    local source = [[
local record Token value: integer end
local record Built
    value: integer
    constructor(self, value: integer) self.value = value end
end
local function direct(value: integer): Token return new Token(value = value) end
local function cast(value: integer): Token return new Token(value = value) as Token end
local function constructed(value: integer): Built return new Built(value) end
return direct, cast, constructed
]]
    local code = generateChecked(source)
    testAssert.eq(countLines(code), countLines(source), "record returns keep source lines")
    local direct, cast, constructed = assert(loadstring(code))()
    local util = require("jit.util")
    local trace = require("debug.profile.trace")
    for _, fn in ipairs({direct, cast, constructed}) do
        testAssert.eq(fn(37).value, 37)
        local pc = 1
        while true do
            local instruction = util.funcbc(fn, pc)
            if not instruction then
                break
            end
            local opcode = trace.opcodename(instruction % 256)
            assert(opcode ~= "CALLT" and opcode ~= "CALLMT", "a new return retains its frame: " .. opcode)
            pc = pc + 1
        end
    end
end

function M.recordReturnsDoNotConsumeAnotherLocalSlot()
    local declarations, terms = {}, {}
    for index = 1, 200 do
        declarations[index] = "local n" .. index .. ": integer = " .. index
        terms[index] = "n" .. index
    end
    local code = generateChecked(
        "local record Token value: integer end\n" .. "local function make(): Token\n" .. table.concat(
            declarations,
            "\n"
        ) .. "\nreturn new Token(value = " .. table.concat(terms, " + ") .. ")\nend\nreturn make()"
    )
    testAssert.eq(assert(loadstring(code))().value, 20100, "a return fits at the local limit")
end

function M.recordReturnsPreserveEvaluationAndMultipleValues()
    local code = generateChecked(
        [[
local record Token value: integer end
local log = ""
local function value(label: string, n: integer): integer log = log .. label return n end
local function tail(): (nil, integer) log = log .. "c" return nil, 9 end
local function one(): Token
    local __nuppT1: integer = 31
    return new Token(value = value("a", __nuppT1))
end
local function many(): (Token, nil, integer)
    return new Token(value = value("b", 32)), tail()
end
local a = one()
local b, c, d = many()
return a.value, b.value, c, d, log
]]
    )
    local a, b, c, d, log = assert(loadstring(code))()
    testAssert.eq(a, 31)
    testAssert.eq(b, 32)
    testAssert.eq(c, nil)
    testAssert.eq(d, 9)
    testAssert.eq(log, "abc", "each constructor argument runs once in source order")
end

function M.exportedPrimitiveFunctionsPublishPreparedWorkerTransfers()
    local code = generateChecked(
        [[
module jobs

export type Count = integer

export record Payload
    id: integer
    label: string
    ready: boolean
end

export function identity(value: Count): Count
    return value
end

export function echo(value: string): string
    return value
end

export function dynamic(value: any): any
    return value
end

export function echoPayload(value: Payload): Payload
    return value
end
]]
    )
    assert(
        code:find('member="identity",captures={values={},count=0},input="number",output="number"', 1, true),
        "a resolved numeric alias publishes its prepared plan: " .. code
    )
    assert(
        code:find('member="echo",captures={values={},count=0},input="string",output="string"', 1, true),
        "a string function publishes its prepared plan: " .. code
    )
    assert(not code:find('member="dynamic"', 1, true), "a dynamic signature stays on the checked fallback: " .. code)
    assert(
        code:find(
            'member="echoPayload",captures={values={},count=0},input={kind="record",schema="jobs\\0Payload\\0id\\0number\\0label\\0string\\0ready\\0boolean",address="jobs\\0Payload",record=Payload,fields={"id","label","ready"},types={"number","string","boolean"}}',
            1,
            true
        ),
        "an exact primitive-field record publishes its schema: " .. code
    )
end

-- An escaped quote inside a backtick string is one escape in the Lua literal too,
-- with or without an interpolation beside it.
function M.escapedQuotesInBacktickStringsLoad()
    local code = generate('local s = `a\\"b`\nlocal t = `x\\"${s}\\"y`\nreturn s, t')
    local chunk = assert(loadstring(code))
    local s, t = chunk()
    testAssert.eq(s, 'a"b', "plain backtick string")
    testAssert.eq(t, 'x"a"b"y', "interpolated backtick string")
end

function M.lineCountInvariant()
    local cases = {
        "local x: number = 1\nreturn x",
        "local record R\n   a: number\n   b: string\nend\nreturn 1",
        "local f =\n   |a: number,\n    b: number| -> a + b\nreturn f(1, 2)",
        "return `multi\nline ${1 +\n2} tail`",
        "local v: number | string = 5\nif v is number then\n   return v\nend",
        "local f = |a: number,\n   b: number| -> do\n   return a + b\nend\nreturn f(1, 2)",
        "local t = nil\nlocal v = t?.a\n   ?.b\nreturn v",
        "local n = 7\nn //=\n   2\nreturn n",
        "local m = nil\nm ??=\n   3\nreturn m",
        "local t = nil\nif v = t\nthen\n   return v\nelseif w =\n   t then\n   return w\nend",
    }
    for _, src in ipairs(cases) do
        local code = generate(src)
        testAssert.eq(countLines(code), countLines(src) + 1, "line count changed for:\n" .. src .. "\n---\n" .. code)
        -- (+1: generated output always ends with a final newline)
    end
end

-- `if NAME = EXPR then` takes its arm on any value but nil, evaluates EXPR
-- once, binds NAME for that arm only, and leaves an outer NAME to the later
-- arms: the desugaring holds the value in a temporary and makes NAME a local
-- of the arm rather than of the chain.
function M.ifBindingsTakeNonNilValuesOnceAndScopeToTheirArm()
    local src = table.concat(
        {
            "local v = 'outer'",
            "local calls = 0",
            "local function probe(value)",
            "   calls = calls + 1",
            "   return value",
            "end",
            "local function classify(value)",
            "   if v = probe(value) then",
            "      return 'bound:' .. tostring(v)",
            "   elseif v == 'outer' then",
            "      return 'outer seen'",
            "   else",
            "      return 'no outer'",
            "   end",
            "end",
            "local function chain(first, second)",
            "   if a = probe(first) then",
            "      return 'a' .. tostring(a)",
            "   elseif b = probe(second) then",
            "      return 'b' .. tostring(b)",
            "   end",
            "   return 'none'",
            "end",
            "return classify, chain, function() return calls end",
        },
        "\n"
    )
    local classify, chain, callsSoFar = run(src)
    testAssert.eq(classify(1), "bound:1")
    testAssert.eq(classify(false), "bound:false", "false is a value, not nil")
    testAssert.eq(classify(nil), "outer seen", "the binding is not the outer name in a later arm")
    testAssert.eq(callsSoFar(), 3, "the bound expression is evaluated once per test")
    testAssert.eq(chain(nil, 2), "b2")
    testAssert.eq(chain(1, 2), "a1")
    testAssert.eq(callsSoFar(), 6, "a later arm's expression is evaluated only when reached")
    testAssert.eq(chain(nil, nil), "none")
    local code = generate(src)
    assert(
        code:find("do local __nuppT%d+ = probe %( value %) if __nuppT%d+ ~= nil then local v = __nuppT%d+\n"),
        "the first arm opens a block around its temporary:\n" .. code
    )
    assert(
        code:find("else local __nuppT%d+ = probe %( second %) if __nuppT%d+ ~= nil then local b = __nuppT%d+\n"),
        "a later binding arm nests under the else of the one before:\n" .. code
    )
end

function M.generatedLinesHaveNoTrailingWhitespace()
    local code = generate(
        table.concat(
            {
                "local record Section",
                "   title: string",
                "   codes: {string}",
                "end",
                "local sections = {",
                "   new Section(",
                "      title = 'Language',",
                "      codes = {}",
                "   )",
                "}",
                "return sections",
            },
            "\n"
        )
    )
    assert(not code:find("[ \t]+\n"), "generated Lua has trailing whitespace:\n" .. code)
end

function M.returnPacksEraseEntirely()
    -- A return annotation is type material and must leave nothing behind. A pack got
    -- this wrong in two ways at once: a parenthesized one was spliced into the function
    -- it annotated, where its `(`, `,` and `)` were indistinguishable from code and
    -- were emitted as `( , )`; and one with a tail was kept whole as a node kind gen
    -- did not know to erase, so its `...` was emitted. Both produced Lua that did not
    -- parse, while the build reported success.
    local cases = {
        {"a bare list", "local function f(a: integer): integer, string\n   return a, 'x'\nend\nreturn f(1)"},
        {"a parenthesized pack", "local function f(a: integer): (integer, string)\n   return a, 'x'\nend\nreturn f(1)"},
        {"a homogeneous tail", "local function f(a: integer): ...integer\n   return a\nend\nreturn f(1)"},
        {"a parenthesized single", "local function f(a: integer): (integer)\n   return a\nend\nreturn f(1)"},
        {"a function-typed return", "local function f(): (function()?)\n   return nil\nend\nreturn f()"},
        {"an empty pack", "local function f(a: integer): ()\n   return\nend\nf(1)\nreturn 1"},
    }
    for _, case in ipairs(cases) do
        local label, src = case[1], case[2]
        local code = generate(src)
        -- The signature this is about is the one in the source, not the runtime
        -- prologue that shares its line: the prologue is ordinary Lua and joins
        -- strings with `..`, which is a `)` followed by a `.` and exactly what
        -- this rejects. Reading the whole line made every case fail as soon as
        -- something in the prologue concatenated.
        local signature = code:match("local function f[^\n]*")
        assert(signature, label .. " emitted no function to inspect:\n" .. code)
        if signature:find("%)%s*[%(%.]") then
            error(("%s left type punctuation in the signature: %s"):format(label, signature), 0)
        end
        local chunk, err = loadstring(code, "@pack_test")
        if not chunk then
            error(("%s generated Lua that does not load: %s\n---\n%s"):format(label, err, code), 0)
        end
        testAssert.eq(countLines(code), countLines(src) + 1, label .. " changed the line count:\n" .. code)
    end
end

function M.coverageModeLeavesNormalOutputAlone()
    local src = "local n: integer = 1\nreturn n"
    local result = parser.parse(src, "coverage-off.nupp")
    local ordinary = assert(gen.generate(result, "coverage-off.nupp"))
    local explicitlyOff = assert(gen.generate(result, "coverage-off.nupp", false))
    testAssert.eq(explicitlyOff, ordinary, "coverage=false changes ordinary Lua")
end

function M.coverageModeCountsStatementsFunctionsAndBranches()
    local code, metadata = generateCoverage(
        table.concat(
            {
                "local function choose(value: boolean): integer",
                "   if value then return 1 end",
                "   return 2",
                "end",
                "return choose(true)",
            },
            "\n"
        )
    )
    testAssert.eq(countLines(code), 5, "coverage generation changes line count")
    assert(metadata and metadata.path == "coverage-test.nupp", "coverage manifest path")
    local kinds = {}
    for _, site in ipairs(metadata.sites) do
        kinds[site.kind] = (kinds[site.kind] or 0) + 1
    end
    assert((kinds.statement or 0) >= 3, "statement sites are recorded")
    assert((kinds["function"] or 0) >= 1, "function sites are recorded")
    assert((kinds.branch or 0) >= 1, "branch sites are recorded")
    withFreshCoverage(function()
        local chunk, err = loadstring(code, "@coverage_generated")
        assert(chunk, tostring(err) .. "\n" .. code)
        testAssert.eq(chunk(), 1, "instrumented program result")
        local hits = assert(_G.__nuppCoverage and _G.__nuppCoverage.hits["coverage-test.nupp"])
        local sawStatement, sawFunction, sawTrue = false, false, false
        for _, site in ipairs(metadata.sites) do
            if site.kind == "statement" and (hits[tostring(site.id)] or 0) > 0 then
                sawStatement = true
            end
            if site.kind == "function" and (hits[tostring(site.id)] or 0) > 0 then
                sawFunction = true
            end
            if site.kind == "branch" and (hits[tostring(site.id) .. ":true"] or 0) > 0 then
                sawTrue = true
            end
        end
        assert(sawStatement and sawFunction and sawTrue, "instrumented run records the executed source sites")
    end)
end

-- A report lists functions rather than reading them against the source, so a
-- function site that carries only a line number leaves a reader with a number.
-- Declarations are named and spanned here; anonymous bodies stay nameless,
-- because inventing one would invent the only handle a reader has.
function M.coverageFunctionSitesCarryNamesAndSpans()
    local _, metadata = generateCoverage(
        table.concat(
            {
                "local function named(value: integer): integer",
                "   return value",
                "end",
                "local anonymous = function(): integer",
                "   return 1",
                "end",
                "return named(1) + anonymous()",
            },
            "\n"
        )
    )
    local byName = {}
    local anonymous = 0
    for _, site in ipairs(metadata.sites) do
        if site.kind == "function" then
            if site.name then
                byName[site.name] = site
            else
                anonymous = anonymous + 1
            end
        end
    end
    local named = assert(byName.named, "the declared function is named in the manifest")
    testAssert.eq(named.line, 1, "the named function starts on its declaration line")
    testAssert.eq(named.endLine, 3, "the named function spans to its end")
    testAssert.eq(anonymous, 1, "the anonymous function is one nameless site")
end

-- A function attached to a table is called by its own name. Naming it by the
-- table would name every function in the file the same thing.
function M.coverageFunctionSitesNameQualifiedFunctionsByTheirLeaf()
    local _, metadata = generateCoverage(
        table.concat(
            {
                "local shapes = {}",
                "function shapes.scaledTotal(values: {number}): number",
                "   return 1",
                "end",
                "function shapes.larger(left: number): number",
                "   return left",
                "end",
                "return shapes",
            },
            "\n"
        )
    )
    local names = {}
    for _, site in ipairs(metadata.sites) do
        if site.kind == "function" and site.name then
            names[site.name] = true
        end
    end
    assert(names.scaledTotal and names.larger, "each attached function is named by its leaf")
    assert(not names.shapes, "the table they attach to is not a function name")
end

-- A method is called what it is called on the receiver, not the path it hangs
-- off: the reader is already looking at the record it belongs to.
function M.coverageFunctionSitesNameMethodsByTheirOwnName()
    local _, metadata = generateCoverage(
        table.concat(
            {
                "local record Point",
                "   x: integer",
                "end",
                "function Point:magnitude(): integer",
                "   return self.x",
                "end",
                "return Point",
            },
            "\n"
        )
    )
    local names = {}
    for _, site in ipairs(metadata.sites) do
        if site.kind == "function" and site.name then
            names[site.name] = true
        end
    end
    assert(names.magnitude, "the method is named by its own name")
end

-- Sites are what a coverage build reports, and an ordinary build has none: the
-- naming walk must not run, and the generated bytes must not move.
function M.ordinaryGenerationRecordsNoFunctionNames()
    local result = parser.parse("local function named(): integer\n   return 1\nend\n", "plain.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in plain source")
    local _, _, metadata = gen.generate(result, "plain.nupp")
    testAssert.eq(metadata, nil, "an ordinary compile produces no coverage manifest")
end

function M.coverageModeCountsANamedVarargFunction()
    -- A named vararg binds its pack at the top of the body; the body is still a
    -- function site, recorded and hit like any other.
    local code, metadata = generateCoverage(
        table.concat(
            {
                "local function count(...values: integer): integer",
                "   return values.n",
                "end",
                "return count(1, 2, 3)",
            },
            "\n"
        )
    )
    testAssert.eq(countLines(code), 4, "coverage generation changes line count")
    local functions = 0
    for _, site in ipairs(metadata.sites) do
        if site.kind == "function" then
            functions = functions + 1
        end
    end
    testAssert.eq(functions, 1, "the vararg function is a function site")
    withFreshCoverage(function()
        local chunk, err = loadstring(code, "@coverage_vararg")
        assert(chunk, tostring(err) .. "\n" .. code)
        testAssert.eq(chunk(), 3, "instrumented program result")
        local hits = assert(_G.__nuppCoverage and _G.__nuppCoverage.hits["coverage-test.nupp"])
        local sawFunction = false
        for _, site in ipairs(metadata.sites) do
            if site.kind == "function" and (hits[tostring(site.id)] or 0) > 0 then
                sawFunction = true
            end
        end
        assert(sawFunction, "the instrumented run records the vararg function")
    end)
end

function M.erasure()
    testAssert.eq(run("local x: number = 21\nreturn x * 2"), 42)
    testAssert.eq(run("local record P\n   x: number\nend\nlocal p = { x = 7 } as P\nreturn p.x"), 7)
    testAssert.eq(run("local type E = 'a' | 'b'\nreturn 'ok'"), "ok")
    testAssert.eq(run("local type Id = uint32\nlocal i = 9\nreturn i + 0"), 9)
    testAssert.eq(run("local function f<T>(x: T): T return x end\nreturn f('generic')"), "generic")
    testAssert.eq(run("@jit local function hot(): number return 5 end\nreturn hot()"), 5)
end

function M.nestedRecordsAndInlineMethodsRun()
    testAssert.eq(
        run(
            table.concat(
                {
                    "local record namespace",
                    "   record Task",
                    "      value: number",
                    "      function doubled(): number",
                    "         return self.value * 2",
                    "      end",
                    "   end",
                    "end",
                    "local task = setmetatable({value = 21}, namespace.Task)",
                    "return task:doubled()",
                },
                "\n"
            )
        ),
        42
    )
end

function M.tecsStyleLateEventRegistrationRuns()
    testAssert.eq(
        run(
            table.concat(
                {
                    "local interface Event",
                    "   eventId: integer",
                    "   init: function(instance: self, ...: any)",
                    "end",
                    "local record events",
                    "   record OnSpawn is Event",
                    "      entity: integer",
                    "      metamethod __call: function(self, entity: integer): self",
                    "   end",
                    "end",
                    "events.OnSpawn.init = function(instance: events.OnSpawn, entity: integer)",
                    "   instance.entity = entity",
                    "end",
                    "local function newEvent<E is Event>(event: Type<E>)",
                    "   local id = 7",
                    "   local instanceMt = {__index = event}",
                    "   setmetatable(event, {__call = function(_self: E, ...: any): E",
                    "      local instance = setmetatable({eventId = id}, instanceMt) as E",
                    "      event.init(instance, ...)",
                    "      return instance",
                    "   end})",
                    "end",
                    "newEvent(events.OnSpawn)",
                    "local spawned = events.OnSpawn(42)",
                    "return spawned.eventId + spawned.entity",
                },
                "\n"
            )
        ),
        49
    )
end

function M.constSemantics()
    testAssert.eq(run("const x: number = 42\nreturn x"), 42)
    testAssert.eq(run("const function f(x: number): number return x * 2 end\nreturn f(21)"), 42)
    local code = generate("const answer: integer = 42\nreturn answer")
    assert(code:find("const answer = 42", 1, true), "const should survive type erasure: " .. code)
end

function M.generatedBindingsPreserveTheSharedRuntimeSubset()
    local recordCode = generate(table.concat({"local record Point", "   x: number", "end", "return Point",}, "\n"))
    assert(recordCode:find("local Point = {}", 1, true), recordCode)

    local interfaceCode = generate(
        table.concat(
            {
                "local interface Named",
                "   name: string",
                "   function getName(): string return self.name end",
                "end",
                "return Named",
            },
            "\n"
        )
    )
    assert(interfaceCode:find("local Named = {}", 1, true), interfaceCode)

    local compoundCode = generate(
        table.concat({"local target = {value = 8}", "target['value'] //= 2", "return target.value",}, "\n")
    )
    assert(compoundCode:find("do const __nuppT", 1, true), compoundCode)
    assert(compoundCode:find("const __nuppT2 =", 1, true), compoundCode)
end

-- A literal type is a type-only node like any other postfix or shape: the annotation
-- has to vanish rather than leaving its token behind as a bare expression statement
-- next to the one the initializer already wrote.
function M.literalTypeErasure()
    testAssert.eq(run("local t: true = true\nreturn t"), true)
    testAssert.eq(run("local f: false = false\nreturn f"), false)
    testAssert.eq(run("local m: \"read\" = \"read\"\nreturn m"), "read")
    testAssert.eq(run("local function mode(x: \"read\"): \"read\" return x end" .. "\nreturn mode(\"read\")"), "read")
end

-- `const T`, the read-only view, is a type node the same way `T?` or `T*` are: erased
-- in place, not left as a stray identifier beside the value.
function M.constTypeErasure()
    testAssert.eq(run("local x: const number = 42\nreturn x"), 42)
end

function M.ternarySemantics()
    testAssert.eq(run("return 1 < 2 ? 'yes' : 'no'"), "yes")
    -- falsy middle arm must still be selected (the a-and-b-or-c pitfall)
    testAssert.eq(run("local t = true\nreturn t ? false : 1"), false)
    -- laziness: the untaken arm must not evaluate
    testAssert.eq(
        run([[
local hits = 0
local function boom() hits = hits + 1 return 9 end
local v = true ? 1 : boom()
return hits]]),
        0
    )
    -- right associativity chain
    testAssert.eq(run("local n = 2\nreturn n == 1 ? 'one' : n == 2 ? 'two' : 'many'"), "two")
end

function M.safeNavigationSemantics()
    testAssert.eq(run("local t = { x = 5 }\nreturn t?.x"), 5)
    testAssert.eq(run("local t = nil\nreturn t?.x"), nil)
    testAssert.eq(run("local t = { m = { n = 3 } }\nreturn t?.m?.n"), 3)
    testAssert.eq(run("local t = nil\nreturn t?.['k']"), nil)
    testAssert.eq(run("local f = nil\nreturn f?.(1)"), nil)
    testAssert.eq(run("local f = function(a) return a * 3 end\nreturn f?.(2)"), 6)
    -- single evaluation of the object expression
    testAssert.eq(
        run(
            [[
local calls = 0
local function get() calls = calls + 1 return { v = 1 } end
local _ = get()?.v
return calls]]
        ),
        1
    )
end

function M.shortFunctionSemantics()
    testAssert.eq(run("local add = |a, b| -> a + b\nreturn add(2, 3)"), 5)
    testAssert.eq(run("local dbl = x -> x * 2\nreturn dbl(21)"), 42)
    testAssert.eq(run("local t = || -> true\nreturn t()"), true)
    testAssert.eq(run("local f = |n: number| -> do return n + 1 end\nreturn f(1)"), 2)
    testAssert.eq(run("local curry = a -> b -> a .. b\nreturn curry('x')('y')"), "xy")
    -- Expression-bodied short functions always return exactly one value.
    testAssert.eq(select("#", run([[
local function pair() return 1, 2 end
local one = || -> pair()
return one()]])), 1)
end

-- What LuaJIT 2.1 backported is written out, not lowered. This is the whole reason a
-- `?.` chain costs a branch instead of a closure call, so it is asserted on the
-- generated text rather than only on the behaviour.
function M.backportedSyntaxIsPassedThrough()
    local cases = {
        {"local t = nil\nreturn t?.a?.b", "?."},
        {"local t = nil\nreturn t?.:m()", "?. : m"},
        {"local t = {}\nreturn t:m?.()", "?."},
        {"return 1 ?? 2", "??"},
        {"return true ? 1 : 2", "?"},
        {"return 3 & 5 | 2 ~ 1 << 1 >> 1 ~>> 1", "&"},
        {"local a = 1\na += 2\nreturn a", "+="},
        {"local a = 5\na ~= 3\nreturn a", "~="},
        {"return (|a| -> a)(1)", "|a| ->"},
        {"return 1_000", "1_000"},
    }
    for _, case in ipairs(cases) do
        local code = generate(case[1])
        assert(
            code:find(case[2], 1, true),
            ("expected %q in the output for %s\n---\n%s"):format(case[2], case[1], code)
        )
    end
    -- and no trace of the lowerings these replaced
    local lowered = generate("local t = nil\nreturn t?.a ?? (1 & 2)")
    local sourceStart = assert(lowered:find("local t = nil", 1, true))
    local loweredBody = lowered:sub(sourceStart)
    assert(not loweredBody:find("function", 1, true), "no closure: " .. lowered)
    assert(not loweredBody:find("bit.", 1, true), "no bit library: " .. lowered)
end

-- What 2.1 did not backport still is lowered, so those keep their own tests.
function M.unbackportedSyntaxIsStillLowered()
    testAssert.eq(run("return -7 // 2"), -4)
    testAssert.eq(run("local a = -7\na //= 2\nreturn a"), -4)
    testAssert.eq(run("local a = nil\na ??= 5\nreturn a"), 5)
    testAssert.eq(run("local f = |...v| -> v.n\nreturn f(1, 2, 3)"), 3)
    testAssert.eq(run("local function f(...v) return v.n end\nreturn f(nil, nil)"), 2)
    local code = generate("return 7 // 2")
    assert(code:find("math.floor", 1, true), "floor division lowers: " .. code)
end

function M.numberSeparatorSemantics()
    testAssert.eq(run("return 1_234 + 0_x_10 + 1_e_2"), 1350)
    local code = generate("return 1_2_3")
    assert(code:find("1_2_3", 1, true), "separators survive: the runtime reads them: " .. code)
end

function M.continueSemantics()
    testAssert.eq(
        run([[
local total = 0
for i = 1, 5 do
   if i % 2 == 0 then continue end
   total += i
end
return total]]),
        9
    )
    testAssert.eq(
        run([[
local n, hits = 0, 0
repeat
   n += 1
   if n < 3 then continue end
   hits += 1
until n >= 3
return hits]]),
        1
    )
    -- The until condition is in the body's scope, so a continue ahead of a
    -- later local would jump into that local's scope.
    testAssert.eq(
        run(
            [[
local total, i = 0, 0
repeat
   i += 1
   local before = i
   if i % 2 == 0 then continue end
   local doubled = i * 2
   total += doubled
until before >= 10
return total]]
        ),
        50
    )
    testAssert.eq(
        run(
            [[
local total, i = 0, 0
repeat
   i += 1
   local kept = do
      if i == 2 then continue end
      yield i
   end
   for j = 1, 2 do
      if j == 1 then continue end
      total += kept
   end
until i >= 4
return total]]
        ),
        8
    )
end

function M.namedVarargSemantics()
    local n, first, second, plain = run(
        [[
local function collect(prefix, ...args)
   return args.n, args[1], args[2], select("#", ...)
end
return collect("ignored", nil, 3)]]
    )
    testAssert.eq(n, 2)
    testAssert.eq(first, nil)
    testAssert.eq(second, 3)
    testAssert.eq(plain, 2)
    testAssert.eq(run("local count = |...args| -> args.n\nreturn count(nil, nil)"), 2)

    local code = generate("local function f(...args) return args.n end")
    assert(code:find("...", 1, true), "plain vararg remains in output")
    assert(code:find("local args = { n = _G.select", 1, true), "named vararg table is lowered")
    assert(not code:find("...args", 1, true), "named spelling is erased")
end

function M.istringSemantics()
    testAssert.eq(run("local n = 6\nreturn `n is ${n}, double ${n * 2}`"), "n is 6, double 12")
    testAssert.eq(run("return `${1}${2}`"), "12")
    testAssert.eq(run("return `plain`"), "plain")
    testAssert.eq(run("return `quote \" and \\` tick`"), 'quote " and ` tick')
    testAssert.eq(run("return `escaped \\${x}`"), "escaped ${x}")
    testAssert.eq(run("return `a\nb`"), "a\nb")
    testAssert.eq(run("local t = { n = 4 }\nreturn `v=${ ({ t.n })[1] }`"), "v=4")
end

function M.dedentLongStringSemantics()
    testAssert.eq(run("return dedent [[\n   hello\n   ]]"), "hello\n")
    testAssert.eq(run("return dedent [[\n   outer\n      inner\n   ]]"), "outer\n   inner\n")
    testAssert.eq(run("return dedent [=[\n   ]] remains text\n   ]=]"), "]] remains text\n")
    testAssert.eq(run("return dedent [[\n    {\n        \"user\": \"foo\"\n    }]]"), "{\n    \"user\": \"foo\"\n}")
end

function M.isSemantics()
    testAssert.eq(run("local v: number | string = 'hi'\nreturn v is string"), true)
    testAssert.eq(run("local v: number | string = 5\nreturn v is string"), false)
    testAssert.eq(run("local v = nil\nreturn v is nil"), true)
    testAssert.eq(run("local f = print\nreturn f is function(): nil"), true)
end

-- A test whose answer the subject's declared type already settles compiles into the
-- one question left, and `nil` is the answer to that question as much as any other
-- value is. On a subject narrowing has already reduced to nil, `is nil` is simply
-- true, and asking whether the value is present would answer it backwards.
function M.isSemanticsWhereTheTestAdmitsNil()
    local source = table.concat(
        {
            "local function classify(v: string | nil): integer",
            "    if v is string then",
            "        return 1",
            "    elseif v is nil then",
            "        return 2",
            "    end",
            "    return 3",
            "end",
            "local function settled(v: string | nil): boolean",
            "    if v is string then",
            "        return false",
            "    end",
            "    return v is string | nil",
            "end",
            "return classify, settled",
        },
        "\n"
    )
    local classify, settled = assert(loadstring(generateChecked(source), "@gen_nil_test"))()
    testAssert.eq(classify(nil), 2, "a nil subject takes the nil arm")
    testAssert.eq(classify("text"), 1, "a string subject takes the string arm")
    testAssert.eq(settled(nil), true, "a target that admits nil is satisfied by nil")
end

function M.bitAndFloordivSemantics()
    testAssert.eq(run("return 5 & 3"), 1)
    testAssert.eq(run("return 5 | 2"), 7)
    testAssert.eq(run("return 2 ~ 3"), 1)
    testAssert.eq(run("return 1 << 4"), 16)
    testAssert.eq(run("return 256 >> 4"), 16)
    testAssert.eq(run("return -8 ~>> 1"), -4)
    testAssert.eq(run("return ~0"), -1)
    testAssert.eq(run("return -7 // 2"), -4)
    testAssert.eq(run("return 7 // 2"), 3)
end

-- These guarantees outlive the portable lowering backend. Both paths consume
-- the same fixtures while the explicit rollback remains supported.
function M.sharedLanguageSemanticsSurviveLegacyRetirement()
    local fixtures = dofile(HERE .. "/fixtures/language-semantics.lua")
    for name, fixture in pairs(fixtures) do
        local result = parser.parse(fixture.source, name .. ".nupp")
        testAssert.eq(#result.errors, 0, name .. " parses")
        local diagnostics = check.check(result, name .. ".nupp", env)
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.msg)
        end
        local code, generated = gen.generate(result, name)
        testAssert.eq(#generated, 0, name .. " generates")
        local chunk = assert(loadstring(code, "@shared-" .. name))

        local function verify(...)
            testAssert.eq(select("#", ...), fixture.count, name .. " result count")
            for index = 1, fixture.count do
                testAssert.eq(select(index, ...), fixture.expected[index], name .. " result " .. index)
            end
        end

        verify(chunk())
    end
end

-- Checks, generates and runs `src`, returning what it printed. `filename` picks the
-- name the checked chunk carries.
local function printed(src, filename)
    filename = filename or "printed.nupp"
    local result = parser.parse(src, filename)
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    for _, d in ipairs(check.check(result, filename, env)) do
        assert(d.severity ~= "error", "check error for " .. src .. ": " .. tostring(d.msg or d.message))
    end
    local code, diags = gen.generate(result, filename)
    testAssert.eq(#diags, 0, "gen diagnostics for " .. src)
    local chunk = assert(loadstring(code, "@" .. filename))
    local out = {}
    setfenv(
        chunk,
        setmetatable(
            {
                print = function(...)
                    local parts = {}
                    for i = 1, select("#", ...) do
                        parts[i] = tostring((select(i, ...)))
                    end
                    out[#out + 1] = table.concat(parts, "\t")
                end,
            },
            {__index = _G}
        )
    )
    chunk()

    return table.concat(out, "\n")
end

-- A lowering that needs a runtime function reaches it through `_G`, so a local of the
-- same name in the program -- `type` in a parser, `math` in a geometry module -- does
-- not change what `a // 2` or `v is number` means.
function M.loweringsReachRuntimeGlobalsPastAShadowingLocal()
    testAssert.eq(
        printed(
            "local math = {floor = function(x: number): number return 42 end}\nlocal a: integer = 7\nprint(a // 2)",
            "printed.nupp"
        ),
        "3"
    )
    testAssert.eq(printed("local math = {}\nlocal a = 7\na //= 2\nprint(a)"), "3")
    testAssert.eq(
        printed(
            "local type = function(x: any): string return 'table' end\nlocal v: any = 5\nprint(v is number, v is string)"
        ),
        "true\tfalse"
    )
    testAssert.eq(
        printed(
            "local getmetatable = function(x: any): any return nil end\nlocal record R\n    x: integer\nend\n"
            .. "local r: any = new R(x = 1)\nprint(r is R)"
        ),
        "true"
    )
    testAssert.eq(
        printed(
            "local select = function(...: any): integer return 99 end\n"
            .. "local function f(...rest: any): integer\n    return rest.n\nend\nprint(f(1, 2))"
        ),
        "2"
    )
    testAssert.eq(
        printed("local tostring = function(x: any): string return 'T' end\nlocal n = 5\nprint(`n=${n}`)"),
        "n=5"
    )
    testAssert.eq(
        printed(
            "local setmetatable = function(t: any, m: any): any return 'hijacked' end\n"
            .. "local record P\n    x: integer\nend\nlocal p = new P(x = 1)\nprint(p.x)"
        ),
        "1"
    )
end

-- `math.floor` refuses cdata and cdata `/` truncates toward zero, so `//` on 64-bit
-- integers is lowered on its own: the quotient rounds toward negative infinity, as it
-- does for numbers.
function M.floorDivisionOnSixtyFourBitIntegersRoundsDown()
    testAssert.eq(
        printed("local a = 7LL\nlocal b = -7LL\nprint(a // 2LL, b // 2LL, a // -2LL, b // -2LL, 6LL // -3LL)"),
        "3LL\t-4LL\t-4LL\t3LL\t-2LL"
    )
    testAssert.eq(printed("local c = -7LL\nc = c // 2LL\nprint(c, 7ULL // 2ULL)"), "-4LL\t3ULL")
end

-- LuaJIT 2.1 takes `;` after a statement and refuses it anywhere else: at the start of
-- a block, or after another `;`. Nupp accepts an empty statement wherever Lua 5.2
-- does, so generation writes a `;` only where it separates two statements.
function M.emptyStatementsGenerateCodeThatLoads()
    testAssert.eq(printed(";;print(1);;\nlocal x = 2;\nprint(x);"), "1\n2")
    testAssert.eq(printed("do ; end\nprint(3)"), "3")
    testAssert.eq(printed("local function f() ; return 4 end\nif true then ; print(f()) ; else ; end"), "4")
    testAssert.eq(printed("repeat ; until true\nwhile false do ; end\nfor i = 1, 1 do ; ; print(i) end"), "1")
    -- The stdlib reviewer's one-line body, each statement separated by `;`.
    testAssert.eq(
        printed(
            "local function read(n: string): string local f = assert(io.open(n, 'rb')); "
            .. "local s = f:read('*a'); f:close(); return s end\nprint(#read('"
            .. HERE
            .. "/compiler/lua/gentest.lua') > 0)"
        ),
        "true"
    )
    -- A `;` that keeps a parenthesized statement from reading as a call survives.
    testAssert.eq(printed("local t = {}\nlocal f = print; (f)('call')"), "call")
end

-- An affine local that ends a `repeat` body leaves the protected region with no
-- statement of its own before the hoisted `until` test.
function M.anAffineLocalCanEndARepeatBody()
    testAssert.eq(
        printed(
            table.concat(
                {
                    "local record Guard",
                    "    name: string",
                    "end",
                    "local function finish(takes guard: Guard): nil",
                    "    print('drop ' .. guard.name)",
                    "end",
                    "local function acquire(name: string): affine(Guard, finish)",
                    "    return new Guard(name = name)",
                    "end",
                    "local i = 0",
                    "repeat",
                    "    i = i + 1",
                    "    local g = acquire('rp' .. i)",
                    "until i >= 2",
                },
                "\n"
            ),
            "printed.nupp"
        ),
        "drop rp1\ndrop rp2"
    )
end

-- Generated Lua that does not load is the compiler's fault, and the report says so
-- at a real position: the start of the line LuaJIT named. Its help names no command,
-- because every command that prints generated code stops at the same failure.
function M.unloadableOutputIsReportedAtItsLine()
    local src = "local a = 1\nlocal b = 'x'\nreturn a, b"
    local result = parser.parse(src, "broken.nupp")
    -- A string the lexer would never let through, so only the load check sees it.
    for _, token in ipairs(result.tokens) do
        if token.text == "'x'" then
            token.text = "'\\q'"
        end
    end
    local _, diags = gen.generate(result, "broken.nupp")
    testAssert.eq(#diags, 1, "one diagnostic")
    testAssert.eq(diags[1].code, "NUPP3005")
    testAssert.eq(diags[1].line, 2, "the line LuaJIT named")
    testAssert.eq(diags[1].col, 1)
    testAssert.eq(diags[1].offset, #"local a = 1\n" + 1, "the offset of that line's first byte")
    testAssert.eq(diags[1].help:find("nupp bc", 1, true), nil, "no command that fails the same way")
end

-- More than 200 locals in one function is a limit of Lua's, reached by the program
-- rather than by the compiler, so it is reported as that limit and not as a bug.
function M.tooManyLocalsIsReportedAsTheLimit()
    -- Locals the module wrote: declarations would be moved into a table instead.
    local lines = {}
    for index = 1, 201 do
        lines[index] = ("local v%d = %d"):format(index, index)
    end
    local src = "module wide\n" .. table.concat(lines, "\n")
    local result = parser.parse(src, "wide.nupp")
    check.check(result, "wide.nupp", env)
    local _, diags = gen.generate(result, "wide.nupp")
    testAssert.eq(#diags, 1, "one diagnostic")
    testAssert.eq(diags[1].code, "NUPP3005")
    assert(diags[1].msg:find("more than 200 local names", 1, true), diags[1].msg)
    testAssert.eq(diags[1].help:find("bug in the compiler", 1, true), nil, "not called a compiler bug")
end

-- The same holds for a switch type case, and for the declarations a `cdef` and a
-- struct lower to, which run in the program's scope too.
function M.typeCasesAndCdefsReachRuntimeGlobalsPastAShadowingLocal()
    testAssert.eq(
        printed(
            table.concat(
                {
                    "local getmetatable = function(x: any): any return nil end",
                    "local record R",
                    "    x: integer",
                    "end",
                    "local function kind(v: R | integer): string",
                    "    return switch v do",
                    "        case is R -> 'record'",
                    "        else -> 'other'",
                    "    end",
                    "end",
                    "print(kind(new R(x = 1)), kind(1))",
                },
                "\n"
            )
        ),
        "record\tother"
    )
    testAssert.eq(
        printed(
            table.concat(
                {
                    "local pcall = function(...: any): any error('shadowed') end",
                    "cdef function strlen(s: cstring): uint64",
                    "print(tonumber(strlen('abc')))",
                },
                "\n"
            )
        ),
        "3"
    )
end

-- Explicit type arguments erase with the rest of the type layer: the angle brackets
-- and the commas between the types are type material, not code.
function M.explicitTypeArgumentsErase()
    testAssert.eq(
        printed(
            "local function id<T>(x: T): T return x end\n"
            .. "local function pair<A, B>(a: A, b: B): (A, B) return a, b end\n"
            .. "print(id<number>(5), pair<string, integer>('a', 1))",
            "printed.nupp"
        ),
        "5\ta\t1"
    )
    testAssert.eq(
        printed(
            "local ffi = require('ffi')\nlocal span = binary.span\nlocal s = ffi.new('uint8_t[?]', 4) as any\n"
            .. "local v = span.fromcarray<uint8>(s, 4)\nprint(#v)"
        ),
        "4"
    )
    testAssert.eq(
        printed(
            "local record Box\n    v: integer\nend\n"
            .. "function Box:get<T>(fallback: T): integer | T return self.v end\n"
            .. "local b = new Box(v = 3)\nprint(b:get<string>('none'))",
            "printed.nupp"
        ),
        "3"
    )
end

-- A `cdef struct` with no fields is an opaque C type -- `import-c` writes a handle
-- such as `sqlite3` or `FILE` this way -- and is declared as one, so LuaJIT itself
-- refuses to allocate the incomplete struct while pointers to it still work.
function M.aFieldlessCdefStructIsOpaque()
    testAssert.eq(
        printed(
            table.concat(
                {
                    "local ffi = require('ffi')",
                    "cdef struct NuppGenOpaqueHandle end",
                    "local name: string = 'struct NuppGenOpaqueHandle'",
                    "local ok = pcall(ffi.new, name)",
                    "local pointer = ffi.typeof(name .. ' *')",
                    "print(ok, pointer ~= nil)",
                },
                "\n"
            )
        ),
        "false\ttrue"
    )
end

-- Checks and generates a declared module, runs it, and answers its exports with the
-- generated text. The module's name is whatever its `module` line says.
local function moduleExports(src, name)
    local filename = name .. ".nupp"
    local result = parser.parse(src, filename)
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local diagnostics = check.check(result, filename, env, {moduleName = name})
    for _, d in ipairs(diagnostics) do
        assert(d.severity ~= "error", "check error: " .. tostring(d.code) .. " " .. tostring(d.msg))
    end
    local code, generated = gen.generate(result, name)
    testAssert.eq(#generated, 0, generated[1] and (generated[1].code .. " " .. generated[1].msg) or "gen diagnostics")
    local chunk = assert(loadstring(code, "@" .. filename))
    package.loaded[name] = nil
    local exports = chunk()
    package.loaded[name] = nil

    return exports, code
end

-- A module body is one Lua function, which holds at most 200 locals. One whose
-- declarations do not fit is generated with them moved into a table its body runs
-- against, so every reference keeps its spelling; one that fits is generated exactly
-- as before (D-36, X-04).
function M.aModuleOverTheLocalLimitSpillsItsDeclarations()
    local function exporting(name, count)
        local lines = {"module " .. name, "", "local base: integer = 100", "local seen: integer = 0", ""}
        lines[#lines + 1] = "export record Counter"
        lines[#lines + 1] = "    n: integer"
        lines[#lines + 1] = "    function bump(self): integer self.n = self.n + 1 return self.n end"
        lines[#lines + 1] = "end"
        for index = 0, count - 1 do
            lines[#lines + 1] = ("export function f%d(): integer"):format(index)
            -- The first reads forward to the last, which is declared after it.
            lines[#lines + 1] = index == 0 and ("    return f%d() + base"):format(count - 1)
                or ("    return %d"):format(index)
            lines[#lines + 1] = "end"
        end
        lines[#lines + 1] = "export function counted(): integer"
        lines[#lines + 1] = "    seen = seen + 1"
        lines[#lines + 1] = "    local counter = new Counter(n = seen)"
        lines[#lines + 1] = "    return counter:bump()"
        lines[#lines + 1] = "end"
        lines[#lines + 1] = ""

        return table.concat(lines, "\n")
    end

    local exports, code = moduleExports(exporting("genspillwide", 201), "genspillwide")
    testAssert.eq(exports.f200(), 200, "a spilled export answers")
    testAssert.eq(exports.f0(), 300, "a forward reference reaches a declaration made after it")
    testAssert.eq(exports.counted(), 2, "a spilled record builds instances and a user local stays shared")
    testAssert.eq(exports.counted(), 3, "the user local keeps its state between calls")
    testAssert.eq(rawget(_G, "f200"), nil, "a spilled declaration does not leak into the global table")
    assert(code:find("__nuppScope", 1, true), "the wide module runs against a table")

    local _, narrow = moduleExports(exporting("genspillnarrow", 150), "genspillnarrow")
    testAssert.eq(narrow:find("__nuppScope", 1, true), nil, "a module that fits keeps every declaration a local")
    assert(narrow:find("local f149;", 1, true), "and declares its exports the way it always did")
end

-- What `nupp import-c` writes for a large header: hundreds of cdef declarations and an
-- `export =` table naming them. Every one is a declaration, so the module spills.
function M.aLargeImportCModuleBuildsAndRuns()
    local lines = {"module genspillcdefs", ""}
    local names = {}
    for index = 0, 289 do
        lines[#lines + 1] = ("cdef struct NuppGenSpill%d"):format(index)
        lines[#lines + 1] = "   a: int32"
        lines[#lines + 1] = "end"
        names[#names + 1] = ("NuppGenSpill%d = NuppGenSpill%d"):format(index, index)
    end
    local functions = {
        "abs(x: int32): int32",
        "labs(x: int64): int64",
        "atoi(s: cstring): int32",
        "strlen(s: cstring): uint64",
        "strcmp(a: cstring, b: cstring): int32",
        "strncmp(a: cstring, b: cstring, n: uint64): int32",
        "toupper(c: int32): int32",
        "tolower(c: int32): int32",
        "isdigit(c: int32): int32",
        "isalpha(c: int32): int32",
    }
    for _, signature in ipairs(functions) do
        lines[#lines + 1] = "cdef function " .. signature
        local name = signature:match("^(%w+)")
        names[#names + 1] = name .. " = " .. name
    end
    lines[#lines + 1] = "export = { " .. table.concat(names, ", ") .. " }"
    lines[#lines + 1] = ""
    local exports, code = moduleExports(table.concat(lines, "\n"), "genspillcdefs")
    assert(code:find("__nuppScope", 1, true), "three hundred cdef declarations spill")
    testAssert.eq(exports.abs(-3), 3, "a spilled cdef function calls through")
    testAssert.eq(tonumber(exports.strlen("four")), 4, "and so does another")
    testAssert.eq(exports.NuppGenSpill289(7).a, 7, "a spilled cdef struct constructs")
end

-- The `local`s a module writes stay locals, so past the limit nothing can spill them:
-- `check` says so, under the code `build` would report.
function M.tooManyUserLocalsAreReportedByCheck()
    local lines = {"module genspilllocals", ""}
    for index = 0, 200 do
        lines[#lines + 1] = ("local v%d: integer = %d"):format(index, index)
    end
    lines[#lines + 1] = "export function sum(): integer return v0 + v200 end"
    local result = parser.parse(table.concat(lines, "\n"), "genspilllocals.nupp")
    local codes = {}
    for _, d in ipairs(check.check(result, "genspilllocals.nupp", env, {moduleName = "genspilllocals"})) do
        codes[#codes + 1] = d.code .. ":" .. d.line
    end
    testAssert.eq(table.concat(codes, " "), "NUPP3005:203", "the 201st local is where the module stops fitting")
end

function M.builtinBindingsImportOnlyTheBuildTargetsImplementation()
    local expected = {
        files = {"nupp.runtime.provider.nativefiles", "nupp.runtime.browser.files"},
        http = {"nupp.runtime.provider.nativehttp", "nupp.runtime.browser.http"},
        gpu = {"nupp.runtime.provider.nativegpu", "nupp.runtime.browser.webgpu.internal"},
        host = {"nupp.runtime.provider.nativehost", "nupp.runtime.browser.host"},
        suspension = {"nupp.runtime.provider.suspension", "nupp.runtime.browser.suspension"},
        system = {"nupp.runtime.provider.nativesystem", "nupp.runtime.browser.system"},
        entropy = {"nupp.runtime.provider.nativecrypto", "nupp.runtime.browser.crypto"},
        ["nupp.io.path.provider"] = {"nupp.runtime.provider.nativepath", "nupp.runtime.browser.path"},
        ["nupp.io.uri.provider"] = {"nupp.runtime.provider.nativeuri", "nupp.runtime.browser.uri"},
        ["nupp.runtime.uuidprovider"] = {"nupp.runtime.provider.nativeuuid", "nupp.runtime.browser.crypto"},
    }
    for name, implementations in pairs(expected) do
        for index, host in ipairs({"native", "browser"}) do
            local module = name:find(".", 1, true) and name or "nupp.runtime.bindings." .. name
            local code, diagnostics = gen.generate({moduleName = module, host = host})
            testAssert.eq(#diagnostics, 0)
            local imported = gen.runtimeModules(code)
            testAssert.eq(#imported, 1)
            testAssert.eq(imported[1], implementations[index])
            local marker, loads = {}, 0
            local chunk = assert(loadstring(code))
            setfenv(chunk, {
                require = function(module)
                    testAssert.eq(module, implementations[index])
                    loads = loads + 1
                    return marker
                end
            })
            testAssert.eq(chunk(), marker, "the selected implementation keeps its identity")
            testAssert.eq(loads, 1)
            assert(not code:find("target.host", 1, true), "there is no runtime host selection")
        end
    end
end

function M.optionalBuiltinBindingsDoNotForceHostFacilitiesIntoArtifacts()
    for _, name in ipairs({"clock", "workers"}) do
        for _, host in ipairs({"native", "browser"}) do
            local code = gen.generate({moduleName = "nupp.runtime.bindings." .. name, host = host})
            local imported = gen.runtimeModules(code)
            testAssert.eq(#imported, 1)
            testAssert.eq(imported[1], "nupp.runtime.optional")
            local marker, loads = {}, 0
            local environment = {
                package = {loaded = {}, preload = {}},
                rawget = rawget,
                _G = host == "browser" and {__nuppBrowser = {}} or {},
                require = function(module)
                    testAssert.eq(module, "nupp.runtime.optional")
                    return {
                        load = function(implementation)
                            loads = loads + 1
                            local expected = host == "browser" and "nupp.runtime.browser." or "nupp.runtime.provider."
                            expected = expected .. (
                                name == "clock" and (host == "browser" and "time" or "nativetime") or "workers"
                            )
                            testAssert.eq(implementation, expected)

                            return marker
                        end
                    }
                end,
            }
            if name == "workers" and host == "native" then
                local absent = setfenv(assert(loadstring(code)), environment)()
                testAssert.eq(absent.provider, nil)
                testAssert.eq(loads, 0, "no worker implementation loads without a host bridge")
                environment.package.preload["nupp.workers.native"] = function()
                end
            end
            testAssert.eq(setfenv(assert(loadstring(code)), environment)().provider, marker)
            testAssert.eq(loads, 1)
        end
    end
end

return M
