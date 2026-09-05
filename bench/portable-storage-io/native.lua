-- Public API baselines. Call/copy accounting is a separate interpreter pass:
-- wrapping FFI in the timed pass would change exactly what we want to measure.
local root = assert(arg[1], "generated source directory required")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local ffi = require("ffi")
local standard = require("nupp.io")
local span = require("nupp.mem.span")
local transferred = {
    ["write-span"] = 4096,
    ["read-into"] = 4096,
    ["grow-bytewise"] = 1,
    ["scalar-write-u32"] = 4,
    ["scalar-write-u64"] = 8
}
local rounds = tonumber(os.getenv("NUPP_IO_ROUNDS") or "9")
local steps = tonumber(os.getenv("NUPP_IO_STEPS") or "10000")
local payload = string.rep("\1\2\3\4", 1024)
local sink = 0
local scenarios = {
    {
        "borrow-slice",
        function(n)
            local buffer = standard.newBuffer(payload)
            local total = 0
            for _ = 1, n do
                local view = buffer:readSpan():slice(2, 1024)
                total = total + view:get(1)
            end
            buffer:drop()

            return total
        end
    },
    {
        "scalar-read-u32",
        function(n)
            local total = 0
            for _ = 1, n do
                local reader = standard.newScalarReader(payload)
                total = total + reader:readUint32()
                reader:drop()
            end

            return total
        end
    },
    {
        "scalar-read-bulk",
        function(n)
            local total = 0
            for _ = 1, n do
                local reader = standard.newScalarReader(payload)
                for _ = 1, 1024 do
                    total = total + reader:readUint32()
                end
                reader:drop()
            end

            return total
        end,
        100
    },
    {
        "scalar-read-u64",
        function(n)
            local total = 0
            for _ = 1, n do
                local reader = standard.newScalarReader("\1\0\0\0\0\0\32\0")
                total = total + tonumber(reader:readUint64() - 9007199254740992ULL)
                reader:drop()
            end
            assert(total == n)

            return total
        end
    },
    {
        "scalar-write-u32",
        function(n)
            local writer = standard.newScalarWriter()
            for index = 1, n do
                writer:writeUint32(index)
            end
            local buffer = writer:buffer()
            assert(buffer:length() == n * 4)
            local reader = standard.newScalarReader(buffer:getString(n * 4 - 4, 4))
            local last = reader:readUint32()
            assert(last == n)
            reader:drop()
            writer:drop()

            return last
        end
    },
    {
        "scalar-write-u64",
        function(n)
            local writer = standard.newScalarWriter()
            for index = 1, n do
                writer:writeUint64(9007199254740992ULL + index)
            end
            local buffer = writer:buffer()
            assert(buffer:length() == n * 8)
            local reader = standard.newScalarReader(buffer:getString(n * 8 - 8, 8))
            local last = reader:readUint64()
            assert(last == 9007199254740992ULL + n)
            reader:drop()
            writer:drop()

            return tonumber(last - 9007199254740992ULL)
        end
    },
    {
        "write-span",
        function(n)
            local source = span.fromString(payload)
            local buffer = standard.newBuffer(#payload)
            local writer = buffer:newWriter()
            local total = 0
            for _ = 1, n do
                total = total + assert(writer:writeSpan(source))
            end
            writer:close()
            buffer:drop()

            return total
        end
    },
    {
        "read-into",
        function(n)
            local destination = standard.newBuffer(#payload)
            local total = 0
            for _ = 1, n do
                local reader = standard.newStringReader(payload)
                total = total + assert(reader:readInto(destination, 0, #payload))
                reader:close()
            end
            destination:drop()

            return total
        end
    },
    {
        "grow-bytewise",
        function(n)
            local buffer = standard.newBuffer()
            local writer = buffer:newWriter()
            for _ = 1, n do
                assert(writer:write("x"))
            end
            local length = buffer:length()
            writer:close()
            buffer:drop()

            return length
        end
    },
}
local function measure(name, operation, count)
    for _ = 1, 3 do
        sink = sink + operation(count)
    end
    local samples = {}
    for index = 1, rounds do
        collectgarbage("collect")
        local start = os.clock()
        sink = sink + operation(count)
        samples[index] = os.clock() - start
    end
    io.write(string.format('{"kind":"timing","case":%q,"steps":%d,"seconds":[', name, count))
    for index, sample in ipairs(samples) do
        io.write(index == 1 and "" or ",", string.format("%.9f", sample))
    end
    io.write("]}\n")
end

io.write(string.format('{"kind":"environment","jit":%q,"os":%q,"arch":%q}\n', jit.version, jit.os, jit.arch))
for _, scenario in ipairs(scenarios) do
    measure(scenario[1], scenario[2], math.max(1, math.floor(steps / (scenario[3] or 1))))
end

jit.off()
jit.flush()
local original = {new = ffi.new, copy = ffi.copy, fill = ffi.fill, string = ffi.string}
local counts
ffi.new = function(...)
    counts.allocations = counts.allocations + 1
    return original.new(...)
end
ffi.copy = function(destination, source, count)
    counts.copyCalls = counts.copyCalls + 1
    counts.copiedBytes = counts.copiedBytes + (count or #source + 1)
    return original.copy(destination, source, count)
end
ffi.fill = function(destination, count, value)
    counts.filledBytes = counts.filledBytes + count
    return original.fill(destination, count, value)
end
ffi.string = function(pointer, count)
    local value = original.string(pointer, count)
    counts.materializedBytes = counts.materializedBytes + #value
    return value
end
for _, scenario in ipairs(scenarios) do
    counts = {allocations = 0, copyCalls = 0, copiedBytes = 0, filledBytes = 0, materializedBytes = 0}
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    sink = sink + scenario[2](10)
    local retained = collectgarbage("count") - before
    collectgarbage("restart")
    io.write(
        string.format(
            '{"kind":"accounting","case":%q,"steps":10,"ffiNewCalls":%d,"copyCalls":%d,"ffiCopiedBytes":%d,"filledBytes":%d,"ffiMaterializedBytes":%d,"apiTransferBytes":%d,"uncollectedKiB":%.3f}\n',
            scenario[1],
            counts.allocations,
            counts.copyCalls,
            counts.copiedBytes,
            counts.filledBytes,
            counts.materializedBytes,
            (transferred[scenario[1]] or 0) * 10,
            retained
        )
    )
end
for name, operation in pairs(original) do
    ffi[name] = operation
end
assert(sink > 0)
