-- A `Fixed<N>` vector field in a storage struct: laid out by the target
-- layout model on both sides, read and written whole through its row by a
-- native kernel and by the same source as ordinary Lua, and held to the same
-- answers. The compiled object reports the layout the wrapper checks at load,
-- alignment included, and an alignment-only disagreement fails that check.
local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end

local M = {}

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text
end

local function project(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    for name, text in pairs(files) do
        write(dir .. "/" .. name, text)
    end
    return dir
end

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
    test.equal(status, 0, policy .. " build at " .. dir .. ": " .. tostring(read(logPath)))
    local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
    local result = pipe:read("*a")
    pipe:close()
    return (result:gsub("%s+$", "")), read(logPath)
end

local PARTICLES = [[
module particles
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

--- A storage struct: a scalar beside a four-lane vector and a three-lane one,
--- which the layout model pads to sixteen bytes each.
local struct Particle
    mass: float
    velocity: simd.Vector<float, simd.Fixed<4>>
    color: simd.Vector<float, simd.Fixed<3>>
end

--- Two vector fields and nothing else: offsets and sizes agree whatever
--- alignment the fields are declared with, so only the alignment check tells.
local struct Pair
    a: simd.Vector<float, simd.Fixed<4>>
    b: simd.Vector<float, simd.Fixed<4>>
end

--- Every row's velocity scaled by `dt` and added to itself, its color
--- reversed, and the masses summed.
@aot
local function advance(exclusive rows: span.WriteSpan<Particle>, dt: float): number
    local total = 0.0
    for i = 1, #rows do
        local p = rows[i]
        local scaled = p.velocity * dt
        rows[i].velocity = scaled + p.velocity
        rows[i].color = p.color:reverse()
        total = total + p.mass
    end
    return total
end

--- The lane sums of both vectors of every pair, written back into `a`.
@aot
local function fold(exclusive pairs: span.WriteSpan<Pair>): number
    local total = 0.0
    for i = 1, #pairs do
        local p = pairs[i]
        pairs[i].a = p.a + p.b
        total = total + simd.horizontal.orderedSum(p.b)
    end
    return total
end

export = {advance = advance, fold = fold, Particle = Particle, Pair = Pair}
]]

local CHECK = [[
package.path = "build/native/?.lua;" .. package.path
local m = require("particles")
local ffi = require("ffi")
local span = require("nupp.mem.span")
local compiled = rawget(_G, "__nuppAotCompiled") or {}
local rows = ffi.new(ffi.typeof("$[?]", m.Particle), 3)
for i = 0, 2 do
    rows[i].mass = i + 0.5
    rows[i].velocity = {i + 1, i + 2, i + 3, i + 4}
    rows[i].color = {1, 2, 3}
end
local total = m.advance(span.writeCarray(rows, 3), 0.5)
local parts = {}
for i = 0, 2 do
    for lane = 0, 3 do parts[#parts + 1] = tostring(rows[i].velocity[lane]) end
    for lane = 0, 2 do parts[#parts + 1] = tostring(rows[i].color[lane]) end
end
parts[#parts + 1] = "|"
parts[#parts + 1] = tostring(total)
local pairs = ffi.new(ffi.typeof("$[?]", m.Pair), 2)
pairs[0].a = {1, 2, 3, 4}
pairs[0].b = {10, 20, 30, 40}
pairs[1].a = {5, 6, 7, 8}
pairs[1].b = {0.5, 0.5, 0.5, 0.5}
local folded = m.fold(span.writeCarray(pairs, 2))
parts[#parts + 1] = "|"
for i = 0, 1 do
    for lane = 0, 3 do parts[#parts + 1] = tostring(pairs[i].a[lane]) end
end
parts[#parts + 1] = tostring(folded)
parts[#parts + 1] = "|"
parts[#parts + 1] = tostring(ffi.sizeof(m.Particle)) .. "/" .. tostring(ffi.alignof(m.Particle))
parts[#parts + 1] = tostring(ffi.offsetof(m.Particle, "velocity")) .. "," .. tostring(ffi.offsetof(m.Particle, "color"))
parts[#parts + 1] = tostring(tonumber(ffi.cast("uintptr_t", rows)) % 16)
parts[#parts + 1] = tostring((tonumber(ffi.cast("uintptr_t", rows + 1)) - tonumber(ffi.cast("uintptr_t", rows))))
if arg[1] == "require" then
    assert(compiled[m.advance] and compiled[m.fold], "the kernels are compiled")
end
print(table.concat(parts, " "))
]]

local EXPECTED = table.concat({
    -- velocity * 1.5 and color reversed, per row
    "1.5 3 4.5 6 3 2 1",
    "3 4.5 6 7.5 3 2 1",
    "4.5 6 7.5 9 3 2 1",
    "| 4.5", -- 0.5 + 1.5 + 2.5
    "| 11 22 33 44 5.5 6.5 7.5 8.5 102", -- a + b, and the lane sums of b: 100 + 2
    "| 48/16 16,32 0 48", -- the model's layout, an aligned allocation and stride
}, " ")

-- The same source answers the same whether the kernel runs natively over the
-- struct's bytes or as ordinary Lua over the FFI struct, and the layout both
-- sides see is the model's: mass at zero, the four-lane vector at sixteen, the
-- three-lane one at thirty-two with its padding, forty-eight bytes a row.
function M.aStoredVectorFieldAgreesBetweenLuaAndNative()
    local dir = project{["src/particles.nupp"] = PARTICLES, ["check.lua"] = CHECK}
    for _, policy in ipairs({"off", "require"}) do
        local result, log = buildAndRun(dir, '"particles"', policy)
        test.equal(result, EXPECTED, policy .. " at " .. dir .. "\n" .. tostring(log))
        if policy == "off" then
            local lua = assert(read(dir .. "/build/native/particles.lua"))
            assert(lua:find('lane.fromStorage("float",4,', 1, true), "a Lua read goes through the lane runtime:\n" .. lua)
        end
    end
    local llvm = assert(read(dir .. "/build/native/aot/src/particles.neon.ll"), "the NEON unit is emitted")
    assert(
        llvm:find("%struct.KsParticle = type { float, [12 x i8], [4 x float], [3 x float], [4 x i8] }", 1, true),
        "the struct is spelled with the model's padding:\n" .. llvm
    )
    assert(llvm:find("%struct.KsPair = type { [4 x float], [4 x float] }", 1, true), llvm)
    assert(llvm:find("load <4 x float>, ptr %", 1, true) and llvm:find(", align 16", 1, true), "vector loads at the model's alignment:\n" .. llvm)
    assert(llvm:find("load <3 x float>, ptr %", 1, true), llvm)
    assert(llvm:find("store <4 x float> %", 1, true), llvm)
    assert(llvm:find("_layout_Particle_align()", 1, true) and llvm:find("_layout_Particle_align_velocity()", 1, true), llvm)
    local generated = assert(read(dir .. "/build/native/particles.lua"))
    assert(
        generated:find("float velocity[4] __attribute__((aligned(16)));", 1, true),
        "the Lua struct declares the field aligned:\n" .. generated
    )
    assert(generated:find("layout alignment mismatch", 1, true), "the wrapper checks the struct's alignment:\n" .. generated)
    assert(generated:find("field alignment mismatch", 1, true), "the wrapper checks each field's alignment:\n" .. generated)
    M.dir = dir
end

-- With the field alignment lowered on the Lua side, `Pair`'s offsets and sizes
-- are unchanged and only the alignments differ; the load-time comparison has
-- to refuse the module on that alone.
function M.anAlignmentOnlyMismatchFailsTheLoadTimeCheck()
    local dir = M.dir
    if dir == nil then
        M.aStoredVectorFieldAgreesBetweenLuaAndNative()
        dir = M.dir
    end
    local path = dir .. "/build/native/particles.lua"
    local generated = assert(read(path))
    local pairDeclaration = "float a[4] __attribute__((aligned(16))); float b[4] __attribute__((aligned(16)));"
    assert(generated:find(pairDeclaration, 1, true), generated)
    local injected = generated:gsub(
        pairDeclaration:gsub("%p", "%%%0"),
        "float a[4] __attribute__((aligned(8))); float b[4] __attribute__((aligned(8)));"
    )
    write(path, injected)
    local pipe = assert(io.popen(("cd %q && luajit check.lua require 2>&1"):format(dir)))
    local result = pipe:read("*a")
    pipe:close()
    assert(result:find("native struct layout alignment mismatch", 1, true), "the alignment check refuses the module:\n" .. result)
    write(path, generated)
end

return M
