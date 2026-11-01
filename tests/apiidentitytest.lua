local test = require("nupp.test")
local identities = require("nupp.compiler.apiidentity")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local generator = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")
local providers = require("nupp.compiler.comptime.materialize.providers")
local T = require("nupp.compiler.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local M = {}

-- Model the next prelude without moving a declaration in the accepting seed.
local function finalEnv(root)
    local env = envMod.new(root or HERE .. "/..", root and {config = {include = {"src"}}} or nil)
    local globals = {}
    for name, entry in pairs(env.globals) do
        globals[name] = entry
    end
    env.globals = globals
    local old = env.globals.nupp.t
    local types = old.byname.types
    local members = {}
    for name, value in pairs(types.byname) do
        members[#members + 1] = {name = name, read = value}
    end
    members[#members + 1] = {name = "reflect", read = old.byname.reflect}
    members[#members + 1] = {name = "derive", read = old.byname.derive}
    env.globals.types = {t = T.shape(members), definition = {name = "types", kind = "variable"}}
    env.globals.own = {t = old, definition = {name = "own", kind = "variable"}}
    local globalTypes = {}
    for name, value in pairs(env.globalTypes) do
        globalTypes[name] = value
    end
    env.globalTypes = globalTypes
    for name, value in pairs(globalTypes) do
        local final = identities.canonical(name)
        if final ~= name then
            env.globalTypes[final] = value
        end
    end

    return env
end

local function compile(source, env)
    local parsed = parser.parse(source, "api-identity.nupp")
    test.equal(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, "api-identity.nupp", env or finalEnv())
    local errors = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            errors[#errors + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
    end
    local code = generator.generate(parsed, "api-identity")

    return code, table.concat(errors, "\n"), parsed
end

local function run(source)
    local code, errors = compile(source)
    test.equal(errors, "", errors .. "\n" .. code)
    return assert(loadstring(code, "@api-identity"))()
end

function M.canonicalizesOnlyRegisteredPublicIdentities()
    for old, final in pairs({
        ["nupp.types.array"] = "types.array",
        ["nupp.reflect.Info"] = "types.reflect.Info",
        ["nupp.derive.array"] = "types.derive.array",
        ["nupp.derive.Debug"] = "types.Debug",
        ["nupp.Debug"] = "types.Debug",
        ["nupp.__Debug"] = "types.Debug",
        ["nupp.util.newStore"] = "types.newStore",
        ["nupp.Copyable"] = "own.Copyable",
        ["nupp.recoverAlias"] = "own.recoverAlias",
    }) do
        test.equal(identities.canonical(old), final)
    end
    test.equal(identities.canonical("nupp.compiler.types"), "nupp.compiler.types")
    test.equal(identities.canonical("nupp.typesExtra.array"), "nupp.typesExtra.array")
    test.equal(identities.canonical("nupp.math.u32.add"), "math.u32.add")
    test.equal(identities.canonical("nupp.simd.Vector"), "simd.Vector")
    test.equal(identities.legacy("gpu.internal.Image"), "gpu.internal.Image")
    test.equal(identities.canonical("nupp.gpu.layout.Buffer"), "gpu.layout.Buffer")
    test.equal(identities.canonical("nupp.gpu.types.Buffer"), "nupp.gpu.types.Buffer")
    test.equal(identities.canonical("nupp.gpu.internal.Image"), "nupp.gpu.internal.Image")
    test.equal(identities.canonical("types.array"), "types.array")
    test.equal(identities.canonical("types.derive.array"), "types.derive.array")
end

function M.preservesOneNominalAndOneEvaluatorLibrary()
    local env = finalEnv()
    test.equal(identities.lookup(env.globalTypes, "types.reflect"), env.globalTypes["nupp.reflect"])
    test.equal(identities.lookup(env.globalTypes, "types.derive"), env.globalTypes["nupp.derive"])
    test.equal(identities.lookup(env.globalTypes, "types.Debug"), env.globalTypes["nupp.Debug"])
    local values = {}
    providers.installEvaluator({}, values)
    test.equal(values.types, values.nupp.types)
    test.equal(values.types.reflect, values.nupp.reflect)
    test.equal(values.types.derive, values.nupp.derive)
    assert(values.types.array ~= values.types.derive.array)
    assert(values.types.error ~= values.types.derive.error)
end

function M.resolvesFinalContractsWithUnchangedPreludeDeclarations()
    local env = envMod.new(HERE .. "/..", {config = {include = {"src"}}})
    test.equal(env.globalTypes["own.Closeable"], nil)
    test.equal(env.globalTypes["types.Debug"], nil)
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
local value = new Resource()
value:close()
return 17
]],
        env
    )
    test.equal(errors, "", errors)
end

function M.executesBothTypeBuilderSurfacesAndAliases()
    for _, root in ipairs({"nupp.types", "types"}) do
        test.equal(
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
    for _, root in ipairs({"nupp.reflect", "types.reflect"}) do
        test.equal(
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
local record Resource is nupp.Closeable
    function close(takes self): nil end
end
local manage = own.manage
local value = new Resource()
local cell = manage(value)
cell:close()
]]
    )
    test.equal(errors, "", errors)
    local block = parsed.root.blocks[1]
    local cell = block.stats[4]
    test.equal(cell.exprs[1].ownershipIntrinsic, "manage")
    local code, shadowErrors = compile(
        [[
local own = {manage = function(value: integer): integer return value + 1 end}
local types = {reflect = function(value: integer): integer return value + 2 end}
return own.manage(types.reflect(types.reflect(1)) + 1)
]]
    )
    test.equal(shadowErrors, "", shadowErrors)
    test.equal(assert(loadstring(code))(), 7)
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
    env.loaded["nupp.derive"] = {type = T.shape(fields), exports = {values = values}}

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
        runtimeEnv()
    )
    test.equal(errors, "", errors)
    for _, root in ipairs({"nupp.derive", "types.derive"}) do
        local source = ([[
return ROOT.entry()
]]):gsub("ROOT", root)
        local _, recipeErrors = compile(source)
        assert(recipeErrors:find("NUPP2809", 1, true), recipeErrors)
    end
