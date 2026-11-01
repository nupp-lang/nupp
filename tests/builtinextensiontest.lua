local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")
local M = {}

local function compile(source, filename, env)
    local parsed = parser.parse(source, filename)
    test.equal(#parsed.errors, 0)
    local errors = {}
    for _, item in ipairs(checker.check(parsed, filename, env)) do
        if item.severity == "error" then
            errors[#errors + 1] = item.code .. ": " .. item.msg
        end
    end
    test.equal(table.concat(errors, "\n"), "", source)
    local code, diagnostics = gen.generate(parsed, filename)
    test.equal(#diagnostics, 0)

    return code, parsed
end

local function withExtension(callback, assertionSource)
    local root = os.tmpname()
    os.remove(root)
    local directory = root .. "/src/nupp/runtime"
    assert(os.execute("mkdir -p '" .. directory .. "'") == 0)
    local path = directory .. "/standardio.nupp"
    local source = [[
@!internal
module nupp.runtime.standardio
export type Buffer = {label: string}
export function newbuffer(value: string): Buffer return {label = value} end
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
    original.newbuffer = newbuffer
    yield original
end
]]
    local file = assert(io.open(path, "wb"));
    file:write(source);
    file:close()
    local argvSource = [[
module arg
local methods = {}
function methods.parse(value: string): string return value end
local argv: {string} = rawget(_G, "arg") as {string}
export = setmetatable(argv, {__index = methods})
]]
    local argvPath = root .. "/src/arg.nupp"
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
    local coroutineSource = [[
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
    local loaded, preload, columns = package.loaded[name], package.preload[name], rawget(io, "columns")
    local newbuffer = rawget(io, "newbuffer")
    local coroutineName = "nupp.runtime.standardcoroutine"
    local coroutineLoaded, coroutinePreload = package.loaded[coroutineName], package.preload[coroutineName]
    local checkpoint = rawget(coroutine, "checkpoint")
    local ok, reason = pcall(function()
        local code = compile(source, path, env)
        package.loaded[name] = nil
        package.preload[name] = assert(loadstring(code, "@standardio-fixture"))
        local coroutineCode = compile(coroutineSource, coroutinePath, env)
        package.loaded[coroutineName] = nil
        package.preload[coroutineName] = assert(loadstring(coroutineCode, "@standardcoroutine-fixture"))
        callback(env, argvSource, argvPath)
    end)
    package.loaded[name], package.preload[name] = loaded, preload
    rawset(io, "columns", columns)
    rawset(io, "newbuffer", newbuffer)
    package.loaded[coroutineName], package.preload[coroutineName] = coroutineLoaded, coroutinePreload
    rawset(coroutine, "checkpoint", checkpoint)
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, reason)
end

function M.preservesTheHostTableThroughAliasesAndRequire()
    withExtension(function(env)
        local source = [[
local original = io
local imported = require("io")
return original == io, original == imported, imported.columns(), original.stdout == imported.stdout
]]
        local code = compile(source, "extension-consumer.nupp", env)
        local global, imported, columns, stdout = assert(loadstring(code))()
        test.equal(global, true)
        test.equal(imported, true)
        test.equal(columns, 73)
        test.equal(stdout, true)
        test.equal(package.loaded.io, io)
        test.equal(require("nupp.runtime.standardio").value, io)
        local separate = envMod.new("/private/tmp", {config = {include = {"no-builtin-extension-fixture"}}})
        test.equal(separate.globals.io.t.byname.columns, nil, "a project extension must not mutate cached preludes")
    end)
end

function M.ordinaryBuiltinMembersDoNotLoadExtensions()
    withExtension(function(env)
        local code = compile("return io.stdout", "ordinary-consumer.nupp", env)
        assert(not code:find('require("nupp.runtime.standardio")', 1, true))
        test.equal(assert(loadstring(code))(), io.stdout)
        test.equal(package.loaded["nupp.runtime.standardio"], nil)
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
        assert(not code:find('require("nupp.runtime.standardio")', 1, true))
        local columns, length = assert(loadstring(code))().run()
        test.equal(columns, 19)
        test.equal(length, 2)
    end)
end

function M.directArgRootKeepsOneRawArrayInstance()
    withExtension(function(env, source, path)
        local previous, loaded, preload = arg, package.loaded.arg, package.preload.arg
        local argv = {[0] = "fixture", [1] = "value", [-1] = "nupp"}
        local ok, reason = pcall(function()
            rawset(_G, "arg", argv)
            package.loaded.arg = nil
            local implementation = compile(source, path, env)
            local loadArg = assert(loadstring(implementation))
            local loads = 0
            package.preload.arg = function(...)
                loads = loads + 1
                return loadArg(...)
            end
            local code = compile(
                [[
require("arg")
local current = arg
require("arg")
local imported = require("arg")
return current == imported, current.parse("kept"), #current
]],
                "argv-consumer.nupp",
                env
            )
            local same, parsed, count = assert(loadstring(code))()
            test.equal(same, true)
            test.equal(parsed, "kept")
            test.equal(count, 1)
            test.equal(loads, 1, "standalone and value requires share one initialization")
            test.equal(rawget(argv, "parse"), nil)
            test.equal(argv[-1], "nupp")
            test.equal(package.loaded.arg, argv)
            local rawCount = 0
            for _ in pairs(argv) do
                rawCount = rawCount + 1
            end
            test.equal(rawCount, 3)
        end)
        rawset(_G, "arg", previous)
        package.loaded.arg, package.preload.arg = loaded, preload
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
return first, gap, last, helpers.equal ~= nil
]],
            "assertion-shim-consumer.nupp",
            env
        )
        local first, gap, last, helper = assert(loadstring(code))()
        test.equal(first, "kept")
        test.equal(gap, nil)
        test.equal(last, 42)
        test.equal(helper, true)
        test.equal(env.builtinExtensions.assert, false)
        test.equal(env.globals.assert.t, builtinType, "the implicit helper preserves the canonical builtin type")
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
                package.preload.assert = assert(loadstring(implementation))
                local code = compile(
                    [[
local first: string, gap: nil, last: integer = assert("kept", nil, 42)
return type(assert), first, gap, last
]],
                    "declared-assertion-consumer.nupp",
                    env
                )
                local kind, first, gap, last = assert(loadstring(code))()
                test.equal(kind, "table")
                test.equal(first, "kept")
                test.equal(gap, nil)
                test.equal(last, 42)
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
        test.equal(code:find('require("nupp.runtime.standardio")', 1, true), nil)
        test.equal(code:find('require("nupp.runtime.standardos")', 1, true), nil)
        test.equal(next(parsed.effects), nil, "type lookup records no runtime effect")
        local label, platform = assert(loadstring(code))()
        test.equal(label, "ready")
        test.equal(platform, "fixture")
        local withValue = compile(
            'local facts: os.Info = os.info()\nreturn facts.platform',
            "typed-value-consumer.nupp",
            env
        )
        assert(withValue:find('require("nupp.runtime.standardos")', 1, true))
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
            test.equal(parsed.moduleExports.types["Selected" .. name], env.globalTypes["io." .. name])
            test.equal(parsed.moduleExports.types["Selected" .. name], env.builtinExtensionExports.io.types[name])
        end
        test.equal(code:find('require("io")', 1, true), nil)
        test.equal(code:find('require("nupp.runtime.standardio")', 1, true), nil)
        test.equal(next(parsed.effects), nil, "type imports record no runtime effect")
        test.equal(package.loaded["nupp.runtime.standardio"], nil)
        local consumer = assert(loadstring(code))()
        local style = {label = "ready"}
        test.equal(consumer.identity(style), style)
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
        test.equal(env.builtinExtensions, nil)
        test.equal(code:find('require("nupp.runtime.standardio")', 1, true), nil)
        test.equal(code:find('require("nupp.runtime.standardos")', 1, true), nil)
        local style, facts = assert(loadstring(code))()
        test.equal(style, "local")
        test.equal(facts, 17)
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
    local buffer: io.Buffer = imported.newbuffer("kept")
    return original == imported, buffer.label
end
]],
            "byte-consumer.nupp",
            env
        )
        test.equal(parsed.moduleExports.types.SelectedBuffer, env.globalTypes["io.Buffer"])
        local same, label = assert(loadstring(code))().run()
        test.equal(same, true)
        test.equal(label, "kept")
        test.equal(require("nupp.runtime.standardio").value, io)
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
        local same, value, shadow = assert(loadstring(code))()
        test.equal(same, true)
        test.equal(value, 29)
        test.equal(shadow, 17)
        test.equal(require("nupp.runtime.standardcoroutine").value, coroutine)
    end)
end

function M.ordinaryCoroutineMembersDoNotLoadExtensions()
    withExtension(function(env)
        local code = compile("return coroutine.running", "ordinary-coroutine-consumer.nupp", env)
        test.equal(code:find('require("nupp.runtime.standardcoroutine")', 1, true), nil)
        test.equal(assert(loadstring(code))(), coroutine.running)
        test.equal(package.loaded["nupp.runtime.standardcoroutine"], nil)
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
            test.equal(parsed.effects["runtime.time"], true, "the deadline carries the clock provider")
        end
        local _, ordinary = compile(
            [[
local coroutine = {scope = function(limit: integer?, timeoutMs: number?): nil return end}
coroutine.scope(nil, 1)
]],
            "shadow-scope-consumer.nupp",
            env
        )
        test.equal(ordinary.effects["runtime.time"], nil)
    end)
end

return M
