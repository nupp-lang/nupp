local ffi = require("ffi")
local bit = require("bit")
local buffer = require("string.buffer")
local util = require("jit.util")
local base = arg[1] or "."
local failures = 0

local function emit(kind, name, detail)
    io.write("@@NUPP_QEMU@@\t", kind, "\t", name, "\t", tostring(detail or ""):gsub("[\r\n\t]", " "), "\n")
    io.flush()
end

local function check(name, body)
    local ok, detail = pcall(body)
    if not ok then
        failures = failures + 1
    end
    emit(ok and "PASS" or "FAIL", name, detail)
end

emit("INFO", "runtime", jit.version .. " " .. jit.os .. " " .. jit.arch)

ffi.cdef[[
int abs(int value);
int snprintf(char *buffer, size_t size, const char *format, ...);
double spike_sum(const double *values, size_t count);
int spike_callback(int (*callback)(int), int value);
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clock, struct timespec *result);
]]

check("bit", function()
    assert(bit.band(0xf0, 0x3c) == 0x30)
    assert(bit.rol(1, 31) == -2147483648)
    assert(bit.tohex(bit.bxor(0x12345678, 0xffffffff)) == "edcba987")
    return "band, rol, bxor"
end)

check("ffi-array-pointer", function()
    local values = ffi.new("double[4]", {1, 2, 3, 4})
    local pointer = ffi.cast("double *", values)
    pointer[2] = 9
    assert(values[2] == 9 and ffi.sizeof("void *") == 8)

    return "64-bit pointers and mutable cdata"
end)

check("ffi-int64", function()
    local value = 9007199254740993LL
    assert(value + 2LL == 9007199254740995LL)
    assert(tostring(value) == "9007199254740993LL")
    return tostring(value)
end)

check("ffi-libc", function()
    assert(ffi.C.abs(-42) == 42)
    local target = ffi.new("char[64]")
    assert(ffi.C.snprintf(target, 64, "%s:%.1f", "ffi", 2.5) == 7)
    assert(ffi.string(target) == "ffi:2.5")

    return "default namespace and C varargs"
end)

local library
check("ffi-load", function()
    library = ffi.load(base .. "/libspike.so")
    assert(library.spike_sum(ffi.new("double[4]", {1, 2, 3, 4}), 4) == 10)
    return jit.os .. " " .. jit.arch .. " shared library"
end)

check("ffi-callback", function()
    assert(library, "shared library was not loaded")
    local callback = ffi.cast("int (*)(int)", function(value)
        return value * 3
    end)
    local result = library.spike_callback(callback, 7)
    callback:free()
    assert(result == 22)

    return "Lua to C to Lua to C to Lua"
end)

check("string-buffer", function()
    local out = buffer.new():put("hello", "\0", "wasm")
    assert(out:get() == "hello\0wasm")
    local pointer, size = out:reserve(4)
    assert(size >= 4)
    ffi.copy(pointer, "test", 4)
    out:commit(4)
    assert(out:get() == "test")

    return "put/get and reserve/commit"
end)

check("buffer-serialization", function()
    local value = buffer.decode(buffer.encode({name = "Nupp", values = {1, 2, 3}}))
    assert(value.name == "Nupp" and value.values[3] == 3)
    return "encode/decode"
end)

check("jit-trace", function()
    jit.flush()
    jit.on()
    local total = 0
    for i = 1, 1000000 do
        total = total + i
    end
    assert(total == 500000500000)
    local trace = assert(util.traceinfo(1), "no LuaJIT trace was recorded")
    local machine = assert(util.tracemc(1), "trace has no machine code")
    assert(#machine > 0)

    return "instructions=" .. trace.nins .. " machineBytes=" .. #machine
end)

local integrate
check("nupp-struct", function()
    integrate = assert(loadfile(base .. "/workload.lua"))()
    assert(integrate(20) == 10)
    return "Nupp luajit lowering, FFI-backed struct"
end)

local timespec = ffi.new("struct timespec[1]")
local clock = jit.os == "OSX" and 6 or 1

local function now()
    assert(ffi.C.clock_gettime(clock, timespec) == 0)
    return tonumber(timespec[0].tv_sec) + tonumber(timespec[0].tv_nsec) / 1e9
end

check("jit-on-off-correctness", function()
    assert(integrate, "Nupp workload did not load")
    local steps = 1000000
    for _, mode in ipairs({"off", "on"}) do
        jit.flush()
        if mode == "on" then
            jit.on()
        else
            jit.off()
        end
        for _ = 1, 5 do
            assert(integrate(steps) == steps / 2)
        end
        for sample = 1, 5 do
            local start = now()
            local value = integrate(steps)
            local elapsed = (now() - start) * 1000
            assert(value == steps / 2)
            emit("BENCH", mode, string.format("%.6f,%d,%d", elapsed, sample, steps))
        end
    end
    jit.on()

    return "identical result in both modes; timings are exploratory"
end)

emit("DONE", "failures", failures)
os.exit(failures == 0 and 0 or 1)
