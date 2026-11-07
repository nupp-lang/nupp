local fmt = require("nupp.tools.fmt")
local envMod = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local program = require("program")

local M = {}
local sharedEnv = nil

local function formatted(source, env)
    sharedEnv = sharedEnv or envMod.new(".")
    local formatter = fmt.new({environment = env or sharedEnv})
    local output, errors = formatter:format(source, "format.nupp")
    assert(#errors == 0, errors[1] and errors[1].msg)
    local again, problems = formatter:format(output, "format.nupp")
    assert(#problems == 0, problems[1] and problems[1].msg)
    assert(again == output, "import formatting must be idempotent:\n" .. again)

    return output
end

local function compile(source, environment)
    local env = environment or envMod.new(".")
    local result = parser.parse(source, "format.nupp")
    local errors = check.check(result, "format.nupp", env)
    for _, err in ipairs(errors) do
        assert(err.severity == "warning" or err.severity == "off", tostring(err.code) .. ": " .. tostring(err.msg))
    end

    return result
end

local function image(source)
    return program.image(compile(source), "format", "format.nupp")
end

local function withUserModules(run)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src/app'") == 0)
    local sources = {
        [
            "files.nupp"
        ] = [[
module app.files
export function read(path: string): (string?, string?) return path, nil end
export function exists(path: string): boolean return true end
export interface Reader
    read: function(self): string
end
]],
        ["span.nupp"] = [[
module app.span
export type Span<T> = bytes.span.Span<T>
]],
    }
    for name, source in pairs(sources) do
        local file = assert(io.open(dir .. "/src/app/" .. name, "wb"))
        file:write(source)
        file:close()
    end
    local ok, result = pcall(run, envMod.new(dir, {cache = false, config = {include = {"src"}}}))
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, result)

    return result
end

local function userFormatted(source)
    return withUserModules(function(env)
        return formatted(source, env)
    end)
end

function M.retainsBuiltinNamespaceCalls()
    local output = formatted('return io.http.file("a"), io.http.file("b")\n')
    assert(not output:find("require", 1, true), output)
    assert(output:find('return io.http.file("a"), io.http.file("b")', 1, true), output)
end

function M.builtinTypeAccessRemainsQualifiedAndErased()
    local source = 'local function count(value: bytes.span.Span<uint8>): integer\nreturn #value\nend\nreturn count\n'
    local output = formatted(source)
    assert(not output:find("require", 1, true), output)
    assert(output:find('value: bytes.span.Span<uint8>', 1, true), output)
    local before, after = image(source), image(output)
    -- Neither image requires the module at run time.
    assert(not before:find('"nupp.mem.span"', 1, true), before)
    assert(not after:find('"nupp.mem.span"', 1, true), after)
end

function M.keepsDirectBuiltinAliases()
    local output = formatted('local files = io.http\nreturn files.file("a"), io.http.file("b")\n')
    assert(output == 'local files = io.http\nreturn files.file("a"), io.http.file("b")\n', output)
end

function M.avoidsCapturingNamesInAnyScope()
    local output = userFormatted(
        'local files = 1\nlocal function read(files2)\nreturn app.files.read("a"), files2\nend\nreturn read, files\n'
    )
    assert(output:find('const files3 = require("app.files")', 1, true), output)
    assert(output:find('return files3.read("a"), files2', 1, true), output)
end

function M.respectsShadowedPackageRoots()
    local output = userFormatted(
        'local function fake(app)\nreturn app.files.read("a")\nend\nreturn app.files.read("b"), fake\n'
    )
    assert(output:find('return app.files.read("a")', 1, true), output)
    assert(output:find('return files.read("b"), fake', 1, true), output)
end

function M.avoidsTheLeafNameOfAQualifiedDeclaration()
    withUserModules(function(env)
        local output = formatted(
            'local process = {}\ninterface process.Reader is app.files.Reader\nend\nreturn process\n',
            env
        )
        assert(output:find('const {type Reader as Reader2} = require("app.files")', 1, true), output)
        assert(output:find('interface process.Reader is Reader2', 1, true), output)
        compile(output, env)
    end)
end

function M.leavesIntrinsicsAndExplicitRequirePlacement()
    local output = formatted(
        'local function size()\nreturn types.sizeof(int32), require("io.http").file("a")\nend\nreturn size\n'
    )
    assert(not output:find('const files', 1, true), output)
    assert(output:find('types.sizeof(int32)', 1, true), output)
    assert(output:find('require("io.http").file', 1, true), output)
end

function M.preservesCommentsAndStrings()
    local output = formatted('-- nupp.io.http.file\nreturn "nupp.io.http.file", io.http.file("a")\n')
    assert(output:find('-- nupp.io.http.file', 1, true), output)
    assert(output:find('"nupp.io.http.file", io.http.file', 1, true), output)
    local inside = formatted('return io -- keep this\n.http.file("a")\n')
    assert(inside:find('-- keep this', 1, true), inside)
    assert(not inside:find('const files', 1, true), inside)
end

function M.importsFollowModuleHeaderAndPreserveDocblocks()
    local output = userFormatted(
        'module app.reader -- module comment\n\n--- Read a file.\nexport function read(): string?\nreturn app.files.read("a")\nend\n'
    )
    assert(output:find('module app.reader -- module comment\n\nconst files = require("app.files")', 1, true), output)
    assert(output:find('--- Read a file.\nexport function read', 1, true), output)
end

function M.keepsModuleDocumentationAheadOfImports()
    local output = userFormatted(
        '--[[A documented module.]]\nmodule format\n\nexport function read(): (string?, string?)\nreturn app.files.read("a")\nend\n'
    )
    assert(output:find('--[[A documented module.]]\nmodule format\n\nconst files', 1, true), output)
    local documented = require("nupp.tools.doc.extract").extract(output, "format.nupp", "format")
    assert(documented.text == "A documented module.", documented.text)
end

function M.doesNotRewritePlainLuaOrDisabledFiles()
    local source = 'return io.http.file("a")\n'
    assert(fmt.format(source, "example.lua") == source)
    local disabled = '@!nofmt\n' .. source
    assert(fmt.format(disabled, "example.nupp") == disabled)
end

function M.leavesAuthoredBuiltinImportsAndOtherQualifiedAccesses()
    local output = formatted('local files = require("io.http")\nreturn io.http.file("a"), files.file("b")\n')
    assert(not output:find('const files', 1, true), output)
    assert(output:find('return io.http.file("a"), files.file("b")', 1, true), output)
end

function M.keepsInnerAnnotationsBeforeImports()
    local output = userFormatted('@!internal\nreturn app.files.read("a")\n')
    assert(output:find('@!internal\nconst files', 1, true), output)
end

function M.keepsDirectBuiltinTypeAliases()
    local output = formatted(
        'local type Bytes = bytes.span.Span\nlocal function count(values: Bytes<uint8>): integer\nreturn #values\nend\nreturn count\n'
    )
    assert(output:find('local type Bytes = bytes.span.Span', 1, true), output)
    assert(not output:find('require', 1, true), output)
    compile(output)
end

function M.constructsTheSameRecordThroughItsBuiltinNamespace()
    local source = 'local function make(): io.http.FileBody\nreturn io.http.FileBody(path = "fmt-test")\nend\nreturn make()\n'
    local output = formatted(source)
    assert(not output:find('require', 1, true), output)
    assert(output:find('io.http.FileBody', 1, true), output)
    local baseline = 'local files = require("io.http")\n' .. source:gsub("io%.http%.FileBody", "files.FileBody")
    local original = program.run(compile(baseline), "format", "format.nupp")
    local rewritten = program.run(compile(output), "format", "format.nupp")
    assert(original.path == rewritten.path)
    assert(getmetatable(original) == getmetatable(rewritten))
end

function M.formatsIsolatedSignaturesWithoutImportsWhenRequested()
    local source = 'local value: bytes.span.Span<uint8>\n'
    local output, errors = fmt.format(source, "signature.nupp", {bindImports = false})
    assert(#errors == 0)
    assert(output == source, output)
end

function M.preservesCodeOnTheModuleHeadersLine()
    local output = userFormatted(
        'module app; export function read(): (string?, string?) return app.files.read("a") end\n'
    )
    assert(output:find('const files = require("app.files")', 1, true), output)
    assert(output:find('return files.read("a")', 1, true), output)
end

function M.compileTimeCapabilitiesDoNotIntroduceRuntimeImports()
    local source = [[
@comptime local function Items(Element: type): type
    local files = Element
    return types.array(files)
end
@comptime local function Refuse(info: types.derive.Info): types.derive.Result<any>
    return types.derive.error("unsupported declaration", info.reference)
end
local kind = comptime do
    return types.kind(Items(types.string))
end
return kind
]]
    local output = formatted(source)
    assert(not output:find('require("types")', 1, true), output)
    assert(not output:find('require("types.derive")', 1, true), output)
    assert(program.run(compile(output), "format", "format.nupp") == "array")

    local mixed = userFormatted((source:gsub("return kind\n$", 'return app.files.exists("a"), kind\n')))
    assert(mixed:find('const files2 = require("app.files")', 1, true), mixed)
    assert(not mixed:find('require("types")', 1, true), mixed)
    assert(mixed:find("types.array(files)", 1, true), mixed)
end

function M.ambientDeclarationsKeepTheirQualifiedNamespaces()
    local env = envMod.new(".")
    local formatter = fmt.new({environment = env})
    local source = '@comptime local function read(): io.http.FileBody return io.http.file("a") end\n'
    local declared, errors = formatter:format(source, "prelude.d.nupp")
    assert(#errors == 0, errors[1] and errors[1].msg)
    assert(not declared:find("require", 1, true), declared)
    assert(declared:find("io.http.file", 1, true), declared)
    local ordinary, problems = formatter:format(source, "ordinary.nupp")
    assert(#problems == 0, problems[1] and problems[1].msg)
    assert(not ordinary:find("require", 1, true), ordinary)
    assert(ordinary:find("io.http.file", 1, true), ordinary)
    local runtime = formatted((source:gsub("@comptime ", "")))
    assert(not runtime:find('require', 1, true), runtime)
    assert(runtime:find('io.http.file', 1, true), runtime)
    local explicit = 'const files = require("io.http")\nlocal read: function(string): io.http.FileBody = files.file\n'
    local authored, issues = formatter:format(explicit, "external.d.nupp")
    assert(#issues == 0, issues[1] and issues[1].msg)
    assert(authored:find('require("io.http")', 1, true), authored)
end

function M.shortensUserModuleAndGenericTypeAliases()
    withUserModules(function(env)
        local output = formatted('local files = app.files\nreturn files.read("a"), app.files.read("b")\n', env)
        assert(output == 'local files = require("app.files")\nreturn files.read("a"), files.read("b")\n', output)
        local typed = formatted(
            'local type Bytes = app.span.Span\nlocal function count(values: Bytes<uint8>): integer return #values end\nreturn count\n',
            env
        )
        assert(typed:find('const {type Span as Bytes} = require("app.span")', 1, true), typed)
        compile(typed, env)
    end)
end

function M.builtinNamespacesRemainQualifiedBesideUserImportsAndLexicalShadows()
    local output = userFormatted(
        [[
local function fake(io)
    return io.http.file("shadow")
end
local files = io.http
local type Bytes = bytes.span.Span
return app.files.read("user"), io.http.file("builtin"), files, fake
]]
    )
    assert(output:find('const files2 = require("app.files")', 1, true), output)
    assert(output:find('io.http.file("shadow")', 1, true), output)
    assert(output:find('io.http.file("builtin")', 1, true), output)
    assert(output:find('local files = io.http', 1, true), output)
    assert(output:find('local type Bytes = bytes.span.Span', 1, true), output)
    assert(not output:find('require("io.http")', 1, true) and not output:find('require("bytes.span")', 1, true), output)
end

function M.keepsBuiltinScopeBorrowingAndCallableLastSubmission()
    local source = [[
module format
export function start(borrows scope: coroutine.Scope): integer
    local child = scope:work(function(): integer return 1 end)
    return child:await()
end
]]
    local output = formatted(source)
    assert(not output:find("require", 1, true), output)
    assert(output:find("borrows scope: coroutine.Scope", 1, true), output)
    assert(output:find("scope:work", 1, true) and output:find("child:await", 1, true), output)
    compile(source)
    compile(output)
end

return M
