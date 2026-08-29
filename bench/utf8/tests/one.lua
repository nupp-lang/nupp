-- One implementation, one corpus, one process. The in-process comparison in
-- `run.lua` is honest for the compiled entry, which is a C closure, and unfair
-- to the three that are Lua: four validators in one process is four sets of
-- traces competing for the same specialization.
local implementations = assert(loadfile("implementations.lua"))()
local which, name = ...
local f = implementations[which]
local function corpus(make) local l = {} for i = 1, 64 do l[i] = make(i) end return l end
local CASES = {
   ["short-ascii"] = {corpus(function(i) return string.rep("ab", 4 + i % 9) end), 3000},
   ["short-accented"] = {corpus(function(i) return ("caf\xc3\xa9 na\xc3\xafve %d"):format(i) end), 3000},
   ["short-cjk"] = {corpus(function(i) return string.rep("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", 2 + i % 3) end), 3000},
   ["json-4k"] = {{string.rep('{"name":"value","n":12345},', 152)}, 8000},
   ["cjk-900"] = {{string.rep("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", 100)}, 8000},
   ["ascii-1m"] = {{string.rep("abcdefgh", 131072)}, 40},
}
local list, rounds = CASES[name][1], CASES[name][2]
for i = 1, #list do f(list[i]) end
local best, bytes = math.huge, 0
for i = 1, #list do bytes = bytes + #list[i] end
for _ = 1, 7 do
   local t0 = os.clock()
   for _ = 1, rounds do for i = 1, #list do f(list[i]) end end
   local dt = os.clock() - t0
   if dt < best then best = dt end
end
io.write(("%.1f"):format((bytes * rounds) / 1048576 / best))
