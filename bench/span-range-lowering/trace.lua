-- Diagnostic trace-shape comparison. The VM's IR numbering is deliberately not a
-- test contract; this reports named categories for the LuaJIT build running it.
local bit = require("bit")
local ffi = require("ffi")
local util = require("jit.util")
local vmdef = require("jit.vmdef")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local out = here .. "build/"
package.path = out .. "runtime/?.lua;" .. out .. "runtime/?/init.lua;" .. package.path

local disabled = assert(loadfile(out .. "disabled/kernel.lua"))()
local enabled = assert(loadfile(out .. "enabled/kernel.lua"))()
local spans = require("nupp.span")
local count, steps, dt = 512, 8, 0.125

local function storage(types)
   local positions = ffi.new(ffi.typeof("$[?]", types.Position), count)
   local velocities = ffi.new(ffi.typeof("$[?]", types.Velocity), count)
   for index = 0, count - 1 do
      velocities[index].x = index % 31 + 0.25
      velocities[index].y = index % 17 - 0.5
   end
   return positions, velocities
end

local function direct(positions, velocities, first, last, repeats, scale)
   assert(positions.count == velocities.count)
   local rows = spans.range(first, last, positions, velocities)
   for _ = 1, repeats do
      for index = rows.first, rows.last do
         local position = positions.pointer[positions.offset + index - 1]
         local velocity = velocities.pointer[velocities.offset + index - 1]
         position.x = velocity.x * scale + velocity.y
         position.y = velocity.y * scale - velocity.x
      end
   end
end

local function opcodeName(ot)
   local opcode = bit.rshift(ot, 8)
   return vmdef.irnames:sub(opcode * 6 + 1, opcode * 6 + 6):match("^%s*(.-)%s*$")
end

local function counts(trace)
   local info = assert(util.traceinfo(trace), "trace disappeared")
   local result = {compare = 0, call = 0, xload = 0, xstore = 0, hload = 0, fload = 0}
   for ref = 1, info.nins - 1 do
      local _, ot = util.traceir(trace, ref)
      local name = opcodeName(ot)
      if name == "LT" or name == "LE" or name == "GT" or name == "GE" then
         result.compare = result.compare + 1
      elseif name:match("^CALL") then
         result.call = result.call + 1
      elseif name == "XLOAD" then
         result.xload = result.xload + 1
      elseif name == "XSTORE" then
         result.xstore = result.xstore + 1
      elseif name == "HLOAD" then
         result.hload = result.hload + 1
      elseif name == "FLOAD" then
         result.fload = result.fload + 1
      end
   end
   return result
end

local function inspect(name, operation, types)
   local positions, velocities = storage(types)
   local writer = spans.writeCarray(positions, count)
   local reader = spans.fromCarray(velocities, count)
   local trace
   local function event(what, number, fn)
      if what == "stop" and fn == operation and not trace then trace = number end
   end
   jit.flush()
   jit.opt.start("hotloop=1", "hotexit=1")
   jit.attach(event, "trace")
   for _ = 1, 8 do operation(writer, reader, 1, count, steps, dt) end
   jit.attach(event)
   writer:drop()
   assert(trace, "LuaJIT recorded no root trace for " .. name)
   return counts(trace)
end

local rows = {
   {"span.range + checked", inspect("checked", disabled.ranged, disabled)},
   {"span.range + OPT-6", inspect("OPT-6", enabled.ranged, enabled)},
   {"span.range + direct", inspect("direct", direct, enabled)},
}

io.write("trace shape (root loop IR)\n")
io.write("implementation             cmp call xload xstore hload fload\n")
for _, row in ipairs(rows) do
   local value = row[2]
   io.write(("%-25s %3d %4d %5d %6d %5d %5d\n"):format(
      row[1], value.compare, value.call, value.xload, value.xstore,
      value.hload, value.fload))
end

assert(rows[2][2].xload > 0 and rows[2][2].xstore > 0,
   "OPT-6 trace contains no external memory operations")
assert(rows[2][2].compare <= rows[1][2].compare,
   "OPT-6 introduced comparison IR")
