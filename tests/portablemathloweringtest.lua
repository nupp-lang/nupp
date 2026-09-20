local M = {}
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local env = require("nupp.compiler.env").new("tests")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")

local function generated(source, dialect, level)
    local result = parser.parse(source, "portable-math.g.nupp")
    assert(#result.errors == 0)
    local diagnostics = check.check(result, "portable-math.g.nupp", env, {dialect=dialect})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    optimize.run(result, {level=level, dialect=dialect})
    local code, errors = gen.generate(result, "portable-math.g.nupp")
    assert(#errors == 0)
    local included = false
    for _, name in ipairs(gen.runtimeModules(code)) do
        if name == "nupp.runtime.portablemath" then included = true end
    end
    return code, included
end

function M.portableLogAliasesCallbacksAndModuleIdentityShareTheAdapter()
    local source = [[
local library = math
local logarithm = library.log
local trace = ""
local function argument(value: number): number
    trace = trace .. tostring(value)
    return value
end
local function invoke(callback: function(number, number?): number): number
    return callback(argument(8), argument(2))
end
local value = invoke(logarithm)
assert(trace == "82", "operands evaluate once in source order")
assert(math.abs(value - 3) < 1e-12, "the optional base is honored")
assert(logarithm(1) == 0)
assert(logarithm == math.log, "every resolved read keeps function identity")
return logarithm
]]
    for _, level in ipairs({0, 2}) do
        local portable, included = generated(source, "lua51", level)
        assert(included, "the generated runtime dependency must be discoverable")
        local native, nativeIncluded = generated(source, "luajit", level)
        assert(not nativeIncluded, "native math keeps the host identity")
        local first = assert(loadstring(portable))()
        local other = generated("return math.log", "lua51", level)
        local second = assert(loadstring(other))()
        assert(first == second, "separately generated modules share one adapter")
        assert(first(1, nil) == 0, "the portable adapter accepts an explicit nil base")
        -- The native identity control retains the host's explicit-nil rejection.
        assert(assert(loadstring(native))() == math.log)
        local shadow, shadowIncluded = generated([[
local math = {log=function(_value: number, _base: number?): number return 42 end}
return math.log(8, 2)
]], "lua51", level)
        assert(not shadowIncluded and assert(loadstring(shadow))() == 42)
    end
end

function M.portableLogReadsKeepReassignedAliasesAndReplacedFields()
    local sources = {
        [[local library = math
library = {log=function(_value: number, _base: number?): number return 43 end} as any
return library.log(8, 2)]],
        [[local original = math.log
math.log = (function(_value: number, _base: number?): number return 43 end) as any
local answer = math.log(8, 2)
math.log = original
return answer]],
    }
    for _, level in ipairs({0, 2}) do
        for _, source in ipairs(sources) do
            local code = generated(source, "lua51", level)
            local original = math.log
            local ok, answer = pcall(assert(loadstring(code)))
            math.log = original
            assert(ok and answer == 43, tostring(answer))
        end
    end
end

function M.aModuleReplacingLogBeforeItsFirstReadKeepsTheReplacement()
    local writer = generated([[
math.log = (function(_value: number, _base: number?): number return 43 end) as any
return true
]], "lua51", 0)
    local reader = generated("return math.log(8, 2)", "lua51", 0)
    local original, cached = math.log, package.loaded["nupp.runtime.portablemath"]
    package.loaded["nupp.runtime.portablemath"] = nil
    local ok, answer = pcall(function()
        assert(loadstring(writer))()
        return assert(loadstring(reader))()
    end)
    math.log = original
    package.loaded["nupp.runtime.portablemath"] = cached
    assert(ok and answer == 43, tostring(answer))
end

function M.aQualifiedFunctionDeclarationPrebindsThePortableMathBaseline()
    for _, level in ipairs({0, 2}) do
        local writer = generated([[
function math.log(_value: number, _base: number?): number return 43 end
return true
]], "lua51", level)
        local reader = generated("return math.log(8, 2)", "lua51", level)
        local original, cached = math.log, package.loaded["nupp.runtime.portablemath"]
        package.loaded["nupp.runtime.portablemath"] = nil
        local ok, answer = pcall(function()
            assert(loadstring(writer))()
            return assert(loadstring(reader))()
        end)
        math.log = original
        package.loaded["nupp.runtime.portablemath"] = cached
        assert(ok and answer == 43, tostring(answer))
    end
end

function M.aModuleReplacingTheMathTableKeepsItsLogFunction()
    local writers = {
        [[math = {log=function(_value: number, _base: number?): number return 43 end} as any
return true]],
        [[local function replace(library: any): nil
    library.log = function(_value: number, _base: number?): number return 43 end
end
replace(math)
return true]],
    }
    for _, source in ipairs(writers) do
    local writer = generated(source, "lua51", 0)
    local reader = generated("return math.log(8, 2)", "lua51", 0)
    local original, originalLog, cached = math, math.log, package.loaded["nupp.runtime.portablemath"]
    package.loaded["nupp.runtime.portablemath"] = nil
    local ok, answer = pcall(function()
        assert(loadstring(writer))()
        return assert(loadstring(reader))()
    end)
    math = original
    math.log = originalLog
    package.loaded["nupp.runtime.portablemath"] = cached
    assert(ok and answer == 43, tostring(answer))
    end
end

function M.safeLogReadsKeepAdapterIdentityAndNilShortCircuiting()
    local source = [[
local type Log = nosuspend function(number, number?): number
local function selectLog(present: boolean): Log?
    local library: {log: Log}? = math
    if not present then library = nil end
    return library?.log
end
local logarithm = selectLog(true)
assert(logarithm ~= nil and logarithm == math.log, "safe and ordinary reads share the adapter")
if logarithm then assert(math.abs(logarithm(8, 2) - 3) < 1e-12) end
assert(selectLog(false) == nil, "a nil receiver remains nil")
local library = math
local original = math.log
local reads = 0
library = setmetatable({}, {__index=function(_object: any, _key: string): any
    reads = reads + 1
    return original
end}) as any
assert(library?.log == original and reads == 1, "the actual field is read once")
return true
]]
    for _, level in ipairs({0, 2}) do
        local code = generated(source, "lua51", level)
        assert(assert(loadstring(code))())
    end
end

function M.typedLogFieldsKeepTheirContractAcrossParametersAndReturns()
    local source = [[
local type Log = nosuspend function(number, number?): number
local type Library = {log: Log}
local function through(library: Library): Library return library end
local function read(library: Library): Log return library.log end
local function safe(library: Library?): Log? return library?.log end
local visits = 0
local trace = ""
local function receiver(): Library visits = visits + 1; return math end
local function argument(value: number): number trace = trace .. tostring(value); return value end
local function invoke(library: Library): number return library.log(argument(8), argument(2)) end
assert(math.abs(invoke(receiver()) - 3) < 1e-12, "typed parameter honors the optional base")
assert(visits == 1 and trace == "82", "receiver and operands evaluate once in order")
assert(math.abs(through(math).log(8, 2) - 3) < 1e-12, "typed return honors the optional base")
assert(through(math) == math, "table identity is unchanged")
assert(read(math) == math.log and safe(math) == math.log, "field views preserve adapter identity")
assert(safe(nil) == nil, "safe reads preserve nil")
local type CustomLog = function(number, number?): number
local type CustomLibrary = {log: CustomLog}
local function readCustom(library: CustomLibrary): CustomLog return library.log end
local function custom(value: number, base: number?): number return value + (base or 0) end
local library: CustomLibrary = {log=custom}
assert(readCustom(library) == custom)
assert(readCustom(library)(8, 2) == 10, "custom functions are not normalized")
local function replacement(_value: number, _base: number?): number return 43 end
library.log = replacement
assert(readCustom(library) == replacement and readCustom(library)(8, 2) == 43, "mutations stay visible")
return true
]]
    for _, level in ipairs({0, 2}) do
        local code = generated(source, "lua51", level)
        local original, cached = math.log, package.loaded["nupp.runtime.portablemath"]
        -- Stock Lua 5.1 ignores the second argument. Reproduce that contract in
        -- the shared LuaJIT suite; the portable corpus also runs on real stock Lua.
        local host = function(value) return original(value) end
        math.log = host
        package.loaded["nupp.runtime.portablemath"] = nil
        local ok, answer = pcall(assert(loadstring(code)))
        local unchanged = math.log == host
        math.log = original
        package.loaded["nupp.runtime.portablemath"] = cached
        assert(ok and answer == true, tostring(answer))
        assert(unchanged, "portable lowering never writes the shared host library")
        local native, included = generated(source, "luajit", level)
        assert(not included and assert(loadstring(native))())
        assert(math.log == original, "native library identity is unchanged")
    end
end

function M.unrelatedTypedLogFieldsDoNotAcquireTheNumericAdapter()
    for _, signature in ipairs({"function(string): string", "function(number): number", "function(number, string?): number"}) do
        local source = "local type Log = " .. signature .. "\n"
            .. "local function read(library: {log: Log}): Log return library.log end\nreturn read\n"
        for _, level in ipairs({0, 2}) do
            local _, included = generated(source, "lua51", level)
            assert(not included, "an unrelated log field keeps its declared behavior")
        end
    end
end

function M.literalIndexingRemainsAPositionedTypedSurfaceRefusal()
    for _, access in ipairs({'math["log"]', 'library["log"]'}) do
        local source = "local library = math\nreturn " .. access .. "(8, 2)\n"
        local result = parser.parse(source, "literal-log.nupp")
        assert(#result.errors == 0)
        local diagnostics = check.check(result, "literal-log.nupp", env, {dialect="lua51"})
        local found = false
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.code == "NUPP2004" then
                assert(diagnostic.line == 2 and diagnostic.col > 0)
                found = true
            end
        end
        assert(found, "literal indexing of the typed math record is not an admitted field read")
    end
end

function M.injectedLogModuleRetainsItsCacheDependencyAndSourceFingerprint()
    local project = require("nupp.compiler.build.project")
    local json = require("testjson")
    local process = require("nupp.compiler.build.process")
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/src/nupp/runtime'") == 0)
    local function write(relative, text)
        local file = assert(io.open(root .. "/" .. relative, "wb"))
        file:write(text); file:close()
    end
    local function read(relative)
        local file = assert(io.open(root .. "/" .. relative, "rb"))
        local text = file:read("*a"); file:close(); return text
    end
    write("nupp.lua", [[return {include={"src"},build={kind="bundle",entries={"main"},outDir="out",output="out/app.lua",dialect="lua51"}}]])
    write("src/main.nupp", "return math.log(8, 2)\n")
    local adapter = [[module nupp.runtime.portablemath
export function log(_value: number, _base: number?): number return 101 end
export function logFunction(_value: any): any return log end
]]
    write("src/nupp/runtime/portablemath.nupp", adapter)
    assert(project.build(root) == 0)
    local first = json.decode(read("out/.nupp-state.json"))
    local included = false
    for _, name in ipairs(first.modules.main.runtimeModules) do
        included = included or name == "nupp.runtime.portablemath"
    end
    assert(included, "implicit adapter remains in persisted dependency inventory")
    local original = assert(first.modules["nupp.runtime.portablemath"])
    assert(original.sourceHash and original.artifactHash, "runtime source and artifact are fingerprinted")
    local function answer()
        local code, output = process.capture({"luajit", "-e", ("print(assert(loadfile(%q))())"):format(root .. "/out/app.lua")})
        assert(code == 0, output)
        return tonumber(output)
    end
    assert(answer() == 101)
    local warm = {}
    assert(project.build(root, {stats=warm}) == 0 and warm.generatedModules == 0)
    write("src/nupp/runtime/portablemath.nupp", adapter:gsub("101", "202"))
    assert(project.build(root) == 0)
    local second = json.decode(read("out/.nupp-state.json"))
    local changed = assert(second.modules["nupp.runtime.portablemath"])
    assert(changed.sourceHash ~= original.sourceHash and changed.artifactHash ~= original.artifactHash)
    assert(answer() == 202, "body edits reach the next bundle")
    os.execute("rm -rf '" .. root .. "'")
end

function M.portableBundleCarriesTheRealAdapterWithoutFilesystemLookup()
    local project = require("nupp.compiler.build.project")
    local json = require("testjson")
    local process = require("nupp.compiler.build.process")
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/src'") == 0)
    local function write(relative, text)
        local file = assert(io.open(root .. "/" .. relative, "wb"))
        file:write(text); file:close()
    end
    local function read(relative)
        local file = assert(io.open(root .. "/" .. relative, "rb"))
        local text = file:read("*a"); file:close(); return text
    end
    write("nupp.lua", [[return {include={"src"},build={kind="bundle",entries={"main"},outDir="out",output="out/app.lua",dialect="lua51"}}]])
    write("src/main.nupp", "local library = math\nlocal logarithm = library.log\nreturn logarithm(8, 2)\n")
    assert(project.build(root) == 0)
    local state = json.decode(read("out/.nupp-state.json"))
    local adapter = assert(state.modules["nupp.runtime.portablemath"], "the compiler-carried adapter is embedded")
    assert(adapter.sourceHash and adapter.artifactHash, "the carried adapter retains source and artifact fingerprints")
    local code, output = process.capture({"luajit", "-e", ("package.path=''; package.cpath=''; print(assert(loadfile(%q))())"):format(root .. "/out/app.lua")})
    assert(code == 0, output)
    assert(math.abs(assert(tonumber(output)) - 3) < 1e-12, output)
    local warm = {}
    assert(project.build(root, {stats=warm}) == 0 and warm.generatedModules == 0)
    os.execute("rm -rf '" .. root .. "'")
end

return M
