local test = require("assert")
local identities = require("nupp.compiler.apiidentity")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")
local providers = require("nupp.compiler.comptime.materialize.providers")
local T = require("nupp.compiler.types")

local HERE = require("helpers.paths").tests
local M = {}

local function finalEnv(root)
    return envMod.new(root or HERE .. "/..", {config = {include = {"src"}}})
end

local function compile(source, env, filename)
    filename = filename or "api-identity.nupp"
    local parsed = parser.parse(source, filename)
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, filename, env or finalEnv())
    local errors = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            errors[#errors + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
    end

    return source, table.concat(errors, "\n"), parsed
end

local function run(source)
    local code, errors, parsed = compile(source)
    test.eq(errors, "", errors .. "\n" .. code)
    return program.run(parsed, "api-identity", "api-identity.nupp")
end

function M.canonicalizesOnlyRegisteredPublicIdentities()
    for _, old in ipairs({
        "nupp.types.array",
        "nupp.reflect.Info",
        "nupp.derive.array",
        "nupp.derive.Debug",
        "nupp.Debug",
        "nupp.util.newStore",
        "nupp.Copyable",
        "nupp.recoverAlias"
    }) do
        test.eq(identities.canonical(old), old)
    end
    test.eq(identities.canonical("nupp.__Debug"), "types.Debug")
    test.eq(identities.canonical("nupp.compiler.types"), "nupp.compiler.types")
    test.eq(identities.canonical("nupp.gpu.types.Buffer"), "nupp.gpu.types.Buffer")
    test.eq(identities.legacy("io.gpu.internal.Image"), "io.gpu.internal.Image")
    test.eq(identities.canonical("types.array"), "types.array")
    test.eq(identities.canonical("types.derive.array"), "types.derive.array")
end

function M.preservesOneNominalAndOneEvaluatorLibrary()
    local env = finalEnv()
    test.eq(identities.lookup(env.globalTypes, "types.reflect"), env.globalTypes["types.reflect"])
    test.eq(identities.lookup(env.globalTypes, "types.derive"), env.globalTypes["types.derive"])
    test.eq(identities.lookup(env.globalTypes, "nupp.__Debug"), env.globalTypes["types.Debug"])
    local values = {}
    providers.installEvaluator({}, values)
    test.eq(values.nupp.types, nil)
    test.eq(values.nupp.reflect, nil)
    test.eq(values.nupp.derive, nil)
    assert(values.types.array ~= values.types.derive.array)
    assert(values.types.error ~= values.types.derive.error)
end

function M.preservesFinalContractsAndThePrivateDebugAlias()
    local env = envMod.new(HERE .. "/..", {config = {include = {"src"}}})
    test.eq(env.globalTypes["nupp.Closeable"], nil)
    test.eq(env.globalTypes["nupp.Debug"], nil)
    local _, errors = compile(
        [[
local function render(value: types.Debug): string
    return value:debug()
end
local function contract(value: nupp.__Debug): types.Debug
    return value
end
local function inspect(info: types.reflect.Info): string
    return info.kind
end
@comptime
local function recipe(info: types.derive.Info): types.derive.Result<types.Debug>
    return nil as any
end
local record Resource is own.Closeable
    function close(takes self): nil end
end
local value = Resource()
value:close()
return 17
]],
        env
    )
    test.eq(errors, "", errors)
end

function M.executesBothTypeBuilderSurfacesAndAliases()
    for _, root in ipairs({"types"}) do
        test.eq(
            run(
                (
                    [[
@comptime local function Items(Element: type): type
    local builders = ROOT
    local array = builders.array
    return array(Element)
end
local type Names = Items(string)
local values: Names = {"one", "two"}
return #values
]]
                ):gsub("ROOT", root)
            ),
            2
        )
    end
end

function M.reflectsThroughBothCallableSurfacesAndLocalAliases()
    for _, root in ipairs({"types.reflect"}) do
        test.eq(
            run(
                (
                    [[
local record Point x: integer end
local count = comptime do
    local reflect = ROOT
    return #reflect(Point).fields
end
return count
]]
                ):gsub("ROOT", root)
            ),
            1
        )
    end
end

function M.keepsOwnershipAliasesIntrinsicAndLocalShadowsOrdinary()
    local _, errors, parsed = compile(
        [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local manage = own.manage
local value = Resource()
local cell = manage(value)
cell:close()
]]
    )
    test.eq(errors, "", errors)
    local block = parsed.root.blocks[1]
    local cell = block.stats[4]
    test.eq(cell.exprs[1].ownershipIntrinsic, "manage")
    local code, shadowErrors, shadowParsed = compile(
        [[
local own = {manage = function(value: integer): integer return value + 1 end}
local types = {reflect = function(value: integer): integer return value + 2 end}
return own.manage(types.reflect(types.reflect(1)) + 1)
]]
    )
    test.eq(shadowErrors, "", shadowErrors)
    test.eq(program.run(shadowParsed, "identity-shadow"), 7)
