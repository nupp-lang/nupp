local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local fmt = require("nupp.compiler.fmt")
local optimize = require("nupp.compiler.optimize")

local function checked(source, dialect)
    local tree = parser.parse(source, "do-expression.g.nupp")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local diagnostics = check.check(tree, "do-expression.g.nupp", nil, {dialect = dialect})
    return tree, diagnostics
end

local function run(source, dialect, level)
    local tree, diagnostics = checked(source, dialect)
    assert(#diagnostics == 0, diagnostics[1] and diagnostics[1].msg)
    if level then
        optimize.run(tree, {level = level, filename = "do-expression.g.nupp", dialect = dialect or "luajit"})
    end
    local code, errors = gen.generate(tree, "do-expression.g.nupp")
    assert(#errors == 0, (errors[1] and errors[1].msg or "") .. "\n" .. code)
    local fn, failure = loadstring(code)
    assert(fn, tostring(failure) .. "\n" .. code)

    return fn(), code
end

local M = {}

function M.earlyYieldAndNestedExpressions()
    for _, dialect in ipairs({"luajit"}) do
        local value, code = run(
            [[
local function result(cached: integer?): number
    local value = do
        if found = cached then
            yield found
        end
        local computed = do
            local increment = 2
            yield increment + 1
        end
        yield computed
    end
    return value * 2
end
return result(5) * 100 + result(nil)
]],
            dialect
        )
        assert(value == 1006, tostring(value))
        assert(not code:find("(function", 1, true), "do lowering must not introduce a closure")
    end
end

function M.lazyOperandsAndFalsyResults()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local count = 0
local function probe(flag: boolean, optional: integer?): boolean
    local a = flag ? do count = count + 1; yield false end : do yield true end
    local b = flag and do count = count + 10; yield nil end
    local c = flag or do count = count + 100; yield true end
    local d = optional ?? do count = count + 1000; yield 9 end
    return a == not flag and b == (flag ? nil : false) and c and d == (optional ?? 9)
end
local okay = probe(true, 3) and probe(false, nil)
return okay and count == 1111
]],
                dialect
            )
        )
    end
end

function M.switchArmsAreOrdinaryDoExpressions()
    assert(
        run(
            [[
local function selectValue(flag: boolean): number
    local selector: number = 2
    return flag ? switch selector do
        case 1 -> 0
        else -> do
            if flag then yield 7 end
            yield 9
        end
    end : do yield 3 end
end
return selectValue(true) == 7 and selectValue(false) == 3
]]
        )
    )
end

function M.eagerOrderAndMultipleValues()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local events = ''
local function mark(label: string): string
    events = events .. label
    return label
end
local function tail(): (integer, integer)
    mark('c')
    return 3, 4
end
local a, b, c, d = mark('a'), do yield mark('b') end, tail()
return events == 'abc' and a == 'a' and b == 'b' and c == 3 and d == 4
]],
                dialect
            )
        )
    end
end

function M.yieldCrossesNestedLoopsAndContinueWrappers()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local visits = 0
local value = do
    for i = 1, 4 do
        if i == 1 then continue end
        for j = 1, 4 do
            visits = visits + 1
            if j == 2 then yield i * 10 + j end
        end
        visits = visits + 100
    end
    yield 0
end
return value == 22 and visits == 2
]],
                dialect
            )
        )
    end
end

function M.returnStillExitsTheFunction()
    assert(
        run(
            [[
local function answer(flag: boolean): number
    local value = do
        if flag then return 17 end
        yield 2
    end
    return value
end
return answer(true) == 17 and answer(false) == 2
]]
        )
    )
end

function M.loopControlCrossesExpressionBlocks()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local sum = 0
for i = 1, 5 do
    local value = do
        if i == 2 then continue
        elseif i == 4 then break end
        yield i
    end
    sum = sum + value
end
return sum == 4
]],
                dialect
            )
        )
    end
end

function M.scopesTypesAndMissingYields()
    local _, diagnostics = checked("local x: string = do yield 42 end")
    assert(diagnostics[1] and diagnostics[1].code == "NUPP2001")
    for _, source in ipairs({
        "local x = do local y = 1 end",
        "local flag: boolean = true\nlocal x = do if flag then yield 1 end end",
        "local x = do yield 1; print('unreachable') end",
    }) do
        local _, found = checked(source)
        assert(found[1] and found[1].code == "NUPP2141", source)
    end
    local tree = parser.parse("local x = do local function bad() yield 1 end; yield 2 end", "test.g.nupp")
    assert(#tree.errors > 0, "a function cannot yield to its lexical caller")
end

function M.ordinaryDoAndYieldCallsRemainOrdinary()
    assert(
        run(
            [[
local count = 0
local function yield(value: integer): nil count = count + value end
do yield(2) end
local value = do
    do yield(3) end
    yield count
end
return value == 5
]]
        )
    )
end

function M.comptimeSupportsNestedBlockResults()
    assert(
        run(
            [[
const value = comptime do
    local result = do
        for i = 1, 3 do
            if i == 2 then yield i end
        end
        yield 0
    end
    return result + 3
end
return value == 5
]]
        )
    )
end

function M.conditionsAndLoopHeaders()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local visits = 0
local optional: number? = 4
if do yield false end then
    visits = 100
elseif found = do yield optional end then
    visits = visits + found
else
    visits = 200
end
while do yield visits < 7 end do
    visits = visits + 1
end
repeat
    local stop = visits == 9
    visits = visits + 1
until do yield stop end
for i = do yield 1 end, do yield 2 end do visits = visits + i end
for _, value in ipairs(do local items = {2, 3}; yield items end) do visits = visits + value end
local f = |x: number| -> (do yield x + 1 end)
return visits == 18 and f(4) == 5
]],
                dialect
            )
        )
    end
