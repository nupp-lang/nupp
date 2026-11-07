local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local testAssert = require("assert")
local HERE = require("helpers.paths").tests
local M = {}
local EXECUTABLE = "vm-column-simd"

function M.columnFieldsUsePackedDescriptorsAndEvaluateArgumentsOnce()
    local env = envMod.new(HERE .. "/..", {cache = false})
    local parsed = parser.parse(
        [[
local Array = table.Array
local span = require("bytes.span")
local simd = require("simd")
local struct Row
    x: float32
    y: float32
end
local trace = ""
local species = assert(simd.species(Array.float, 2))
local function position(value: integer): integer
    trace = trace .. "i"
    return value
end
local function mask(value: simd.Mask<float32, simd.Fixed<2>>): simd.Mask<float32, simd.Fixed<2>>
    trace = trace .. "m"
    return value
end
local function vector(value: simd.Vector<float32, simd.Fixed<2>>): simd.Vector<float32, simd.Fixed<2>>
    trace = trace .. "v"
    return value
end
local function update(exclusive rows: span.WriteSpan<Row, "columnar">): nil
    local cursor: uint32 = 0
    while cursor < #rows do
        local active = species:tail(#rows - cursor)
        local values = species:load(rows, position(cursor + 1), "x", mask(active))
        species:store(rows, position(cursor + 1), "y", vector(values + 10), mask(active))
        cursor = cursor + species.lanes
    end
end
local values = Array.alloc(ffi.typeof<Row>(), 3, "columnar")
do local rows = values:write() ;
    for index = 1, #rows do rows[index] = Row(index, 0) end
    update(rows)
end
local rows = values:read()
return {rows[1].x, rows[3].x, rows[1].y, rows[3].y, trace}
]],
        "column-simd.nupp"
    )
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "column-simd.nupp", env, {moduleName = EXECUTABLE})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity == "warning", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local result = program.run(parsed, EXECUTABLE, "column-simd.nupp")
    testAssert.deepeq(result, {1, 3, 11, 13, "imivmimivm"}, "column identities, tail, and operand order")
    local fields = {}
    for _, token in ipairs(parsed.tokens) do
        if token.soaColumn then
            fields[token.soaColumn.identity] = token.soaColumn.ordinal
        end
    end
    testAssert.eq(fields["Row.x"], 1, "loaded field identity")
    testAssert.eq(fields["Row.y"], 2, "stored field identity")
end

function M.publicFloatWitnessesKeepPhysicalKindsAndWidths()
    local kernels = require("nupp.compiler.vm.kernels")
    local graph = require("nupp.compiler.vm.graph")
    local env = envMod.new(HERE .. "/..", {cache = false})
    for _, entry in ipairs({
        {name = "float", kind = 8, size = 4, lanes = 4},
        {name = "number", kind = 9, size = 8, lanes = 2},
    }) do
        for _, width in ipairs({false, 4}) do
            local source = [[
local Array = table.Array
local simd = require("simd")
local function width(): float64
    local species = simd.species(Array.]]
                .. entry.name
                .. (
                    width and ", " .. width or ""
                ) .. [[)
    local value = species:splat(1.0)
    return species.lanes + 0.0
end
]]
            local parsed = parser.parse(source, "public-witness-" .. entry.name .. ".nupp")
            testAssert.eq(#parsed.errors, 0, "syntax errors")
            local diagnostics = check.check(parsed, "public-witness-" .. entry.name .. ".nupp", env)
            for _, diagnostic in ipairs(diagnostics) do
                assert(diagnostic.severity == "warning", diagnostic.code .. ": " .. diagnostic.msg)
            end
            local fn
            for _, stat in ipairs(parsed.root.blocks[1].stats) do
                if stat.kind == "localFuncStmt" then
                    fn = stat.body
                end
            end
            local result, reason = kernels.tryBuild(assert(fn))
            assert(result, reason)
            graph.verify(result)
            local splats, foundWidth = 0, false
            local lanes = width or entry.lanes
            for _, block in ipairs(result.blocks) do
                for index, op in ipairs(block.op) do
                    local args = block.args[index]
                    if op == "VSplatN" then
                        splats = splats + 1
                        testAssert.eq(args[2], entry.kind, "physical element kind")
                    elseif op == "IK" and args[1] == lanes then
                        foundWidth = true
                    end
                end
            end
            testAssert.eq(splats, math.ceil(lanes * entry.size / 16), "physical register count")
            assert(foundWidth, "public witness changed its default or explicit lane count")
        end
    end
end

function M.checkedDynamicAndPackedFieldsKeepExplicitBootstrapRefusals()
    for _, entry in ipairs({
        {layout = '"columnar"', field = "field", reason = "VM column SIMD requires a static field name"},
        {layout = '"packed"', field = '"x"', reason = "VM packed field SIMD is not supported"},
    }) do
        local source = [[
local Array = table.Array
local simd = require("simd")
local span = require("bytes.span")
local struct Row
    x: float32
end
local function read(borrows rows: span.Span<Row, ]]
            .. entry.layout
            .. [[>, field: string): nil
    local species = simd.species(Array.float, 2)
    local value = species:load(rows, 1, ]]
            .. entry.field
            .. [[)
end
return read
]]
        local parsed = parser.parse(source, "field-gap.nupp")
        testAssert.eq(#parsed.errors, 0, "syntax errors")
        local diagnostics = check.check(parsed, "field-gap.nupp", envMod.new(HERE .. "/..", {cache = false}))
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity == "warning", diagnostic.code .. ": " .. diagnostic.msg)
        end
        local ok, problem = pcall(program.image, parsed, "field-gap", "field-gap.nupp")
        assert(not ok, "the frozen VM cannot execute this accepted field form")
        assert(tostring(problem):find(entry.reason, 1, true), tostring(problem))
    end
end

return M