end

local function runtimeEnv()
    local env = finalEnv()
    local values = {
        entry = T.func({T.any}, {
            T.any
        }),
        initializer = T.func({T.any}, {
            T.any
        }),
        debug = T.func({T.any, T.any}, {T.string}),
    }
    local fields = {}
    for name, value in pairs(values) do
        fields[#fields + 1] = {name = name, read = value}
    end
    env.loaded["nupp.derive"] = {type = T.shape(fields), exports = {types = {}, values = values}}

    return env
end

function M.keepsImportedDeriveRuntimeHelpersOrdinary()
    local _, errors = compile(
        [[
local runtime = require("nupp.derive")
local record Value end
local entry = runtime.entry(Value)
local initializer = runtime.initializer(Value)
local render = runtime.debug
return 17
]],
        runtimeEnv(),
        HERE .. "/../src/nupp/compiler/apiidentityfixture.nupp"
    )
    test.eq(errors, "", errors)
    for _, root in ipairs({"types.derive"}) do
        local source = ([[
return ROOT.entry()
]]):gsub("ROOT", root)
        local _, recipeErrors = compile(source)
        assert(recipeErrors:find("NUPP2809", 1, true), recipeErrors)
    end
end

function M.preservesLazyExplicitModuleRequires()
    local code, errors, parsed = compile(
        [[
local function later(): any
    local runtime = require("nupp.derive")
    return runtime
end
return 17
]],
        runtimeEnv(),
        HERE .. "/../src/nupp/compiler/apiidentityfixture.nupp"
    )
    test.eq(errors, "", errors)
    local original = _G.require
    local calls = 0
    _G.require = function(name)
        if name == "nupp.derive" then
            calls = calls + 1
        end
        return original(name)
    end
    local ok, result = pcall(program.run, parsed, "lazy-module")
    _G.require = original
    assert(ok, result)
    test.eq(result, 17)
    test.eq(calls, 0)
end

function M.preservesCanonicalAssertionAliasesAndShadowing()
    test.eq(
        run(
            [[
local check = assert
local function length(value: string?): integer
    check(value)
    return #value
end
return length("abc")
]]
        ),
        3
    )
    test.eq(
        run(
            [[
local assert = function(value: string?): string? return value end
local value: string? = nil
return assert(value) == nil
]]
        ),
        true
    )
end

local function withProject(source, callback)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local moduleName = assert(source:match("module ([%w_.]+)"))
    local path = dir .. "/src/" .. moduleName:gsub("%.", "/") .. ".nupp"
    assert(os.execute("mkdir -p '" .. path:match("^(.*)/[^/]+$") .. "'") == 0)
    local file = assert(io.open(path, "wb"))
    file:write(source)
    file:close()
    local ok, failure = pcall(callback, finalEnv(dir))
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(failure, 0)
    end
end

function M.mixesImportedRuntimeExportsAndCompilerMembers()
    withProject(
        [[
module types
export const answer: integer = 17
export type Debug = nupp.__Debug
@comptime
export function debug(info: types.derive.Info): types.derive.Result<types.Debug>
    return types.derive.implement{
        methods = {
            debug = types.derive.forward{
                helper = types.derive.helper(types, "render"),
                arguments = {types.derive.receiver()},
            },
        },
    }
end
export function render(value: any): string return "ready" end
]],
        function(env)
            local _, errors = compile(
                [[
local api = require("types")
local Debug = api.debug
@derive(Debug)
local record Point label: string end
local value: types.Debug = Point(label = "one")
local type Bounded = api.range(integer, 0, 20)
local answer: Bounded = 17
return value:debug(), answer, api.answer
]],
                env
            )
            test.eq(errors, "", errors)
        end
    )
end

function M.mixesImportedOwnershipIntrinsicsAndRuntimeMembers()
    withProject([[
module own
export type Closeable = own.Closeable
export const answer: integer = 23
]], function(env)
        local _, errors, parsed = compile(
            [[
local api = require("own")
local move = api.manage
local record Resource is api.Closeable
    function close(takes self): nil end
end
local value = Resource()
local cell = move(value)
cell:close()
return api.answer
]],
            env
        )
        test.eq(errors, "", errors)
        local stats = parsed.root.blocks[1].stats
        test.eq(stats[5].exprs[1].ownershipIntrinsic, "manage")
    end)
end

function M.parsesCanonicalAdoptTypeArgumentsAndPreservesShadows()
    local _, errors, parsed = compile(
        [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local raw: any = {}
local value = @unsafe own.adopt<Resource>(raw)
value:close()
]]
    )
    test.eq(errors, "", errors)
    local stats = parsed.root.blocks[1].stats
    test.eq(stats[3].exprs[1].ownershipIntrinsic, "adopt")
    local shadowCode, shadowErrors, shadow = compile(
        [[
local own = {adopt = function<T>(value: any): T return value as T end}
local value: string = own.adopt<string>("ready")
return value
]]
    )
    test.eq(shadowErrors, "", shadowErrors)
    test.eq(shadow.root.blocks[1].stats[2].exprs[1].ownershipIntrinsic, nil)
    test.eq(#shadow.root.blocks[1].stats[2].exprs[1].typeArgs, 1)
    test.eq(program.run(shadow, "adopt-shadow"), "ready")
end

function M.sealsImportedCompilerNamespacesThroughPersistedHelpers()
    withProject(
        [[
module types
const builders = require("types")
@comptime local function list(Element: type): type
    return builders.array(Element)
end
@comptime
export function Items(Element: type): type
    local builders = 7
    assert(builders == 7)
    return list(Element)
end
export const answer: integer = 17
]],
        function(env)
            local _, errors = compile(
                [[
local api = require("types")
local type Names = api.Items(string)
local names: Names = {"one", "two"}
return #names
]],
                env
            )
            test.eq(errors, "", errors)
            local exports = env.resolveModuleExports(env, "types")
            local program = exports.comptimeFunctions.Items
            assert(program.serializedHelpers.list.source:find("types.array", 1, true))
            assert(not program.serializedHelpers.list.source:find("builders.array", 1, true))
            assert(program.serializedHelpers.Items.source:find("local builders = 7", 1, true))
            local images = require("nupp.compiler.project.interfaceimage")
            local path = env.rootDir .. "/src/types.nupp"
            local encoded, encodeProblem = images.encode(
                {types = {path = path, interface = {type = env.resolveModule(env, "types")}, exports = exports,}},
                {projectPaths = {path}}
            )
            assert(encoded, encodeProblem)
            local loaded, loadProblem = images.decode(encoded)
            assert(loaded, loadProblem)
            local persisted = loaded.types.exports.comptimeFunctions.Items
            test.eq(persisted.identity, program.identity)
            local envelope, failure = require(
                "nupp.compiler.comptime"
            ).evaluateTypeFunctionDirect(persisted, {{kind = "type", value = T.string}}, {})
            assert(envelope, failure and failure.message)
            test.eq(envelope.payload.nodes[envelope.payload.root].kind, "array")
        end
    )
end

function M.identifiesClosedHelpersIndependentlyOfImportedAliasNames()
    local identity
    for _, alias in ipairs({"builders", "constructors"}) do
        withProject(
            (
                [[
module types
const ALIAS = require("types")
@comptime
export function Items(Element: type): type
    return ALIAS.array(Element)
end
]]
            ):gsub("ALIAS", alias),
            function(env)
                env.resolveModule(env, "types")
                local program = env.resolveModuleExports(env, "types").comptimeFunctions.Items
                assert(program.serializedHelpers.Items.source:find("types.array", 1, true))
                if identity then
                    test.eq(program.identity, identity)
                end
                identity = program.identity
            end
        )
    end
end

function M.keepsImportedRuntimeNamespacesOutOfCompilerClosures()
    local parsed = parser.parse(
        [[
local function Entry(Value: type): any
    return runtime.entry(Value)
end
]],
        "helper.nupp"
    )
    test.eq(#parsed.errors, 0)
    local helper = parsed.root.blocks[1].stats[1]

    local function bind(value)
        if value.kind == "name" and value.token and value.token.text == "runtime" then
            value.token.definition = {
                filename = "outer.nupp",
                token = {offset = 0},
                exactCallExport = {module = "nupp.derive", identity = "nupp.derive"},
            }
        end
        for _, child in ipairs(value) do
            if type(child) == "table" then
                bind(child)
            end
        end
    end

    bind(helper)
    local comptime = require("nupp.compiler.comptime")
    local program = comptime.sealTypeFunction(helper, {}, nil, {filename = "helper.nupp"})
    assert(program.serializedHelpers.Entry.source:find("runtime.entry", 1, true))
    assert(not program.serializedHelpers.Entry.source:find("types.derive.entry", 1, true))
    test.eq(program.identity, comptime.typeFunctionProgram(helper, {}).identity)
end

function M.closesTopLevelCompilerImportsForDirectLocalTypeCalls()
    withProject("module types\nexport const answer: integer = 17", function(env)
        local _, errors = compile(
            [[
local builders = require("types")
@comptime local function List(Element: type): type
    return builders.array(Element)
end
@comptime local function Checked(Element: type): type
    local builders = 7
    assert(builders == 7)
    return List(Element)
end
local type Names = Checked(string)
local names: Names = {"first", "second"}
return #names
]],
            env
        )
        test.eq(errors, "", errors)
    end)
end

function M.closesImportedNamespacesForHelpersCalledFromComptimeBlocks()
    withProject("module types\nexport const answer: integer = 17", function(env)
        local _, errors, parsed = compile(
            [[
local builders = require("types")
@comptime local function List(Element: type): type
    return builders.array(Element)
end
return comptime do return types.kind(List(types.string)) end
]],
            env
        )
        test.eq(errors, "", errors)
        local evaluated = parsed.root.blocks[1].stats[3].exprs[1]
        test.eq(assert(loadstring("return " .. evaluated.comptimeValue))(), "array")
    end)
end

function M.closesAmbientCompilerImportsBeforeModuleResolutionIsInstalled()
    local env = finalEnv()
    env.resolveModule = nil
    local _, errors = compile(
        [[
const types2 = require("types")
@comptime local function List(Element: type): type
    return types2.array(Element)
end
local type Names = List(string)
local names: Names = {"first", "second"}
return #names
]],
        env
    )
    test.eq(errors, "", errors)
end

function M.workerRequestsCarryTheSameClosedLocalHelperSource()
    withProject("module types\nexport const answer: integer = 17", function(env)
        local _, errors, parsed = compile(
            [[
local builders = require("types")
@comptime local function List(Element: type): type
    return builders.array(Element)
end
local type Names = List(string)
local names: Names = {"first"}
return names
]],
            env
        )
        test.eq(errors, "", errors)
        local helper

        local function find(node)
            if node.kind == "localFuncStmt" and node.name.text == "List" then
                helper = node
            end
            for _, child in ipairs(node) do
                if type(child) == "table" then
                    find(child)
                end
            end
        end

        find(parsed.root)
        assert(helper)
        local process = require("nupp.compiler.process")
        local worker = require("nupp.compiler.comptime.worker")
        local json = require("testjson")
        local original = process.captureIsolated
        process.captureIsolated = function(argv)
            local file = assert(io.open(argv[3], "rb"))
            local request = json.decode(file:read("*a"))
            file:close()
            assert(request.helpers.List.source:find("types.array", 1, true))
            assert(not request.helpers.List.source:find("builders.array", 1, true))
            local pieces, write = {}, io.write
            io.write = function(...)
                for _, text in ipairs({...}) do
                    pieces[#pieces + 1] = text
                end
            end
            local ok, status = pcall(worker.main, {argv[3]})
            io.write = write
            assert(ok, status)

            return status, table.concat(pieces)
        end
        local ok, quoted, failure = pcall(
            worker.evaluate,
            "comptime do return types.kind(List(types.string)) end",
            "fixture-worker",
            {},
            {},
            {List = helper}
        )
        process.captureIsolated = original
        assert(ok, quoted)
        test.eq(failure, nil, failure and failure.message)
        test.eq(assert(loadstring("return " .. quoted))(), "array")
    end)
end

function M.formattedLuaDeclarationHelpersCloseImportedNamespaces()
    local bundled = require("nupp.compiler.bundled")
    local cst = require("nupp.compiler.syntax.cst")
    local source = assert(bundled.source("/decls/lua.d.nupp"))
    local parsed = parser.parse(source, "lua.d.nupp")
    local wanted = {__NuppPatternClassEnd = true, __NuppPatternCaptures = true, __NuppFindResults = true}
    local pieces = {'const types2 = require("types")'}

    local function collect(node)
        if node.kind == "localFuncStmt" and node.name and wanted[node.name.text] then
            local text = cst.textOf(node):gsub("nupp%.types", "types2"):gsub("([^%w_])types%.", "%1types2.")
            pieces[#pieces + 1] = "@comptime\n" .. text
        end
        for _, child in ipairs(node) do
            if type(child) == "table" then
                collect(child)
            end
        end
    end

    collect(parsed.root)
    test.eq(#pieces, 4)
    pieces[
        #pieces + 1
    ] = [[
local function accepts(...: unpackof __NuppFindResults("(%a+)", false)): nil end
accepts(1, 3, "one")
]]
    local formatted = require("nupp.tools.fmt").new():format(table.concat(pieces, "\n"))
    withProject("module types\nexport const answer: integer = 17", function(env)
        local _, errors = compile(formatted, env)
        test.eq(errors, "", errors)
        local shadow = formatted:gsub(
            "local plain = types2.describe",
            "local types2 = 7\n    local plain = types2.describe",
            1
        )
        local _, refusal = compile(shadow, env)
        assert(refusal ~= "", "a lexical shadow must not become the imported compiler namespace")
    end)
end

function M.reusesSealedProgramsUntilTheirHelperDependenciesChange()
    local comptime = require("nupp.compiler.comptime")

    local function helper(source)
        local parsed = parser.parse(source, "cached-helper.nupp")
        test.eq(#parsed.errors, 0)
        return parsed.root.blocks[1].stats[1]
    end

    local main = helper("local function Main(Element: type): type return Dependency(Element) end")
    local dependency = helper("local function Dependency(Element: type): type return types.array(Element) end")
    local first = comptime.sealTypeFunction(main, {Dependency = dependency})
    test.eq(comptime.sealTypeFunction(main, {Dependency = dependency}), first)
    local changed = helper("local function Dependency(Element: type): type return types.optional(Element) end")
    local nextProgram = comptime.sealTypeFunction(main, {Dependency = changed})
    assert(nextProgram ~= first)
    assert(nextProgram.identity ~= first.identity)
    local original, parses = parser.parse, 0
    parser.parse = function(...)
        parses = parses + 1
        return original(...)
    end
    local ok, failure = pcall(function()
        local arguments = {{kind = "type", value = T.string}}
        local firstResult, firstFailure = comptime.evaluateTypeFunctionDirect(first, arguments, {})
        assert(firstResult, firstFailure and firstFailure.message)
        local afterFirst = parses
        assert(afterFirst > 0)
        local secondResult, secondFailure = comptime.evaluateTypeFunctionDirect(first, arguments, {})
        assert(secondResult, secondFailure and secondFailure.message)
        test.eq(parses, afterFirst, "an immutable sealed program must be parsed once")
        test.eq(secondResult.fingerprint, firstResult.fingerprint)
    end)
    parser.parse = original
    assert(ok, failure)
end

function M.qualifiedLocalRecordsOwnTheirNamespacePastAmbientRoots()
    local _, errors = compile(
        [[
local types = {}
record types.Point value: integer end
local point = types.Point(value = 7)
return point.value
]]
    )
    test.eq(errors, "", errors)
    local code, shadowErrors, shadowParsed = compile(
        [[
local types = {}
record types.Point value: integer end
local function read(): integer
    local types = {Point = function(value: integer): integer return value + 1 end}
    return types.Point(7)
end
return read()
]]
    )
    test.eq(shadowErrors, "", shadowErrors)
    test.eq(program.run(shadowParsed, "qualified-shadow"), 8)
end

function M.referencedRecipeRefusalsKeepTheirDiagnostic()
    withProject(
        [[
module types
@comptime
export function Refuse(info: types.derive.Info): types.derive.Result<any>
    return types.derive.error("fixture refusal", info.reference)
end
]],
        function(env)
            local _, errors = compile(
                [[
local api = require("types")
local Refuse = api.Refuse
@derive(Refuse)
local record Point label: string end
]],
                env
            )
            assert(errors:find("NUPP2810: fixture refusal", 1, true), errors)
        end
    )
end

function M.reflectionParsesFinalGenericTypeArguments()
    for _, root in ipairs({"types.reflect"}) do
        test.eq(
            run(
                (
                    [[
local record Box<T> value: T end
return comptime do return #ROOT(Box<string>).fields end
]]
                ):gsub("ROOT", root)
            ),
            1
        )
    end
end

function M.assertionAliasesPreserveTheWholeResultPack()
    local value, message = run([[
local check = assert
return check("okay", false)
]])
    test.eq(value, "okay")
    test.eq(message, false)
    local _, errors = compile(
        [[
local check = assert
local value, message = check("okay", false)
local kept: boolean = message
return value, kept
]]
    )
    test.eq(errors, "", errors)
end

function M.recognizesDeclaredRootsWithoutAnAmbientBinding()
    withProject([[
module types
export const answer: integer = 17
]], function(env)
        env.globals.types = nil
        local _, errors = compile(
            [[
local api = types
local type Bounded = api.range(integer, 0, 20)
local answer: Bounded = 17
return api.answer, answer
]],
            env
        )
        test.eq(errors, "", errors)
    end)
    withProject([[
module own
export const answer: integer = 17
]], function(env)
        env.globals.own = nil
        local _, errors = compile(
            [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local value = Resource()
local cell = own.manage(value)
cell:close()
]],
            env
        )
        test.eq(errors, "", errors)
    end)
end

function M.loggingKeepsLazyLoweringThroughCanonicalBindings()
    withProject([[
module debug.log
export function info(format: string, value: integer?): nil end
]], function(env)
        local missingModules = {}
        for _, source in ipairs({
            'local logger = debug.log\nlogger.info("value=%d", 1)',
            'local logger = require("debug.log")\nlocal alias = logger\nalias.info("value=%d", 1)',
            'debug.log.info("value=%d", 1)',
            'local logger = require("debug.log")\nlogger.info("value=%d", 1)',
        }) do
            local code, errors, parsed = compile(source, env)
            test.eq(errors, "", errors)
            local stats = parsed.root.blocks[1].stats
            local expectedModule = "debug.log"
            test.eq(stats[#stats].expr.logIntrinsic, 3, source)
            test.eq(stats[#stats].expr.logModule, expectedModule, source)
            if not program.names(program.image(parsed, "logging-identity"), expectedModule) then
                missingModules[#missingModules + 1] = expectedModule .. ": " .. source
            end
        end
        local _, errors, parsed = compile(
            [[
local debug = {log = {info = function(format: string, value: integer): nil end}}
debug.log.info("value=%d", 1)
]],
            env
        )
        test.eq(errors, "", errors)
        test.eq(parsed.root.blocks[1].stats[2].expr.logIntrinsic, nil)
        local _, aliasErrors, alias = compile('local info = require("debug.log").info\ninfo("value=%d", 1)', env)
        test.eq(aliasErrors, "", aliasErrors)
        test.eq(alias.root.blocks[1].stats[2].expr.logIntrinsic, nil)
        test.eq(#missingModules, 0, table.concat(missingModules, "\n"))
    end)
end

function M.resolvesConstraintIntrinsicsWithoutAProjectEnvironment()
    for _, root in ipairs({"types"}) do
        local function diagnostics(prefix, expression)
            local source = prefix .. "\nlocal type Count = " .. root .. expression
            local parsed = parser.parse(source, "constraint-fragment.nupp")
            test.eq(#parsed.errors, 0)
            return checker.check(parsed, "constraint-fragment.nupp", nil, {strict = false})
        end

        local clean = diagnostics("", ".range(integer, 0, 10)")
        test.eq(#clean, 0)
        local invalid = diagnostics("", ".range(integer, 10, 0)")
        test.eq(invalid[1].code, "NUPP2422")
        local shadow = diagnostics("local " .. root:match("^[^.]+") .. " = {}", ".range(integer, 0, 10)")
        test.eq(shadow[1].code, "NUPP2421")
    end
end

function M.lowercaseDeriveAnnotationtypeKeepsItsCheckedOperation()
    local state, values = {}, {}
    providers.installEvaluator(state, values)
    test.eq(values.types.derive.annotationType, nil)
    test.eq(type(state.intrinsics[values.types.derive.annotationtype]), "function")
    local handle, expected = {}, {}
    state.opaque[handle] = {provider = "derive", family = "View", payload = {value = {kind = "type", type = 1}}}
    state.deriveAnnotationTypes = {expected}
    local operation = state.intrinsics[values.types.derive.annotationtype]
    test.eq(operation(nil, {n = 1, handle}), expected)
    local value, refusal = operation(nil, {n = 0})
    test.eq(value, nil)
    test.eq(refusal.code, "NUPP2810")
    local _, errors = compile(
        [[
@comptime local function referred(argument: types.reflect.AnnotationArgument): any
    return types.derive.annotationtype(argument)
end
]]
    )
    test.eq(errors, "", errors)
    local result = run(
        [[
local types = {derive = {annotationtype = function(value: integer): integer return value + 1 end}}
return types.derive.annotationtype(4)
]]
    )
    test.eq(result, 5)
end

local function withComptimeFacade(callback)
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/src/nupp/internal' '" .. root .. "/src/coroutine/workers'") == 0)
    local files = {
        [
            "nupp/internal/typehelper.nupp"
        ] = [[
@!internal
module nupp.internal.typehelper
@comptime
export function Parameters(F: type): typepack return types.parameters(F) end
@comptime
export function Identity(T: type): type return T end
@comptime
export function Answer(): integer return 37 end
]],
        [
            "coroutine/workers/contracts.nupp"
        ] = [[
module coroutine.workers.contracts
const implementation = require("nupp.internal.typehelper")
export const submitted = implementation.Parameters
export const identity = implementation.Identity
export const answer = implementation.Answer
]],
        [
            "coroutine/workers/forward.nupp"
        ] = [[
module coroutine.workers.forward
const facade = require("coroutine.workers.contracts")
export const parameters = facade.submitted
]],
        [
            "ordinary.nupp"
        ] = [[
module ordinary
local implementation = {Identity = function(value: integer): integer return value + 1 end}
export const identity: function(integer): integer = implementation.Identity
]],
    }
    for path, source in pairs(files) do
        local file = assert(io.open(root .. "/src/" .. path, "wb"))
        file:write(source)
        file:close()
    end
    local env = finalEnv(root)
    local saved = {}
    for path in pairs(files) do
        local name = path:gsub("%.nupp$", ""):gsub("/", ".")
        saved[name] = {loaded = package.loaded[name], preload = package.preload[name]}
        package.loaded[name] = nil
        package.preload[name] = function()
            env.resolveModuleExports(env, name)
            local parsed = env.loadedPaths[root .. "/src/" .. path].result
            return program.run(parsed, name, root .. "/src/" .. path)
        end
    end
    local ok, failure = pcall(callback, env, root)
    for name, old in pairs(saved) do
        package.loaded[name], package.preload[name] = old.loaded, old.preload
    end
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, failure)
end

function M.exportedComptimeAliasesRetainTheExactSealedHelper()
    withComptimeFacade(function(env)
        local code, errors, consumer = compile(
            [[
local api = require("coroutine.workers.contracts")
local forwarded = require("coroutine.workers.forward")
local type Item = api.identity(integer)
local function accept(...: unpackof forwarded.parameters(function(integer, string): nil)): nil end
accept(1, "kept")
local value: Item = 11
return value
]],
            env
        )
        test.eq(errors, "", errors)
        local value = program.run(consumer, "api-identity", "api-identity.nupp")
        test.eq(value, 11)
        local origin = env.resolveModuleExports(env, "nupp.internal.typehelper")
        local facade = env.resolveModuleExports(env, "coroutine.workers.contracts")
        local forwarded = env.resolveModuleExports(env, "coroutine.workers.forward")
        test.eq(facade.comptimeFunctions.submitted, origin.comptimeFunctions.Parameters)
        test.eq(facade.comptimeFunctions.identity, origin.comptimeFunctions.Identity)
        test.eq(facade.comptimeFunctions.answer, origin.comptimeFunctions.Answer)
        test.eq(forwarded.comptimeFunctions.parameters, origin.comptimeFunctions.Parameters)
        local path = env.rootDir .. "/src/coroutine/workers/contracts.nupp"
        local parsed = env.loadedPaths[path].result
        local listing = {}
        program.image(parsed, "coroutine.workers.contracts", path, listing)
        local images = {}
        for _, entry in ipairs(listing) do
            images[#images + 1] = entry.image
        end
        local emitted = table.concat(images, "\n")
        test.eq(emitted:find('str "submitted"', 1, true), nil)
        test.eq(emitted:find('str "Parameters"', 1, true), nil)
        local images = require("nupp.compiler.project.interfaceimage")
        local encoded, problem = images.encode(
            {
                facade = {
                    path = path,
                    interface = {type = env.resolveModule(env, "coroutine.workers.contracts")},
                    exports = facade,
                }
            },
            {projectPaths = {path}}
        )
        assert(encoded, problem)
        local decoded, decodeProblem = images.decode(encoded)
        assert(decoded, decodeProblem)
        local restored = decoded.facade
        test.eq(restored.exports.comptimeFunctions.submitted.identity, origin.comptimeFunctions.Parameters.identity)
        test.eq(restored.exports.valueDefs.answer.comptimeOnly, true)
        local fresh = finalEnv(env.rootDir)
        fresh.loaded["coroutine.workers.contracts"] = {type = restored.interface.type, exports = restored.exports}
        local _, runtimeError = compile(
            'local api = require("coroutine.workers.contracts")\nreturn api.answer()',
            fresh
        )
        assert(runtimeError:find("NUPP2421", 1, true), runtimeError)
    end)
end

function M.exportedComptimeAliasesKeepRuntimeRefusalsAndOrdinaryShadows()
    withComptimeFacade(function(env)
        for _, source in ipairs({
            'local api = require("coroutine.workers.contracts")\nreturn api.submitted',
            'local api = require("coroutine.workers.contracts")\nreturn api.answer()',
        }) do
            local _, errors = compile(source, env)
            assert(errors:find("NUPP2421", 1, true), errors)
        end
        local _, localLeak = compile(
            [[
module coroutine.workers.leak
const api = require("coroutine.workers.contracts")
export const identity = api.identity
export function leak(): any return identity end
]],
            env
        )
        assert(localLeak:find("NUPP2415", 1, true), localLeak)
        local _, invalid = compile(
            [[
local api = require("coroutine.workers.contracts")
local type Bad = api.identity(integer, string)
]],
            env
        )
        assert(invalid:find("NUPP2421", 1, true), invalid)
        local code, errors, consumer = compile(
            [[
local api = require("ordinary")
local shadow = {submitted = function(value: integer): integer return value end}
return api.identity(5), shadow.submitted(7)
]],
            env
        )
        test.eq(errors, "", errors)
        local first, second = program.run(consumer, "api-identity", "api-identity.nupp")
        test.eq(first, 6)
        test.eq(second, 7)
        local ordinary = env.resolveModuleExports(env, "ordinary")
        test.eq(ordinary.comptimeFunctions.identity, nil)
    end)
end

function M.canonicalWorkKeepsTheWorkerCallSurfaceAndRetiresFork()
    local surfaces = require("nupp.compiler.check.surfaces").COMPILER_SURFACES["nupp.tasks"].Scope
    test.eq(surfaces.fork, nil, "the preceding public call surface is absent")
    test.eq(surfaces.work.effect, "runtime.workers")
    test.eq(surfaces.work.rotate, true)
    test.eq(surfaces.work.sendableLast, true)
    for _, member in ipairs({"work"}) do
        local source = (
            [[
module acceptingwork
export function submit(borrows scope: coroutine.Scope): (integer, string?, nil)
    local task = scope:%s(7, function(value: integer): (integer, string?, nil)
        return value + 1, "tail", nil
    end)
    local done: boolean = task:isdone()
    return task:await()
end
]]
        ):format(member)
        local _, errors, parsed = compile(source, nil, "acceptingwork.nupp")
        test.eq(errors, "", errors)
        local found = {}

        local function visit(node)
            if type(node) ~= "table" or not node.kind then
                return
            end
            if node.trailingCallableCall then
                found[#found + 1] = node
            end
            for _, child in ipairs(node) do
                visit(child)
            end
        end

        visit(parsed.root)
        test.eq(#found, 1)
        test.eq(found[1].trailingCallableMember, member)
        test.eq(found[1].compilerFeatureEffect, "runtime.workers")
        local _, escaping = compile(
            (
                [[
module acceptingescape
export function escape(borrows scope: coroutine.Scope): coroutine.Task<function(): integer>
    return scope:%s(function(): integer return 1 end)
end
]]
            ):format(member)
        )
        assert(escaping:find("NUPP2608", 1, true), escaping)
        local _, capture = compile(
            (
                [[
module acceptingcapture
export function refuse(borrows scope: coroutine.Scope, value: thread): nil
    scope:%s(function(): thread return value end)
end
]]
            ):format(member)
        )
        assert(capture ~= "" and capture:find("thread", 1, true), capture)
    end
    local _, retired = compile(
        [[
local function stale(borrows scope: coroutine.Scope): nil
    scope:fork(function(): integer return 1 end)
end
return stale
]]
    )
    assert(retired:find("NUPP2004", 1, true), retired)
    local ordinary = run(
        [[
local function ordinary(scope: {work: function(any, integer, string): integer}): integer
    return scope:work(7, "last")
end
return ordinary
]]
    )
    test.eq(
        ordinary({
            work = function(_, value, last)
                assert(last == "last")
                return value
            end
        }),
        7,
        "an unrelated work method keeps its ordinary argument order"
    )
end

return M
