-- Lua twin of catalog-assert-value.nupp. Lua has no `assert` module; the
-- global is the function Nupp's module is.
local original = rawget(_G, "assert")
assert(type(original) == "function")
local first, gap, last = original("ready", nil, 7)
assert(first == "ready" and gap == nil and last == 7)
local marker = {}
local ok, message = pcall(original, false, marker)
assert(not ok and message == marker)
local absent, reason = pcall(original)
assert(not absent and type(reason) == "string" and string.find(reason, "value expected", 1, true) ~= nil)

local assertions = assert
local a, b, c = assertions("module", nil, 9)
assert(a == "module" and b == nil and c == 9)
local x, y, z = original("retained", nil, 11)
assert(x == "retained" and y == nil and z == 11)

return 1
