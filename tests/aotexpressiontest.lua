-- Differential execution of statementful expressions through Lua and native C.
local test = require("assert")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local NUPP = HERE .. "/../bin/nupp"
local M = {}

local SOURCE = [[
module expressions
local span = require("nupp.mem.span")
const STRING_COMMAND = "ready\0go"
@aot
local function choose(value: number): number
    local seen = 1.0
    local result = seen + do
        seen = 5.0
        if value < 0 then yield 2.0 end
        yield switch value do
            case 0 -> do
                local extra = 7.0
                yield extra
            end
            else -> 9.0
        end
    end
    return result + seen
end

@aot
local function lazy(flag: boolean): number
    local count = 0.0
    local a = flag and do count = count + 1.0 yield true end
    local b = flag or do count = count + 10.0 yield false end
    local c = flag ? do count = count + 100.0 yield 1.0 end : do count = count + 1000.0 yield 2.0 end
    if a and b then return count + c end
    return count + c
end

@aot
local function nested(value: number): number
    return do
        if value < 0 then return 19.0 end
        for i = 1, 5 do
            if i == value then
                yield do
                    local x = switch value do case 2 -> 20.0 else -> 30.0 end
                    yield x + 1.0
                end
            end
        end
        yield 99.0
    end
end

@aot
local function whileHeader(): number
    local count = 0.0
    local total = 0.0
    local visits = 0.0
    while do count = count + 1.0 yield count < 5.0 end do
        visits = visits + 1.0
        if visits > 8.0 then return -1.0 end
        if count == 2.0 then continue end
        total = total + count
    end
    return total * 10.0 + count
end

@aot
local function repeatHeader(): number
    local count = 0.0
    local total = 0.0
    repeat
        count = count + 1.0
        if count > 8.0 then return -1.0 end
        local stop = count >= 4.0
        if count == 2.0 then continue end
        total = total + count
    until do yield stop end
    return total * 10.0 + count
end

@aot
local function headerExits(): number
    local total = 0.0
    local budget = 0.0
    for i = 1, 5 do
        while do
            budget = budget + 1.0
            if budget > 16.0 then return -1.0 end
            if i == 2 then continue
            elseif i == 4 then break end
            yield false
        end do
            total = total + 1000.0
            if total > 10000.0 then return -1.0 end
        end
        total = total + i
    end
    return total
end

@aot
local function switchExits(): number
    local total = 0.0
    for i = 1, 5 do
        local result = switch i do
            case 2 -> do continue end
            case 4 -> do break end
            else -> do yield i * 10.0 end
        end
        total = total + result
    end
    return total
end

@aot
local function elseifSetup(value: number): number
    local count = 0.0
    if value < 0 then return count
    elseif do count = count + 1.0 yield value == 0 end then return count
    elseif do count = count + 10.0 yield value == 1 end then return count
    else return count + 100.0 end
end

@aot
local function order(): number
    local x = 1.0
    local first, second = x, do x = 5.0 yield 7.0 end
    x, second = do x = 9.0 yield 3.0 end, x
    return first * 100.0 + second * 10.0 + x
end

@aot
local function booleanResult(value: number): boolean
    return switch value do
        case 1 -> do yield false end
        else -> do yield true end
    end
end

@aot
local function fixed(value: int32): int32
    return nupp.math.i32.wrap(switch value do
        case 1 -> do yield 31 end
        else -> do yield 47 end
    end)
end
local function combine(a: number, b: number, c: number): number
    return a * 100 + b * 10 + c
end
local function pair(): (number, number)
    return 7.0, 99.0
end
@aot
local function arguments(): number
    local x = 1.0
    return combine(x, do x = 2.0 yield 3.0 end, x)
end
@aot
local function mixed(flag: boolean): number
    return do
        if flag then
            local first: int32 = 7
            yield first
        end
        yield 1.5
    end
end
@aot
local function neverArm(value: number): number
    local result = switch value do
        case 0 -> do return 37 end
        else -> do yield true end
    end
    if result then return 41 end
    return 43
end
@aot
local function packed(): number
    return do yield pair() end
end
@aot
local function yieldFromHeader(): number
    return do
        local count = 0.0
        while do
            count = count + 1
            if count == 3 then yield true end
            yield count < 5
        end do
            if count == 3 then yield 29 end
        end
        yield 31
    end
end
@aot
local function repeatedOuterExits(): number
    local total = 0.0
    local budget = 0.0
    for i = 1, 5 do
        repeat
            total = total + i
        until do
            budget = budget + 1.0
            if budget > 16.0 then return -1.0 end
            if i == 2 then continue
            elseif i == 4 then break end
            yield true
        end
        total = total + 10
    end
    return total
end
@aot
local function booleanSelector(flag: boolean): number
    return switch flag do case true -> do yield 3 end case false -> 5 end
end
@aot
local function fractionalSelector(value: number): number
    return switch value do case 1.5 -> 7 case -2.25 -> 11 else -> 13 end
end
@aot
local function nilSelector(): number
    return switch nil do case nil -> do yield 17 end end
end
@aot
local function lazyReturns(flag: boolean): number
    local a = flag and do return 51 end
    local b = flag ? do return 53 end : do yield false end
    if a or b then return 57 end
    return 59
end
@aot
local function returningCondition(): number
    while do return 61 end do
    end
    return 63
end
@aot
local function nilBlock(): number
    local value = do yield nil end
    return switch value do case nil -> 67 end
end
@aot
local function textBlock(flag: boolean): string
    return do
        if flag then
            local text = "first"
            yield text
        end
        local text = "second"
        yield text
    end
end
@aot
local function stringSelector(command: string): number
    return switch command do
        case "" -> 0
        case "start", "run" -> 1
        case "stop" -> 2
        case (STRING_COMMAND) -> 8
        case "a\0b" -> 3
        case "a\0c" -> 4
        case "\255" -> 5
        case "λ" -> 6
        case "quote\"\\" -> 7
        else -> -1
    end
end
@aot
local function computedStringSelector(command: string): number
    local visits = 0.0
    local current = command
    local result = switch do visits = visits + 1 yield current end do
        case "start" -> do current = "stop" yield 9 end
        case "stop" -> do return 20 + visits end
        else -> -1
    end
    return result + visits * 10
end
@aot
local function staticStringSelector(): number
    return switch "a\0b" do case "a\0b" -> do local result = 23 yield result end end
end
@aot
local function capturedStringSelector(): number
    return switch (STRING_COMMAND) do case "ready\0go" -> 29 end
end
@aot
local function stringBlockSelector(flag: boolean): string
    return switch do
        local start = "start"
        if flag then yield start end
        local stop = "stop"
        yield stop
    end do
        case "start" -> do local result = "go" yield result end
        else -> do local result = "halt" yield result end
    end
end
@aot
local function repeatedStringSelector(command: string, count: integer): number
    local total = 0.0
    for i = 1, count do
        local label = i % 2 == 0 ? command : "other"
        total = total + switch label do case "start" -> 3 else -> 1 end
    end
    return total
end
@aot
local function countedHeaders(): number
    local first = 1.0
    local total = 0.0
    for i = first, do first = 9.0 yield 3 end do
        total = total + i
    end
    return total * 10.0 + first
end
@aot
local function countedHeaderExits(): number
    local total = 0.0
    for i = 1, 5 do
        for j = 1, do
            if i == 2 then continue
            elseif i == 4 then break end
            yield 1
        end do
            total = total + i * j
        end
        total = total + 10.0
    end
    return total
end
@aot
local function returningSwitchCondition(value: number): boolean
    while switch value do
        case 1 -> do return true end
        else -> do return false end
    end do
        return false
    end
    return false
end
@aot
local function mapped(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        local value = input[i]
        output[i] = do
            if value < 2 then yield value + 10 end
            yield switch value do
                case 3 -> do yield 30 end
                else -> value * 2
            end
        end
    end
end
@aot
local function mappedHeaders(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        local budget = 0.0
        while do
            budget = budget + 1
            if budget > 8 then return end
            local value = input[i]
            if value == 2 then continue
            elseif value == 4 then break end
            yield false
        end do
            output[i] = 1000
        end
        output[i] = input[i]
    end
end
@aot
local function repeatedStrings(count: integer): string
    local result = ""
    for i = 1, count do
        result = do
            if i % 2 == 0 then
                local text = "even"
                yield text
            end
            local text = "odd"
            yield text
        end
    end
    return result
end
export = {capturedStringSelector = capturedStringSelector, stringSelector = stringSelector, computedStringSelector = computedStringSelector, staticStringSelector = staticStringSelector, stringBlockSelector = stringBlockSelector, repeatedStringSelector = repeatedStringSelector, returningSwitchCondition = returningSwitchCondition, mappedHeaders = mappedHeaders, repeatedStrings = repeatedStrings, mapped = mapped, countedHeaders = countedHeaders, countedHeaderExits = countedHeaderExits, nilBlock = nilBlock, textBlock = textBlock, lazyReturns = lazyReturns, returningCondition = returningCondition, choose = choose, lazy = lazy, nested = nested, whileHeader = whileHeader, repeatHeader = repeatHeader, headerExits = headerExits, switchExits = switchExits, elseifSetup = elseifSetup, order = order, booleanResult = booleanResult, booleanSelector = booleanSelector, fractionalSelector = fractionalSelector, nilSelector = nilSelector, fixed = fixed, arguments = arguments, mixed = mixed, neverArm = neverArm, packed = packed, yieldFromHeader = yieldFromHeader, repeatedOuterExits = repeatedOuterExits}
]]

local SCRIPT = [[
local m = require("expressions")
assert(m.choose(-1) == 8)
assert(m.choose(0) == 13)
assert(m.choose(1) == 15)
assert(m.lazy(true) == 102)
assert(m.lazy(false) == 1012)
assert(m.nested(-1) == 19)
assert(m.nested(2) == 21)
assert(m.nested(3) == 31)
assert(m.nested(7) == 99)
assert(m.whileHeader() == 85)
assert(m.repeatHeader() == 84)
assert(m.headerExits() == 4)
assert(m.switchExits() == 40)
assert(m.elseifSetup(-1) == 0)
assert(m.elseifSetup(0) == 1)
assert(m.elseifSetup(1) == 11)
assert(m.elseifSetup(2) == 111)
assert(m.order() == 193)
assert(m.booleanResult(1) == false)
assert(m.booleanResult(0) == true)
assert(m.fixed(1) == 31)
assert(m.fixed(0) == 47)
assert(m.arguments() == 132)
assert(m.mixed(true) == 7)
assert(m.mixed(false) == 1.5)
assert(m.neverArm(0) == 37)
assert(m.neverArm(1) == 41)
assert(m.packed() == 7)
assert(m.yieldFromHeader() == 29)
assert(m.repeatedOuterExits() == 30)
assert(m.booleanSelector(true) == 3)
assert(m.booleanSelector(false) == 5)
assert(m.fractionalSelector(1.5) == 7)
assert(m.fractionalSelector(-2.25) == 11)
assert(m.fractionalSelector(1) == 13)
assert(m.nilSelector() == 17)
assert(m.lazyReturns(true) == 51)
assert(m.lazyReturns(false) == 59)
assert(m.returningCondition() == 61)
assert(m.returningSwitchCondition(1))
assert(not m.returningSwitchCondition(0))
assert(m.nilBlock() == 67)
assert(m.textBlock(true) == "first")
assert(m.textBlock(false) == "second")
for _, case in ipairs({
    {"", 0}, {"start", 1}, {"run", 1}, {"stop", 2}, {"a\0b", 3}, {"a\0c", 4},
    {"\255", 5}, {"λ", 6}, {"quote\"\\", 7}, {"a", -1}, {"a\0d", -1},
    {"a\0b\0", -1}, {"starter", -1}, {"Start", -1}, {"unknown", -1},
}) do
    assert(m.stringSelector(case[1]) == case[2], "string selector for " .. string.format("%q", case[1]))
end
assert(m.computedStringSelector("start") == 19)
assert(m.computedStringSelector("stop") == 21)
assert(m.computedStringSelector("other") == 9)
assert(m.staticStringSelector() == 23)
assert(m.capturedStringSelector() == 29)
assert(m.stringSelector("ready\0go") == 8)
assert(m.stringBlockSelector(true) == "go")
assert(m.stringBlockSelector(false) == "halt")
assert(m.repeatedStringSelector("start", 10000) == 20000)
assert(m.repeatedStringSelector("stop", 10000) == 10000)
assert(m.countedHeaders() == 69)
assert(m.countedHeaderExits() == 24)
local ffi = require("ffi")
local span = require("nupp.mem.span")
for _, count in ipairs({0, 1, 3, 17, 64}) do
    local input = ffi.new("double[?]", math.max(1, count))
    local output = ffi.new("double[?]", math.max(1, count))
    for i = 0, count - 1 do input[i] = i % 8 end
    local writable = span.writeCarray(output, count)
    m.mapped(writable, span.fromCarray(input, count))
    for i = 0, count - 1 do
        local value = input[i]
        local expected = value < 2 and value + 10 or value == 3 and 30 or value * 2
        assert(output[i] == expected, "mapped result at " .. i)
    end
    for i = 0, count - 1 do output[i] = -99 end
    m.mappedHeaders(writable, span.fromCarray(input, count))
    for i = 0, count - 1 do
        local expected = i < 4 and i ~= 2 and input[i] or -99
        assert(output[i] == expected, "mapped header result at " .. i)
    end
end
assert(m.repeatedStrings(10000) == "even")
assert(m.repeatedStrings(9999) == "odd")
print("expression results match")
]]

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

function M.nativeAndLuaAgreeOnValueBlocksAndSwitchExpressions()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    write(dir .. "/src/expressions.nupp", SOURCE)
    write(dir .. "/check.lua", 'package.path="build/native/?.lua;"..package.path;\n' .. SCRIPT)
    for _, policy in ipairs({"off", "require"}) do
        write(
            dir .. "/nupp.lua",
            (
                'return {include={"src"}, build={targets={native={kind="modules",entries={"expressions"},outDir="build/native",aot=%q}}}}'
            ):format(policy)
        )
        local pipe = assert(io.popen(("cd %q && %q build --target native 2>&1; echo __exit__:$?"):format(dir, NUPP)))
        local output = pipe:read("*a")
        pipe:close()
        local status = tonumber(output:match("__exit__:(%d+)%s*$"))
        test.equal(status, 0, policy .. " build at " .. dir .. ": " .. output)
        pipe = assert(io.popen(("cd %q && luajit check.lua 2>&1"):format(dir)))
        output = pipe:read("*a")
        pipe:close()
        test.equal(output:gsub("%s+$", ""), "expression results match", policy .. " at " .. dir)
    end
end

return M
