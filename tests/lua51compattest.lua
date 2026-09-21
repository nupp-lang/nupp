local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")
local compat = require("nupp.compiler.compat")
local env = envMod.new("tests", {cache = false})
local M = {}

local function checked(source, options)
    local result = parser.parse(source, "compat.g.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    local diags = check.check(result, "compat.g.nupp", env, options or {compat = "lua51"})
    return result, diags
end

local function errors(diags)
    local found = {}
    for _, diag in ipairs(diags) do
        if diag.severity == nil or diag.severity == "error" then
            found[#found + 1] = diag.code .. ": " .. diag.msg
        end
    end

    return table.concat(found, "\n")
end

function M.rejectsAuthoredExtensionsBeforeOptimization()
    for _, source in ipairs({
        "const x = 1; return x",
        "local x = 1; x += 1; return x",
        "return 1 << 2",
        "return 3 // 2",
        "return true ? 1 : 2",
        "local x = {}; return x?.name",
        "return nil ?? 1",
        "return |x| -> x",
        "return !true",
        "return true && false",
        "return 1_000",
        "return 1ULL",
        "return 0x1p2",
        [[return "\x41"]],
        [[print "\x41"]],
        [[local x: any = {}; return x?.:go()]],
        [[return "a\z  b"]],
        "for i = 1, 2 do continue end",
        "goto done; ::done:: return 1",
        "if false then local x = 2ULL end; return 1",
    }) do
        local _, diags = checked(source)
        assert(errors(diags):find("NUPP3013", 1, true), source .. "\n" .. errors(diags))
    end
end

function M.acceptsOrdinaryTypedCodeWithoutDifferentEmission()
    local source = [[
local function values<T>(value: T, ...: number): (T, number)
    local total = 0
    for _, item in ipairs({...}) do total = total + item end
    return value, total
end
local text, total = values("ready", 2, 3)
return text, total
]]
    for level = 0, 2 do
        local result, diags = checked(source)
        assert(errors(diags) == "", errors(diags))
        assert(result.dialect == "luajit")
        optimize.run(result, {level = level})
        local code, generated = gen.generate(result, "compat.g.nupp")
        assert(errors(generated) == "", errors(generated))
        local native = checked(source, {dialect = "luajit"})
        optimize.run(native, {level = level})
        local ordinary = gen.generate(native, "compat.g.nupp")
        assert(code == ordinary, "compatibility must not select alternate emission")
        local label, total = assert(loadstring(code))()
        assert(label == "ready" and total == 5)
    end
end

function M.runtimeIdentitiesSurviveAliasesAndAny()
    for _, source in ipairs({
        "return jit.status()",
        "local b: any = bit; return b.bor(1, 2)",
        "local t: any = table; return t.new(1, 2)",
        "local s = string; return s.buffer",
        "return require('bit')",
        "return require('ffi')",
        "return require('string.buffer')",
        "return _G.jit",
        "return require('table.new')",
        "local t: any = (table as any); return t['new'](1, 2)",
        "local t: any; t = table; return t.new(1, 2)",
        "return rawget(_G, 'jit')",
        "return table:new()",
        "return rawget(table, 'new')",
        "local g = getfenv(); return g.jit",
    }) do
        local _, diags = checked(source)
        assert(errors(diags):find("NUPP3014", 1, true), source .. "\n" .. errors(diags))
    end
end

function M.sameNamedApplicationValuesRemainOrdinary()
    local _, diags = checked(
        [[
local bit = {bor = function(a, b) return a + b end}
local jit = {status = function() return true end}
local table = {new = function() return {} end}
return bit.bor(1, 2), jit.status(), table.new()
]]
    )
    assert(errors(diags) == "", errors(diags))
end

function M.unsafePermissionDoesNotRelaxCompatibility()
    for _, case in ipairs({
        {"return @unsafe 1ULL", "NUPP3013"},
        {"@unsafe do if false then local value = 2ULL end end", "NUPP3013"},
        {"return @unsafe require('ffi')", "NUPP3014"},
        {"local b: any = @unsafe bit; return b.bor(1, 2)", "NUPP3014"},
        {"local name: any = ...; return @unsafe require(name)", "NUPP3015"},
        {[[return @unsafe loadstring("return 2ULL")]], "NUPP3015"},
    }) do
        local _, diags = checked(case[1])
        local found = errors(diags)
        assert(found:find(case[2], 1, true), case[1] .. "\n" .. found)
    end
end

function M.unsafeAnnotationsPreserveCompatibleApplicationValuesAndEmission()
    local source = [[
@unsafe local bit = {bor = function(a: number, b: number): number return a + b end}
local jit = {status = function(): string return "application" end}
local function pair(): (number, number) return 4, 5 end
local a, b = @unsafe pair()
return @unsafe bit.bor(a, b), @unsafe jit.status()
]]
    for level = 0, 2 do
        local result, diags = checked(source)
        assert(errors(diags) == "", errors(diags))
        optimize.run(result, {level = level})
        local code, generated = gen.generate(result, "compat.g.nupp")
        assert(errors(generated) == "", errors(generated))
        local ordinary, ordinaryDiags = checked(source, {dialect = "luajit"})
        assert(errors(ordinaryDiags) == "", errors(ordinaryDiags))
        optimize.run(ordinary, {level = level})
        assert(code == gen.generate(ordinary, "compat.g.nupp"), "unsafe permission must not select alternate emission")
        local sum, label = assert(loadstring(code))()
        assert(sum == 9 and label == "application")
    end
end

function M.stock51SurfaceIsNotTheOldIntersection()
    local _, diags = checked(
        "local environment = getfenv(); local loaders = package.loaders; return unpack, setfenv, math.ldexp, table.maxn, io.stdout.write"
    )
    assert(errors(diags) == "", errors(diags))
end

function M.rejectsOpaqueDependenciesAndDynamicCode()
    for _, source in ipairs({
        "local name: any = ...; return require(name)",
        "local name: any = ...; return require(name, 'values')",
        "local r = require; return r('some_unseen_native_module')",
        "return require('some_unseen_native_module')",
        "local native = package.loadlib; return native('opaque.so', 'open')",
        "local loader = loadstring; local source: any = ...; return loader(source)",
    }) do
        local _, diags = checked(source)
        assert(errors(diags):find("NUPP3015", 1, true), source .. "\n" .. errors(diags))
    end
end

function M.rejectsRuntimeIdentitiesEscapingInspection()
    for _, source in ipairs({
        "local box: any = {table}; return box[1].new()",
        "local function invoke(f: any) return f('ffi') end; return invoke(require)",
        "return (function(t: any) return t.new() end)(table)",
        "return pcall(require, 'ffi')",
        "return debug.getregistry()",
        "return getfenv",
    }) do
        local _, diags = checked(source)
        assert(errors(diags):find("NUPP3015", 1, true), source .. "\n" .. errors(diags))
    end
end

function M.literalLoadsAreCheckedWithoutExecutingThem()
    local _, admitted = checked([[return loadstring("return 1")]])
    assert(errors(admitted) == "", errors(admitted))
    for _, source in ipairs({
        [[return loadstring("return jit.status()")]],
        [[return loadstring("return 2ULL")]],
        [[return loadstring("return require('ffi')")]],
        [[return loadstring("\027Lua")]],
        [[return xpcall(function(x) return x end, tostring, 42)]],
    }) do
        local _, diags = checked(source)
        assert(errors(diags):find("NUPP3015", 1, true), errors(diags))
    end
end

function M.compatibilityCannotSelectALowererOrBeDisabled()
    for _, value in ipairs({false, true, "", "luajit", "lua54", 1}) do
        local _, problem = compat.resolve(value)
        assert(problem, tostring(value))
    end
    for _, dialect in ipairs({"lua51", "luajit-compat"}) do
        local _, problem = compat.resolve("lua51", nil, dialect)
        assert(problem, dialect)
    end
    assert(compat.resolve(nil, "lua51", "luajit") == "lua51")
end

function M.generatedOutputGuardDoesNotNeedAStockVm()
    for _, source in ipairs({
        "const x = 1",
        "return 1ULL",
        "return 1 << 2",
        "return x?.name",
        "local x: number = 1",
        "local {x} = value",
        "local function f(borrows x) end",
        "local function f(...rest) end",
        "return 1; print(2)"
    }) do
        assert(#compat.generated(source, "test") > 0, source)
    end
    assert(#compat.generated([[return "\\x41", 0xff, 1.5e2]], "test") == 0)
end

local function inProject(callback)
    local fs = require("nupp.compiler.fs")
    local root = os.tmpname()
    os.remove(root)
    assert(fs.mkdir(root))

    local function write(name, source)
        assert(fs.writeFile(root .. "/" .. name, source))
    end

    local ok, problem = pcall(callback, root, write)
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, problem)
end

function M.explicitPureLuaBitLibraryRemainsAnOrdinaryDependency()
    inProject(function(root, write)
        local fs = require("nupp.compiler.fs")
        local source = assert(fs.readFile("src/nupp/runtime/provider/scalarbitops.nupp"))
        -- Reuse the actual arithmetic implementation through an application's
        -- public module; the repository provider itself has an internal API.
        source = source:gsub("@!internal", ""):gsub("module nupp.runtime.provider.scalarbitops", "module bits")
        write("bits.nupp", source)
        write("nupp.lua", 'return {compat="lua51",include={"."}}')
        write("main.g.nupp", 'local bits = require("bits"); return bits.bor(1,2)')
        local options = {diagnostics = {}, produced = {}}
        assert(require("nupp.compiler.build.project").check(root, options) == 0, errors(options.diagnostics))
    end)
end

function M.incrementalDependenciesRecheckCompatibilityAfterBodyEdits()
    inProject(function(root, write)
        write("nupp.lua", 'return {compat="lua51", include={"."}}')
        write("dep.g.nupp", 'local value = 1; return {value=value}')
        write("main.g.nupp", 'local dep = require("dep"); return dep.value')
        local inc = require("nupp.compiler.incremental").new(root, {cache = false})
        assert(inc.env.compat == "lua51")
        assert(errors(inc.checkFile(root .. "/main.g.nupp").diags) == "")
        inc.changeDocument(root .. "/dep.g.nupp", 'const value = 1; return {value=value}')
        local invalid = errors(inc.checkFile(root .. "/main.g.nupp").diags)
        assert(invalid:find("NUPP3015", 1, true), invalid)
        inc.changeDocument(root .. "/dep.g.nupp", 'local value = 1; return {value=value}')
        assert(errors(inc.checkFile(root .. "/main.g.nupp").diags) == "")
    end)
end

function M.projectCacheCannotReuseAnUnrestrictedVerdict()
    inProject(function(root, write)
        write("nupp.lua", 'return {include={"."}, build={kind="modules",outDir="build"}}')
        write("main.g.nupp", 'const value = 1; return value')
        local project = require("nupp.compiler.build.project")
        local ordinary = {diagnostics = {}, produced = {}}
        assert(project.check(root, ordinary) == 0, errors(ordinary.diagnostics))
        local constrained = {compat = "lua51", diagnostics = {}, produced = {}}
        assert(project.check(root, constrained) == 1)
        assert(errors(constrained.diagnostics):find("NUPP3013", 1, true))
        local again = {diagnostics = {}, produced = {}}
        assert(project.check(root, again) == 0, errors(again.diagnostics))
        write("nupp.lua", 'return {compat="lua51", include={"."}}')
        local inherited = {diagnostics = {}, produced = {}}
        assert(project.check(root, inherited) == 1)
        assert(errors(inherited.diagnostics):find("NUPP3013", 1, true))
    end)
end

function M.apiCompatibilityDoesNotTrustAnUnrestrictedDependencyCache()
    inProject(function(root, write)
        write("nupp.lua", 'return {include={"."}}')
        write("dep.g.nupp", 'const value = 1; return {value=value}')
        local projectEnv = envMod.new(root, {cache = false})
        local source = 'local dep = require("dep"); return dep.value'
        local path = root .. "/main.g.nupp"
        assert(errors(check.check(parser.parse(source, path), path, projectEnv)) == "")
        local diags = check.check(parser.parse(source, path), path, projectEnv, {compat = "lua51"})
        assert(errors(diags):find("NUPP3015", 1, true), errors(diags))
    end)
end

function M.multipleOwnersUseTheStock51ProtectedCallContract()
    local source = [[
local closed = {}
local record Guard value: number end
local function close(takes guard: Guard): nil
    closed[#closed + 1] = guard.value
end
local function acquire(value: number, fail: boolean): affine(Guard, close)
    if fail then error("acquisition failed") end
    return new Guard(value = value)
end
local function work(fail: boolean): number
    local first = acquire(1, false)
    local second = acquire(2, fail)
    return first.value + second.value
end
local answer = work(false)
local ok = pcall(work, true)
return answer, ok, table.concat(closed, ",")
]]
    local result, diags = checked(source)
    assert(errors(diags) == "", errors(diags))
    local code, generated = gen.generate(result, "compat.g.nupp")
    assert(errors(generated) == "", errors(generated))
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.xpcall = function(body, handler, ...)
        assert(select("#", ...) == 0, "compatible cleanup forwarded LuaJIT-only xpcall arguments")
        return xpcall(body, handler)
    end
    local chunk = assert(loadstring(code))
    setfenv(chunk, environment)
    local answer, ok, closed = chunk()
    assert(answer == 3 and ok == false and closed == "2,1,1", tostring(closed))
end

function M.cleanupRejectsTransitiveSuspensionWithoutAnAuthoredYield()
    local source = [[
local record Guard value: number end
local function close(takes guard: Guard): nil end
local function acquire(): affine(Guard, close) return new Guard(value=1) end
local function work(fail: boolean): number
    with item = acquire() do
        if fail then error("failure") end
        return item.value
    end
end
return work(false)
]]
    for _, feature in ipairs({
        "runtime.http",
        "runtime.net",
        "runtime.tls",
        "runtime.process",
        "runtime.time",
        "runtime.workers"
    }) do
        local result, diags = checked(source)
        assert(errors(diags) == "", errors(diags))
        -- Isolate the emitted effect boundary from each facade's separate
        -- source/runtime eligibility; the authored cleanup does not yield.
        local _, generated = gen.generate(result, "compat.g.nupp", nil, nil, nil, {[feature] = true})
        local message = errors(generated)
        assert(message:find(feature .. " -> runtime.suspension", 1, true), message)
    end
end

return M
