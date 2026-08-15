-- M0 gate for comptime materialization's PEG provider.
--
-- Run from the repository root:
--   LUA_CPATH='./.rocks/lib/lua/5.1/?.so;;' luajit bench/comptime-materialization.lua
--
-- This file deliberately records its thresholds before any result is checked
-- into plans/011-materialization-m0.md. The reference column is a small flat
-- parsing machine in the shape M4 originally proposed. The specialized column
-- is handwritten Lua in the shape M6 would emit. This is a historical lowering
-- spike, not the shipped Nupp matcher architecture; LPeg 1.1 is its independent
-- semantics and performance comparison.

local jit = require("jit")
local lpeg = require("lpeg")

local ROUNDS = 7
local CONSTRUCTION_N = 300
local FIRST_MATCH_N = 300
local WARM_N = 300000
local ALLOCATION_N = 3000

-- Frozen M0 gates. Changing one after plans/011-materialization-m0.md records a
-- result is a new benchmark decision, not a way to turn a failure green.
local REFERENCE_MIN_MATCHES_PER_SECOND = {
   identifier = 200000,
   captures = 100000,
   recursive = 100000,
}
local SPECIALIZED_MIN_EACH = 1.10
local SPECIALIZED_MIN_GEOMEAN = 1.50
local SPECIALIZED_MAX_SOURCE_RATIO = 12.0
local SPECIALIZED_MAX_BYTECODE_RATIO = 8.0
local SPECIALIZED_MAX_EXTRA_TRACE_ABORTS = 4
local MIN_RECURSIVE_DEPTH = 128

local CLASS, SPAN, CHAR, TEST_CHAR, JUMP = 1, 2, 3, 4, 5
local CALL, RET, OPEN, CLOSE, DONE = 6, 7, 8, 9, 10

local function byteClass(ranges, singles)
   local answer = {}
   for _, range in ipairs(ranges or {}) do
      for byte = range[1], range[2] do answer[byte] = true end
   end
   for i = 1, #(singles or "") do answer[(singles or ""):byte(i)] = true end
   return answer
end

local alpha = byteClass({{65, 90}, {97, 122}}, "_")
local alnum = byteClass({{48, 57}, {65, 90}, {97, 122}}, "_")

