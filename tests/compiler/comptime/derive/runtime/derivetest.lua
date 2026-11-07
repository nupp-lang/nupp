local fixture = require("helpers.derive")
local testAssert = fixture.testAssert
local run = fixture.run

local program = require("helpers.derive").program

local M = {}

function M.constructsFreshMutableDefaults()
    local result = run(
        "derivetest.constructsFreshMutableDefaults",
        [[
local record Options
    tags: {string} = {}
    values: {[string]: integer} = {}
    point: {x: integer, label: string} = {x = 0, label = ""}
end
local left = Options()
local right = Options()
left.tags[1] = "changed"
left.values.changed = 1
left.point.x = 9
return {
    tags = #right.tags,
    changed = right.values.changed,
    x = right.point.x,
    distinct = left.tags ~= right.tags and left.values ~= right.values
        and left.point ~= right.point,
}
]]
    )
    testAssert.eq(result.tags, 0)
    testAssert.eq(result.changed, nil)
    testAssert.eq(result.x, 0)
    testAssert.eq(result.distinct, true)
end

function M.supportsNestedAndBoundedGenericDebugRecords()
    local result = run(
        "derivetest.supportsNestedAndBoundedGenericDebugRecords",
        [[
@derive(types.debug)
local record Item
    label: string
end

@derive(types.debug)
local record Box<T is types.Debug>
    value: T
end

local record Namespace
    @derive(types.debug)
    record Inner
        count: integer = 0
    end
end

local boxed: Box<Item> = Box(value = Item(label = "ok"))
local inner: Namespace.Inner = Namespace.Inner()
return {box = boxed:debug(), inner = inner:debug()}
]]
    )
    testAssert.eq(result.box, 'Box { value = Item { label = "ok" } }')
    testAssert.eq(result.inner, "Inner { count = 0LL }")
end

function M.debugsDerivedStructsAndRecordsHoldingThem()
    -- A struct's derived debug is the renderer itself; reading it as a custom
    -- method made the renderer call itself until the stack ran out.
    local result = run(
        "derivetest.debugsDerivedStructsAndRecordsHoldingThem",
        [[
@derive(types.debug)
local struct Point
    x: float64
    y: float32
end

@derive(types.debug)
local record Shape
    origin: Point
end

local point = Point(1, 2)
local shape = Shape(origin = point)
return {point = point:debug(), shape = shape:debug()}
]]
    )
    testAssert.eq(result.point, "Point { x = 1.0, y = 2.0 }")
    testAssert.eq(result.shape, "Shape { origin = Point { x = 1.0, y = 2.0 } }")
end

return M
