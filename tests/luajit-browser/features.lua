local ffi = require("ffi")
local bit = require("bit")
local buffer = require("string.buffer")
local util = require("jit.util")
assert(jit.arch == "x86" and jit.os == "Linux")
assert(ffi.sizeof("void *") == 4)
assert(bit.band(0xf0, 0x3c) == 0x30 and bit.rol(1, 31) == -2147483648)
assert(9007199254740993LL + 2LL == 9007199254740995LL)
ffi.cdef[[
int abs(int);
int snprintf(char *, size_t, const char *, ...);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
]]
assert(ffi.C.abs(-42) == 42)
local text = ffi.new("char[64]")
assert(ffi.C.snprintf(text, 64, "%s:%.1f", "ffi", 2.5) == 7)
assert(ffi.string(text) == "ffi:2.5")
local libc = ffi.load("/lib/libc.so")
assert(libc.abs(-17) == 17)
local values = ffi.new("int[4]", {4, 1, 3, 2})
local compare = ffi.cast("int (*)(const void *, const void *)", function(left, right)
    return ffi.cast("const int *", left)[0] - ffi.cast("const int *", right)[0]
end)
libc.qsort(values, 4, ffi.sizeof("int"), compare)
compare:free()
assert(values[0] == 1 and values[3] == 4)
local out = buffer.new():put("hello", "\0", "browser")
assert(out:get() == "hello\0browser")
local pointer, capacity = out:reserve(4)
assert(capacity >= 4)
ffi.copy(pointer, "test", 4)
out:commit(4)
assert(out:get() == "test")
assert(buffer.decode(buffer.encode({value = 42})).value == 42)
assert(require("lpeg").match(require("lpeg").P("yes"), "yes") == 4)
assert(assert(loadstring("const x = 3; return x << 2"))() == 12)
jit.flush()
jit.on()
local total = 0
for index = 1, 100000 do
    total = total + index
end
assert(total == 5000050000)
assert(util.traceinfo(1) and #util.tracemc(1) > 0, "guest JIT did not produce machine code")
local entropy = assert(io.open("/nupp/entropy.bin", "rb"))
local seed = entropy:read("*a")
entropy:close()
assert(#seed == 32)
return {
    ok = true,
    runtime = jit.version,
    seed = (seed:gsub(".", function(byte)
        return ("%02x"):format(byte:byte())
    end))
}