-- REFERENCE_HELPER_BEGIN
local function runMachine(program, subject)
   local pc, position = 1, 1
   local calls, opens, captures = {}, {}, {}
   while true do
      local instruction = program[pc]
      local opcode, argument = instruction[1], instruction[2]
      if opcode == CLASS then
         if not argument[subject:byte(position)] then return nil end
         position, pc = position + 1, pc + 1
      elseif opcode == SPAN then
         while argument[subject:byte(position)] do position = position + 1 end
         pc = pc + 1
      elseif opcode == CHAR then
         if subject:byte(position) ~= argument then return nil end
         position, pc = position + 1, pc + 1
      elseif opcode == TEST_CHAR then
         pc = subject:byte(position) == instruction[3] and pc + 1 or argument
      elseif opcode == JUMP then
         pc = argument
      elseif opcode == CALL then
         calls[#calls + 1], pc = pc + 1, argument
      elseif opcode == RET then
         local target = calls[#calls]
         if not target then return nil end
         calls[#calls], pc = nil, target
      elseif opcode == OPEN then
         opens[#opens + 1], pc = position, pc + 1
      elseif opcode == CLOSE then
         local first = opens[#opens]
         opens[#opens] = nil
         captures[#captures + 1], pc = subject:sub(first, position - 1), pc + 1
      elseif opcode == DONE then
         if position ~= #subject + 1 then return nil end
         return program.captures and captures or position
      else
         error("unknown reference-machine opcode " .. tostring(opcode))
      end
   end
end
-- REFERENCE_HELPER_END

local function referenceMatcher(program)
   return function(subject) return runMachine(program, subject) end
end

local function identifierProgram()
   return {
      {CLASS, alpha},
      {SPAN, alnum},
      {DONE},
   }
end

local function captureProgram()
   local program = {
      {OPEN},
      {CLASS, alpha},
      {SPAN, alpha},
      {CLOSE},
      {TEST_CHAR, 8, 44},
      {CHAR, 44},
      {JUMP, 1},
      {DONE},
   }
   program.captures = true
   return program
end

local function recursiveProgram()
   return {
      {CALL, 3},
      {DONE},
      {TEST_CHAR, 8, 40},
      {CHAR, 40},
      {CALL, 3},
      {CHAR, 41},
      {RET},
      {RET},
   }
end

local SPECIALIZED_IDENTIFIER = [[
return function(subject)
   local byte, length = string.byte, #subject
   if length == 0 then return nil end
   local first = byte(subject, 1)
   if not ((first >= 65 and first <= 90) or (first >= 97 and first <= 122)
      or first == 95) then return nil end
   for position = 2, length do
      local value = byte(subject, position)
      if not ((value >= 48 and value <= 57) or (value >= 65 and value <= 90)
         or (value >= 97 and value <= 122) or value == 95) then return nil end
   end
   return length + 1
end
]]

local SPECIALIZED_CAPTURES = [[
return function(subject)
   local answer, first, length = {}, 1, #subject
   while first <= length do
      local position = first
      while position <= length do
         local value = string.byte(subject, position)
         if not ((value >= 65 and value <= 90) or (value >= 97 and value <= 122)
            or value == 95) then break end
         position = position + 1
      end
      if position == first then return nil end
      answer[#answer + 1] = string.sub(subject, first, position - 1)
      if position > length then return answer end
      if string.byte(subject, position) ~= 44 then return nil end
      first = position + 1
   end
   return nil
end
]]

local SPECIALIZED_RECURSIVE = [[
local function parse(subject, position)
   if string.byte(subject, position) ~= 40 then return position end
   position = parse(subject, position + 1)
   if not position or string.byte(subject, position) ~= 41 then return nil end
   return parse(subject, position + 1)
end
return function(subject)
   local position = parse(subject, 1)
   return position == #subject + 1 and position or nil
end
]]

local P, R, S, C, Ct, Cp, V = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cp, lpeg.V

local function lpegIdentifier()
   local head = R("az", "AZ") + P("_")
   local tail = head + R("09")
   return head * tail^0 * Cp() * -P(1)
end

local function lpegCaptures()
   local field = C((R("az", "AZ") + P("_"))^1)
   return Ct(field * (P(",") * field)^0) * -P(1)
end

local function lpegRecursive()
   local grammar = P({"S", S = P("(") * V("S") * P(")") * V("S") + P("")})
   return grammar * Cp() * -P(1)
end

local function specialized(source)
   return assert(loadstring(source, "@comptime-materialization-specialized"))()
end

local function lpegMatcher(builder)
   local pattern = builder()
   return function(subject) return pattern:match(subject) end
end

local workloads = {
   {
      name = "identifier",
      subject = "materialized_identifier_0123456789",
      reference = function() return referenceMatcher(identifierProgram()) end,
      specialized = function() return specialized(SPECIALIZED_IDENTIFIER) end,
      lpeg = function() return lpegMatcher(lpegIdentifier) end,
      source = SPECIALIZED_IDENTIFIER,
      program = identifierProgram,
   },
   {
      name = "captures",
      subject = "position,velocity,rotation,scale,health,mana,team,target",
      reference = function() return referenceMatcher(captureProgram()) end,
      specialized = function() return specialized(SPECIALIZED_CAPTURES) end,
      lpeg = function() return lpegMatcher(lpegCaptures) end,
      source = SPECIALIZED_CAPTURES,
      program = captureProgram,
   },
   {
      name = "recursive",
      subject = string.rep("(", 16) .. string.rep(")", 16),
      reference = function() return referenceMatcher(recursiveProgram()) end,
      specialized = function() return specialized(SPECIALIZED_RECURSIVE) end,
      lpeg = function() return lpegMatcher(lpegRecursive) end,
      source = SPECIALIZED_RECURSIVE,
      program = recursiveProgram,
   },
}

local sink = 0
local function consume(value)
   if type(value) == "table" then
      sink = sink + #value
   elseif value then
      sink = sink + value
   end
end

local function median(values)
   table.sort(values)
   return values[math.ceil(#values / 2)]
end

local function construction(builder)
   local values = {}
   for round = 1, ROUNDS do
      collectgarbage("collect")
      local started = os.clock()
      for _ = 1, CONSTRUCTION_N do consume(builder()("a")) end
      values[round] = (os.clock() - started) / CONSTRUCTION_N
   end
   return median(values)
end

local function firstMatch(builder, subject)
   local values = {}
   for round = 1, ROUNDS do
      collectgarbage("collect")
      local started = os.clock()
      for _ = 1, FIRST_MATCH_N do consume(builder()(subject)) end
      values[round] = (os.clock() - started) / FIRST_MATCH_N
   end
   return median(values)
end

local function throughput(builder, subject)
   local matcher = builder()
   for _ = 1, 2000 do consume(matcher(subject)) end
   local values = {}
   for round = 1, ROUNDS do
      local started = os.clock()
      for _ = 1, WARM_N do consume(matcher(subject)) end
      values[round] = WARM_N / (os.clock() - started)
   end
   return median(values)
end

local function allocation(builder, subject)
   collectgarbage("collect")
   local matcher, keep = builder(), {}
   collectgarbage("stop")
   local before = collectgarbage("count")
   for i = 1, ALLOCATION_N do keep[i] = matcher(subject) end
   local bytes = (collectgarbage("count") - before) * 1024 / ALLOCATION_N
   collectgarbage("restart")
   consume(keep[1])
   collectgarbage("collect")
   return bytes
end

local function traceAborts(builder, subject)
   jit.flush()
   local aborts = 0
   local function observer(what)
      if what == "abort" then aborts = aborts + 1 end
   end
   jit.attach(observer, "trace")
   local matcher = builder()
   for _ = 1, 20000 do consume(matcher(subject)) end
   jit.attach(observer)
   return aborts
end

local function recursiveDepth(builder)
   local matcher = builder()
   local depth = 1
   while depth <= 2048 do
      local subject = string.rep("(", depth) .. string.rep(")", depth)
      local ok, result = pcall(matcher, subject)
      if not ok or not result then return depth - 1 end
      depth = depth * 2
   end
   return 2048
end

local function programSource(program)
   local parts = {"{"}
   for _, instruction in ipairs(program) do
      local fields = {}
      for i, value in ipairs(instruction) do
         fields[i] = type(value) == "table" and "<byte-class>" or tostring(value)
      end
      parts[#parts + 1] = "{" .. table.concat(fields, ",") .. "},"
   end
   parts[#parts + 1] = "}"
   return table.concat(parts)
end

local function helperSourceSize()
   local file = assert(io.open(arg[0], "rb"))
   local text = file:read("*a")
   file:close()
   local first = assert(text:find("%-%- REFERENCE_HELPER_BEGIN", 1))
   local last = assert(text:find("%-%- REFERENCE_HELPER_END", first))
   return last - first
end

local function moduleSize(name)
   local pathName = name:gsub("%.", "/")
   for template in package.cpath:gmatch("[^;]+") do
      local path = template:gsub("%?", pathName)
      local file = io.open(path, "rb")
      if file then
         local size = file:seek("end")
         file:close()
         return path, size
      end
   end
   return "built in", 0
end

jit.on()
local failures, rows = {}, {}
local ratios = {}
for _, workload in ipairs(workloads) do
   local expected = workload.reference()(workload.subject)
   local actual = workload.specialized()(workload.subject)
   local oracle = workload.lpeg()(workload.subject)
   assert(type(expected) == type(actual) and type(actual) == type(oracle),
      workload.name .. " engines disagree on result kind")
   if type(expected) == "table" then
      assert(table.concat(expected, "\0") == table.concat(actual, "\0") and
         table.concat(actual, "\0") == table.concat(oracle, "\0"),
         workload.name .. " engines disagree on captures")
   else
      assert(expected == actual and actual == oracle,
         workload.name .. " engines disagree on position")
   end

   local row = {name = workload.name}
   for _, engine in ipairs({"reference", "specialized", "lpeg"}) do
      local builder = workload[engine]
      row[engine] = {
         construction = construction(builder),
         first = firstMatch(builder, workload.subject),
         throughput = throughput(builder, workload.subject),
         allocation = allocation(builder, workload.subject),
         aborts = traceAborts(builder, workload.subject),
      }
   end
   row.reference.depth = workload.name == "recursive" and recursiveDepth(workload.reference) or 0
   row.specialized.depth = workload.name == "recursive" and recursiveDepth(workload.specialized) or 0
   row.lpeg.depth = workload.name == "recursive" and recursiveDepth(workload.lpeg) or 0
   row.ratio = row.specialized.throughput / row.reference.throughput
   ratios[#ratios + 1] = row.ratio
   rows[#rows + 1] = row

   if row.reference.throughput < REFERENCE_MIN_MATCHES_PER_SECOND[row.name] then
      failures[#failures + 1] = row.name .. " reference throughput"
   end
   if row.ratio < SPECIALIZED_MIN_EACH then
      failures[#failures + 1] = row.name .. " specialized margin"
   end
   if row.specialized.aborts > row.reference.aborts + SPECIALIZED_MAX_EXTRA_TRACE_ABORTS then
      failures[#failures + 1] = row.name .. " specialized trace aborts"
   end
end

local geomean = 1
for _, ratio in ipairs(ratios) do geomean = geomean * ratio end
geomean = geomean^(1 / #ratios)
if geomean < SPECIALIZED_MIN_GEOMEAN then
   failures[#failures + 1] = "specialized throughput geomean"
end

local referenceSource = helperSourceSize()
local specializedSource, referenceBytecode, specializedBytecode = 0, #string.dump(runMachine), 0
for _, workload in ipairs(workloads) do
   referenceSource = referenceSource + #programSource(workload.program())
   specializedSource = specializedSource + #workload.source
   specializedBytecode = specializedBytecode + #string.dump(workload.specialized())
end
local sourceRatio = specializedSource / referenceSource
local bytecodeRatio = specializedBytecode / referenceBytecode
if sourceRatio > SPECIALIZED_MAX_SOURCE_RATIO then failures[#failures + 1] = "specialized source size" end
if bytecodeRatio > SPECIALIZED_MAX_BYTECODE_RATIO then failures[#failures + 1] = "specialized bytecode size" end
for _, row in ipairs(rows) do
   if row.name == "recursive" then
      if row.reference.depth < MIN_RECURSIVE_DEPTH then failures[#failures + 1] = "reference recursion depth" end
      if row.specialized.depth < MIN_RECURSIVE_DEPTH then failures[#failures + 1] = "specialized recursion depth" end
   end
end

io.write(("\n comptime materialization M0, LuaJIT %s, LPeg %s\n\n"):format(
   jit.version, tostring(lpeg.version)))
io.write(" workload/engine       build us   first us   matches/s   bytes/match  aborts\n")
io.write(" -------------------- --------- ---------- ----------- ------------- -------\n")
for _, row in ipairs(rows) do
   for _, engine in ipairs({"reference", "specialized", "lpeg"}) do
      local result = row[engine]
      io.write((" %-10s %-11s %8.2f %10.2f %11.0f %13.1f %7d\n"):format(
         row.name, engine, result.construction * 1e6, result.first * 1e6,
         result.throughput, result.allocation, result.aborts))
   end
   io.write((" %-10s specialized/reference warm throughput: %.2fx\n\n"):format(
      row.name, row.ratio))
end
io.write((" specialized/reference geomean: %.2fx (gate %.2fx)\n"):format(
   geomean, SPECIALIZED_MIN_GEOMEAN))
io.write((" generated source: reference %d B, specialized %d B, %.2fx (cap %.2fx)\n"):format(
   referenceSource, specializedSource, sourceRatio, SPECIALIZED_MAX_SOURCE_RATIO))
io.write((" LuaJIT matcher bytecode: reference %d B, specialized %d B, %.2fx (cap %.2fx)\n"):format(
   referenceBytecode, specializedBytecode, bytecodeRatio, SPECIALIZED_MAX_BYTECODE_RATIO))
for _, row in ipairs(rows) do
   if row.name == "recursive" then
      io.write((" recursive depth: reference %d, specialized %d, LPeg %d (gate %d)\n"):format(
         row.reference.depth, row.specialized.depth, row.lpeg.depth, MIN_RECURSIVE_DEPTH))
   end
end
local lpegPath, lpegBytes = moduleSize("lpeg")
io.write((" spike dependencies: reference none, specialized none, LPeg %s (%d B)\n"):format(
   lpegPath, lpegBytes))
io.write("\n")

if #failures > 0 then
   io.write(" DELETE M6: " .. table.concat(failures, ", ") .. "\n\n")
   os.exit(1)
end
io.write(" KEEP M6: the handwritten specializer clears every frozen M0 gate\n\n")
