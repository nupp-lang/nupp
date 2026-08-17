-- Switch dispatch lowering benchmark.
--
-- Run from the repository root:
--
--   luajit bench/switch-dispatch.lua
--   NUPP_BENCH_MODE=check luajit bench/switch-dispatch.lua
--   NUPP_BENCH_N=1000000 NUPP_BENCH_ROUNDS=15 luajit bench/switch-dispatch.lua
--
-- The output is TSV. Its schema is:
--
--   family  cases  jit  stream  lowering  median_ns  spread_ns  traces  aborts
--
-- `check` compiles every generated lowering and runs its agreement preflight without
-- timing. Full mode interleaves samples by scenario, reports the median and range, and
-- observes trace starts/stops/aborts. Record the first environment line with results;
-- it carries the exact VM, OS and architecture which chose the thresholds.

local ffi, bit = require("ffi"), require("bit")
local band, rshift, tobit = bit.band, bit.rshift, bit.tobit

local MODE = os.getenv("NUPP_BENCH_MODE") or "full"
local N = tonumber(os.getenv("NUPP_BENCH_N")) or 400000
local ROUNDS = tonumber(os.getenv("NUPP_BENCH_ROUNDS")) or 9
local BIAS = 0.95
local sink = 0

local function vmVersion()
   local pipe = io.popen("luajit -v 2>&1")
   local version = pipe and pipe:read("*l") or "unknown"
   if pipe then pipe:close() end
   return version
end

print(("# vm=%s os=%s arch=%s n=%d rounds=%d mode=%s"):format(
   vmVersion(), ffi.os, ffi.arch, N, ROUNDS, MODE))
print("family\tcases\tjit\tstream\tlowering\tmedian_ns\tspread_ns\ttraces\taborts")

