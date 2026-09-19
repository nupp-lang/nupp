-- Untimed shader conformance against Lua's numeric-for semantics.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local generated = require("counted")
local context = gpu.open()
local size = 257 -- Includes a partially populated dispatch workgroup.
local input = ffi.new("uint32_t[?]", size)
local output = ffi.new("uint32_t[?]", size)
for index = 0, size - 1 do
    input[index] = index * 17 + 3
end
local read = context:buffer(ffi.typeof("uint32_t"), size)
local write = context:buffer(ffi.typeof("uint32_t"), size)
context:upload(read, span.fromCarray(input, size))
local cases = {{1, 4}, {0, 0}, {3, 2}, {-2, 1}, {2147483645, 2147483647}, {-2147483648, -2147483646}}
local checked = 0

local function check(kernel, first, last, expected)
    local bound = kernel:compile(context):bind(write, read)
    if first == nil then
        bound:dispatch()
    else
        bound:dispatch(first, last)
    end
    context:enqueueDownload(write)
    context:synchronize()
    context:readDownloaded(write, span.writeCarray(output, size))
    for index = 0, size - 1 do
        assert(
            output[index] == input[index] + expected,
            ("counted shader differs at %d: %s versus %s"):format(index, output[index], input[index] + expected)
        )
    end
    checked = checked + 1
end

check(generated.literal, nil, nil, 68)
for _, range in ipairs(cases) do
    local first, last = range[1], range[2]
    local expected = 0
    for cursor = first, last do
        expected = expected + 1
        if cursor < 0 then
            expected = expected + 100
        end
        if cursor == 2147483647 then
            expected = expected + 1000
        end
        cursor = 99
    end
    check(generated.boundaries, first, last, expected)
    expected = 0
    for cursor = first, last do
        if cursor ~= first then
            local inner = 0
            while inner < 3 do
                inner = inner + 1
                if inner == 2 then
                    break
                end
                expected = expected + 1
            end
            for cursor = 1, 3 do
                if cursor == 2 then
                    break
                end
                expected = expected + 10
            end
            if cursor == 3 then
                break
            end
        end
    end
    check(generated.control, first, last, expected)
end
check(generated.snapshots, 1, 4, 1004)
check(generated.snapshots, 3, 2, 1000)
context:drop()
print(("counted GPU loops: %d cases, %d output values checked"):format(checked, checked * size))
