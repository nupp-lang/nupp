-- Native-only `@aot` entries: a signature carrying a vector or a mask gets no Lua
-- wrapper, is called natively from other entries of its own module and of
-- others, and the module around it keeps its exports and its initialization.
--
-- Every case builds one project twice, under `aot = "off"` and `aot = "require"`,
-- and runs the same script against each: the answers have to agree, and only
-- the compiled build may refuse the Lua call.
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

local function read(path)
    local f = assert(io.open(path, "rb"));
    local text = f:read("*a");
    f:close()
    return text
end

local function project(files)
    local dir = os.tmpname();
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    for name, text in pairs(files) do
        write(dir .. "/" .. name, text)
    end
    return dir
end

-- Builds `dir` under `policy` and runs `check.lua` with the policy as its one
-- argument, answering the script's trimmed output.
local function buildAndRun(dir, entries, policy)
    write(
        dir .. "/nupp.lua",
        (
            'return {include={"src"}, build={targets={native={kind="modules",entries={%s},outDir="build/native",aot=%q}}}}'
        ):format(entries, policy)
    )
    local logPath = dir .. "/build.log"
    local status = os.execute(
        ("cd %q && rm -rf build && %q build --target native > %q 2>&1"):format(dir, HERE .. "/../bin/nupp", logPath)
    )
    test.equal(status, 0, policy .. " build at " .. dir .. ": " .. read(logPath))
    local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
    local result = pipe:read("*a");
    pipe:close()
    return (result:gsub("%s+$", "")), read(logPath)
end

local VEC = [[
module vec
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

--- Doubles every lane.
@aot
local function twice(value: simd.Vector<float, simd.Preferred>): simd.Vector<float, simd.Preferred>
    return value + value
end

--- The lanes above zero.
@aot
local function positive(value: simd.Vector<float, simd.Preferred>): simd.Mask<float, simd.Preferred>
    return value > 0.0
end

local loads = 0
loads = loads + 1

export = {twice = twice, positive = positive, loads = loads}
]]

local MAIN = [[
module main
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local vec = require("vec")
local twice = vec.twice

--- Four times each positive input, zero elsewhere: the alias and the member
--- both reach the native entry, and the mask entry drives the select.
@aot
local function quadruple(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#input) do
        local value = species:load(input, at, active)
        local keep = vec.positive(value)
        species:store(output, at, keep:select(vec.twice(twice(value)), species:splat(0.0)), active)
    end
end

export = {quadruple = quadruple, vec = vec}
]]

local CHECK = [[
package.path = "build/native/?.lua;" .. package.path
local m = require("main")
local ffi = require("ffi")
local span = require("nupp.mem.span")
local compiled = rawget(_G, "__nuppAotCompiled") or {}
local input = ffi.new("float[6]", {1, -2, 3, -4, 5, 6})
local output = ffi.new("float[6]")
m.quadruple(span.writeCarray(output, 6), span.fromCarray(input, 6))
local answers = {}
for i = 0, 5 do answers[#answers + 1] = tostring(output[i]) end
assert(table.concat(answers, " ") == "4 0 12 0 20 24", table.concat(answers, " "))
assert(m.vec.loads == 1, "the exporting module initialized once")
local calledFromLua, message = pcall(m.vec.twice, 1.5)
if arg[1] == "require" then
    assert(compiled[m.quadruple], "the caller is compiled")
    assert(not compiled[m.vec.twice] and not compiled[m.vec.positive], "a native-only entry is not a compiled Lua entry")
    assert(not calledFromLua and tostring(message):find("native%-only"), "the stub refuses a Lua call: " .. tostring(message))
else
    assert(calledFromLua and message == 3, "as Lua the entry is one lane wide: " .. tostring(message))
end
print("native-only agrees")
]]

-- A vector entry and a mask entry in one module, reached natively from another
-- module's entry through an alias and through the member, with the exporting
-- module's initialization intact and no Lua entry for either.
function M.vectorAndMaskEntriesLinkAcrossModulesWithoutALuaEntry()
    local dir = project{["src/vec.nupp"] = VEC, ["src/main.nupp"] = MAIN, ["check.lua"] = CHECK}
    for _, policy in ipairs({"off", "require"}) do
        local result, log = buildAndRun(dir, '"main"', policy)
        test.equal(result, "native-only agrees", policy .. " at " .. dir .. "\n" .. log)
    end
    local generated = read(dir .. "/build/native/vec.lua")
    assert(not generated:find("ks_%w*twice", 1), "no foreign declaration for a native-only entry:\n" .. generated)
    assert(generated:find("native%-only AOT entry"), "the stub stands where the declaration was:\n" .. generated)
    local caller = read(dir .. "/build/native/aot/src/main.neon.ll")
    assert(
        caller:find("call <4 x float> @ks_%x+_twice__neon%(<4 x float>"),
        "the caller names the exporting module's qualified symbol:\n" .. caller
    )
    assert(
        caller:find("call <4 x i1> @ks_%x+_positive__neon%(<4 x float>")
        or caller:find("call <4 x i1> @ks_%x+_positive__neon%(<4 x float>", 1, true),
        "the mask entry is called natively:\n" .. caller
    )
end

local FLOATS = [[
module floats
local span = require("nupp.mem.span")

--- One binary32 product.
@aot
local function scaleOne(value: float, factor: float): float
    return nupp.math.f32.mul(value, factor)
end

--- Every element through `scaleOne`, which another entry of this file calls
--- at its own width.
@aot
local function apply(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #input do
        output[i] = scaleOne(input[i], factor)
    end
end

export = {scaleOne = scaleOne, apply = apply}
]]

local FLOAT_CHECK = [[
package.path = "build/native/?.lua;" .. package.path
local m = require("floats")
local ffi = require("ffi")
local span = require("nupp.mem.span")
local input = ffi.new("float[4]", {1, 2, 3, 4})
local output = ffi.new("float[4]")
m.apply(span.writeCarray(output, 4), span.fromCarray(input, 4), 10)
local answers = {}
for i = 0, 3 do answers[#answers + 1] = tostring(output[i]) end
print(table.concat(answers, " "))
]]

-- A native call to a same-file entry with `float` parameters passes binary32,
-- as the callee declares them. It used to pass binary64, which the callee read
-- as zeros.
function M.floatParametersReachANativeCalleeAtTheirOwnWidth()
    local dir = project{["src/floats.nupp"] = FLOATS, ["check.lua"] = FLOAT_CHECK}
    for _, policy in ipairs({"off", "require"}) do
        local result, log = buildAndRun(dir, '"floats"', policy)
        test.equal(result, "10 20 30 40", policy .. " at " .. dir .. "\n" .. log)
    end
end

return M
