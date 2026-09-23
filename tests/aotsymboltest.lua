-- Private declarations from different source modules share one output library.
local M = {}
local equivalenceMutation = require("tests.simd.equivalence-mutation")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = assert(pipe:read("*l")) .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function write(path, value)
    local file = assert(io.open(path, "wb"))
    file:write(value)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

function M.samePrivateNamesInDistinctModulesLinkAndExecuteIndependently()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. quote(dir .. "/src")) == 0)
    write(
        dir .. "/nupp.lua",
        [[
return {include={"src"},build={targets={native={kind="modules",
entries={"first", "second"},outDir="build/native",aot="require"}}}}
]]
    )
    for index, name in ipairs({"first", "second"}) do
        write(
            dir .. "/src/" .. name .. ".nupp",
            (
                [=[
@aot
local function same(value: int32): int32
    return value + %d
end
return {same = same}
]=]
            ):format(index * 17)
        )
    end
    local build = "cd " .. quote(dir) .. " && " .. quote(ROOT .. "/bin/nupp") .. " build --target native"
    local status = os.execute(build .. " >" .. quote(dir .. "/build.log") .. " 2>&1")
    assert(status == 0, "preserved " .. dir .. "/build.log\n" .. read(dir .. "/build.log"))
    local runSource = [[
package.path = "build/native/?.lua;" .. package.path
jit.off()
local first, second = require("first"), require("second")
local registry = assert(rawget(_G, "__nuppAotCompiled"))
local calls = 0
for _, module in ipairs({first, second}) do
    assert(registry[module.same], "missing native replacement")
    local found = false
    for at = 1, 128 do
        local name, native = debug.getupvalue(module.same, at)
        if not name then break end
        if name:match("^ks_.*_native$") and type(native) == "cdata" then
            debug.setupvalue(module.same, at, function(...)
                local answer = native(...)
                calls = calls + 1
                return answer
            end)
            found = true
        end
    end
    assert(found, "missing native entry")
end
assert(first.same(5) == 22)
assert(second.same(5) == 39)
assert(first.same(-5) == 12)
assert(second.same(-5) == 29)
assert(calls == 4, "both modules must execute their own native entry")
]]
    runSource = equivalenceMutation.text(
        "symbol-collisions",
        runSource,
        "second%.same%(5%) == 39",
        "second.same(5) == 22"
    )
    write(dir .. "/run.lua", runSource)
    local run = "cd " .. quote(dir) .. " && luajit run.lua"
    status = os.execute(run .. " >" .. quote(dir .. "/run.log") .. " 2>&1")
    assert(
        status == 0,
        equivalenceMutation.active("symbol-collisions")
        and equivalenceMutation.marker("symbol-collisions", "artifact-identity-mismatch")
        or "preserved " .. dir .. "/run.log\n" .. read(dir .. "/run.log")
    )
end

return M
