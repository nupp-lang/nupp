-- Gate A1's paired comparison: the same kernels built by the C lowering and
-- by LLVM, loaded into one process, checked bit for bit and timed interleaved.
--
--   luajit compare.lua C_LIBRARY LLVM_LIBRARY LLVM_UNIT.ll [ROUNDS]
--
-- Every exported kernel in the unit is called through the entry ABI both
-- backends share. A span parameter the kernel writes is a fresh output; one
-- it reads is filled with seeded values. Element types are named below, by
-- kernel, because the ABI carries only pointers.
local ffi = require("ffi")
io.stdout:setvbuf("no")

local cPath, llvmPath, unitPath, roundsText = arg[1], arg[2], arg[3], arg[4]
assert(cPath and llvmPath and unitPath, "usage: compare.lua C_LIBRARY LLVM_LIBRARY LLVM_UNIT.ll [ROUNDS]")
local ROUNDS = tonumber(roundsText or "15")

-- The span element type of each kernel; `double` when absent. GATE_ELEMENTS
-- adds `name=ctype` pairs, comma separated, for another project's kernels.
local ELEMENT = {cross_lane = "int32_t"}
for name, ctype in (os.getenv("GATE_ELEMENTS") or ""):gmatch("([%w_]+)=([%w_]+)") do
    ELEMENT[name] = ctype
end

-- GATE_FILL=utf8 fills byte inputs with valid UTF-8 text, which a validator
-- reads to the end, instead of random bytes it would stop in early.
local UTF8 = "h\195\169llo w\195\182rld \226\130\172 \240\157\132\158 plain ascii text "

local SIZES = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 63, 65539}

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end

