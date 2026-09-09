local fmt = require("nupp.compiler.fmt")
local envMod = require("nupp.compiler.env")
local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local gen = require("nupp.compiler.gen")

local M = {}
local sharedEnv = nil

local function formatted(source, env)
    sharedEnv = sharedEnv or envMod.new(".")
    local formatter = fmt.new({environment = env or sharedEnv})
    local output, errors = formatter:format(source, "format.g.nupp")
    assert(#errors == 0, errors[1] and errors[1].msg)
    local again, problems = formatter:format(output, "format.g.nupp")
    assert(#problems == 0, problems[1] and problems[1].msg)
    assert(again == output, "import formatting must be idempotent:\n" .. again)

    return output
end

local function compile(source)
    local env = envMod.new(".")
    local result = parser.parse(source, "format.g.nupp")
    local errors = check.check(result, "format.g.nupp", env)
    for _, err in ipairs(errors) do
        assert(err.severity == "warning" or err.severity == "off", tostring(err.code) .. ": " .. tostring(err.msg))
    end
    local code, problems = gen.generate(result, "format.g.nupp")
    assert(#problems == 0, problems[1] and problems[1].msg)

    return code
end

function M.bindsAbsoluteModuleCalls()
    local output = formatted('return nupp.io.files.read("a"), nupp.io.files.read("b")\n')
    assert(output:find('const files = require("nupp.io.files")', 1, true), output)
    assert(output:find('return files.read("a"), files.read("b")', 1, true), output)
end

function M.typeOnlyImportsRemainErased()
    local source = 'local function count(value: nupp.mem.span.Span<uint8>): integer\nreturn #value\nend\nreturn count\n'
    local output = formatted(source)
    assert(output:find('const {type Span} = require("nupp.mem.span")', 1, true), output)
    assert(output:find('value: Span<uint8>', 1, true), output)
    local before, after = compile(source), compile(output)
    assert(not before:find('require("nupp.mem.span")', 1, true), before)
    assert(not after:find('require("nupp.mem.span")', 1, true), after)
end

function M.turnsAnExistingModuleAliasIntoItsImport()
    local output = formatted('local files = nupp.io.files\nreturn files.read("a"), nupp.io.files.read("b")\n')
    assert(output == 'local files = require("nupp.io.files")\nreturn files.read("a"), files.read("b")\n', output)
end

function M.avoidsCapturingNamesInAnyScope()
    local output = formatted(
        'local files = 1\nlocal function read(files2)\nreturn nupp.io.files.read("a"), files2\nend\nreturn read, files\n'
    )
    assert(output:find('const files3 = require("nupp.io.files")', 1, true), output)
    assert(output:find('return files3.read("a"), files2', 1, true), output)
end

function M.respectsShadowedPackageRoots()
    local output = formatted(
        'local function fake(nupp)\nreturn nupp.io.files.read("a")\nend\nreturn nupp.io.files.read("b"), fake\n'
    )
    assert(output:find('return nupp.io.files.read("a")', 1, true), output)
    assert(output:find('return files.read("b"), fake', 1, true), output)
end

function M.avoidsTheLeafNameOfAQualifiedDeclaration()
    local output = formatted('local process = {}\ninterface process.Reader is nupp.io.Reader\nend\nreturn process\n')
    assert(output:find('const {type Reader as Reader2} = require("nupp.io")', 1, true), output)
    assert(output:find('interface process.Reader is Reader2', 1, true), output)
    compile(output)
end

function M.leavesIntrinsicsAndExplicitRequirePlacement()
    local output = formatted(
        'local function size()\nreturn nupp.sizeof(int32), require("nupp.io.files").read("a")\nend\nreturn size\n'
    )
    assert(not output:find('const files', 1, true), output)
    assert(output:find('nupp.sizeof(int32)', 1, true), output)
    assert(output:find('require("nupp.io.files").read', 1, true), output)
end

function M.preservesCommentsAndStrings()
    local output = formatted('-- nupp.io.files.read\nreturn "nupp.io.files.read", nupp.io.files.read("a")\n')
    assert(output:find('-- nupp.io.files.read', 1, true), output)
    assert(output:find('"nupp.io.files.read", files.read', 1, true), output)
    local inside = formatted('return nupp.io -- keep this\n.files.read("a")\n')
    assert(inside:find('-- keep this', 1, true), inside)
    assert(not inside:find('const files', 1, true), inside)
end

function M.importsFollowModuleHeaderAndPreserveDocblocks()
    local output = formatted(
        'module app.reader -- module comment\n\n--- Read a file.\nexport function read(): string?\nreturn nupp.io.files.read("a")\nend\n'
    )
    assert(output:find('module app.reader -- module comment\nconst files = require("nupp.io.files")', 1, true), output)
    assert(output:find('--- Read a file.\nexport function read', 1, true), output)
end

function M.keepsModuleDocumentationAheadOfImports()
    local output = formatted(
        'module format\n\n--[[A documented module.]]\nexport function read(): (string?, string?)\nreturn nupp.io.files.read("a")\nend\n'
    )
    assert(output:find('--[[A documented module.]]\nconst files', 1, true), output)
    local documented = require("nupp.compiler.doc.extract").extract(output, "format.g.nupp", "format")
    assert(documented.text == "A documented module.", documented.text)
end

function M.doesNotRewritePlainLuaOrDisabledFiles()
    local source = 'return nupp.io.files.read("a")\n'
    assert(fmt.format(source, "example.lua") == source)
    local disabled = '@!nofmt\n' .. source
    assert(fmt.format(disabled, "example.g.nupp") == disabled)
end

function M.reusesAnUnshadowedModuleBinding()
    local output = formatted(
        'local files = require("nupp.io.files")\nreturn nupp.io.files.read("a"), files.exists("b")\n'
    )
    assert(not output:find('const files', 1, true), output)
    assert(output:find('return files.read("a"), files.exists("b")', 1, true), output)
end

function M.keepsInnerAnnotationsBeforeImports()
    local output = formatted('@!internal\nreturn nupp.io.files.read("a")\n')
    assert(output:find('@!internal\nconst files', 1, true), output)
end

function M.convertsAnExistingTypeAliasWithoutAddingAnotherAlias()
    local output = formatted(
        'local type Bytes = nupp.mem.span.Span\nlocal function count(values: Bytes<uint8>): integer\nreturn #values\nend\nreturn count\n'
    )
    assert(output:find('const {type Span as Bytes} = require("nupp.mem.span")', 1, true), output)
    assert(not output:find('local type Bytes', 1, true), output)
end

function M.constructsTheSameRecordThroughADeclarationImport()
    local source = 'local function make(): nupp.io.files.TemporaryOptions\nreturn new nupp.io.files.TemporaryOptions(prefix = "fmt-test")\nend\nreturn make()\n'
    local output = formatted(source)
    assert(output:find('const {TemporaryOptions}', 1, true), output)
    assert(output:find('const {type TemporaryOptions}', 1, true), output)
    local baseline = 'local files = require("nupp.io.files")\n' .. source:gsub(
        "nupp%.io%.files%.TemporaryOptions",
        "files.TemporaryOptions"
    )
    local original = assert(loadstring(compile(baseline)))()
    local rewritten = assert(loadstring(compile(output)))()
    assert(original.prefix == rewritten.prefix)
    assert(getmetatable(original) == getmetatable(rewritten))
end

function M.formatsIsolatedSignaturesWithoutImportsWhenRequested()
    local source = 'local value: nupp.mem.span.Span<uint8>\n'
    local output, errors = fmt.format(source, "signature.nupp", {bindImports = false})
    assert(#errors == 0)
    assert(output == source, output)
end

function M.preservesCodeOnTheModuleHeadersLine()
    local output = formatted(
        'module app; export function read(): (string?, string?) return nupp.io.files.read("a") end\n'
    )
    assert(output:find('const files = require("nupp.io.files")', 1, true), output)
    assert(output:find('return files.read("a")', 1, true), output)
end

return M
