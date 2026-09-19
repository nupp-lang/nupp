-- Loop condition blocks must execute exactly once for each live lane/test.
local test = require("assert")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local NUPP = HERE .. "/../bin/nupp"
local M = {}
local SOURCE = [[
module conditions
local span = require("nupp.mem.span")
@aot
local function before(exclusive output: span.WriteSpan<number>, exclusive checks: span.WriteSpan<number>, borrows limits: span.Span<number>): nil
    assert(#output == #limits and #checks == #limits)
    @simd
    for i = 1, #output do
        local count, total = 0.0, 0.0
        while do
            checks[i] = checks[i] + 1.0
            count = count + 1.0
            local keep = count <= limits[i]
            yield keep
        end do
            if count == 2.0 then continue end
            if count == 4.0 then break end
            total = total + count
        end
        output[i] = total * 100.0 + count
    end
end
@aot
local function after(exclusive output: span.WriteSpan<number>, exclusive checks: span.WriteSpan<number>, borrows limits: span.Span<number>): nil
    assert(#output == #limits and #checks == #limits)
    @simd
    for i = 1, #output do
        local count, total = 0.0, 0.0
        repeat
            count = count + 1.0
            if count == 2.0 then continue end
            if count == 4.0 then break end
            total = total + count
        until do
            checks[i] = checks[i] + 1.0
            local done = count >= limits[i]
            yield done
        end
        output[i] = total * 100.0 + count
    end
end
@aot
local function enclosing(exclusive output: span.WriteSpan<number>, borrows limits: span.Span<number>): nil
    assert(#output == #limits)
    @simd
    for i = 1, #output do
        local count, total = 0.0, 0.0
        while count < limits[i] do
            count = count + 1.0
            while do
                if count == 2.0 then continue end
                if count == 4.0 then break end
                local stop = false
                yield stop
            end do
                total = total + 1000.0
            end
            total = total + count
        end
        output[i] = total * 100.0 + count
    end
end
@aot
local function uniform(exclusive output: span.WriteSpan<number>): nil
    @simd
    for i = 1, #output do
        local count, checks = 0.0, 0.0
        while do
            checks = checks + 1.0
            local keep = count < 5.0
            yield keep
        end do
            count = count + 1.0
            if count == 3.0 then break end
        end
        output[i] = count * 100.0 + checks
    end
end
export = {before = before, after = after, enclosing = enclosing, uniform = uniform}
]]
local SCRIPT = [[
local m = require("conditions")
local ffi = require("ffi")
local span = require("nupp.mem.span")
if arg[1] == "require" then
    local compiled = assert(rawget(_G, "__nuppAotCompiled"), "missing native registry")
    for name, fn in pairs(m) do assert(compiled[fn], name .. " was not compiled") end
end
local function oracle(limit, repeated)
    local count, total, checks = 0, 0, 0
    while true do
        if not repeated then
            checks = checks + 1
            count = count + 1
            if count > limit then break end
        else
            count = count + 1
        end
        if count == 4 then break end
        if count ~= 2 then total = total + count end
        if repeated then
            checks = checks + 1
            if count >= limit then break end
        end
    end
    return total * 100 + count, checks
end
for count = 0, 37 do
    local input = ffi.new("double[?]", math.max(1, count))
    local output = ffi.new("double[?]", count + 4)
    local checks = ffi.new("double[?]", count + 4)
    for i = 0, count - 1 do input[i] = i % 7 - 1 end
    local out = span.writeCarray(output, count)
    local calls = span.writeCarray(checks, count)
    local limits = span.fromCarray(input, count)
    for _, name in ipairs({"before", "after"}) do
        for i = 0, count + 3 do output[i], checks[i] = -99, 0 end
        m[name](out, calls, limits)
        for i = 0, count - 1 do
            local value, visits = oracle(input[i], name == "after")
            assert(output[i] == value, name .. " output lane " .. i .. ": " .. output[i] .. " vs " .. value)
            assert(checks[i] == visits, name .. " condition lane " .. i .. ": " .. checks[i] .. " vs " .. visits)
        end
        for i = count, count + 3 do assert(output[i] == -99 and checks[i] == 0, "tail wrote outside span") end
    end
    m.enclosing(out, limits)
    for i = 0, count - 1 do
        local n, total = 0, 0
        while n < input[i] do
            n = n + 1
            if n == 4 then break end
            if n ~= 2 then total = total + n end
        end
        assert(output[i] == total * 100 + n, "condition exit did not target enclosing loop at " .. i)
    end
    m.uniform(out)
    for i = 0, count - 1 do assert(output[i] == 303, "break evaluated uniform condition again") end
end
print("condition results match")
]]
local function write(path, text)
    local f = assert(io.open(path, "wb")); f:write(text); f:close()
end
function M.statementfulConditionsPreserveLaneEvaluationAndOuterExits()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    write(dir .. "/src/conditions.nupp", SOURCE)
    write(dir .. "/check.lua", 'package.path="build/native/?.lua;"..package.path;\n' .. SCRIPT)
    for _, policy in ipairs({"off", "require"}) do
        write(dir .. "/nupp.lua", ('return {include={"src"}, build={targets={native={kind="modules",entries={"conditions"},outDir="build/native",aot=%q}}}}'):format(policy))
        local output = dir .. "/build.log"
        local status = os.execute(("cd %q && %q build --target native > %q 2>&1"):format(dir, NUPP, output))
        local f = assert(io.open(output, "rb")); local log = f:read("*a"); f:close()
        test.equal(status, 0, policy .. " build at " .. dir .. ": " .. log)
        local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
        local result = pipe:read("*a"); pipe:close()
        test.equal(result:gsub("%s+$", ""), "condition results match", policy .. " at " .. dir)
    end
end
return M