-- One kernel per exported definition: its symbol, logical name, result and
-- parameters as (kind, readonly).
local kernels = {}
for line in read(unitPath):gmatch("[^\n]+") do
    local result, symbol, open = line:match("^define (%S+) @(ks_[%w_]+)()%(")
    local params = nil
    if open then
        -- The parameter list, to its balancing parenthesis: attributes like
        -- `captures(none)` nest.
        local depth, close = 0, nil
        for at = open, #line do
            local ch = line:sub(at, at)
            depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
            if depth == 0 then
                close = at
                break
            end
        end
        -- Attributes with arguments (`range(i64 0, N)`) carry commas of their own.
        params = line:sub(open + 1, close - 1):gsub("range%b()", "")
    end
    if symbol and not symbol:find("_forced_scalar", 1, true) and not symbol:find("_layout_", 1, true) then
        local logical = symbol:match("^ks_%x+_(.-)__%w+$") or symbol
        local list = {}
        for param in (params .. ", "):gmatch("(.-), ") do
            local kind = param:match("^(%S+)")
            if kind == nil then
                break
            end
            list[#list + 1] = {kind = kind, readonly = param:find("readonly", 1, true) ~= nil, name = param:match("%%(%S+)$")}
        end
        kernels[#kernels + 1] = {symbol = symbol, name = logical, result = result, params = list}
    end
end
table.sort(kernels, function(a, b) return a.name < b.name end)
-- GATE_ONLY=name keeps one kernel, for rerunning a single measurement.
local only = os.getenv("GATE_ONLY")
if only then
    local kept = {}
    for _, kernel in ipairs(kernels) do
        if kernel.name == only then
            kept[#kept + 1] = kernel
        end
    end
    kernels = kept
end

local CTYPE = {double = "double", float = "float", i64 = "uint64_t", i32 = "uint32_t", ptr = "void *", void = "void"}
local declarations = {}
for _, kernel in ipairs(kernels) do
    local params = {}
    for _, param in ipairs(kernel.params) do
        params[#params + 1] = assert(CTYPE[param.kind], "no C type for " .. param.kind)
    end
    declarations[#declarations + 1] = ("%s %s(%s);"):format(
        assert(CTYPE[kernel.result], "no C type for " .. kernel.result),
        kernel.symbol,
        #params == 0 and "void" or table.concat(params, ", ")
    )
end
ffi.cdef(table.concat(declarations, "\n"))
ffi.cdef("int clock_gettime(int, struct timespec *); struct timespec { long tv_sec; long tv_nsec; };")

local libraries = {c = ffi.load(cPath), llvm = ffi.load(llvmPath)}

local function now()
    local t = ffi.new("struct timespec")
    ffi.C.clock_gettime(6, t) -- CLOCK_UPTIME_RAW on Darwin; monotonic elsewhere
    return tonumber(t.tv_sec) + tonumber(t.tv_nsec) * 1e-9
end

-- A deterministic generator, so both backends see the same inputs.
local seed = 12345
local function random()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end

--- Arguments for one call at size `n`, and the outputs to compare.
local function arguments(kernel, n)
    local element = ELEMENT[kernel.name] or "double"
    local args, outputs = {}, {}
    for _, param in ipairs(kernel.params) do
        if param.kind == "ptr" then
            -- Sixteen guard elements past the span catch a write outside it.
            local buffer = ffi.new(element .. "[?]", n + 16)
            for i = n, n + 15 do
                buffer[i] = 77
            end
            if param.readonly then
                for i = 0, n - 1 do
                    if os.getenv("GATE_FILL") == "utf8" and element == "uint8_t" then
                        buffer[i] = UTF8:byte(i % #UTF8 + 1)
                    else
                        buffer[i] = element == "double" and (random() * 8 - 2) or math.floor(random() * 200 - 100)
                    end
                end
            else
                outputs[#outputs + 1] = buffer
            end
            args[#args + 1] = buffer
        elseif param.kind == "i64" then
            args[#args + 1] = n
        elseif param.kind == "double" then
            args[#args + 1] = 1.5
        else
            args[#args + 1] = 0
        end
    end
    return args, outputs, element
end

local function bits(value, element)
    local cell = ffi.new(element .. "[1]", value)
    local width = ffi.sizeof(element)
    return ffi.string(cell, width)
end

-- Bit-identical outputs and results between the backends.
local mismatches = 0
for _, kernel in ipairs(kernels) do
    for _, n in ipairs(SIZES) do
        local saved = seed
        local argsC, outC, element = arguments(kernel, n)
        seed = saved
        local argsL, outL = arguments(kernel, n)
        if os.getenv("GATE_TRACE") then
            print("call", kernel.name, n)
        end
        local resultC = libraries.c[kernel.symbol](unpack(argsC))
        local resultL = libraries.llvm[kernel.symbol](unpack(argsL))
        local same = true
        if kernel.result == "double" then
            same = bits(resultC, "double") == bits(resultL, "double")
        elseif kernel.result ~= "void" then
            same = resultC == resultL
        end
        for label, outputs in pairs({c = outC, llvm = outL}) do
            for _, buffer in ipairs(outputs) do
                for i = n, n + 15 do
                    if buffer[i] ~= 77 then
                        print(("OVERRUN %s %s n=%d at element %d"):format(label, kernel.name, n, i))
                        os.exit(1)
                    end
                end
            end
        end
        for index, buffer in ipairs(outC) do
            if ffi.string(buffer, n * ffi.sizeof(element)) ~= ffi.string(outL[index], n * ffi.sizeof(element)) then
                same = false
            end
        end
        if not same then
            mismatches = mismatches + 1
            print(("MISMATCH %s n=%d c=%s llvm=%s"):format(kernel.name, n, tostring(resultC), tostring(resultL)))
        end
    end
end
print(("correctness: %d mismatches over %d kernels x %d sizes"):format(mismatches, #kernels, #SIZES))

-- Interleaved timing: per kernel and size, alternating which backend goes
-- first, each sample a batch long enough to measure.
local function batch(fn, args, calls)
    local start = now()
    for _ = 1, calls do
        fn(unpack(args))
    end
    return (now() - start) / calls
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

print(("%-22s %7s %12s %12s %8s"):format("kernel", "n", "C ns", "LLVM ns", "LLVM/C"))
for _, kernel in ipairs(kernels) do
    for _, n in ipairs({0, 1, 3, 7, 16, 17, 63, 65539}) do
        local args = arguments(kernel, n)
        local fnC, fnL = libraries.c[kernel.symbol], libraries.llvm[kernel.symbol]
        local calls = n > 1000 and 200 or 200000
        batch(fnC, args, calls)
        batch(fnL, args, calls)
        local ratios, cTimes, lTimes = {}, {}, {}
        for round = 1, ROUNDS do
            local c, l
            if round % 2 == 1 then
                c = batch(fnC, args, calls)
                l = batch(fnL, args, calls)
            else
                l = batch(fnL, args, calls)
                c = batch(fnC, args, calls)
            end
            cTimes[#cTimes + 1], lTimes[#lTimes + 1], ratios[#ratios + 1] = c, l, l / c
        end
        print(("%-22s %7d %12.1f %12.1f %8.3f"):format(kernel.name, n, median(cTimes) * 1e9, median(lTimes) * 1e9, median(ratios)))
    end
end