end

function M.preservesLazyExplicitModuleRequires()
    local code, errors = compile(
        [[
local function later(): any
    local runtime = require("nupp.derive")
    return runtime
end
return 17
]],
        runtimeEnv()
    )
    test.equal(errors, "", errors)
    local original = _G.require
    local calls = 0
    _G.require = function(name)
        if name == "nupp.derive" then
            calls = calls + 1
        end
        return original(name)
    end
    local ok, result = pcall(assert(loadstring(code, "@lazy-module")))
    _G.require = original
    assert(ok, result)
    test.equal(result, 17)
    test.equal(calls, 0)
end

function M.preservesCanonicalAssertionAliasesAndShadowing()
    test.equal(
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
    test.equal(
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
    local moduleName = assert(source:match("module ([%w_]+)"))
    local file = assert(io.open(dir .. "/src/" .. moduleName .. ".nupp", "wb"))
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
export type Debug = nupp.Debug
@comptime
export function Debug(info: types.derive.Info): types.derive.Result<types.Debug>
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
local Debug = api.Debug
@derive(Debug)
local record Point label: string end
local value: types.Debug = new Point(label = "one")
local type Bounded = api.range(integer, 0, 20)
local answer: Bounded = 17
return value:debug(), answer, api.answer
]],
                env
            )
            test.equal(errors, "", errors)
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
local value = new Resource()
local cell = move(value)
cell:close()
return api.answer
]],
            env
        )
        test.equal(errors, "", errors)
        local stats = parsed.root.blocks[1].stats
        test.equal(stats[5].exprs[1].ownershipIntrinsic, "manage")
    end)
end

