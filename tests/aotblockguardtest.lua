local test = require("assert")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"));
    HERE = pipe:read("*l") .. "/" .. HERE;
    pipe:close()
end
local M = {}

local function write(path, text)
    local f = assert(io.open(path, "wb"));
    f:write(text);
    f:close()
end

function M.blockSpanGuardsRejectBeforeExecutingTheBody()
    local dir = os.tmpname();
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    write(
        dir .. "/src/guarded.nupp",
        [[
module guarded
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
@aot
local function dot(borrows left: span.Span<number>, borrows right: span.Span<number>): number
    assert(#left == #right)
    local result = simd.reducer.orderedDot(0.0)
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
]]
    )
    write(
        dir .. "/check.lua",
        [[
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
]]
    )
    for _, policy in ipairs({"off", "require"}) do
        write(
            dir .. "/nupp.lua",
            (
                'return {include={"src"}, build={targets={native={kind="modules",entries={"guarded"},outDir="build/native",aot=%q}}}}'
            ):format(policy)
        )
        local logPath = dir .. "/build.log"
        local status = os.execute(
            ("cd %q && %q build --target native > %q 2>&1"):format(dir, HERE .. "/../bin/nupp", logPath)
        )
        local f = assert(io.open(logPath, "rb"));
        local log = f:read("*a");
        f:close()
        test.equal(status, 0, policy .. " build at " .. dir .. ": " .. log)
        local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
        local result = pipe:read("*a");
        pipe:close()
        test.equal(result:gsub("%s+$", ""), "block guards match", policy .. " at " .. dir)
    end
end

-- A guard relating two counts through a factor is checked at the call
-- boundary like any other, before the body runs, and the body it admits
-- reads the longer span as far as the factor carries.
function M.factorGuardsRejectAtTheCallBoundary()
    local dir = os.tmpname();
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    write(
        dir .. "/src/factored.nupp",
        [[
module factored
local span = require("nupp.mem.span")
@aot
local function box3(exclusive grey: span.WriteSpan<uint8>, borrows rgb: span.Span<uint8>): nil
    assert(#rgb == 3 * #grey)
    local at: uint32 = 0
    while at < #grey do
        grey[at + 1] = rgb[at + 1] + rgb[at + 2] + rgb[at + 3]
        at = at + 1
    end
end
@aot
local function padded(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): uint32
    if #output < 4 * #input + 2 then error("output too short", 2) end
    local i: uint32 = 0
    while i < #input do
        output[i + 1] = input[i + 1]
        output[i + 6] = 9
        i = i + 1
    end
    return i
end
export = {box3 = box3, padded = padded}
]]
    )
    write(
        dir .. "/check.lua",
        [[
package.path = "build/native/?.lua;" .. package.path
local m = require("factored")
local ffi = require("ffi")
local span = require("nupp.mem.span")
if arg[1] == "require" then
    for name, fn in pairs(m) do assert(__nuppAotCompiled[fn], name .. " is interpreted") end
end
local rgb = ffi.new("uint8_t[6]", {1, 2, 3, 4, 5, 6})
local grey = ffi.new("uint8_t[2]")
m.box3(span.writeCarray(grey, 2), span.fromCarray(rgb, 6))
assert(grey[0] == 6 and grey[1] == 9, "the window sums three bytes from each cursor")
grey[0] = 77
assert(not pcall(m.box3, span.writeCarray(grey, 2), span.fromCarray(rgb, 5)), "five is not three times two")
assert(not pcall(m.box3, span.writeCarray(grey, 1), span.fromCarray(rgb, 6)), "nor six three times one")
assert(grey[0] == 77, "body executed before the guard")
m.box3(span.writeCarray(grey, 0), span.fromCarray(rgb, 0))
local input = ffi.new("uint8_t[2]", {5, 6})
local output = ffi.new("uint8_t[10]")
assert(m.padded(span.writeCarray(output, 10), span.fromCarray(input, 2)) == 2)
assert(output[0] == 5 and output[1] == 6 and output[5] == 9 and output[6] == 9, "writes land where the factor allows")
assert(not pcall(m.padded, span.writeCarray(output, 9), span.fromCarray(input, 2)), "nine is below 4 * 2 + 2")
print("factor guards match")
]]
    )
    for _, policy in ipairs({"off", "require"}) do
        write(
            dir .. "/nupp.lua",
            (
                'return {include={"src"}, build={targets={native={kind="modules",entries={"factored"},outDir="build/native",aot=%q}}}}'
            ):format(policy)
        )
        local logPath = dir .. "/build.log"
        local status = os.execute(
            ("cd %q && %q build --target native > %q 2>&1"):format(dir, HERE .. "/../bin/nupp", logPath)
        )
        local f = assert(io.open(logPath, "rb"));
        local log = f:read("*a");
        f:close()
        test.equal(status, 0, policy .. " build at " .. dir .. ": " .. log)
        local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
        local result = pipe:read("*a");
        pipe:close()
        test.equal(result:gsub("%s+$", ""), "factor guards match", policy .. " at " .. dir)
    end
end

return M