end

function M.repeatContinueEvaluatesBlockConditionInScope()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local visits, checks = 0, 0
repeat
    visits = visits + 1
    local stop = visits >= 3
    if visits == 2 then continue end
until do checks = checks + 1; yield stop end
return visits == 3 and checks == 3
]],
                dialect
            )
        )
    end
end

function M.tableIndexAndAssignmentOrder()
    assert(
        run(
            [[
local target = {10, 20}
local index: integer = 1
local original = target
target[index], index = do target = {30, 40}; yield 11 end, 2
local values = {[do local key = 'key'; yield key end] = do yield original[1] end, do yield 7 end}
return original[1] == 11 and target[1] == 30 and index == 2 and values.key == 11 and values[1] == 7
]]
        )
    )
end

function M.safeNavigationAndMethodLookupOrder()
    for _, dialect in ipairs({"luajit"}) do
        local okay, code = run(
            [[
local count = 0
local absent: any = nil
local obj: any = {value = 5}
function obj:read(extra) return self.value + extra end
local original = obj.read
local value = obj:read(do obj.read = function() return 99 end; yield 2 end)
obj.read = original
local a = absent?.[do count = count + 1; yield 1 end]
local b = absent?.(do count = count + 1; yield 1 end)
local c = absent?.:read(do count = count + 1; yield 1 end)
local d = obj:missing?.(do count = count + 1; yield 1 end)
local e = obj?.:read(do count = count + 1; yield 3 end)
absent?.:read(do count = count + 1; yield 3 end)
obj?.:read(do yield 3 end)
return value == 7 and a == nil and b == nil and c == nil and d == nil and e == 8 and count == 1
]],
            dialect
        )
        assert(okay)
        assert(not code:find("(function", 1, true), "guarded block expressions must not introduce closures")
    end
end

function M.formatRoundTrip()
    local source = "local value=do\nlocal n=2\nif n>1 then yield n else yield 0 end\nend\nreturn value\n"
    local formatted = fmt.format(source)
    assert(formatted:find("    local n = 2", 1, true), formatted)
    assert(fmt.format(formatted) == formatted)
    assert(run(formatted) == 2)
end

function M.compoundAndGuardedAssignments()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local n = 2
n += do n = 100; yield 3 end
local count = 0
local absent: any = nil
absent?.value = do count = count + 1; yield 3 end
absent?.[do count = count + 1; yield 1 end] = do count = count + 1; yield 4 end
absent?.value += do count = count + 1; yield 3 end
local obj: any = {value = 4}
obj.value ??= do count = count + 1; yield 3 end
obj?.value += do yield 2 end
return n == 5 and count == 0 and obj.value == 6
]],
                dialect
            )
        )
    end
end

function M.optimizerPreservesBlockSideEffects()
    for _, level in ipairs({1, 2}) do
        for _, dialect in ipairs({"luajit"}) do
            assert(
                run(
                    [[
local n = 0
for i = 1, 4 do
    local value = do
        n = n + 1
        if i == 2 then yield 10 end
        yield n
    end
    n = n + value
end
return n == 58
]],
                    dialect,
                    level
                )
            )
        end
    end
end

function M.returnInsideAShortFunctionExpressionStaysInThatFunction()
    assert(
        run(
            [[
local function outer(): number
    local f = |flag: boolean| -> (do
        if flag then return 7 end
        yield 2
    end)
    return f(true) * 10 + f(false)
end
return outer() == 72
]]
        )
    )
end

function M.safeCallsPreserveMultipleResults()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local function pair(value: number): (number, number) return value, value + 1 end
local call: any = pair
local a, b = call?.(do yield 4 end)
local obj: any = {}
function obj:pair(value) return value, value + 2 end
local c, d = obj?.:pair(do yield 6 end)
local function count(...) return select('#', ...) end
local missing: any = nil
return a == 4 and b == 5 and c == 6 and d == 8 and count(missing?.(do yield 4 end)) == 1
]],
                dialect
            )
        )
    end
end

function M.loopHeaderControlKeepsItsAuthoredTarget()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local total, budget = 0, 0
for i = 1, 3 do
    while do
        budget = budget + 1
        if budget > 10 then return false end
        if i == 1 then continue
        elseif i == 2 then break end
        yield false
    end do
        total = total + 100
    end
    total = total + 10
end
for i = 1, 3 do
    repeat
        total = total + 1
        if total == 1 then continue end
    until do
        budget = budget + 1
        if budget > 10 then return false end
        if i == 1 then continue
        elseif i == 2 then break end
        yield true
    end
    total = total + 10
end
return total == 2
]],
                dialect
            )
        )
    end
end

function M.loopHeaderExitsRunAutomaticCleanup()
    for _, dialect in ipairs({"luajit"}) do
        assert(
            run(
                [[
local closed, visits = 0, 0
local record Resource
    id: number
end
local function closeResource(takes value: Resource): nil
    closed = closed + 1
end
local function openResource(id: number): affine(Resource, closeResource)
    return new Resource(id = id)
end
for i = 1, 3 do
    repeat
        local resource = openResource(i)
        visits = visits + 1
    until do
        if visits > 10 then return false end
        if resource.id == 1 then continue
        elseif resource.id == 2 then break end
        yield true
    end
    visits = visits + 100
end
return closed == 2 and visits == 2
]],
                dialect
            )
        )
    end
end

return M
