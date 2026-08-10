-- L4 of plans/layout.md: the thing tecs actually does on its hot side.
--
-- `internal/snapshot.tl` writes a whole archetype column as one `putcdata` of
-- `structSize * count` bytes and reads it back into the column's memory. The only
-- thing it needs from the type is the stride, and a fingerprint so a load can
-- refuse bytes a different layout wrote -- which is the failure a bulk memcpy
-- cannot otherwise notice, since the bytes are the right length and mean
-- something else.
--
-- This is the acceptance question for `layoutof`: can that be written against the
-- language instead of against hand-maintained constants.
local parser = require("nupp.compiler.parser")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local ffi = require("ffi")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function runs(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source\n" .. src)
   local diags = check.check(result, "test", env)
   for _, diag in ipairs(diags or {}) do
      if diag.severity == "error" then
         error(("%s: %s\n%s"):format(diag.code, diag.msg, src), 2)
      end
   end
   optimize.run(result, {level = 1})
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
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
const sb = require("string.buffer")

local struct Particle
    x: float
    y: float
    vx: float
    vy: float
end

local function writeColumn(cells: any, count: integer, out: any): nil
    const layout = layoutof(Particle)
    out:encode(layout.fingerprint)
    out:encode(count)
    -- One copy for the whole column: not one call per element, not one per field.
    out:putcdata(cells as voidptr, (layout.size * count) as uint64)
end

local function readColumn(inp: any, cells: any): integer
    const layout = layoutof(Particle)
    const saved = inp:decode() as string
    if saved ~= layout.fingerprint then
        error("column was written by a different layout: " .. saved)
    end
    const count = inp:decode() as integer
    const raw = inp:get(layout.size * count)
    require("ffi").copy(cells as voidptr, raw, (layout.size * count) as uint64)
    return count
end

%s
]]

local M = {}

function M.aWholeColumnRoundTripsAsOneCopy()
   local total = runs(COLUMN:format([[
const cells = carray(Particle, 8)
for i = 0, 7 do
    cells[i].x = i
    cells[i].y = i * 2
    cells[i].vx = i * 3
    cells[i].vy = i * 4
end

const out = sb.new()
writeColumn(cells, 8, out)

const back = carray(Particle, 8)
const input = sb.new()
input:set(out:tostring())
const count = readColumn(input, back)

local sum = 0
for i = 0, count - 1 do
    sum = sum + back[i].x + back[i].vy
end
return sum
]]))
   -- x is i and vy is 4i, so the sum over 0..7 is 5 * 28.
   assertEq(total, 140, "every field survives the copy")
end

function M.theStrideIsTheOnlyThingTheFastPathNeeds()
   local size = runs(COLUMN:format("return layoutof(Particle).size"))
   assertEq(size, ffi.sizeof(ffi.typeof(
      "struct { float x; float y; float vx; float vy; }")),
      "four floats, and the bulk write is size times count")
end

function M.aColumnFromAnotherLayoutIsRefused()
   -- The failure a bulk copy cannot notice on its own: the byte count is right
   -- and the bytes mean something else.
   local refused = runs(COLUMN:format([[
const wrong = sb.new()
wrong:encode("x:float,y:float|8")
wrong:encode(2)
const cells = carray(Particle, 2)
const ok = pcall(readColumn, wrong, cells)
return not ok
]]))
   assertEq(refused, true, "the fingerprint is what makes the refusal possible")
end

return M
