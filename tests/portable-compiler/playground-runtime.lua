-- The playground runner is checked source carried by the application VM, not
-- source assembled in JavaScript. Exercise it independently under stock 5.1.

dofile(assert(arg[1], "the checked application runtime bundle is required"))

local result = __nuppPlaygroundRun([[print("hello", 42)]])
assert(result:find('"stdout":"hello\\t42"', 1, true), result)

local ok, problem = pcall(__nuppPlaygroundRun, [[
print(string.rep("x", 1048577))
]])
assert(not ok, "oversized playground output was accepted")
assert(tostring(problem):find("output exceeded 1048576 bytes", 1, true), tostring(problem))