function M.parsesCanonicalAdoptTypeArgumentsAndPreservesShadows()
    local _, errors, parsed = compile(
        [[
local record Resource is nupp.Closeable
    function close(takes self): nil end
end
local raw: any = {}
local value = @unsafe own.adopt<Resource>(raw)
value:close()
]]
    )
    test.equal(errors, "", errors)
    local stats = parsed.root.blocks[1].stats
    test.equal(stats[3].exprs[1].ownershipIntrinsic, "adopt")
    local shadowCode, shadowErrors, shadow = compile(
        [[
local own = {adopt = function<T>(value: any): T return value as T end}
local value: string = own.adopt<string>("ready")
return value
]]
    )
    test.equal(shadowErrors, "", shadowErrors)
    test.equal(shadow.root.blocks[1].stats[2].exprs[1].ownershipIntrinsic, nil)
    test.equal(#shadow.root.blocks[1].stats[2].exprs[1].typeArgs, 1)
    test.equal(assert(loadstring(shadowCode, "@adopt-shadow"))(), "ready")
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
            test.equal(errors, "", errors)
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
            test.equal(persisted.identity, program.identity)
            local envelope, failure = require(
                "nupp.compiler.comptime"
            ).evaluateTypeFunctionDirect(persisted, {{kind = "type", value = T.string}}, {})
            assert(envelope, failure and failure.message)
            test.equal(envelope.payload.nodes[envelope.payload.root].kind, "array")
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
                    test.equal(program.identity, identity)
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
    test.equal(#parsed.errors, 0)
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
    test.equal(program.identity, comptime.typeFunctionProgram(helper, {}).identity)
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
        test.equal(errors, "", errors)
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
return comptime do return nupp.types.kind(List(nupp.types.string)) end
]],
            env
        )
        test.equal(errors, "", errors)
        local evaluated = parsed.root.blocks[1].stats[3].exprs[1]
        test.equal(assert(loadstring("return " .. evaluated.comptimeValue))(), "array")
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
    test.equal(errors, "", errors)
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
        test.equal(errors, "", errors)
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
            "comptime do return nupp.types.kind(List(nupp.types.string)) end",
            "fixture-worker",
            {},
            {},
            {List = helper}
        )
        process.captureIsolated = original
        assert(ok, quoted)
        test.equal(failure, nil, failure and failure.message)
        test.equal(assert(loadstring("return " .. quoted))(), "array")
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
            local text = cst.textOf(node):gsub("nupp%.types", "types2")
            pieces[#pieces + 1] = "@comptime\n" .. text
        end
        for _, child in ipairs(node) do
            if type(child) == "table" then
                collect(child)
            end
        end
    end

    collect(parsed.root)
    test.equal(#pieces, 4)
    pieces[
        #pieces + 1
    ] = [[
local function accepts(...: unpackof __NuppFindResults("(%a+)", false)): nil end
accepts(1, 3, "one")
]]
    local formatted = require("nupp.tools.fmt").new():format(table.concat(pieces, "\n"))
    withProject("module types\nexport const answer: integer = 17", function(env)
        local _, errors = compile(formatted, env)
        test.equal(errors, "", errors)
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
        test.equal(#parsed.errors, 0)
        return parsed.root.blocks[1].stats[1]
    end

    local main = helper("local function Main(Element: type): type return Dependency(Element) end")
    local dependency = helper("local function Dependency(Element: type): type return nupp.types.array(Element) end")
    local first = comptime.sealTypeFunction(main, {Dependency = dependency})
    test.equal(comptime.sealTypeFunction(main, {Dependency = dependency}), first)
    local changed = helper("local function Dependency(Element: type): type return nupp.types.optional(Element) end")
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
        test.equal(parses, afterFirst, "an immutable sealed program must be parsed once")
        test.equal(secondResult.fingerprint, firstResult.fingerprint)
    end)
    parser.parse = original
    assert(ok, failure)
end

function M.referencedRecipeRefusalsKeepTheirDiagnostic()
    withProject(
        [[
module types
@comptime
export function Refuse(info: nupp.derive.Info): nupp.derive.Result<any>
    return nupp.derive.error("fixture refusal", info.reference)
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
    for _, root in ipairs({"nupp.reflect", "types.reflect"}) do
        test.equal(
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
    test.equal(value, "okay")
    test.equal(message, false)
    local _, errors = compile(
        [[
local check = assert
local value, message = check("okay", false)
local kept: boolean = message
return value, kept
]]
    )
    test.equal(errors, "", errors)
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
        test.equal(errors, "", errors)
    end)
    withProject([[
module own
export const answer: integer = 17
]], function(env)
        env.globals.own = nil
        local _, errors = compile(
            [[
local record Resource is nupp.Closeable
    function close(takes self): nil end
end
local value = new Resource()
local cell = own.manage(value)
cell:close()
]],
            env
        )
        test.equal(errors, "", errors)
    end)
end

function M.loggingKeepsLazyLoweringThroughCanonicalBindings()
    withProject([[
module log
export function info(format: string, value: integer?): nil end
]], function(env)
        local missingModules = {}
        for _, source in ipairs({
            'nupp.log.info("value=%d", 1)',
            'local logger = require("nupp.log")\nlogger.info("value=%d", 1)',
            'log.info("value=%d", 1)',
            'local logger = require("log")\nlogger.info("value=%d", 1)',
        }) do
            local code, errors, parsed = compile(source, env)
            test.equal(errors, "", errors)
            local stats = parsed.root.blocks[1].stats
            local expectedModule = source:find("nupp.log", 1, true) and "nupp.log" or "log"
            test.equal(stats[#stats].expr.logIntrinsic, 3, source)
            test.equal(stats[#stats].expr.logModule, expectedModule, source)
            if not code:find('require("' .. expectedModule .. '").forModule', 1, true) then
                missingModules[#missingModules + 1] = expectedModule .. ": " .. source
            end
        end
        local _, errors, parsed = compile(
            [[
local log = {info = function(format: string, value: integer): nil end}
log.info("value=%d", 1)
]],
            env
        )
        test.equal(errors, "", errors)
        test.equal(parsed.root.blocks[1].stats[2].expr.logIntrinsic, nil)
        local _, aliasErrors, alias = compile('local info = require("log").info\ninfo("value=%d", 1)', env)
        test.equal(aliasErrors, "", aliasErrors)
        test.equal(alias.root.blocks[1].stats[2].expr.logIntrinsic, nil)
        test.equal(#missingModules, 0, table.concat(missingModules, "\n"))
    end)
end

function M.resolvesConstraintIntrinsicsWithoutAProjectEnvironment()
    for _, root in ipairs({"nupp.types", "types"}) do
        local function diagnostics(prefix, expression)
            local source = prefix .. "\nlocal type Count = " .. root .. expression
            local parsed = parser.parse(source, "constraint-fragment.nupp")
            test.equal(#parsed.errors, 0)
            return checker.check(parsed, "constraint-fragment.nupp", nil, {strict = false})
        end

        local clean = diagnostics("", ".range(integer, 0, 10)")
        test.equal(#clean, 0)
        local invalid = diagnostics("", ".range(integer, 10, 0)")
        test.equal(invalid[1].code, "NUPP2422")
        local shadow = diagnostics("local " .. root:match("^[^.]+") .. " = {}", ".range(integer, 0, 10)")
        test.equal(shadow[1].code, "NUPP2421")
    end
end

return M
