local function make(d) if d == 0 then return {} end return {left = make(d - 1), right = make(d - 1)} end
local function check(t) if t.left == nil then return 1 end return 1 + check(t.left) + check(t.right) end
local t = os.clock(); local total = 0
for i = 1, 10 do total = total + check(make(15)) end
print(string.format("trees15x10\t%.6f", os.clock() - t)); assert(total == 10 * 65535)
