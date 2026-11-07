local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local json = fixture.json
local write = fixture.write
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local libraryName = fixture.libraryName
local setEnvironment = fixture.setEnvironment

local M = {}

--- One `@aot` entry calling another of the same file reaches that entry's own
--- symbol, qualified by its file and spelled for the tier being built. The
--- call used to name an unqualified symbol nothing defined, so the program
--- failed to link.
function M.anAotEntryCallsAnotherEntryOfItsFile()
    if jit.os == "Windows" then
        return
    end
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
local array = table.Array
local span = require("bytes.span")

@aot
local function curve(x: number): number
   return x * x + 1
end

@aot
local function total(borrows values: span.Span<float>): number
   local sum = 0.0
   for index = 1, #values do
      sum = sum + curve(values[index])
   end
   return sum
end

local values = array.scalar(array.float, 4)
do
   local writable = values:write()
   for index = 1, 4 do
      writable[index] = index
   end
   own.drop(writable)
end
print(curve(3), total(values:read()))
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "binary",
      stub = "nupp", standalone = true, aot = "require", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/app")
    )
    testAssert.eq(project.build(dir), 0)
    local ran, text = process.capture({dir .. "/out/app" .. (jit.os == "Windows" and ".exe" or "")})
    testAssert.eq(ran, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "10\t34", "the calling entry reached the called one")
    remove(dir)
end

function M.staticAotComponentProducesAnArchiveAndDefaultNamespaceBinding()
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
@aot
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do result = result + index end
   return result
end
return {triangular = triangular}
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/component.lua")
    )
    testAssert.eq(project.build(dir), 0)
    assert(exists(dir .. "/out/lib/libdefault_aot.a"), "static component AOT emits an archive")
    assert(not read(dir .. "/out/component.lua"):find('from"@lib/', 1, true), "static component binds through ffi.C")
    remove(dir)
end

function M.staticAotComponentRegistersLuaBuildersThroughTheHost()
    local dir = tempProject({
        ["src/main.nupp"] = [[
@aot
local function make(): {string: any} return {ready = true} end
return {make = make}
]]
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/component.lua")
    )
    testAssert.eq(project.build(dir), 0)
    local component = read(dir .. "/out/component.lua")
    assert(component:find("__nuppAotBuilderModules", 1, true), "static builder reads host registration")
    assert(not component:find("package.loadlib", 1, true), "static builder does not dynamically load")

    -- The host calls a tier-spelled registrar and registers what it returns
    -- under the unsuffixed key the wrapper reads. The manifest names both.
    local link = json.decode(assert(read(dir .. "/out/aot/link.json")))
    testAssert.eq(#link.builders, 1, "the one Lua-building entry is a registration the host owes")
    local builder = link.builders[1]
    testAssert.eq(builder.entry, "make", "named after the entry it stands for")
    assert(component:find(builder.key, 1, true), "the wrapper reads the registry key")
    assert(
        builder.symbols[1]:find(builder.key, 1, true) and builder.symbols[1] ~= builder.key,
        "and the host calls a tier spelling of it: " .. builder.symbols[1]
    )
    remove(dir)
end

function M.staticAotComponentCarriesAProbeAndALinkManifest()
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
@aot
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do result = result + index end
   return result
end
return {triangular = triangular}
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/component.lua")
    )
    testAssert.eq(project.build(dir), 0)

    local link = json.decode(assert(read(dir .. "/out/aot/link.json")))
    testAssert.eq(link.schemaVersion, 1, "the host handoff is versioned")
    testAssert.eq(link.component, "default", "and names the component it describes")
    testAssert.eq(link.archive, "lib/libdefault_aot.a", "and the archive to retain")
    local probe = link.fingerprint.symbol
    assert(probe:find("^ks_aot_archive_"), probe)
    testAssert.eq(link.symbols.probe, probe, "the probe is among the symbols to export")
    assert(#link.symbols.kernels > 0, "so is every kernel")
    assert(#link.retain.forceLoad > 0, "a desktop linker extracts nothing from an archive nothing references")

    local ir = assert(read(dir .. "/out/aot/archive.ll"), "the probe is emitted as LLVM IR")
    assert(ir:find("define i64 @" .. probe .. "()", 1, true), ir)
    assert(
        ir:find("ret i64 " .. ("%d"):format(link.fingerprint.value), 1, true),
        "the probe returns exactly what the manifest says it does"
    )

    -- The check stands ahead of every declaration in the module, because a
    -- kernel `cdef` binds eagerly too and would raise LuaJIT's own message first.
    local module = assert(read(dir .. "/out/main.lua"))
    local at = module:find(probe, 1, true)
    -- The interpreted runtime-mode probe shares the stem but binds no C symbol.
    local kernel = module:find("ks_[0-9a-f]+_triangular__")
    assert(at and kernel and at < kernel, "the archive probe is checked first")
    assert(module:find("was not linked into the host", 1, true), "a missing probe says the archive was not linked")
    assert(
        module:find("is not the one this module was compiled against", 1, true),
        "and a mismatched one says which failure it is"
    )
    remove(dir)
end

function M.staticAotIsRefusedForATargetThatHasNoArchiveToLink()
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
@aot
local function double(value: number): number return value * 2.0 end
return {double = double}
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", aotTarget = "wasm32-unknown-emscripten",
      outDir = %q, output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/component.lua")
    )
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local code = project.build(dir)
    io.stderr:close()
    io.stderr = originalStderr
    local reported = read(errorPath) or ""
    os.remove(errorPath)
    assert(code ~= 0, "a target with no static archive cannot take static linkage")
    assert(reported:find("produces static AOT archives", 1, true), reported)
    remove(dir)
end

return M
