local ffi = require("ffi")
local lpeg = require("lpeg")
ffi.cdef[[double ks_sum_squares(double);]]
local aot = ffi.load("nuppaot")
for _, count in ipairs({0, 1, 10, 1000}) do
    assert(aot.ks_sum_squares(count) == count * (count + 1) * (2 * count + 1) / 6)
end
local pattern = lpeg.C(lpeg.R("09") ^ 1) * lpeg.P("\0") * lpeg.C(lpeg.P(1) ^ 0)
local left, right = pattern:match("123\0native")
assert(left == "123" and right == "native")
assert(type(require("jit.bc").dump) == "function")
assert(type(require("jit.dump").on) == "function")
assert(type(require("jit.p").start) == "function")
local compiled = assert(loadstring("return function(value) return value * 7 end"))()
assert(assert(loadstring(string.dump(compiled)))(6) == 42)
local co = coroutine.create(function()
    local ok, value = pcall(function()
        return coroutine.yield("yielded")
    end)
    assert(ok and value == 42)

    return value
end)
assert(select(2, coroutine.resume(co)) == "yielded")
assert(select(2, coroutine.resume(co, 42)) == 42)
-- A pointer and transfer lease must keep the underlying allocation alive.
local memory = assert(_G.__qemuMemory)
local allocation = memory.allocate(1024)
local pointer = memory.pointer(allocation, 0, 1)
ffi.fill(pointer, 1024, 173)
local lease = memory.lease(pointer, 1024, true)
allocation = nil
collectgarbage("collect")
collectgarbage("collect")
assert(ffi.string(pointer, 1024) == string.rep(string.char(173), 1024))
memory.releaseLease(lease)
assert(memory.stats().leases == 0)
return {
    nuppGeneratedAot = true,
    cModule = "LPeg 1.1.0",
    jitHelpers = true,
    dynamicCompilation = true,
    bytecodeReload = true,
    yieldAcrossPcall = true,
    allocationRetained = true,
    jit = jit.status()
}
