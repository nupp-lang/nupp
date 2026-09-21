local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local env = require("nupp.compiler.env").new(".")

local function compile(source, dialect, optimized)
    local parsed = parser.parse(source, "indexedassignment.g.nupp")
    assert(#parsed.errors == 0, "fixture parse failure")
    local diagnostics = check.check(parsed, "indexedassignment.g.nupp", env, {dialect = dialect})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity == "warning", diagnostic.code .. ": " .. diagnostic.msg)
    end
    if optimized then
        require("nupp.compiler.optimize").run(parsed, {level = 1})
    end
    local code, generated = gen.generate(parsed, "indexedassignment")
    assert(#generated == 0, generated[1] and generated[1].msg)

    return assert(loadstring(code, "@indexedassignment"))(), code
end

local M = {}
function M.spanAssignmentsPreserveLocationsOrderAndTupleAdjustment()
    local source = [[
local span = require("nupp.mem.span")
local u32 = nupp.math.u32
local function apply(exclusive values: span.WriteSpan<number>, trace: {number}): number
    local function index(mark: number): uint32
        trace[#trace + 1] = mark
        return u32.wrap(1)
    end
    local function value(mark: number): number
        trace[#trace + 1] = mark
        return mark
    end
    values[index(1)], values[index(2)] = value(3), value(4)
    local first = values[u32.wrap(1)]
    local function pair(): (number, number) return 7, 8 end
    values[u32.wrap(1)], values[u32.wrap(2)] = pair()
    assert(values[u32.wrap(1)] == 7 and values[u32.wrap(2)] == 8)
    values[u32.wrap(1)], values[u32.wrap(2)] = pair(), 6
    assert(values[u32.wrap(1)] == 7 and values[u32.wrap(2)] == 6)
    local missing: number? = 42
    values[u32.wrap(1)], missing = 5
    assert(missing == nil)
    values[u32.wrap(1)], values[u32.wrap(2)] = pair()
    local key = u32.wrap(1)
    key, values[key] = u32.wrap(2), 9
    return first * 100 + values[u32.wrap(1)] * 10 + values[u32.wrap(2)]
end
return apply
]]
    for _, dialect in ipairs({"luajit"}) do
        local apply = compile(source, dialect)
        local trace, data = {}, {0, 0}
        local view = {
            get = function(_, i)
                return data[i]
            end,
            set = function(_, i, value)
                data[i] = value
            end,
        }
        assert(apply(view, trace) == 398, "aliased stores and tuple expansion")
        assert(table.concat(trace, ",") == "1,2,3,4", "target indices precede RHS evaluations")
    end
end

function M.mixedAssignmentsFreezeTableReceiversBeforeRebinding()
    local source = [[
local span = require("nupp.mem.span")
local u32 = nupp.math.u32
local function apply(exclusive values: span.WriteSpan<number>, trace: {number}): number
    local current: {number} = {10}
    local original = current
    local function receiver(): {number}
        trace[#trace + 1] = 1
        return current
    end
    local function index(): uint32
        trace[#trace + 1] = 2
        return u32.wrap(1)
    end
    local function value(): number
        trace[#trace + 1] = 3
        return 4
    end
    values[u32.wrap(1)], receiver()[index()], current = 3, value(), {20}
    return values[u32.wrap(1)] * 100 + original[1] * 10 + current[1]
end
return apply
]]
    for _, dialect in ipairs({"luajit"}) do
        local apply = compile(source, dialect)
        local trace, data = {}, {0}
        local view = {
            get = function(_, i)
                return data[i]
            end,
            set = function(_, i, value)
                data[i] = value
            end
        }
        assert(apply(view, trace) == 360, "table receiver remains the original object")
        assert(table.concat(trace, ",") == "1,2,3", "receiver and index precede RHS")
    end
end

function M.optimizedVirtualViewsKeepSimultaneousStores()
    local source = [[
local span = require("nupp.mem.span")
local function apply(exclusive storage: number[?]): number
    const values = span.writeCarray(storage, 2)
    values[1], values[2] = 3, 4
    values[1], values[1] = values[2], values[1]
    local result = values[1] * 10 + values[2]
    drop values
    return result
end
return apply
]]
    local ffi = require("ffi")
    for _, optimized in ipairs({false, true}) do
        local apply, code = compile(source, "luajit", optimized)
        if optimized then
            assert(not code:find(".writeCarray(", 1, true), "exercise the virtual view path")
        end
        assert(apply(ffi.new("double[2]")) == 44, "virtual view aliased store semantics")
    end
end

function M.temporaryStructFieldReceiversRemainRefused()
    local source = [[
local span = require("nupp.mem.span")
local u32 = nupp.math.u32
local struct Cell value: number end
local function apply(factory: function(): span.WriteSpan<Cell>, trace: {number}): nil
    local function index(mark: number): uint32
        trace[#trace + 1] = mark
        return u32.wrap(1)
    end
    local function value(mark: number): number
        trace[#trace + 1] = mark
        return mark
    end
    factory()[index(2)].value, factory()[index(4)].value = value(5), value(6)
end
return apply
]]
    for _, dialect in ipairs({"luajit"}) do
        local parsed = parser.parse(source, "indexedassignment.g.nupp")
        assert(#parsed.errors == 0)
        local diagnostics = check.check(parsed, "indexedassignment.g.nupp", env, {dialect = dialect})
        local refused = false
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.code == "NUPP2619" then
                assert(diagnostic.line > 0 and diagnostic.col > 0, "positioned temporary-root refusal")
                refused = true
            end
        end
        assert(refused, "temporary struct references require a rooted receiver")
    end
end

function M.rootedStructFieldsEvaluateIndicesOnce()
    local source = [[
local span = require("nupp.mem.span")
local u32 = nupp.math.u32
local struct Cell value: number end
local function apply(exclusive values: span.WriteSpan<Cell>, trace: {number}): nil
    local function index(mark: number): uint32
        trace[#trace + 1] = mark
        return u32.wrap(1)
    end
    local function value(mark: number): number
        trace[#trace + 1] = mark
        return mark
    end
    values[index(1)].value, values[index(2)].value = value(3), value(4)
end
return apply
]]
    for _, dialect in ipairs({"luajit"}) do
        local apply = compile(source, dialect)
        local trace, row, reads = {}, {value = 0}, 0
        local view = {
            getMut = function()
                reads = reads + 1;
                return row
            end
        }
        apply(view, trace)
        assert(row.value == 3, "leftmost aliased field wins")
        assert(reads == 2, "each mutable row receiver is evaluated once")
        assert(table.concat(trace, ",") == "1,2,3,4", "field index/RHS order")
    end
end

return M
