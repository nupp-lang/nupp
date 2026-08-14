-- Where LuaJIT's trace thresholds should sit for a compiler run.
-- Run: luajit bench/jit-thresholds.lua        (wants a quiet machine)
--
-- Half of a cold self-build is the trace compiler rather than compiled code -- the
-- `J` share of a `nupp.profile` sample session, against 37% for `N`. That is not
-- waste from allocation: turning allocation sinking off entirely leaves `J` where it
-- was, at 51%. It is the number of traces compiled.
--
-- A compiler is branches over node kinds, token kinds and type tags, and LuaJIT
-- compiles a side trace for every guard that fails often enough. The tail of that
-- distribution never ends, so the compiler keeps paying to compile traces that a
-- compile-once workload never runs enough to repay.
--
-- `hotexit` is the threshold that stops it. Both it and `hotloop` peak and turn back
-- down, because past the peak the refused traces are ones that would have paid.
--
-- This measures each setting interleaved against the default, because the machine
-- moves: on a loaded one, `hotloop=200` measured *worse* than default and on a quiet
-- one it is 10% better. Never compare two settings from different runs.

local SETTINGS = {
   "hotloop=100", "hotloop=200", "hotloop=500", "hotloop=1000", "hotloop=2000",
   "hotexit=60", "hotexit=200", "hotexit=1000",
   "hotexit=200,hotloop=1000",
}
local PAIRS = tonumber(os.getenv("PAIRS") or "3")

-- The workload has to be a real one: a synthetic loop has none of the branch
-- diversity that makes side traces multiply, which is the whole effect.
local ROOT = os.getenv("NUPP_COMPILER_ROOT") or "."
local RUN = [[cd %s && rm -rf build/nupp build/cache && %s ./bin/nupp build >/dev/null 2>&1]]

-- os.clock cannot see a child process, so shell the timing out to `time`.
local function timed(env)
   local pipe = io.popen(("{ time -p ( " .. RUN .. " ) ; } 2>&1 | awk '/^real/{print $2}'")
      :format(ROOT, env))
   local out = pipe:read("*a")
   pipe:close()
   return tonumber((out:gsub("%s", ""))) or 0 / 0
end

local function median(values)
   table.sort(values)
   return values[math.ceil(#values / 2)]
end

io.write(("\n jit thresholds, %d interleaved pairs each\n\n"):format(PAIRS))
io.write((" %-26s %9s %9s %8s %7s\n"):format("setting", "default", "tuned", "delta", "pairs"))
io.write((" %s %s %s %s %s\n"):format(("─"):rep(26), ("─"):rep(9), ("─"):rep(9),
   ("─"):rep(8), ("─"):rep(7)))

for _, setting in ipairs(SETTINGS) do
   local base, tuned, wins = {}, {}, 0
   for _ = 1, PAIRS do
      local b = timed("NUPP_JIT_DEFAULT=1")
      local t = timed("NUPP_JIT_TUNE=" .. setting)
      base[#base + 1] = b
      tuned[#tuned + 1] = t
      if t < b then wins = wins + 1 end
   end
   local b, t = median(base), median(tuned)
   io.write((" %-26s %8.2fs %8.2fs %7.0f%% %5d/%d\n")
      :format(setting, b, t, 100 * (t - b) / b, wins, PAIRS))
end

io.write("\n the shipped setting is in src/nupp/compiler/cli/init.nupp; this is how\n")
io.write(" to justify changing it\n\n")
