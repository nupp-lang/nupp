local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end
local t = os.clock(); local r = fib(30); print(string.format("fib30\t%.6f", os.clock() - t)); assert(r == 832040)
