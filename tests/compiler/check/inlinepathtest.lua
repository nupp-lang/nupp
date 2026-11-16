-- The `inline-module-path` lint and the import its fix writes.
--
-- A qualified module path is valid source; the lint asks for it to be spelled as an
-- import instead, and its fix does the spelling. Every case here checks a source,
-- applies the fix the lint attached, and checks the result again: a fix that leaves
-- the lint reporting, or that changes what the program means, is the failure.
local fmt = require("nupp.tools.fmt")
local envMod = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local program = require("program")

local CODE = "NUPP2520"
local FILE = "format.nupp"

local M = {}
local sharedEnv, userEnv, userDir

local function environment()
    sharedEnv = sharedEnv or envMod.new(".")
    return sharedEnv
end

local function diagnostics(source, env, filename)
    local result = parser.parse(source, filename or FILE)
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    local reported = check.check(result, filename or FILE, env or environment())
    local found = {}
    for _, diagnostic in ipairs(reported) do
        if diagnostic.code == CODE then
            found[#found + 1] = diagnostic
        end
    end

    return found, reported
end

local function apply(source, edits)
    local sorted = {}
    for index, edit in ipairs(edits) do
        sorted[index] = edit
    end
    table.sort(sorted, function(a, b)
        return a.offset > b.offset
    end)
    local out = source
    for _, edit in ipairs(sorted) do
        out = out:sub(1, edit.offset - 1) .. edit.newText .. out:sub(edit.offset + edit.length)
    end

    return out
end

--- The source once the lint's fix is applied, which has to leave nothing for the lint
--- to say. Every report in a file carries the same fix.
local function organized(source, env, filename)
    local found = diagnostics(source, env, filename)
    if #found == 0 then
        return source
    end
    local fix = found[1].fixes and found[1].fixes[1]
    assert(fix, "the lint carries a fix")
    for _, diagnostic in ipairs(found) do
        assert(diagnostic.severity == "warning", diagnostic.severity)
        assert(diagnostic.lint == "inline-module-path", tostring(diagnostic.lint))
        assert(diagnostic.fixes and diagnostic.fixes[1] == fix, "every report carries the file's one fix")
    end
    local output = apply(source, fix.edits)
    local again = diagnostics(output, env, filename)
    assert(#again == 0, "the fix leaves the lint reporting:\n" .. output)

    return output
end

local function compile(source, environment)
    if not environment then
        sharedEnv = sharedEnv or envMod.new(".")
    end
    local env = environment or sharedEnv
    local result = parser.parse(source, FILE)
    local errors = check.check(result, FILE, env)
    for _, err in ipairs(errors) do
        assert(err.severity == "warning" or err.severity == "off", tostring(err.code) .. ": " .. tostring(err.msg))
    end

    return result
end

local function image(source)
    return program.image(compile(source), "format", FILE)
end

local function withUserModules(run)
    if userEnv then
        return run(userEnv)
    end
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
    userDir = dir
    userEnv = envMod.new(dir, {cache = false, config = {include = {"src"}}})

    return run(userEnv)
end

function M.afterAll()
    if userDir then
        assert(os.remove(userDir, true))
    end
    userEnv, userDir, sharedEnv = nil, nil, nil
end

local function userOrganized(source)
    return withUserModules(function(env)
        return organized(source, env)
    end)
end

function M.reportsEachPathWithAnImportFix()
    withUserModules(function(env)
        local source = 'return app.files.read("a"), app.files.exists("b")\n'
        local found = diagnostics(source, env)
        assert(#found == 2, #found)
        assert(found[1].line == 1 and found[1].col == 8, found[1].line .. ":" .. found[1].col)
        assert(found[1].msg == "app.files is written as a full module path; import it instead", found[1].msg)
        assert(found[1].help == 'add `const files = require("app.files")` and write `files`', found[1].help)
        local edits = found[1].fixes[1].edits
        assert(#edits == 3, "one insertion and a replacement per path, not the whole file: " .. #edits)
        assert(organized(source, env) == 'const files = require("app.files")\n\nreturn files.read("a"), files.exists("b")\n')
    end)
end

function M.honorsLevelAndSuppression()
    withUserModules(function(env)
        local result = parser.parse('return app.files.read("a")\n', FILE)
        local reported = check.check(result, FILE, env, {lints = {["inline-module-path"] = "off"}})
        for _, diagnostic in ipairs(reported) do
            assert(diagnostic.code ~= CODE, "an off lint reports nothing")
        end
        local raised = parser.parse('return app.files.read("a")\n', FILE)
        local escalated = check.check(raised, FILE, env, {lints = {style = "error"}})
        local seen = false
        for _, diagnostic in ipairs(escalated) do
            if diagnostic.code == CODE then
                seen = diagnostic.severity == "error"
            end
        end
        assert(seen, "the style category moves it")
        local source = '@allow("inline-module-path")\nlocal read = app.files.read\nreturn read("a"), app.files.exists("b")\n'
        local found = diagnostics(source, env)
        assert(#found == 1 and found[1].line == 3, "only the unsuppressed path reports")
        local output = organized(source, env)
        assert(output:find("local read = app.files.read", 1, true), output)
        assert(output:find('files.exists("b")', 1, true), output)
    end)
end

function M.retainsBuiltinNamespaceCalls()
    local source = 'return io.http.file("a"), io.http.file("b")\n'
    assert(#diagnostics(source) == 0)
end

function M.builtinTypeAccessRemainsQualifiedAndErased()
    local source = 'local function count(value: bytes.span.Span<uint8>): integer\nreturn #value\nend\nreturn count\n'
    assert(#diagnostics(source) == 0)
    -- The image does not require the module at run time.
    local built = image(source)
    assert(not built:find('"nupp.mem.span"', 1, true), built)
end

function M.keepsDirectBuiltinAliases()
    assert(#diagnostics('local files = io.http\nreturn files.file("a"), io.http.file("b")\n') == 0)
end

function M.avoidsCapturingNamesInAnyScope()
    local output = userOrganized(
        'local files = 1\nlocal function read(files2)\nreturn app.files.read("a"), files2\nend\nreturn read, files\n'
    )
    assert(output:find('const files3 = require("app.files")', 1, true), output)
    assert(output:find('return files3.read("a"), files2', 1, true), output)
end

function M.respectsShadowedPackageRoots()
    local output = userOrganized(
        'local function fake(app)\nreturn app.files.read("a")\nend\nreturn app.files.read("b"), fake\n'
    )
    assert(output:find('return app.files.read("a")', 1, true), output)
    assert(output:find('return files.read("b"), fake', 1, true), output)
end

function M.avoidsTheLeafNameOfAQualifiedDeclaration()
    withUserModules(function(env)
        local output = organized(
            'local process = {}\ninterface process.Reader is app.files.Reader\nend\nreturn process\n',
            env
        )
        assert(output:find('const {type Reader as Reader2} = require("app.files")', 1, true), output)
        assert(output:find('interface process.Reader is Reader2', 1, true), output)
        compile(output, env)
    end)
end

function M.leavesIntrinsicsAndExplicitRequirePlacement()
    local source = 'local function size()\nreturn types.sizeof(int32), require("io.http").file("a")\nend\nreturn size\n'
    assert(#diagnostics(source) == 0)
end

function M.preservesCommentsAndStrings()
    withUserModules(function(env)
        local output = organized('-- app.files.read\nreturn "app.files.read", app.files.read("a")\n', env)
        assert(output:find('-- app.files.read', 1, true), output)
        assert(output:find('"app.files.read", files.read', 1, true), output)
        assert(#diagnostics('return app -- keep this\n.files.read("a")\n', env) == 0)
    end)
end

function M.importsFollowModuleHeaderAndPreserveDocblocks()
    local output = userOrganized(
        'module app.reader -- module comment\n\n--- Read a file.\nexport function read(): string?\nreturn app.files.read("a")\nend\n'
    )
    assert(output:find('module app.reader -- module comment\n\nconst files = require("app.files")\n\n--- Read', 1, true), output)
    assert(output:find('--- Read a file.\nexport function read', 1, true), output)
end

function M.keepsModuleDocumentationAheadOfImports()
    local output = userOrganized(
        '--[[A documented module.]]\nmodule format\n\nexport function read(): (string?, string?)\nreturn app.files.read("a")\nend\n'
    )
    assert(output:find('--[[A documented module.]]\nmodule format\n\nconst files', 1, true), output)
    local documented = require("nupp.tools.doc.extract").extract(output, FILE, "format")
    assert(documented.text == "A documented module.", documented.text)
end

-- What the fix writes is what the formatter would: one blank line under the
-- header, one after the imports, and nothing for `nupp fmt` to move.
function M.theFixWritesFormattedSource()
    withUserModules(function(env)
        for _, source in ipairs({
            'module app.reader\n\nexport function read(): (string?, string?)\n    return app.files.read("a")\nend\n',
            'module app.reader\nexport function read(): (string?, string?)\n    return app.files.read("a")\nend\n',
            'module app.reader\n\nconst other = require("app.span")\n\nexport function read(): (string?, string?)\n'
            .. '    return app.files.read("a")\nend\n',
            'return app.files.read("a")\n',
            '@!internal\nreturn app.files.read("a")\n',
        }) do
            local output = organized(source, env)
            assert(output ~= source, source)
            local formatted, errors = fmt.format(output, FILE)
            assert(#errors == 0, errors[1] and errors[1].msg)
            assert(formatted == output, "the fix left work for the formatter:\n" .. output .. "\n--\n" .. formatted)
        end
    end)
end

function M.skipsPlainLuaDeclarationsAndGeneratedFiles()
    withUserModules(function(env)
        local source = 'return app.files.read("a")\n'
        assert(#diagnostics(source, env, "example.lua") == 0)
        local declared = 'local read: function(string): (string?, string?) = app.files.read\n'
        assert(#diagnostics(declared, env, "ambient.d.nupp") == 0)
        local result = parser.parse(source, FILE)
        for _, diagnostic in ipairs(check.check(result, FILE, env, {generatedSource = true})) do
            assert(diagnostic.code ~= CODE, "a generated file reports nothing")
        end
    end)
end

function M.leavesTypesReachedThroughAnExplicitBinding()
    withUserModules(function(env)
        local source = 'local files = require("app.files")\nlocal value: files.Reader = nil as any\nreturn value\n'
        assert(#diagnostics(source, env) == 0)
    end)
end

function M.leavesAuthoredBuiltinImportsAndOtherQualifiedAccesses()
    assert(#diagnostics('local files = require("io.http")\nreturn io.http.file("a"), files.file("b")\n') == 0)
end

function M.keepsInnerAnnotationsBeforeImports()
    local output = userOrganized('@!internal\nreturn app.files.read("a")\n')
    assert(output:find('@!internal\nconst files', 1, true), output)
end

function M.keepsDirectBuiltinTypeAliases()
    local source =
        'local type Bytes = bytes.span.Span\nlocal function count(values: Bytes<uint8>): integer\nreturn #values\nend\nreturn count\n'
    assert(#diagnostics(source) == 0)
    compile(source)
end

function M.constructsTheSameRecordThroughItsBuiltinNamespace()
    local source = 'local function make(): io.http.FileBody\nreturn io.http.FileBody(path = "fmt-test")\nend\nreturn make()\n'
    assert(#diagnostics(source) == 0)
    local baseline = 'local files = require("io.http")\n' .. source:gsub("io%.http%.FileBody", "files.FileBody")
    local original = program.run(compile(baseline), "format", FILE)
    local qualified = program.run(compile(source), "format", FILE)
    assert(original.path == qualified.path)
    assert(getmetatable(original) == getmetatable(qualified))
end

function M.preservesCodeOnTheModuleHeadersLine()
    local output = userOrganized(
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
    assert(#diagnostics(source) == 0)
    assert(program.run(compile(source), "format", FILE) == "array")

    local mixed = userOrganized((source:gsub("return kind\n$", 'return app.files.exists("a"), kind\n')))
    assert(mixed:find('const files2 = require("app.files")', 1, true), mixed)
    assert(not mixed:find('require("types")', 1, true), mixed)
    assert(mixed:find("types.array(files)", 1, true), mixed)
end

function M.ambientDeclarationsKeepTheirQualifiedNamespaces()
    local source = '@comptime local function read(): io.http.FileBody return io.http.file("a") end\n'
    assert(#diagnostics(source, nil, "prelude.d.nupp") == 0)
    assert(#diagnostics(source) == 0)
    assert(#diagnostics((source:gsub("@comptime ", ""))) == 0)
end

function M.shortensUserModuleAndGenericTypeAliases()
    withUserModules(function(env)
        local output = organized('local files = app.files\nreturn files.read("a"), app.files.read("b")\n', env)
        assert(output == 'local files = require("app.files")\nreturn files.read("a"), files.read("b")\n', output)
        local typed = organized(
            'local type Bytes = app.span.Span\nlocal function count(values: Bytes<uint8>): integer return #values end\nreturn count\n',
            env
        )
        assert(typed:find('const {type Span as Bytes} = require("app.span")', 1, true), typed)
        compile(typed, env)
    end)
end

function M.builtinNamespacesRemainQualifiedBesideUserImportsAndLexicalShadows()
    local output = userOrganized(
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
    assert(#diagnostics(source) == 0)
    compile(source)
end

return M
