-- Minimal dependency-free test runner: loads tests/*_test.lua, runs every
-- function in the returned table, reports failures with their assert message.
local dir = arg[0]:match("^(.*)[/\\]") or "."
package.path = dir .. "/../build/?.lua;" .. dir .. "/?.lua;" .. package.path

local names = {}
do
   local p = assert(io.popen("ls '" .. dir .. "'"), "cannot list test directory")
   for f in p:lines() do
      local mod = f:match("^(.*test)%.lua$")
      if mod then names[#names + 1] = mod end
   end
   p:close()
end
table.sort(names)

local total, failed = 0, 0
for _, mod in ipairs(names) do
   local suite = dofile(dir .. "/" .. mod .. ".lua")
   local cases = {}
   for name in pairs(suite) do cases[#cases + 1] = name end
   table.sort(cases)
   for _, name in ipairs(cases) do
      total = total + 1
      local ok, err = pcall(suite[name])
      if not ok then
         failed = failed + 1
         io.write(("FAIL  %s / %s\n      %s\n"):format(mod, name, tostring(err)))
      end
   end
end

io.write(("%d tests, %d failed\n"):format(total, failed))
os.exit(failed == 0 and 0 or 1)
