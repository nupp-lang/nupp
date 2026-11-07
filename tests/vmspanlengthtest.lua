local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local M = {}
local sequence = 0

local function fixture(typeName, expectedCode)
    sequence = sequence + 1
    local name = "vmspanlengthfixture" .. sequence
    local path = "=" .. name .. ".nupp"
    local parsed = parser.parse(
        "module "
        .. name
        .. "\nlocal {type Span, type WriteSpan, type FixedSpan, type FixedWriteSpan, type Writable, type FixedWritable} = require(\"binary.span\")\nexport function length("
        .. "borrows value: "
        .. typeName:gsub(
            "span%.",
            ""
        ) .. "): integer\n    return #value\nend\n",
        path
    )
    assert(#parsed.errors == 0, "Span fixture parse")
    local diagnostics, moduleType = checker.check(
        parsed,
        path,
        environment.new(".", {
            memoryOnly = true,
            cache = false,
            nativeCompilerServices = false
        }),
        {moduleName = name, strict = false, lints = {["unused-binding"] = "off"}}
    )
    local matched = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            assert(expectedCode == diagnostic.code, diagnostic.msg)
            matched = true
        end
    end
    if expectedCode then
        assert(matched, "expected diagnostic " .. expectedCode)
        return
    end
    local length

    local function walk(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "unop" and node.op and node.op.text == "#" then
            length = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)
    assert(length, "Span fixture length node")
    local p = program.describe(
        {{name = name, path = path, parsed = parsed, diagnostics = diagnostics, type = moduleType}},
        name
    )

    return p, length, program.select(p, name, "length")
end

local function compile(p, owner)
    return program.compile(p, tagged.forVersion(8)).graphs[owner.id + 1]
end

local function count(g, opcode)
    local found = 0
    for _, block in ipairs(g.blocks) do
        for _, op in ipairs(block.op) do
            if op == opcode then
                found = found + 1
            end
        end
    end

    return found
end

function M.checkedSpanLengthsProjectTheirCount()
    for _, typeName in ipairs({
        "span.Span<uint8>",
        "span.WriteSpan<uint8>",
        "span.FixedSpan<uint8, 4>",
        "span.FixedWriteSpan<uint8, 4>",
        "span.Writable<uint8>",
        "span.FixedWritable<uint8, 4>",
        'span.Writable<uint8, "columnar">',
        "span.Span<uint8, \"columnar\">"
    }) do
        local p, node, owner = fixture(typeName)
        assert(
            node.indexedLength and node.indexedLength.descriptor,
            "checked view marker missing: " .. typeName .. " type=" .. require(
                "nupp.compiler.types"
            ).tostring(node.operand.inferredType)
        )
        local g = compile(p, owner)
        assert(
            count(g, "Len") == 0 and count(g, "GetIdx") == 1,
            typeName .. " Len=" .. count(g, "Len") .. " GetIdx=" .. count(g, "GetIdx")
        )
        local found = false
        for _, constant in ipairs(g.constants) do
            found = found or constant.kind == "str" and constant.value == "count"
        end
        assert(found, "checked span count field was not projected")
    end
end

function M.nestedOwnershipKeepsLayoutRefusals()
    fixture('span.Writable<uint8, "unpacked">', "NUPP2403")
    fixture('span.Span<uint8, "unpacked">', "NUPP2403")
end

function M.ordinaryLuaLengthsKeepTheirOperator()
    for _, typeName in ipairs({"string", "{integer}"}) do
        local p, node, owner = fixture(typeName)
        assert(node.indexedLength == nil, "ordinary value marked as view")
        local g = compile(p, owner)
        assert(count(g, "Len") == 1 and count(g, "GetIdx") == 0, "ordinary length changed: " .. typeName)
    end
end

function M.missingOrAlteredViewEvidenceIsRefused()
    local mutations = {
        function(node)
            node.indexedLength = nil
        end,
        function(node)
            node.indexedLength = true
        end,
        function(node)
            node.indexedLength.adapter = "forged"
        end,
        function(node)
            node.indexedLength.descriptor.nominal = {tag = "nominal"}
        end,
        function(node)
            node.indexedLength.descriptor.element = {tag = "any"}
        end,
        function(node)
            node.indexedLength.receiverDefinition = {}
        end
    }
    for _, mutate in ipairs(mutations) do
        local p, node, owner = fixture("span.Span<uint8>")
        mutate(node)
        local okay, refusal = pcall(compile, p, owner)
        assert(not okay and tostring(refusal):find("checked sealed view descriptor", 1, true), tostring(refusal))
    end
    local p, node, owner = fixture("string")
    node.indexedLength = {adapter = "span", descriptor = {nominal = node.operand.inferredType}}
    local okay, refusal = pcall(compile, p, owner)
    assert(not okay and tostring(refusal):find("checked sealed view descriptor", 1, true), tostring(refusal))
end

return M
