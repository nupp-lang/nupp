local testAssert = require("assert")
-- The bulk path the SoA layout was designed around: what tecs does on its hot
-- side.
--
-- The snapshot fixture writes a whole archetype column as one bulk copy of
-- `structSize * count` bytes and reads it back into the column's memory. The only
-- thing it needs from the type is the stride, and a fingerprint so a load can
-- refuse bytes a different layout wrote -- which is the failure a bulk memcpy
-- cannot otherwise notice, since the bytes are the right length and mean
-- something else.
--
-- This is the acceptance question for `types.layoutof`: can that be written against the
-- language instead of against hand-maintained constants.
local parser = require("nupp.compiler.syntax.parser")
local optimize = require("nupp.compiler.lua.optimize")
local gen = require("nupp.compiler.lua.gen")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local ffi = require("ffi")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function runs(src)
    local result = parser.parse(src, "test")
    testAssert.eq(#result.errors, 0, "syntax errors in test source\n" .. src)
    local diags = check.check(result, "test", env)
    for _, diag in ipairs(diags or {}) do
        if diag.severity == "error" then
            error(("%s: %s\n%s"):format(diag.code, diag.msg, src), 2)
        end
    end
    optimize.run(result, {level = 1})
    local code, genDiags = gen.generate(result, "test")
    testAssert.eq(#genDiags, 0, "gen diagnostics")
    local chunk, err = loadstring(code, "@bulk_column_test")
    if not chunk then
        error(("does not load: %s\n---\n%s"):format(tostring(err), code), 2)
    end
    local ok, value = pcall(chunk)
    if not ok then
        error(("raised: %s\n---\n%s"):format(tostring(value), code), 2)
    end

    return value
end

-- One source, reused: a column of particles written as a single copy and read
-- back into fresh memory, with the fingerprint carried alongside.
local COLUMN = [[
const sb = require("bytes")

local struct Particle
    x: float
    y: float
    vx: float
    vy: float
end

local function header(exclusive input: bytes.Buffer): string
    local text = ""
    while true do
        local byte = input:get(1)
        if byte == "\n" then return text end
        if byte == "" then error("missing column header") end
        text = text .. byte
    end
end

local function writeColumn(cells: any, count: integer, exclusive out: bytes.Buffer): nil
    const layout = types.layoutof(Particle)
    out:put(layout.fingerprint, "\n", count, "\n")
    const lease = out:reserve(layout.size * count)
    do
        const target = lease:span()
        const copy: function(borrows destination: uint8[?], source: any, count: integer): nil = require("ffi").copy as any
        copy(target:ref(), cells, layout.size * count)
        own.drop(target)
    end
    lease:commit(layout.size * count)
end

local function readColumn(exclusive inp: bytes.Buffer, cells: any): integer
    const layout = types.layoutof(Particle)
    const saved = header(inp)
    if saved ~= layout.fingerprint then
        error("column was written by a different layout: " .. saved)
    end
    const count = assert(tonumber(header(inp))) as integer
    const raw = inp:get(layout.size * count)
    require("ffi").copy(cells as voidptr, raw, (layout.size * count) as uint64)
    return count
end

%s
]]

local M = {}

function M.aWholeColumnRoundTripsAsOneCopy()
    local total = runs(
        COLUMN:format(
            [[
const cells = carray(Particle, 8)
for i = 0, 7 do
    cells[i].x = i
    cells[i].y = i * 2
    cells[i].vx = i * 3
    cells[i].vy = i * 4
end

const out = sb.Buffer.create()
writeColumn(cells, 8, out)

const back = carray(Particle, 8)
const input = sb.Buffer.create(out:tostring())
const count = readColumn(input, back)

local sum = 0
for i = 0, count - 1 do
    sum = sum + back[i].x + back[i].vy
end
return sum
]]
        )
    )
    -- x is i and vy is 4i, so the sum over 0..7 is 5 * 28.
    testAssert.eq(total, 140, "every field survives the copy")
end

function M.theStrideIsTheOnlyThingTheFastPathNeeds()
    local size = runs(COLUMN:format("return types.layoutof(Particle).size"))
    testAssert.eq(
        size,
        ffi.sizeof(ffi.typeof("struct { float x; float y; float vx; float vy; }")),
        "four floats, and the bulk write is size times count"
    )
end

function M.aColumnFromAnotherLayoutIsRefused()
    -- The failure a bulk copy cannot notice on its own: the byte count is right
    -- and the bytes mean something else.
    local refused = runs(
        COLUMN:format(
            [[
const wrong = sb.Buffer.create()
wrong:put("x:float,y:float|8\n2\n")
const cells = carray(Particle, 2)
const ok = pcall(readColumn, wrong, cells)
return not ok
]]
        )
    )
    testAssert.eq(refused, true, "the fingerprint is what makes the refusal possible")
end

return M
