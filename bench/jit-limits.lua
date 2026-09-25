-- What LuaJIT's capacity limits cost a compiler run.
-- Run: luajit bench/jit-limits.lua        (wants a quiet machine)
--
-- Reaching a limit throws every trace away: too many live traces, or a machine-code
-- area that cannot grow, flushes the lot and the process is interpreted until it
-- earns them back. On macOS arm64 the second area almost never lands within branch
-- range, so with the default 64 KB areas a cold check flushed thousands of times.
-- `nupp.tools.jitlimits` raises the limits for every process; this measures what that
-- is worth, and is how to justify moving them.
--
-- Four configurations, interleaved per round because the machine moves:
--
--   defaults     LuaJIT's own limits and thresholds (`NUPP_JIT_DEFAULT`)
--   thresholds   the compiler's thresholds alone, LuaJIT's limits
--                (`NUPP_JIT_LIMITS=`, empty): what shipped before the limits
--   limits       the raised limits alone, LuaJIT's thresholds
--   shipped      the raised limits and the compiler's thresholds
--
-- `LIMITS=flag,flag` replaces the raised limits in the last two rows, through
-- `NUPP_JIT_LIMITS`, which is how to sweep them.
--
-- Each process counts its flushes and compiled traces and appends them to a file on
-- exit. The shipped row includes one flush per process, at startup, where the limits
-- are applied: that is where the area gets its size.

local PAIRS = tonumber(os.getenv("PAIRS") or "3")
local ROOT = os.getenv("NUPP_COMPILER_ROOT") or "."

local function readAll(path)
   local file = io.open(path, "rb")
   if not file then return "" end
   local text = file:read("*a")
   file:close()
   return text
end

-- The flags `nupp.tools.jitlimits` applies, read from its source so the two
-- cannot come apart, unless `LIMITS` names others.
local function limitFlags()
   local override = os.getenv("LIMITS")
   local flags = {}
   if override then
      for flag in override:gmatch("[^,]+") do flags[#flags + 1] = flag end
      return flags
   end
   local source = readAll(ROOT .. "/src/nupp/tools/jitlimits.nupp")
   local list = assert(source:match("jitlimits%.FLAGS = {(.-)}"), "the limits are declared")
   for flag in list:gmatch('"([^"]+)"') do flags[#flags + 1] = flag end
   return flags
end

local LIMITS = limitFlags()
local function quotedLimits()
   local quoted = {}
   for index, flag in ipairs(LIMITS) do quoted[index] = ("%q"):format(flag) end
   return table.concat(quoted, ",")
end

local COUNTS = os.tmpname()
local COUNTER = ([[
local flushes, traces = 0, 0
jit.attach(function(what)
   if what == "flush" then flushes = flushes + 1 elseif what == "stop" then traces = traces + 1 end
end, "trace")
local exit = os.exit
os.exit = function(...)
   local file = io.open(%q, "a")
   if file then file:write(flushes, " ", traces, "\n") file:close() end
   return exit(...)
end
]]):format(COUNTS)

local CONFIGURATIONS = {
   {name = "defaults", env = "NUPP_JIT_DEFAULT=1", init = COUNTER},
   {name = "thresholds", env = "NUPP_JIT_LIMITS=", init = COUNTER},
   {name = "limits", env = "NUPP_JIT_DEFAULT=1",
      init = ("jit.opt.start(%s) "):format(quotedLimits()) .. COUNTER},
   {name = "shipped", env = "NUPP_JIT_LIMITS=" .. table.concat(LIMITS, ","), init = COUNTER},
}

local RUN = [[cd %s && rm -rf build/cache && %s LUA_INIT=%s ./bin/nupp check >/dev/null 2>&1]]

local function shellQuote(text)
   return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- os.clock cannot see a child process, so shell the timing out to `time`.
local function measure(configuration)
   os.remove(COUNTS)
   local command = RUN:format(ROOT, configuration.env, shellQuote(configuration.init))
   local pipe = io.popen(("{ time -p ( %s ) ; } 2>&1 | awk '/^real/{print $2}'"):format(command))
   local out = pipe:read("*a")
   pipe:close()
   local flushes, traces = 0, 0
   for f, t in readAll(COUNTS):gmatch("(%d+) (%d+)") do
      flushes, traces = flushes + tonumber(f), traces + tonumber(t)
   end
   return tonumber((out:gsub("%s", ""))) or 0 / 0, flushes, traces
end

local function median(values)
   table.sort(values)
   return values[math.ceil(#values / 2)]
end

local results = {}
for _, configuration in ipairs(CONFIGURATIONS) do
   results[configuration.name] = {seconds = {}, flushes = {}, traces = {}}
end
for _ = 1, PAIRS do
   for _, configuration in ipairs(CONFIGURATIONS) do
      local seconds, flushes, traces = measure(configuration)
      local row = results[configuration.name]
      row.seconds[#row.seconds + 1] = seconds
      row.flushes[#row.flushes + 1] = flushes
      row.traces[#row.traces + 1] = traces
   end
end
os.remove(COUNTS)

io.write(("\n cold `nupp check`, %d interleaved rounds, medians\n\n"):format(PAIRS))
io.write((" %-12s %9s %9s %10s\n"):format("", "time", "flushes", "traces"))
io.write((" %s %s %s %s\n"):format(("─"):rep(12), ("─"):rep(9), ("─"):rep(9), ("─"):rep(10)))
for _, configuration in ipairs(CONFIGURATIONS) do
   local row = results[configuration.name]
   io.write((" %-12s %8.2fs %9d %10d\n"):format(configuration.name, median(row.seconds),
      median(row.flushes), median(row.traces)))
end
io.write("\n the shipped limits are in src/nupp/tools/jitlimits.nupp and\n")
io.write(" native/crates/host/c/lua_shim.c\n\n")
