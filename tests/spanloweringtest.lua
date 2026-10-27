local testAssert = require("nupp.test")
-- Span checking: removed members, the trusted range, refused indexes, and the
-- view facts the compiler infers for a function body.
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function checked(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors")
    local diagnostics = check.check(result, "test.nupp", env)
    return result, diagnostics
end

local HEADER = [[
local span = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")
local struct Cell
    value: int32
end
]]

local M = {}

function M.removedSpanMembersAreUnknownMembers()
    for _, line in ipairs({"print(values.count)", "print(values:get(1).value)", "span.range(1, 1, values)",}) do
        local _, diagnostics = checked(
            HEADER .. "local function old(borrows values: span.Span<Cell>): nil\n    " .. line .. "\nend\n"
        )
        assert(diagnostics and #diagnostics > 0, line)
    end
end

function M.aLookalikeIndexedTypeCannotEnterTheTrustedRange()
    local _, diagnostics = checked(
        [[
local indexed = require("nupp.mem.indexed")
local record Fake
    @readonly count: integer
end
const fake = new Fake(count = 1)
const range = indexed.range(1, 1, fake)
print(range)
]]
    )
    local text = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        text[#text + 1] = diagnostic.msg or diagnostic.message
    end
    text = table.concat(text, "\n")
    assert(text:find("standard Span or SoA view", 1, true), text)
end

-- NaN fails every comparison, so a guard written `index < 1 or index > count`
-- would pass it, and a store would truncate it onto the parent's first element,
-- outside the slice. Every index, slice bound, split point and count must refuse
-- NaN and a fraction, and leave the storage as it was.
function M.nanAndFractionalIndexesAreRefused()
    local source = [[
local array = require("nupp.mem.array")
local Probe = {}
function Probe.storage(): array.Array<int32>
    const owned = array.scalar(array.int32, 4)
    const values = owned:write()
    for at = 1, 4 do
        values[at] = at as int32
    end
    nupp.drop(values)
    return owned
end
function Probe.element(borrows storage: array.Array<int32>, at: integer): int32
    return storage:read()[at]
end
function Probe.writeTail(exclusive storage: array.Array<int32>, index: integer): nil
    const values = storage:write()
    const tail = values:slice(3, 4)
    tail[index] = 99
    nupp.drop(tail)
    nupp.drop(values)
end
function Probe.writeSlice(exclusive storage: array.Array<int32>, index: integer): nil
    const values = storage:write()
    const part = values:slice(index, 4)
    part[1] = 99
    nupp.drop(part)
    nupp.drop(values)
end
function Probe.split(exclusive storage: array.Array<int32>, index: integer): nil
    const values = storage:write()
    do
        const parts = values:splitAt(index)
        parts.right[1] = 99
    end
    nupp.drop(values)
end
function Probe.readTail(borrows storage: array.Array<int32>, index: integer): int32
    const values = storage:read()
    const tail = values:slice(3, 4)
    return tail[index]
end
function Probe.sliceFirst(borrows storage: array.Array<int32>, index: integer): integer
    const values = storage:read()
    return #values:slice(index, 4)
end
function Probe.sliceLast(borrows storage: array.Array<int32>, index: integer): integer
    const values = storage:read()
    return #values:slice(1, index)
end
return Probe
]]
    local result, diagnostics = checked(source)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local probe = program.run(result, "nan-probe")
    for _, bad in ipairs({0 / 0, 1.5}) do
        for _, name in ipairs({"writeTail", "writeSlice", "split", "readTail", "sliceFirst", "sliceLast"}) do
            local storage = probe.storage()
            local ok, got = pcall(probe[name], storage, bad)
            assert(not ok, ("%s(%s) was accepted and gave %s"):format(name, tostring(bad), tostring(got)))
            -- Refused by the bounds check, or earlier, where an integer is required.
            local message = tostring(got)
            assert(
                message:find("out of bounds", 1, true)
                or message:find("cannot be negative", 1, true)
                or message:find("expected an exact integer", 1, true)
                or message:find("integer out of range", 1, true),
                ("%s(%s): %s"):format(name, tostring(bad), tostring(got))
            )
            for at = 1, 4 do
                testAssert.equal(
                    probe.element(storage, at),
                    at,
                    ("%s(%s) left element %d"):format(name, tostring(bad), at)
                )
            end
        end
    end
end

function M.privateViewGraphsRejectCyclesAndInvalidSlots()
    local viewfacts = require("nupp.compiler.viewfacts")
    local graph = {version = 1, root = 1, nodes = {{kind = "funcbody", children = {1}}}, definitions = {}, params = {}}
    assert(viewfacts.instantiate(graph, {}, "bad", {line = 1, col = 1, offset = 1}) == nil)
    graph.nodes[1].children = {2}
    assert(viewfacts.instantiate(graph, {}, "bad", {line = 1, col = 1, offset = 1}) == nil)
    graph.nodes[1].children = {}
    graph.params = {1}
    assert(viewfacts.instantiate(graph, {}, "bad", {line = 1, col = 1, offset = 1}) == nil)
end

function M.privateViewBodiesRejectEscapingTablesAndViewReassignment()
    local viewfacts = require("nupp.compiler.viewfacts")
    for _, operation in ipairs({
        "return {values}",
        "values = other return 0",
        "return (values as any)",
        "return values == other"
    }) do
        local result = checked(
            [[local span = require("nupp.mem.span")
local function work(borrows values: span.Span<uint8>, borrows other: span.Span<uint8>): any
]]
            .. operation
            .. "\nend\nreturn work"
        )
        local info = result.analysis.functions[1]
        local artifact = viewfacts.infer(info.body)
        assert(not artifact.nodes, "unsupported runtime operations must not be erased as type syntax")
    end
end

function M.privateArtifactsRejectWideAndMultilineLiterals()
    local viewfacts = require("nupp.compiler.viewfacts")
    local inlinefacts = require("nupp.compiler.inlinefacts")
    for _, case in ipairs({
        {result = "uint64", expression = "5"},
        {result = "string", expression = "[=[first\nsecond]=]"},
    }) do
        for _, view in ipairs({false, true}) do
            local parameter = view and "borrows values: span.Span<uint8>" or "value: number"
            local result = checked(
                'local span = require("nupp.mem.span")\nlocal function work('
                .. parameter
                .. "): "
                .. case.result
                .. " return "
                .. case.expression
                .. " end\nreturn work"
            )
            local body = result.analysis.functions[1].body
            local artifact = view and viewfacts.infer(body) or inlinefacts.infer(body)
            assert(artifact.reason, "wide and multiline literals keep their original checked body")
        end
    end
end

return M
