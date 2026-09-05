local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")
local header = require("nupp.compiler.header")
local incremental = require("nupp.compiler.incremental")
local runtime = require("nupp.compiler.runtime")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s: want %s, got %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function diagnosticContaining(diags, text)
    for _, diag in ipairs(diags) do
        if diag.msg and diag.msg:find(text, 1, true) then
            return diag
        end
    end
end

local function writeFile(path, text)
    local parent = assert(path:match("^(.*)[/\\]"))
    assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function withProject(files, callback)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for path, source in pairs(files) do
        writeFile(dir .. "/" .. path, source)
    end
    local ok, result = pcall(callback, dir)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(result, 0)
    end

    return result
end

local function projectEnv(dir)
    return envMod.new(dir, {config = {include = {"src"}}})
end

local function compile(path, env)
    local result = parser.parse(readFile(path), path)
    if #result.errors > 0 then
        return nil, result.errors[1].msg
    end
    local diags = check.check(result, path, env)
    if #diags > 0 then
        return nil, diags[1].msg
    end
    local code, generated = gen.generate(result, path)
    if #generated > 0 then
        return nil, generated[1].msg
    end

    return code
end

local M = {}

function M.parsesChecksAndRunsDeclaredExports()
    withProject(
        {
            [
                "src/mathbox.nupp"
            ] = [[
module mathbox

export const answer: integer = 42

export record Box
   value: integer
end

export function twice(value: integer): integer
   return value * 2
end

export function box(value: integer): Box
   return new Box(value = value)
end
]],
        },
        function(dir)
            local path = dir .. "/src/mathbox.nupp"
            local env = projectEnv(dir)
            local parsed = parser.parse(readFile(path), path)
            assertEq(#parsed.errors, 0, "declared syntax")
            local diags, moduleType, exports = check.check(parsed, path, env)
            assertEq(#diags, 0, diags[1] and diags[1].msg)
            assert(exports.values.answer, "constant is in the value interface")
            assert(exports.values.twice, "function is in the value interface")
            assert(exports.types.Box, "record is in the type interface")
            assert(exports.values.Box, "record constructor is in the value interface")
            assert(moduleType, "declared module has a boundary type")

            package.loaded.mathbox = nil
            local removeLoader = runtime.install(env, compile)
            local mathbox = require("mathbox")
            removeLoader()
            package.loaded.mathbox = nil
            assertEq(mathbox.answer, 42)
            assertEq(mathbox.twice(21), 42)
            assertEq(mathbox.box(42).value, 42)
        end
    )
end

-- A declaration carrying a runtime value has nowhere to land in a module whose value
-- is `export =`: the named value is the module, and the compiler builds no table for
-- it. It used to compile to a write into the export table before the assignment
-- established it, so the module raised on its first require and checking said nothing.
function M.aValueCarryingExportIsRefusedBesideAnExportAssignment()
    for _, form in ipairs({
        "export record Thing\n   value: integer\nend",
        "export function make(): integer\n   return 1\nend",
        "export const ANSWER = 42",
    }) do
        withProject({["src/m.nupp"] = "module m\n\nlocal api = {}\n\n" .. form .. "\n\nexport = api\n",}, function(dir)
            local path = dir .. "/src/m.nupp"
            local parsed = parser.parse(readFile(path), path)
            assertEq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local diags = check.check(parsed, path, projectEnv(dir))
            assertEq(#diags, 1, "one diagnostic for " .. form)
            assertEq(diags[1].code, "NUPP2143", form .. " is refused beside export =")
            assert(
                diags[1].help and diags[1].help:find("api.", 1, true),
                "the help names the module value: " .. tostring(diags[1].help)
            )
        end)
    end
end

-- The other half of the same rule. An interface and a type alias are erased, so they
-- put nothing on the table and compose with a named module value; seven modules in
-- this compiler are written that way. The module is required rather than only
-- checked, because a write into an unassigned export table is a load-time fault that
-- checking never sees.
function M.anErasedExportComposesWithAnExportAssignment()
    withProject(
        {
            [
                "src/erased.nupp"
            ] = [[
module erased

local api = {answer = 42}

export interface Reader
   value: integer
end

export type Count = integer

function api.read(): integer
   return api.answer
end

export = api
]],
        },
        function(dir)
            local path = dir .. "/src/erased.nupp"
            local env = projectEnv(dir)
            local parsed = parser.parse(readFile(path), path)
            assertEq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local diags, _, exports = check.check(parsed, path, env)
            assertEq(#diags, 0, diags[1] and diags[1].msg)
            assert(exports.types.Reader, "an exported interface enters the declared interface")
            assert(exports.types.Count, "an exported type alias enters the declared interface")

            package.loaded.erased = nil
            local removeLoader = runtime.install(env, compile)
            local erased = require("erased")
            removeLoader()
            package.loaded.erased = nil
            assertEq(erased.read(), 42, "the module loads and its value is the table it named")
            assertEq(erased.Reader, nil, "an erased export puts nothing on the module value")
        end
    )
end

function M.exportAssignmentMigratesAnExistingModuleTable()
    withProject(
        {
            [
                "src/legacy.nupp"
            ] = [[
module legacy

local legacy = {answer = 40}

type legacy.Count = integer

function legacy.add(value: legacy.Count): number
   return legacy.answer + value
end

export = setmetatable(legacy, {__call = function(self, value) return self.add(value) end})
]],
        },
        function(dir)
            local path = dir .. "/src/legacy.nupp"
            local env = projectEnv(dir)
            local parsed = parser.parse(readFile(path), path)
            assertEq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local diags, moduleType, exports = check.check(parsed, path, env)
            assertEq(#diags, 0, diags[1] and diags[1].msg)
            assert(moduleType, "export assignment has a module boundary")
            assert(exports.values.add, "table members enter the declared interface")
            assert(exports.types.Count, "qualified table types enter the declared interface")

            package.loaded.legacy = nil
            local removeLoader = runtime.install(env, compile)
            local legacy = require("legacy")
            removeLoader()
            package.loaded.legacy = nil
            assertEq(legacy.add(2), 42)
            assertEq(legacy(2), 42, "the migration boundary preserves the table metatable")
            legacy.answer = 50
            assertEq(legacy.add(2), 52, "the migration boundary preserves the module table's identity")
        end
    )
end

function M.rejectsWrongCanonicalNameAndTopLevelReturn()
    withProject({["src/right.nupp"] = "module wrong\nreturn {}\n",}, function(dir)
        local path = dir .. "/src/right.nupp"
        local parsed = parser.parse(readFile(path), path)
        local diags = check.check(parsed, path, projectEnv(dir))
        assert(diags[1] and diags[1].msg:find("canonical module name", 1, true))
        local sawReturn = false
        for _, diag in ipairs(diags) do
            sawReturn = sawReturn or diag.msg:find("no top-level return", 1, true) ~= nil
        end
        assert(sawReturn, "declared modules reject a return table")
    end)
end

function M.recursiveChecksUsePublishedInterfacesInsteadOfAny()
    withProject(
        {
            [
                "src/a.nupp"
            ] = [[
module a
const b = require("b")
export function fromA(value: integer): integer
   return b.fromB(value)
end
]],
            [
                "src/b.nupp"
            ] = [[
module b
const a = require("a")
export function fromB(value: integer): integer
   return value + 1
end
export function throughA(value: integer): integer
   return a.fromA(value)
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/a.nupp")
            assertEq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            assert(checked.exports.values.fromA ~= nil, "the recursive interface keeps its function")

            package.loaded.a = nil
            package.loaded.b = nil
            local env = projectEnv(dir)
            local removeLoader = runtime.install(env, compile)
            local a = require("a")
            removeLoader()
            package.loaded.a = nil
            package.loaded.b = nil
            assertEq(a.fromA(41), 42, "benign function cycle")
        end
    )
end

function M.typeSelectionsAreErasedButStillResolveTheInterface()
    withProject(
        {
            ["src/model.nupp"] = [[
module model
export record Point
   x: number
end
]],
            [
                "src/use.nupp"
            ] = [[
module use
const {type Point as LocalPoint} = require("model")
export function accept(value: LocalPoint): nil
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/use.nupp")
            assertEq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            local code, diags = gen.generate(checked.result, dir .. "/src/use.nupp")
            assertEq(#diags, 0, diags[1] and diags[1].msg)
            assert(not code:find('require("model")', 1, true), "a type-only selection emits no require")
        end
    )
end

function M.qualifiedNamespacesSelectOneHiddenDirectRequire()
    withProject(
        {
            [
                "src/tecs/world/query.nupp"
            ] = [[
module tecs.world.query
export function each(value: integer): integer
   return value + 1
end
]],
            [
                "src/use.nupp"
            ] = [[
module use
export function answer(): integer
   return tecs.world.query.each(41) + tecs.world.query.each(0)
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/use.nupp")
            assertEq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            local code, diags = gen.generate(checked.result, dir .. "/src/use.nupp")
            assertEq(#diags, 0, diags[1] and diags[1].msg)
            local _, count = code:gsub('require%("tecs.world.query"%)', "")
            assertEq(count, 1, "one hidden module binding")
            assert(not code:find("tecs.world.query.each", 1, true), "qualified path is lowered away")

            package.loaded.use = nil
            package.loaded["tecs.world.query"] = nil
            local env = projectEnv(dir)
            local removeLoader = runtime.install(env, compile)
            local use = require("use")
            removeLoader()
            package.loaded.use = nil
            package.loaded["tecs.world.query"] = nil
            assertEq(use.answer(), 43, "qualified module call")
        end
    )
end

function M.registryRejectsReservedAndChildExportCollisions()
    withProject(
        {
            ["src/nupp/pin.nupp"] = "module nupp.pin\nexport const value: integer = 1\n",
            ["src/pkg.nupp"] = "module pkg\nexport const child: integer = 1\n",
            ["src/pkg/child.nupp"] = "module pkg.child\nexport const value: integer = 2\n",
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local reserved = inc.checkFile(dir .. "/src/nupp/pin.nupp").diags
            assert(diagnosticContaining(reserved, "compiler-owned"), "reserved compiler path")
            local collision = inc.checkFile(dir .. "/src/pkg/child.nupp").diags
            local found = diagnosticContaining(collision, "collides with export")
            assert(found, "child/export collision")
            assert(found.related and found.related[1], "collision points at the export")
        end
    )
end

function M.exportedFunctionHeadersIgnorePrivateBodies()
    local before = parser.parse(
        [[
module sample
export function answer(value: integer): integer
   return value + 1
end
]],
        "sample.nupp"
    )
    local after = parser.parse(
        [[
module sample
export function answer(value: integer): integer
   return value + 2
end
]],
        "sample.nupp"
    )
    local left = header.of("sample.nupp", "sample", before)
    local right = header.of("sample.nupp", "sample", after)
    assertEq(
        left.declarations[1].signature,
        right.declarations[1].signature,
        "body-only edits preserve the exported interface header"
    )
end

function M.exportedComptimeAliasesKeepTheirBoundaryInTheHeader()
    local parsed = parser.parse(
        [[
module sample
export comptime type Field = {readonly name: string, readonly read: type?}
]],
        "sample.nupp"
    )
    local found = header.of("sample.nupp", "sample", parsed).declarations[1]
    assertEq(found.name, "Field")
    assertEq(found.kind, "type")
    assertEq(found.comptimeOnly, true)
end

function M.moduleWordsRemainContextualNames()
    local parsed = parser.parse("export = function() end\nexport()\nmodule('legacy')\n", "names.lua")
    assertEq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    assertEq(parsed.root.blocks[1].stats[1].kind, "assignStmt")
    assertEq(parsed.root.blocks[1].stats[2].kind, "callStmt")
    assertEq(parsed.root.blocks[1].stats[3].kind, "callStmt")
end

function M.eagerCallsIntoAnInitializingModuleAreRejected()
    withProject(
        {
            [
                "src/a.nupp"
            ] = [[
module a
const b = require("b")
export function fromA(value: integer): integer
   return value + 1
end
]],
            [
                "src/b.nupp"
            ] = [[
module b
const a = require("a")
const tooEarly: integer = a.fromA(1)
export function fromB(value: integer): integer
   return value + tooEarly
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            inc.checkFile(dir .. "/src/a.nupp")
            local diags = inc.checkFile(dir .. "/src/b.nupp").diags
            assert(diagnosticContaining(diags, "eager module cycle"), "eager cycle diagnostic")
        end
    )
end

function M.internalModulesEnforcePackageBoundaries()
    withProject(
        {
            ["src/library/init.nupp"] = "module library\nexport const answer: integer = 42\n",
            [
                "src/library/hidden.nupp"
            ] = "@!internal\nmodule library.hidden\nexport record Token\n value: integer\nend\nexport const answer: integer = 42\n",
            [
                "src/library/internal/helper.nupp"
            ] = "module library.internal.helper\nexport const answer: integer = 42\n",
            ["src/library/engine/init.nupp"] = "@!internal\nmodule library.engine\n",
            ["src/library/engine/child.nupp"] = "module library.engine.child\nexport const answer: integer = 42\n",
            [
                "src/library/client.nupp"
            ] = "module library.client\nexport const answer: integer = require(\"library.hidden\").answer\n",
            ["src/app/main.nupp"] = "module app.main\n",
        },
        function(dir)
            local env = projectEnv(dir)
            local function inspect(source, filename)
                local parsed = parser.parse(source, filename)
                assertEq(#parsed.errors, 0, "privacy fixture parses")
                return check.check(parsed, filename, env)
            end

            local client = dir .. "/src/app/main.nupp"
            for _, name in ipairs({"library.hidden", "library.internal.helper", "library.engine.child"}) do
                local diags = inspect(
                    "module app.main\nlocal x = require(" .. string.format("%q", name) .. ")\n",
                    client
                )
                local denied = diagnosticContaining(diags, "is internal to package namespace")
                assert(denied and denied.code == "NUPP2144", "static import must reject " .. name)
                diags = inspect("module app.main\nlocal x = " .. name .. ".answer\n", client)
                denied = diagnosticContaining(diags, "is internal to package namespace")
                assert(denied and denied.code == "NUPP2144", "qualified import must reject " .. name)
            end
            local diags = inspect("module app.main\nlocal value: library.hidden.Token = nil as any\n", client)
            assert(diagnosticContaining(diags, "is internal to package namespace"), "qualified type must be private")
            diags = inspect(readFile(dir .. "/src/library/client.nupp"), dir .. "/src/library/client.nupp")
            assertEq(#diags, 0, diags[1] and diags[1].msg)
            diags = inspect("module app.main\nlocal value = library.answer\n", client)
            assertEq(#diags, 0, diags[1] and diags[1].msg)
        end
    )
end

function M.moduleWithChildrenRequiresInitSource()
    withProject(
        {
            ["src/package.nupp"] = "module package\nexport const answer: integer = 1\n",
            ["src/package/child.nupp"] = "module package.child\nexport const answer: integer = 2\n",
        },
        function(dir)
            local index = projectEnv(dir):ensureProjectIndex()
            assert(diagnosticContaining(index.registrationDiagnostics, "has child modules; move its source"))
        end
    )
end

function M.privacyChangesInvalidateImporters()
    withProject(
        {
            ["src/library/init.nupp"] = "module library\nexport const value: integer = 1\n",
            ["src/app.nupp"] = "module app\nexport const value: integer = library.value\n",
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local app, library = dir .. "/src/app.nupp", dir .. "/src/library/init.nupp"
            assertEq(#inc.checkFile(app).diags, 0, "initial public import")
            inc.changeDocument(library, "@!internal\nmodule library\nexport const value: integer = 1\n")
            assert(
                diagnosticContaining(inc.checkFile(app).diags, "is internal to package namespace"),
                "changing only module privacy must invalidate the importer"
            )
            inc.changeDocument(library, "module library\nexport const value: integer = 1\n")
            assertEq(#inc.checkFile(app).diags, 0, "making a module public restores access")
        end
    )
end

function M.shippedImplementationModulesAreNotApplicationImports()
    withProject({["src/app.nupp"] = "module app\n"}, function(dir)
        for _, name in ipairs({
            "nupp.compiler.lexer",
            "nupp.runtime.browser.effects",
            "nupp.runtime.seam.registry",
            "nupp.data.json.provider",
            "nupp.data.json.aot",
            "nupp.io.net.internal",
            "nupp.gpu.internal",
            "nupp.gpu.layoutfacts"
        }) do
            local filename = dir .. "/src/app.nupp"
            local parsed = parser.parse(
                "module app\nlocal implementation = require(" .. string.format("%q", name) .. ")\n",
                filename
            )
            local diags = check.check(parsed, filename, projectEnv(dir))
            assert(diagnosticContaining(diags, "is internal to package namespace"), name .. " must remain private")
        end
    end)
end

function M.generatedImportPermissionDoesNotSurviveAnOrdinaryOverlay()
    withProject(
        {
            ["src/library/internal.nupp"] = "module library.internal\nexport const value: integer = 1\n",
            ["src/app.nupp"] = "module app\n",
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local app = dir .. "/src/app.nupp"
            local text = 'module app\nlocal implementation = require("library.internal")\nexport const value: integer = implementation.value\n'
            inc.openGeneratedDocument(app, text)
            assertEq(#inc.checkFile(app).diags, 0, "compiler-owned replacement")
            inc.openDocument(app, text)
            assert(
                diagnosticContaining(inc.checkFile(app).diags, "is internal to package namespace"),
                "the same bytes as ordinary source must lose generated import permission"
            )
        end
    )
end

function M.stagedDeclarationsReuseTheirRegisteredNominalIdentity()
    withProject(
        {
            [
                "src/app.nupp"
            ] = [[module app
const schema = require("schema")
export const message: schema.Message = new schema.Message(value = 42)
]]
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local staged = dir .. "/build/cache/runtime-source"
            inc.env.roots[#inc.env.roots + 1] = staged
            inc.openDocument(staged .. "/schema.nupp", [[module schema
export record Message
    value: integer
end
]])
            local result = inc.checkFile(dir .. "/src/app.nupp")
            assertEq(#result.diags, 0, result.diags[1] and result.diags[1].msg)
        end
    )
end

return M
