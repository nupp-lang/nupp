-- Use tests/wasm-memory/run.sh wasm bench/portable-storage-io/wasm.lua.
-- This measures the real interpreted memory service, not a table mock or AOT.
local memory = assert(__nuppWasmHost)
local sizes = {0, 16, 4096, 1048576}
local rounds = 9
for _, size in ipairs(sizes) do
    local steps = size > 4096 and 256 or 10000
    local source = memory.pointer(memory.allocate(size), 0, 1)
    local destination = memory.pointer(memory.allocate(size), 0, 1)
    if size > 0 then
        memory.store(source, size - 1, "uint8", 173)
    end
    local samples = {}
    for round = 1, rounds + 3 do
        collectgarbage("collect")
        local start = os.clock()
        for _ = 1, steps do
            memory.copy(destination, source, size)
        end
        local elapsed = os.clock() - start
        if size > 0 then
            assert(memory.load(destination, size - 1, "uint8") == 173)
        end
        if round > 3 then
            samples[#samples + 1] = elapsed
        end
    end
    io.write(string.format('{"case":"bulk-copy","bytes":%d,"steps":%d,"seconds":[', size, steps))
    for index, value in ipairs(samples) do
        io.write(index == 1 and "" or ",", string.format("%.9f", value))
    end
    io.write("]}\n")
end
local pointer = memory.pointer(memory.allocate(4096), 0, 1)
local total = 0
local start = os.clock()
for index = 1, 100000 do
    memory.store(pointer, 0, "uint32", index)
    total = total + memory.load(pointer, 0, "uint32")
end
assert(total == 5000050000)
io.write(string.format('{"case":"scalar-store-load","steps":100000,"seconds":%.9f}\n', os.clock() - start))
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 1000 do
    local id = memory.lease(pointer, 4096)
    assert(memory.releaseLease(id))
end
local retained = collectgarbage("count") - before
collectgarbage("restart")
io.write(string.format('{"case":"lease-metadata","steps":1000,"uncollectedKiB":%.3f}\n', retained))
