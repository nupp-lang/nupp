local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local program = require("program")
local loadImage = assert(rawget(_G, "__nupp_load_image"))
local envMod = require("nupp.compiler.project.env")
local M = {}
local fixtureImage = 0

local function loadProgram(compiled)
    return loadImage(compiled.image)
end

local function namesModule(compiled, name)
    return compiled.listing:find("str " .. string.format("%q", name) .. "\n", 1, true) ~= nil
end

local function compile(source, filename, env)
    local parsed = parser.parse(source, filename)
    test.eq(#parsed.errors, 0)
    local errors = {}
    for _, item in ipairs(checker.check(parsed, filename, env)) do
        if item.severity == "error" then
            errors[#errors + 1] = item.code .. ": " .. item.msg
        end
    end
    test.eq(table.concat(errors, "\n"), "", source)
    program.installSourceModules()
    local listing = {}
    -- Loading a fixture must not replace a canonical entry in the VM image registry.
    fixtureImage = fixtureImage + 1
    local image = program.image(parsed, "nupp.tests.builtinextension.fixture" .. fixtureImage, filename, listing)
    local lines = {}
    for _, entry in ipairs(listing) do
        lines[#lines + 1] = entry.image
    end

    return {image = image, listing = table.concat(lines, "\n")}, parsed
end

local function withExtension(callback, assertionSource, ioSource, coroutineOverride)
    local root = os.tmpname()
    os.remove(root)
    local directory = root .. "/src/nupp/runtime"
    assert(os.execute("mkdir -p '" .. directory .. "'") == 0)
    local path = directory .. "/standardio.nupp"
    local source = ioSource
        or [[
@!internal
module nupp.runtime.standardio
export type Buffer = {label: string}
export const Buffer = {create = function(value: string): Buffer return {label = value} end}
export type Style = {label: string}
export type ColorMode = "auto" | "always" | "never"
export type Alignment = "left" | "right"
export type Cell = {text: string}
export type Column = {heading: string}
export type TableOptions = {rows: {{Cell}}}
export function columns(): integer return 73 end
export const value: table = do
    local original = rawget(_G, "io") as any
    original.columns = columns
    original.Buffer = Buffer
    yield original
end
]]
    local file = assert(io.open(path, "wb"));
    file:write(source);
    file:close()
    local argvSource = [[
module io.cli
local cli = {}
function cli.parse(value: string): string return value end
cli.args = rawget(_G, "arg") as {string}
export = cli
]]
    assert(os.execute("mkdir -p '" .. root .. "/src/io'") == 0)
    local argvPath = root .. "/src/io/cli.nupp"
    local argvFile = assert(io.open(argvPath, "wb"));
    argvFile:write(argvSource);
    argvFile:close()
    local assertionPath = root .. "/src/assert.lua"
    if assertionSource then
        assertionPath = root .. "/src/assert.nupp"
    end
    local assertionFile = assert(io.open(assertionPath, "wb"))
    assertionFile:write(assertionSource or 'return _G.assert')
    assertionFile:close()
    local osFile = assert(io.open(directory .. "/standardos.nupp", "wb"))
    osFile:write(
        [[
@!internal
module nupp.runtime.standardos
export type Info = {platform: string}
export function info(): Info return {platform = "fixture"} end
export const value: table = rawget(_G, "os") as table
]]
    )
    osFile:close()
    local coroutineSource = coroutineOverride
        or [[
@!internal
module nupp.runtime.standardcoroutine
export function checkpoint(): integer return 29 end
export function scope(limit: integer?, timeoutMs: number?): nil return end
export const value: table = do
    local original = rawget(_G, "coroutine") as any
    original.checkpoint = checkpoint
    yield original
end
]]
    local coroutinePath = directory .. "/standardcoroutine.nupp"
    local coroutineFile = assert(io.open(coroutinePath, "wb"))
    coroutineFile:write(coroutineSource)
    coroutineFile:close()
    local env = envMod.new(root, {config = {include = {"src"}}})
    local name = "nupp.runtime.standardio"
    local nativePopen = require(name).popen
    local loaded, preload, columns = package.loaded[name], package.preload[name], rawget(io, "columns")
    local bufferType = rawget(io, "Buffer")
    local ioError = rawget(io, "Error")
    local coroutineName = "nupp.runtime.standardcoroutine"
    local coroutineLoaded, coroutinePreload = package.loaded[coroutineName], package.preload[coroutineName]
    local checkpoint = rawget(coroutine, "checkpoint")
    local scopeType, cancellationType = rawget(coroutine, "Scope"), rawget(coroutine, "Cancellation")
    local ok, reason = pcall(function()
        local code = compile(source, path, env)
        package.loaded[name] = nil
        local fixture = assert(loadProgram(code, "@standardio-fixture"))
        package.preload[name] = function(...)
            local value = fixture(...)
            -- Checking a dependency can start the comptime worker while this
            -- fixture is installed. Keep its subprocess transport available.
            value.popen = nativePopen
            return value
        end
        local coroutineCode = compile(coroutineSource, coroutinePath, env)
        package.loaded[coroutineName] = nil
        package.preload[coroutineName] = assert(loadProgram(coroutineCode, "@standardcoroutine-fixture"))
        callback(env, argvSource, argvPath)
    end)
    package.loaded[name], package.preload[name] = loaded, preload
    rawset(io, "columns", columns)
    rawset(io, "Buffer", bufferType)
    rawset(io, "Error", ioError)
    package.loaded[coroutineName], package.preload[coroutineName] = coroutineLoaded, coroutinePreload
    rawset(coroutine, "checkpoint", checkpoint)
    rawset(coroutine, "Scope", scopeType)
    rawset(coroutine, "Cancellation", cancellationType)
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, reason)
end

function M.preservesTheHostTableThroughAliasesAndRequire()
    withExtension(function(env)
        local source = [[
local original = io
local imported = require("io")
return original == io, original == imported, imported.Buffer.create("ready").label, original.stdout == imported.stdout
]]
        local code = compile(source, "extension-consumer.nupp", env)
        local global, imported, label, stdout = assert(loadProgram(code))()
        test.eq(global, true)
        test.eq(imported, true)
        test.eq(label, "ready")
        test.eq(stdout, true)
        test.eq(package.loaded.io, io)
        test.eq(require("nupp.runtime.standardio").value, io)
        local separate = envMod.new("/private/tmp", {config = {include = {"no-builtin-extension-fixture"}}})
        test.eq(separate.globals.io.t.byname.columns, nil, "a project extension must not mutate cached preludes")
    end)
end

function M.ordinaryBuiltinMembersDoNotLoadExtensions()
    withExtension(function(env)
        local code = compile("return io.stdout", "ordinary-consumer.nupp", env)
        assert(not namesModule(code, "nupp.runtime.standardio"))
        local stdout = io.stdout
        -- Compiler setup may use its own I/O extension. Observe the fragment alone.
        package.loaded["nupp.runtime.standardio"] = nil
        test.eq(assert(loadProgram(code))(), stdout)
        test.eq(package.loaded["nupp.runtime.standardio"] == nil, true)
    end)
end

function M.localTablesAndRequireShadowsKeepTheirOwnMeaning()
    withExtension(function(env)
        local code = compile(
            [[
module shadowconsumer
export function run(): (integer, integer)
    local io = {columns = function(): integer return 19 end}
    local require: function(string): integer = function(name: string): integer return #name end
    local length: integer = require("io")
    return io.columns(), length
end
]],
            "shadow-consumer.nupp",
            env
        )
        assert(not namesModule(code, "nupp.runtime.standardio"))
        local columns, length = assert(loadProgram(code))().run()
        test.eq(columns, 19)
        test.eq(length, 2)
    end)
end

function M.cliArgumentsRemainSeparateFromTheLibraryTable()
    withExtension(function(env, source, path)
        local previous = rawget(_G, "arg")
        local loaded, preload = package.loaded["io.cli"], package.preload["io.cli"]
        local argv = {[0] = "fixture", [1] = "value", [-1] = "nupp"}
        local ok, reason = pcall(function()
            rawset(_G, "arg", argv)
            package.loaded["io.cli"] = nil
            local implementation = compile(source, path, env)
            local loadCli = assert(loadProgram(implementation))
            local loads = 0
            package.preload["io.cli"] = function(...)
                loads = loads + 1
                return loadCli(...)
            end
            local code = compile(
                [[
require("io.cli")
local current = io.cli.args
require("io.cli")
local imported = require("io.cli")
return current == imported.args, imported.parse("kept"), #current
]],
                "argv-consumer.nupp",
                env
            )
            local same, parsed, count = assert(loadProgram(code))()
            test.eq(same, true)
            test.eq(parsed, "kept")
            test.eq(count, 1)
            test.eq(loads, 1, "standalone and value requires share one initialization")
            test.eq(rawget(argv, "parse"), nil)
            test.eq(getmetatable(argv), nil, "the library must not attach an argv metatable")
            test.eq(argv[-1], "nupp")
            test.eq(package.loaded["io.cli"].args, argv)
            test.ne(package.loaded["io.cli"], argv)
            local rawCount = 0
            for _ in pairs(argv) do
                rawCount = rawCount + 1
            end
            test.eq(rawCount, 3)
        end)
        rawset(_G, "arg", previous)
        package.loaded["io.cli"], package.preload["io.cli"] = loaded, preload
        assert(ok, reason)
    end)
end

function M.anImplicitAssertionHelperDoesNotReplaceTheBuiltin()
    withExtension(function(env)
        local builtinType = env.globals.assert.t
        local code = compile(
            [[
local helpers = require("assert")
local first: string, gap: nil, last: integer = assert("kept", nil, 42)
return first, gap, last, helpers.eq ~= nil
]],
            "assertion-shim-consumer.nupp",
            env
        )
        local first, gap, last, helper = assert(loadProgram(code))()
        test.eq(first, "kept")
        test.eq(gap, nil)
        test.eq(last, 42)
        test.eq(helper, true)
        test.eq(env.builtinExtensions.assert, false)
        test.eq(env.globals.assert.t, builtinType, "the implicit helper preserves the canonical builtin type")
    end)
end

function M.aDeclaredCallableAssertionStillSuppliesTheGlobal()
    local source = [[
module assert
local interface Callable
    metamethod __call: function<A...>(self, A...): A...
end
local original = rawget(_G, "assert") as function<A...>(A...): A...
local value = {} as Callable
export = setmetatable(value, {__call = function<A...>(_self: Callable, ...: A...): A...
    return original(...)
end})
]]
    withExtension(
        function(env)
            local loaded, preload = package.loaded.assert, package.preload.assert
            local ok, reason = pcall(function()
                package.loaded.assert = nil
                local implementation = compile(source, "assertion-fixture.nupp", env)
                package.preload.assert = assert(loadProgram(implementation))
                local code = compile(
                    [[
local first: string, gap: nil, last: integer = assert("kept", nil, 42)
return type(assert), first, gap, last
]],
                    "declared-assertion-consumer.nupp",
                    env
                )
                local kind, first, gap, last = assert(loadProgram(code))()
                test.eq(kind, "table")
                test.eq(first, "kept")
                test.eq(gap, nil)
                test.eq(last, 42)
            end)
            package.loaded.assert, package.preload.assert = loaded, preload
            assert(ok, reason)
        end,
        source
    )
end

function M.extensionTypesResolveBeforeAnyValueRead()
    withExtension(function(env)
        local code, parsed = compile(
            [[
local style: io.Style = {label = "ready"}
local facts: os.Info = {platform = "fixture"}
return style.label, facts.platform
]],
            "type-only-extension-consumer.nupp",
            env
        )
        test.eq(namesModule(code, "nupp.runtime.standardio"), false)
        test.eq(namesModule(code, "nupp.runtime.standardos"), false)
        test.eq(next(parsed.effects), nil, "type lookup records no runtime effect")
        local label, platform = assert(loadProgram(code))()
        test.eq(label, "ready")
        test.eq(platform, "fixture")
        local withValue = compile(
            'local facts: os.Info = os.info()\nreturn facts.platform',
            "typed-value-consumer.nupp",
            env
        )
        assert(namesModule(withValue, "nupp.runtime.standardos"))
    end)
end

function M.typeOnlyRequiresShareQualifiedExtensionTypes()
    withExtension(function(env)
        local code, parsed = compile(
            [[
module extensiontypes
const {type ColorMode, type Style, type Cell, type TableOptions, type Alignment, type Column} = require("io")
export type SelectedColorMode = ColorMode
export type SelectedStyle = Style
export type SelectedCell = Cell
export type SelectedTableOptions = TableOptions
export type SelectedAlignment = Alignment
export type SelectedColumn = Column
export function identity(style: Style): Style return style end
]],
            "type-import-extension-consumer.nupp",
            env
        )
        for _, name in ipairs({"ColorMode", "Style", "Cell", "TableOptions", "Alignment", "Column"}) do
            test.eq(parsed.moduleExports.types["Selected" .. name], env.globalTypes["io." .. name])
            test.eq(parsed.moduleExports.types["Selected" .. name], env.builtinExtensionExports.io.types[name])
        end
        test.eq(namesModule(code, "io"), false)
        test.eq(namesModule(code, "nupp.runtime.standardio"), false)
        test.eq(next(parsed.effects), nil, "type imports record no runtime effect")
        -- Isolate fragment execution from the compiler's own extension loading.
        package.loaded["nupp.runtime.standardio"] = nil
        local consumer = assert(loadProgram(code))()
        test.eq(package.loaded["nupp.runtime.standardio"] == nil, true)
        local style = {label = "ready"}
        test.eq(consumer.identity(style), style)
    end)
end

function M.incrementalTypeImportsReadTheExtensionExports()
    withExtension(function(env)
        local inc = require("nupp.compiler.project.incremental").new(env.rootDir, {
            config = {include = {"src"}},
            cache = false
        })
        for index = 1, 2 do
            local path = env.rootDir .. "/src/consumer" .. index .. ".nupp"
            inc.openDocument(
                path,
                [[
module consumer]]
                .. index
                .. "\n"
                .. [[
const {type Buffer} = require("io")
export type SelectedBuffer = Buffer
export function identity(value: Buffer): Buffer return value end
]]
            )
            local checked = inc.checkFile(path)
            test.eq(checked.syntax, nil)
            local errors = {}
            for _, diagnostic in ipairs(checked.diags) do
                if diagnostic.severity == "error" then
                    errors[#errors + 1] = diagnostic.code .. ": " .. diagnostic.msg
                end
            end
            test.eq(table.concat(errors, "\n"), "")
            local exports = inc.q:get("moduleExports", "nupp.runtime.standardio")
            test.eq(checked.result.moduleExports.types.SelectedBuffer, exports.types.Buffer)
            local reached = {}
            for _, dependency in ipairs(inc.moduleDependencies(path)) do
                reached[dependency] = true
            end
            test.eq(reached["nupp.runtime.standardio"], true)
            local listing = {}
            local image = program.image(checked.result, "consumer" .. index, path, listing)
            local functions = {}
            for _, entry in ipairs(listing) do
                functions[#functions + 1] = entry.image
            end
            local compiled = {listing = table.concat(functions, "\n")}
            test.eq(namesModule(compiled, "io"), false)
            test.eq(namesModule(compiled, "nupp.runtime.standardio"), false)
            test.eq(next(checked.result.effects), nil)
            package.loaded["nupp.runtime.standardio"] = nil
            local consumer = assert(loadImage(image))()
            test.eq(package.loaded["nupp.runtime.standardio"] == nil, true)
            local buffer = {label = "kept"}
            test.eq(consumer.identity(buffer), buffer)
        end
    end)
end

function M.incrementalRequiredAliasesShareHoistedTypesAndInvalidate()
    withExtension(function(env)
        local inc = require("nupp.compiler.project.incremental").new(env.rootDir, {
            config = {include = {"src"}},
            cache = false
        })
        inc.importModules({
            io = {
                interface = {type = inc.env.globals.io.t},
                exports = {types = {}, typeDefs = {}, values = {}, valueDefs = {}}
            }
        })
        local paths = {}

        local function checked(path)
            local result = inc.checkFile(path)
            test.eq(result.syntax, nil)
            for _, diagnostic in ipairs(result.diags) do
                test.eq(diagnostic.severity == "error", false, diagnostic.msg)
            end

            return result
        end

        for index, alias in ipairs({"io", "streams"}) do
            local path = env.rootDir .. "/src/alias" .. index .. ".nupp"
            paths[index] = path
            inc.openDocument(
                path,
                (
                    "module alias%d\nconst %s = require(\"io\")\n"
                    .. "export function identity(value: %s.Buffer): %s.Buffer return value end\n"
                    .. "export type Selected = %s.Buffer\n"
                ):format(index, alias, alias, alias, alias)
            )
            local result = checked(path)
            local exports = inc.q:get("moduleExports", "nupp.runtime.standardio")
            test.eq(result.result.moduleExports.types.Selected, exports.types.Buffer)
        end
        local old = checked(paths[1]).result.moduleExports.types.Selected
        local implementation = env.rootDir .. "/src/nupp/runtime/standardio.nupp"
        inc.changeDocument(
            implementation,
            [[
@!internal
module nupp.runtime.standardio
export type Buffer = {count: integer}
export const Buffer = {create = function(value: string): Buffer return {count = #value} end}
export const value: table = rawget(_G, "io") as table
]]
        )
        for _, path in ipairs(paths) do
            local result = checked(path)
            local exports = inc.q:get("moduleExports", "nupp.runtime.standardio")
            test.eq(result.result.moduleExports.types.Selected, exports.types.Buffer)
            test.eq(result.result.moduleExports.types.Selected == old, false)
            local reached = {}
            for _, dependency in ipairs(inc.moduleDependencies(path)) do
                reached[dependency] = true
            end
            test.eq(reached["nupp.runtime.standardio"], true)
        end
        inc.changeDocument(
            implementation,
            [[
@!internal
module nupp.runtime.standardio
export const value: table = rawget(_G, "io") as table
]]
        )
        for _, path in ipairs(paths) do
            local failed = false
            for _, diagnostic in ipairs(inc.checkFile(path).diags) do
                failed = failed or diagnostic.code == "NUPP2101"
            end
            test.eq(failed, true, "removed extension types invalidate every required alias")
        end
    end)
end

function M.incrementalBuiltinExportCyclesKeepPendingNominalIdentity()
    withExtension(function(env)
        local inc = require("nupp.compiler.project.incremental").new(env.rootDir, {
            config = {include = {"src"}},
            cache = false
        })
        local path = env.rootDir .. "/src/dependent.nupp"
        local implementation = env.rootDir .. "/src/nupp/runtime/standardio.nupp"
        inc.openDocument(
            path,
            [[
module dependent
const streams = require("io")
export function identity(value: streams.Buffer.Nested): streams.Buffer.Nested return value end
export type Selected = streams.Buffer
export type Nested = streams.Buffer.Nested
]]
        )
        inc.changeDocument(
            implementation,
            [[
@!internal
module nupp.runtime.standardio
export record Buffer
    record Nested count: integer end
    label: string
end
local dependent = require("dependent")
export const value: table = rawget(_G, "io") as table
]]
        )
        local result = inc.checkFile(path)
        test.eq(result.syntax, nil)
        for _, diagnostic in ipairs(result.diags) do
            test.eq(diagnostic.severity == "error", false, diagnostic.msg)
        end
        local exports = inc.q:get("moduleExports", "nupp.runtime.standardio")
        test.eq(inc.q:get("moduleExports", "io"), exports)
        test.eq(inc.moduleSemantic("io").exports, exports)
        test.eq(result.result.moduleExports.types.Selected, exports.types.Buffer)
        test.eq(result.result.moduleExports.types.Nested, exports.types.Buffer.nestedTypes.Nested)
        inc.changeDocument(implementation, "return {}")
        test.eq(require("nupp.compiler.builtinextensions").implementation(inc.env, "io"), nil)
        local refused = false
        for _, diagnostic in ipairs(inc.checkFile(path).diags) do
            refused = refused or diagnostic.code == "NUPP2101"
        end
        test.eq(refused, true, "a headerless lookalike must not retain extension type exports")
    end)
end

function M.lexicalTypeNamespacesWinOverExtensionTypes()
    withExtension(function(env)
        local code = compile(
            [[
local io = {}
type io.Style = string
local os = {}
type os.Info = integer
local style: io.Style = "local"
local facts: os.Info = 17
return style, facts
]],
            "local-type-extension-consumer.nupp",
            env
        )
        test.eq(env.builtinExtensions, nil)
        test.eq(namesModule(code, "nupp.runtime.standardio"), false)
        test.eq(namesModule(code, "nupp.runtime.standardos"), false)
        local style, facts = assert(loadProgram(code))()
        test.eq(style, "local")
        test.eq(facts, 17)
    end)
end

function M.lowercaseByteFactoriesPreserveBuiltinIdentityAndTypeExports()
    withExtension(function(env)
        local code, parsed = compile(
            [[
module byteconsumer
const {type Buffer} = require("io")
export type SelectedBuffer = Buffer
export function run(): (boolean, string)
    local original = io
    local imported = require("io")
    local buffer: io.Buffer = imported.Buffer.create("kept")
    return original == imported, buffer.label
end
]],
            "byte-consumer.nupp",
            env
        )
        test.eq(parsed.moduleExports.types.SelectedBuffer, env.globalTypes["io.Buffer"])
        local same, label = assert(loadProgram(code))().run()
        test.eq(same, true)
        test.eq(label, "kept")
        test.eq(require("nupp.runtime.standardio").value, io)
    end)
end

function M.extendedLuaPipeRemainsWritable()
    compile([[
io.popen = function(...: any): (nil, nil)
    return nil, nil
end
]], "replace-popen.nupp", envMod.new("."))
end

function M.aPartialIoExtensionPreservesTheLuaPipe()
    withExtension(function(env)
        compile([[
local pipe = io.popen("true")
if pipe ~= nil then pipe:close() end
]], "partial-io-popen.nupp", env)
    end)
end

function M.coroutineExtensionsPreserveAliasesRequireAndLocalShadows()
    withExtension(function(env)
        local code = compile(
            [[
local original = coroutine
local imported = require("coroutine")
local checkpoint = imported.checkpoint
local same = original == imported
local value = checkpoint()
local coroutine = {checkpoint = function(): integer return 17 end}
return same, value, coroutine.checkpoint()
]],
            "coroutine-consumer.nupp",
            env
        )
        local same, value, shadow = assert(loadProgram(code))()
        test.eq(same, true)
        test.eq(value, 29)
        test.eq(shadow, 17)
        test.eq(require("nupp.runtime.standardcoroutine").value, coroutine)
    end)
end

function M.ordinaryCoroutineMembersDoNotLoadExtensions()
    withExtension(function(env)
        local code = compile("return coroutine.running", "ordinary-coroutine-consumer.nupp", env)
        test.eq(namesModule(code, "nupp.runtime.standardcoroutine"), false)
        test.eq(assert(loadProgram(code))(), coroutine.running)
        test.eq(package.loaded["nupp.runtime.standardcoroutine"], nil)
    end)
end

function M.coroutineScopeAliasesRetainDeadlineEffectsAndLocalShadows()
    withExtension(function(env)
        for _, source in ipairs({
            "coroutine.scope(timeoutMs = 1)",
            "local scope = coroutine.scope\nscope(timeoutMs = 1)",
            'local imported = require("coroutine")\nimported.scope(timeoutMs = 1)',
        }) do
            local _, parsed = compile(source, "scope-deadline-consumer.nupp", env)
            test.eq(parsed.effects["runtime.time"], true, "the deadline carries the clock provider")
        end
        local _, ordinary = compile(
            [[
local coroutine = {scope = function(limit: integer?, timeoutMs: number?): nil return end}
coroutine.scope(nil, 1)
]],
            "shadow-scope-consumer.nupp",
            env
        )
        test.eq(ordinary.effects["runtime.time"], nil)
    end)
end

function M.byteErrorFacadeKeepsItsConstructorAndNominalIdentity()
    local source = [[
@!internal
module nupp.runtime.standardio
local existing = require("nupp.io")
export type Error = existing.Error
export const Error = existing.Error
export const value: table = do
    local original = rawget(_G, "io") as any
    original.Error = Error
    yield original
end
]]
    withExtension(
        function(env)
            local code, parsed = compile(
                [[
local constructor = io.Error
local problem: io.Error = io.Error(kind = "other", message = "kept")
return constructor, problem, tostring(problem)
]],
                "byte-error-consumer.nupp",
                env
            )
            local constructor, problem, rendered = assert(loadProgram(code))()
            local original = require("io").Error
            test.eq(constructor, original)
            test.eq(getmetatable(problem), original)
            test.eq(rendered, "kept")
            assert(namesModule(code, "nupp.runtime.standardio"))
        end,
        nil,
        source
    )
end

function M.coroutineRecordValuesKeepTheirOriginalNominalOwners()
    local source = [[
@!internal
module nupp.runtime.standardcoroutine
local existing = require("nupp.tasks")
export type Cancellation = existing.Cancellation
export type Scope = existing.Scope
export const Cancellation = existing.Cancellation
export const Scope = existing.Scope
export const value: table = do
    local original = rawget(_G, "coroutine") as any
    original.Cancellation = Cancellation
    original.Scope = Scope
    yield original
end
]]
    withExtension(
        function(env)
            local code = compile(
                [[
local existing = require("coroutine")
local scopeType = coroutine.Scope
local cancellation: existing.Cancellation = coroutine.Cancellation(operation = "kept")
return scopeType, cancellation, coroutine.Cancellation == existing.Cancellation
]],
                "coroutine-record-consumer.nupp",
                env
            )
            local scopeType, cancellation, sameCancellation = assert(loadProgram(code))()
            local original = require("coroutine")
            test.eq(scopeType, original.Scope)
            test.eq(sameCancellation, true)
            test.eq(cancellation.operation, "kept")
        end,
        nil,
        nil,
        source
    )
end

function M.coroutineStructuredCombinatorsPreserveAliasesAndShadows()
    local source = [[
@!internal
module nupp.runtime.standardcoroutine
local original = require("nupp.tasks")
export const run = original.run
export const gather = original.gather
export const race = original.race
export const value: table = do
    local host = rawget(_G, "coroutine") as any
    host.run = run
    host.gather = gather
    host.race = race
    yield host
end
]]
    local saved = {run = coroutine.run, gather = coroutine.gather, race = coroutine.race}
    local ok, failure = pcall(function()
        withExtension(
            function(env)
                local code = compile(
                    [[
local imported = require("coroutine")
return coroutine.run, imported.gather, imported.race
]],
                    "coroutine-combinators.nupp",
                    env
                )
                local run, gather, race = assert(loadProgram(code))()
                local original = require("nupp.tasks")
                test.eq(run, original.run)
                test.eq(gather, original.gather)
                test.eq(race, original.race)
                local shadow = compile(
                    [[
local coroutine = {run = function(): integer return 11 end}
return coroutine.run()
]],
                    "coroutine-combinators-shadow.nupp",
                    env
                )
                test.eq(assert(loadProgram(shadow))(), 11)
            end,
            nil,
            nil,
            source
        )
    end)
    for _, name in ipairs({"run", "gather", "race"}) do
        rawset(coroutine, name, saved[name])
    end
    assert(ok, failure)
end

return M
