local fs = require("nupp.compiler.fs")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local metadata = require("nupp.compiler.vm.metadata")
local M = {}
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")

function M.checkedDeclarationsMatchTheMeasuredDarwinCLayouts()
    local specifications = {
        {
            "compressioncodec",
            "ZStream",
            112,
            {next_in = 0, avail_in = 8, total_in = 16, next_out = 24, avail_out = 32, total_out = 40, state = 56}
        },
        {"cryptocodec", "Parameter", 40, {key = 0, data_type = 8, data = 16, data_size = 24, return_size = 32}},
    }
    for _, spec in ipairs(specifications) do
        local name = "nupp.runtime.core." .. spec[1]
        local path = ROOT .. "/src/nupp/runtime/core/" .. spec[1] .. ".nupp"
        local parsed = parser.parse(assert(fs.readFile(path)), path)
        assert(#parsed.errors == 0, "codec source must parse")
        local env = environment.new(ROOT, {cache = false, nativeCompilerServices = false, config = {include = {"src"}}})
        for _, diagnostic in ipairs(checker.check(parsed, path, env, {moduleName = name})) do
            assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
        end
        local declaration
        for _, block in ipairs(parsed.root.blocks) do
            for _, node in ipairs(block.stats) do
                if node.name and node.name.text == spec[2] then
                    declaration = node;
                    break
                end
            end
        end
        assert(declaration, "missing checked C declaration: " .. spec[2])
        local layout = metadata.structLayout(declaration, "aarch64-apple-darwin")
        assert(
            layout.supported and layout.size == spec[3] and layout.alignment == 8,
            "C ABI layout mismatch: " .. spec[2]
        )
        local remaining = {}
        for field, offset in pairs(spec[4]) do
            remaining[field] = offset
        end
        for _, field in ipairs(layout.fields) do
            if remaining[field.name] ~= nil then
                assert(field.offset == remaining[field.name], "C ABI field mismatch: " .. field.name)
                remaining[field.name] = nil
            end
        end
        assert(next(remaining) == nil, "missing measured C ABI field")
    end
end

return M
