local test = require("assert")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd")); HERE = pipe:read("*l") .. "/" .. HERE; pipe:close()
end
local M = {}
local function write(path, text)
    local f = assert(io.open(path, "wb")); f:write(text); f:close()
end
function M.blockSpanGuardsRejectBeforeExecutingTheBody()
    local dir = os.tmpname(); os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    write(dir .. "/src/guarded.nupp", [[
module guarded
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
@aot
local function dot(borrows left: span.Span<number>, borrows right: span.Span<number>): number
    assert(#left == #right)
    local result = simd.reducer.orderedDot(0.0)
    @simd
    for i = 1, #left do result:add(left[i], right[i]) end
    return result:value()
end
@aot
local function fill(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): number
    if #output ~= #input then error("length mismatch", 2) end
    local total = 0.0
    for i = 1, #input do
        output[i] = input[i]
        total = total + input[i]
    end
    return total
end
export = {dot = dot, fill = fill}
]])
    write(dir .. "/check.lua", [[
package.path = "build/native/?.lua;" .. package.path
local m = require("guarded")
local ffi = require("ffi")
local span = require("nupp.mem.span")
if arg[1] == "require" then
    for name, fn in pairs(m) do assert(__nuppAotCompiled[fn], name .. " is interpreted") end
end
local a, b, out = ffi.new("double[5]", {1, 2, 3, 4, 5}), ffi.new("double[5]", {2, 3, 4, 5, 6}), ffi.new("double[5]")
local left, right = span.fromCarray(a, 5), span.fromCarray(b, 5)
assert(m.dot(left, right) == 70)
assert(m.dot(span.fromCarray(a, 0), span.fromCarray(b, 0)) == 0)
assert(not pcall(m.dot, left, span.fromCarray(b, 4)))
assert(not pcall(m.dot, span.fromCarray(a, 4), right))
out[0] = -99
assert(not pcall(m.fill, span.writeCarray(out, 4), right))
assert(out[0] == -99, "body executed before the guard")
assert(m.fill(span.writeCarray(out, 5), right) == 20 and out[0] == 2)
print("block guards match")
]])
    for _, policy in ipairs({"off", "require"}) do
        write(dir .. "/nupp.lua", ('return {include={"src"}, build={targets={native={kind="modules",entries={"guarded"},outDir="build/native",aot=%q}}}}'):format(policy))
        local logPath = dir .. "/build.log"
        local status = os.execute(("cd %q && %q build --target native > %q 2>&1"):format(dir, HERE .. "/../bin/nupp", logPath))
        local f = assert(io.open(logPath, "rb")); local log = f:read("*a"); f:close()
        test.equal(status, 0, policy .. " build at " .. dir .. ": " .. log)
        local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
        local result = pipe:read("*a"); pipe:close()
        test.equal(result:gsub("%s+$", ""), "block guards match", policy .. " at " .. dir)
    end
end
return M