local function samples(fn, values)
   local times, traces, aborts = {}, 0, 0
   local function onTrace(what)
      if what == "stop" then traces = traces + 1 end
      if what == "abort" then aborts = aborts + 1 end
   end
   jit.attach(onTrace, "trace")
   for round = 1, ROUNDS do
      local started = os.clock()
      sink = sink + fn(values, N)
      times[round] = (os.clock() - started) / N * 1e9
   end
   jit.attach(onTrace)
   table.sort(times)
   local middle = times[math.ceil(#times / 2)]
   return middle, times[#times] - times[1], traces, aborts
end

local function report(family, count, jitOn, streamName, name, fn, values)
   local answer = fn(values, math.min(N, 1003))
   assert(type(answer) == "number", name .. " did not answer a number")
   if MODE == "check" then
      print(("%s\t%d\t%s\t%s\t%s\tcheck\tcheck\t0\t0"):format(
         family, count, tostring(jitOn), streamName, name))
      return answer
   end
   local median, spread, traces, aborts = samples(fn, values)
   print(("%s\t%d\t%s\t%s\t%s\t%.2f\t%.2f\t%d\t%d"):format(
      family, count, tostring(jitOn), streamName, name,
      median, spread, traces, aborts))
   return answer
end

local function stream(keys, kind)
   local values = {}
   math.randomseed(42)
   for index = 1, N do
      local pick
      if kind == "first" then
         pick = 1
      elseif kind == "last" then
         pick = #keys
      elseif kind == "biased" then
         pick = math.random() < BIAS and 1 or math.random(#keys)
      elseif kind == "mixed-miss" and index % 4 == 0 then
         values[index] = type(keys[1]) == "string" and "absent" or -987654321
      else
         pick = math.random(#keys)
      end
      if pick then values[index] = keys[pick] end
   end
   return values
end

local function load(source, ...)
   return assert(loadstring(source))(...)
end

local function scalar(value)
   return type(value) == "string" and string.format("%q", value) or tostring(value)
end

local function chain(keys)
   local out = {"return function(vs,n) local sum=0 for j=1,n do local v=vs[j] local r\n"}
   for index, key in ipairs(keys) do
      out[#out + 1] = ("%s v==%s then r=%d\n"):format(
         index == 1 and "if" or "elseif", scalar(key), index * 3)
   end
   out[#out + 1] = "else r=0 end sum=sum+r end return sum end"
   return load(table.concat(out))
end

local function keyedTable(keys)
   local entries = {}
   for index, key in ipairs(keys) do
      entries[index] = ("[%s]=%d"):format(scalar(key), index * 3)
   end
   return load(([=[local T={%s}
      return function(vs,n) local sum=0 for j=1,n do
         local r=T[vs[j]] if r==nil then r=0 end sum=sum+r
      end return sum end]=]):format(table.concat(entries, ",")))
end

local function denseTable(count, guarded, sentinel)
   local values = {}
   for index = 1, count do
      values[index] = sentinel and index == 3 and "S" or tostring(index * 3)
   end
   local read = guarded and
      ("local i=vs[j] local r if i>=1 and i<=%d then r=T[i] end"):format(count) or
      "local r=T[vs[j]]"
   local miss = sentinel and
      "if r==nil then r=0 elseif r==S then r=0 end" or
      "if r==nil then r=0 end"
   return load(([=[local S={} local T={%s}
      return function(vs,n) local sum=0 for j=1,n do
         %s %s sum=sum+r
      end return sum end]=]):format(table.concat(values, ","), read, miss))
end

local function stringKeys(count)
   local keys = {}
   for index = 1, count do keys[index] = ("key-%03d"):format(index) end
   return keys
end

local function sparseKeys(count)
   local keys = {}
   math.randomseed(7)
   for index = 1, count do
      keys[index] = tobit(math.random(1, 2 ^ 30) * 4 + 1)
   end
   return keys
end

local function perfectLayout(keys)
   local base = 1
   while base < #keys do base = base * 2 end
   local multipliers = {
      2654435761, 40503, 2246822519, 3266489917,
      668265263, 374761393, 1103515245, 22695477,
   }
   for _, growth in ipairs({2, 4, 8, 16}) do
      local size = base * growth
      for _, multiplier in ipairs(multipliers) do
         for shift = 0, 31 do
            local occupied, collision = {}, false
            for _, key in ipairs(keys) do
               local slot = band(rshift(tobit(key * multiplier), shift), size - 1)
               if occupied[slot] then collision = true break end
               occupied[slot] = true
            end
            if not collision then return multiplier, shift, size end
         end
      end
   end
   return nil
end

local function perfectHash(keys, useFfi)
   local multiplier, shift, size = perfectLayout(keys)
   if not multiplier then return nil end
   local keyData = useFfi and ffi.new("int32_t[?]", size) or {}
   local valueData = useFfi and ffi.new("int32_t[?]", size) or {}
   if not useFfi then
      for index = 1, size do keyData[index], valueData[index] = 0, 0 end
   end
   for index, key in ipairs(keys) do
      local slot = band(rshift(tobit(key * multiplier), shift), size - 1)
      local at = useFfi and slot or slot + 1
      keyData[at], valueData[at] = key, index * 3
   end
   return load(([=[local K,V,band,rshift,tobit=...
      return function(vs,n) local sum=0 for j=1,n do local v=vs[j]
         local h=band(rshift(tobit(v*%d),%d),%d)%s
         local r if K[h]==v then r=V[h] else r=0 end sum=sum+r
      end return sum end]=]):format(
         multiplier, shift, size - 1, useFfi and "" or "+1"),
      keyData, valueData, band, rshift, tobit)
end

local records, instances = {}, {}
for index = 1, 128 do
   records[index] = {}
   records[index].__index = records[index]
   instances[index] = setmetatable({}, records[index])
end

local function nominal(count, shape)
   local out = {"local R=... return function(vs,n) local sum=0 for j=1,n do local v=vs[j] local r\n"}
   if shape == "shared" then
      out[#out + 1] = "local identity=getmetatable(v).__index\n"
   end
   for index = 1, count do
      local left
      if shape == "guarded" then
         left = "getmetatable(v) and getmetatable(v).__index"
      elseif shape == "raw" then
         left = "getmetatable(v).__index"
      else
         left = "identity"
      end
      out[#out + 1] = ("%s %s==R[%d] then r=%d\n"):format(
         index == 1 and "if" or "elseif", left, index, index)
   end
   out[#out + 1] = "else r=0 end sum=sum+r end return sum end"
   return load(table.concat(out), records)
end

local STREAMS = {"first", "last", "biased", "uniform", "mixed-miss"}
local COUNTS = {2, 4, 8, 16, 32, 64, 128}

for _, jitOn in ipairs({true, false}) do
   if jitOn then jit.on() else jit.off() end
   for _, count in ipairs(COUNTS) do
      local dense = {}
      for index = 1, count do dense[index] = index end
      for _, family in ipairs({
         {name = "dense-int", keys = dense},
         {name = "string", keys = stringKeys(count)},
         {name = "sparse-int", keys = sparseKeys(count)},
      }) do
         local implementations = {
            {"chain", chain(family.keys)},
            {"table", family.name == "dense-int" and denseTable(count, false, false) or keyedTable(family.keys)},
         }
         if family.name == "sparse-int" and count >= 16 then
            local phFfi = perfectHash(family.keys, true)
            local phLua = perfectHash(family.keys, false)
            if phFfi and phLua then
               implementations[#implementations + 1] = {"ph-ffi", phFfi}
               implementations[#implementations + 1] = {"ph-lua", phLua}
            end
         end
         for _, streamName in ipairs(STREAMS) do
            local values = stream(family.keys, streamName)
            local expected
            for _, implementation in ipairs(implementations) do
               local answer = report(family.name, count, jitOn, streamName,
                  implementation[1], implementation[2], values)
               expected = expected or answer
               assert(answer == expected, family.name .. " lowerings disagree")
            end
         end
      end
   end

   for _, count in ipairs({4, 16, 64}) do
      for _, streamName in ipairs({"biased", "uniform", "mixed-miss"}) do
         local values = stream((function()
            local keys = {} for index = 1, count do keys[index] = index end return keys
         end)(), streamName)
         values[1], values[2], values[3] = 9999, 0 / 0, -7
         local plain = report("range-guard", count, jitOn, streamName,
            "unguarded", denseTable(count, false, false), values)
         local guarded = report("range-guard", count, jitOn, streamName,
            "guarded", denseTable(count, true, false), values)
         assert(plain == guarded, "range guard changes misses")

         local hitValues = stream((function()
            local keys = {} for index = 1, count do keys[index] = index end return keys
         end)(), streamName == "mixed-miss" and "uniform" or streamName)
         report("nil-sentinel", count, jitOn, streamName,
            "plain", denseTable(count, false, false), hitValues)
         report("nil-sentinel", count, jitOn, streamName,
            "sentinel", denseTable(count, false, true), hitValues)

         local nominalStream = streamName == "mixed-miss" and "uniform" or streamName
         local nominalValues = stream(instances, nominalStream)
         local expected = report("nominal", count, jitOn, nominalStream,
            "guarded", nominal(count, "guarded"), nominalValues)
         assert(report("nominal", count, jitOn, nominalStream,
            "raw", nominal(count, "raw"), nominalValues) == expected)
         assert(report("nominal", count, jitOn, nominalStream,
            "shared", nominal(count, "shared"), nominalValues) == expected)
      end
   end
end

io.stderr:write("switch-dispatch sink ", tostring(sink), "\n")
