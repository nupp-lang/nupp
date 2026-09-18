-- Run the existing playground compiler smoke corpus inside the small guest.
local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value
end

local before = read("/proc/meminfo")
print("COMPILER_LOAD_BEGIN")
io.flush()
local Browser = assert(loadfile("/nupp/playground-compiler.ljbc"))()
print("COMPILER_LOAD_END", collectgarbage("count"))
io.flush()
NUPP_REQUIRED = {}
local smoke = assert(loadfile("/nupp/compiler-smoke.lua"))()
for iteration = 1, 3 do
    smoke(Browser)
    collectgarbage("collect")
    print("COMPILER_SMOKE_PASS", iteration, collectgarbage("count"))
    io.flush()
end
return {
    compilerSmokePasses = 3,
    luaHeapKiB = collectgarbage("count"),
    guestProcess = read("/proc/self/status"),
    guestMemoryBefore = before,
    guestMemoryAfter = read("/proc/meminfo")
}
