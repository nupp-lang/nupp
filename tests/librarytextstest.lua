local test = require("assert")
local fs = require("nupp.compiler.fs")
local coretexts = require("nupp.compiler.vm.coretexts")
local generator = require("nupp.core.librarytextsgen")
local ROOT = require("helpers.paths").root
local PATH = ROOT .. "/src/nupp/runtime/core/librarytexts.nupp"
local M = {}

function M.generatedModuleFitsTheOrdinaryVmInitializer()
    local source = assert(fs.readFile(PATH))
    local parsed = require("nupp.compiler.syntax.parser").parse(source, PATH)
    test.eq(#parsed.errors, 0)
    local env = require("nupp.compiler.project.env").new(ROOT, {cache = false, nativeCompilerServices = false})
    local name = "nupp.runtime.core.librarytexts"
    local diagnostics = require("nupp.compiler.check").check(parsed, PATH, env, {moduleName = name})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local program = require("program")
    local image = program.image(parsed, name, PATH)
    assert(type(image) == "string" and #image > 0, "the full generated module must emit")
    if program.onVm() then
        assert(type(assert(rawget(_G, "__nupp_load_image"))(image)) == "function", "the emitted image must verify")
    end
end

function M.generatedExportsAndWordBytesMatchTheCanonicalTexts()
    local source = assert(fs.readFile(PATH))
    test.eq(source, generator.source(), "regenerate librarytexts from its canonical generator")
    local exports, branches, current = {}, {}, nil
    for line in source:gmatch("[^\n]+") do
        local name, id = line:match("^export const ([%w_]+): uint64 = (%d+)ULL$")
        if name then
            assert(not exports[name], "duplicate text export")
            exports[name] = tonumber(id)
        end
        local branch = line:match("^    if id == (%d+)ULL then$") or line:match("^    elseif id == (%d+)ULL then$")
        if branch then
            current = tonumber(branch)
            assert(not branches[current], "duplicate text branch")
            branches[current] = {}
        end
        for hex, count in line:gmatch("strings%.appendWord%(h, b, 0x(%x+)ULL, (%d+)ULL%)") do
            count = tonumber(count)
            assert(current and count >= 1 and count <= 8 and #hex <= count * 2)
            hex = string.rep("0", count * 2 - #hex) .. hex
            for at = #hex - 1, 1, -2 do
                branches[current][#branches[current] + 1] = string.char(tonumber(hex:sub(at, at + 1), 16))
            end
        end
    end
    for _, entry in ipairs(coretexts.all()) do
        test.eq(exports[entry.name], entry.id, "named text ids remain unchanged")
        test.eq(table.concat(assert(branches[entry.id])), entry.text, entry.name)
        exports[entry.name], branches[entry.id] = nil, nil
    end
    assert(next(exports) == nil and next(branches) == nil, "no unregistered text exports or branches")
end

return M
