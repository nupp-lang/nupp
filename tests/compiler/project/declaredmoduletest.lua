local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")
local header = require("nupp.compiler.project.header")
local incremental = require("nupp.compiler.project.incremental")
local runtime = require("nupp.compiler.runtime")

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

local function compile(path, env, name, source)
    local result = parser.parse(source or readFile(path), path)
    if #result.errors > 0 then
        return nil, result.errors[1].msg
    end
    local diags = check.check(result, path, env)
    if #diags > 0 then
        return nil, diags[1].msg
    end

    return program.image(result, name, path)
end

-- Requires through the project's own modules, each lowered to an image the running
-- VM loads.
local function installProject(env)
    local loadImage = assert(rawget(_G, "__nupp_load_image"), "fragments run on the VM")

    return runtime.install(env, compile, nil, nil, function(image)
        return loadImage(image)
    end)
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
   return Box(value = value)
end
]],
        },
        function(dir)
            local path = dir .. "/src/mathbox.nupp"
            local env = projectEnv(dir)
            local parsed = parser.parse(readFile(path), path)
            testAssert.eq(#parsed.errors, 0, "declared syntax")
            local diags, moduleType, exports = check.check(parsed, path, env)
            testAssert.eq(#diags, 0, diags[1] and diags[1].msg)
            assert(exports.values.answer, "constant is in the value interface")
            assert(exports.values.twice, "function is in the value interface")
            assert(exports.types.Box, "record is in the type interface")
            assert(exports.values.Box, "record constructor is in the value interface")
            assert(moduleType, "declared module has a boundary type")

            package.loaded.mathbox = nil
            local removeLoader = installProject(env)
            local mathbox = require("mathbox")
            removeLoader()
            package.loaded.mathbox = nil
            testAssert.eq(mathbox.answer, 42)
            testAssert.eq(mathbox.twice(21), 42)
            testAssert.eq(mathbox.box(42).value, 42)
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
            testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local diags = check.check(parsed, path, projectEnv(dir))
            testAssert.eq(#diags, 1, "one diagnostic for " .. form)
            testAssert.eq(diags[1].code, "NUPP2143", form .. " is refused beside export =")
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
            testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local diags, _, exports = check.check(parsed, path, env)
            testAssert.eq(#diags, 0, diags[1] and diags[1].msg)
            assert(exports.types.Reader, "an exported interface enters the declared interface")
            assert(exports.types.Count, "an exported type alias enters the declared interface")

            package.loaded.erased = nil
            local removeLoader = installProject(env)
            local erased = require("erased")
            removeLoader()
            package.loaded.erased = nil
            testAssert.eq(erased.read(), 42, "the module loads and its value is the table it named")
            testAssert.eq(erased.Reader, nil, "an erased export puts nothing on the module value")
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
            testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local diags, moduleType, exports = check.check(parsed, path, env)
            testAssert.eq(#diags, 0, diags[1] and diags[1].msg)
            assert(moduleType, "export assignment has a module boundary")
            assert(exports.values.add, "table members enter the declared interface")
            assert(exports.types.Count, "qualified table types enter the declared interface")

            package.loaded.legacy = nil
            local removeLoader = installProject(env)
            local legacy = require("legacy")
            removeLoader()
            package.loaded.legacy = nil
            testAssert.eq(legacy.add(2), 42)
            testAssert.eq(legacy(2), 42, "the migration boundary preserves the table metatable")
            legacy.answer = 50
            testAssert.eq(legacy.add(2), 52, "the migration boundary preserves the module table's identity")
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
            testAssert.eq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            assert(checked.exports.values.fromA ~= nil, "the recursive interface keeps its function")

            package.loaded.a = nil
            package.loaded.b = nil
            local env = projectEnv(dir)
            local removeLoader = installProject(env)
            local a = require("a")
            removeLoader()
            package.loaded.a = nil
            package.loaded.b = nil
            testAssert.eq(a.fromA(41), 42, "benign function cycle")
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
            testAssert.eq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            local image = program.image(checked.result, "use", dir .. "/src/use.nupp")
            assert(not program.names(image, "model"), "a type-only selection emits no require")
        end
    )
end

function M.qualifiedNamespacesSelectOneHiddenDirectRequire()
    -- Its own module name: a VM image keeps answering a module name an earlier
    -- case's image declared, even after package.loaded forgets it.
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
                "src/usequery.nupp"
            ] = [[
module usequery
export function answer(): integer
   return tecs.world.query.each(41) + tecs.world.query.each(0)
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/usequery.nupp")
            testAssert.eq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            local image = program.image(checked.result, "usequery", dir .. "/src/usequery.nupp")
            assert(not program.names(image, "tecs"), "qualified path is lowered away")

            local previousUse = package.loaded.usequery
            local previousQuery = package.loaded["tecs.world.query"]
            package.loaded.usequery = nil
            package.loaded["tecs.world.query"] = nil
            local env = projectEnv(dir)
            local removeLoader = installProject(env)
            local ok, problem = pcall(function()
                local use = require("usequery")
                -- The hidden direct require executes inside answer on the VM,
                -- so the project loader must remain installed through the call.
                testAssert.eq(use.answer(), 43, "qualified module call")
            end)
            removeLoader()
            package.loaded.usequery = previousUse
            package.loaded["tecs.world.query"] = previousQuery
            if not ok then
                error(problem, 0)
            end
        end
    )
end

-- Construction through a qualified path stamps the module's export. The metatable used
-- to be the path as written, `tecs.world.shape.Box`, which names no runtime table, so a
-- construction that checked clean failed with "attempt to index" when it ran.
function M.aRecordConstructedThroughAQualifiedPathIsTheModulesRecord()
    withProject(
        {
            [
                "src/tecs/world/shape.nupp"
            ] = [[
module tecs.world.shape
export record Box
   side: integer
   function area(self): integer
      return self.side * self.side
   end
end
]],
            [
                "src/use.nupp"
            ] = [[
module use
export function answer(): integer
   local box = tecs.world.shape.Box(side = 6)
   return box:area() + 6
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/use.nupp")
            testAssert.eq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
            local image = program.image(checked.result, "use", dir .. "/src/use.nupp")
            assert(not program.names(image, "tecs"), "qualified path is lowered away")

            package.loaded.use = nil
            package.loaded["tecs.world.shape"] = nil
            local env = projectEnv(dir)
            local removeLoader = installProject(env)
            local use = require("use")
            local ok, answer = pcall(use.answer)
            removeLoader()
            package.loaded.use = nil
            package.loaded["tecs.world.shape"] = nil
            assert(ok, tostring(answer))
            testAssert.eq(answer, 42, "the constructed record carries the module's methods")
        end
    )
end

function M.registryRejectsReservedAndChildExportCollisions()
    withProject(
        {
            ["src/nupp/pin.nupp"] = "module own.pin\nexport const value: integer = 1\n",
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
    testAssert.eq(
        left.declarations[1].signature,
        right.declarations[1].signature,
        "body-only edits preserve the exported interface header"
    )
end

function M.exportedComptimeAliasesKeepTheirBoundaryInTheHeader()
    local parsed = parser.parse(
        [[
module sample
@comptime export type Field = {@readonly name: string, @readonly read: type?}
]],
        "sample.nupp"
    )
    local found = header.of("sample.nupp", "sample", parsed).declarations[1]
    testAssert.eq(found.name, "Field")
    testAssert.eq(found.kind, "type")
    testAssert.eq(found.comptimeOnly, true)
end

function M.moduleWordsRemainContextualNames()
    local parsed = parser.parse("export = function() end\nexport()\nmodule('legacy')\n", "names.lua")
    testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    testAssert.eq(parsed.root.blocks[1].stats[1].kind, "assignStmt")
    testAssert.eq(parsed.root.blocks[1].stats[2].kind, "callStmt")
    testAssert.eq(parsed.root.blocks[1].stats[3].kind, "callStmt")
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
                testAssert.eq(#parsed.errors, 0, "privacy fixture parses")
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
            testAssert.eq(#diags, 0, diags[1] and diags[1].msg)
            diags = inspect("module app.main\nlocal value = library.answer\n", client)
            testAssert.eq(#diags, 0, diags[1] and diags[1].msg)
        end
    )
end

function M.standardLibraryRootsSharePrivateImplementationOnlyWithEachOther()
    withProject({["src/app/main.nupp"] = "module app.main\n"}, function(dir)
        local env = projectEnv(dir)
        for _, consumer in ipairs({
            "nupp.tools.consumer",
            "serde.json",
            "binary.Digest",
            "coroutine.workers",
            "table"
        }) do
            for _, implementation in ipairs({
                "nupp.serde.internal.value",
                "serde.internal.codec",
                "binary.internal.hash"
            }) do
                testAssert.eq(
                    env.moduleAccess(env, consumer, implementation),
                    nil,
                    consumer .. " imports " .. implementation
                )
            end
        end
        for _, implementation in ipairs({
            "nupp.serde.internal.value",
            "serde.internal.codec",
            "binary.internal.hash"
        }) do
            assert(env.moduleAccess(env, "app.main", implementation), "application must not import " .. implementation)
        end
        assert(
            env.moduleAccess(env, "serde.json", "library.internal.hidden"),
            "stdlib must not import another package's internals"
        )
    end)
end

function M.theNuppImplementationRootIsInternalAcrossStandardRoots()
    withProject({["src/app.nupp"] = "module app\n"}, function(dir)
        local env = projectEnv(dir)
        for _, name in ipairs({"nupp", "nupp.array", "nupp.tasks", "nupp.compiler.types", "nupp.workers.contracts", "nupp.embedded.private"}) do
            local reason = env.moduleAccess(env, "app", name)
            assert(reason and reason:find("internal", 1, true), name)
            testAssert.eq(env.moduleAccess(env, "coroutine", name), nil)
        end
        for _, name in ipairs({"table", "io", "coroutine", "simd", "binary.span", "io.http", "nupp.embedded"}) do
            testAssert.eq(env.moduleAccess(env, "app", name), nil)
        end
        local filename = dir .. "/src/app.nupp"
        local source = [[
module app
local function consume(...: unpackof nupp.workers.contracts.Submitted(function(string): nil)): nil end
]]
        local diags = check.check(parser.parse(source, filename), filename, env)
        local denied = diagnosticContaining(diags, "is internal to package namespace")
        assert(denied and denied.code == "NUPP2144", "type-position calls must respect internal modules")
    end)
end

function M.bareBundledModuleRootsKeepCanonicalCachedIdentity()
    withProject({["src/app.nupp"] = "module app\nexport const api = serde\n"}, function(dir)
        local env = projectEnv(dir)
        assert(not env.ensureProjectIndex(env).declaredModules.serde, "fixture must use the bundled serde root")
        local source = readFile(dir .. "/src/app.nupp")
        local parsed = parser.parse(source, dir .. "/src/app.nupp")
        local problems = check.check(parsed, dir .. "/src/app.nupp", env)
        testAssert.eq(#problems, 0, problems[1] and problems[1].msg)
        local image = program.image(parsed, "app", dir .. "/src/app.nupp")
        assert(program.names(image, "serde"), "the bundled root keeps its canonical name")
        assert(not program.names(image, "nupp.serde"), "the retired root is absent")
        local published = program.run(parsed, "app", dir .. "/src/app.nupp")
        testAssert.eq(published.api, require("serde"), "the cached canonical module instance")
    end)
end

function M.targetOutputSourcesStayOutsideTheProjectIndex()
    withProject(
        {
            ["main.nupp"] = "module main\nexport const value: integer = 1\n",
            ["out/cache/runtime-source/generated.nupp"] = "export const value: integer = 2\n",
        },
        function(dir)
            local config = {
                include = {"."},
                build = {default = "app", outDir = "common", targets = {app = {outDir = "out"}}},
            }
            local env = envMod.new(dir, {config = config})
            testAssert.eq(envMod.outDir(env), dir .. "/out", "the default target owns its output")
            local files = envMod.listProjectFiles(env)
            testAssert.eq(#files, 1, "staged runtime sources are not project source")
            testAssert.eq(files[1], dir .. "/main.nupp")
            config._target = {outDir = "selected"}
            local selected = envMod.new(dir, {config = config})
            testAssert.eq(envMod.outDir(selected), dir .. "/selected", "an explicit target controls indexing")
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

function M.privateParentFilesKeepPublicChildrenAndCanonicalTypeOwners()
    withProject(
        {
            ["src/library/model.nupp"] = "@!internal\nmodule library.model\nexport record Token value: integer end\n",
            ["src/library/model/child.nupp"] = "module library.model.child\nexport const answer: integer = 29\n",
            [
                "src/library/facade.nupp"
            ] = [[
module library.facade
local implementation = require("library.model")
export type Token = implementation.Token
export const Token = implementation.Token
]],
            [
                "src/app.nupp"
            ] = [[
module app
local facade = require("library.facade")
local process = require("library.model.child")
export const token: facade.Token = facade.Token(value = process.answer)
]],
        },
        function(dir)
            local env = projectEnv(dir)
            local index = env:ensureProjectIndex()
            testAssert.eq(#index.registrationDiagnostics, 0)
            local code, problem = compile(dir .. "/src/app.nupp", env)
            assert(code, problem)
            local origin = env.resolveModuleExports(env, "library.model")
            local facade = env.resolveModuleExports(env, "library.facade")
            testAssert.eq(facade.types.Token, origin.types.Token)
            testAssert.eq(origin.types.Token.moduleName, "library.model")
            for _, source in ipairs({
                'module app\nlocal old = require("library.model")\n',
                'module app\nlocal old = library.model.Token\n',
            }) do
                local parsed = parser.parse(source, dir .. "/src/app.nupp")
                local diags = check.check(parsed, dir .. "/src/app.nupp", env)
                local denied = diagnosticContaining(diags, "is internal to package namespace")
                assert(denied and denied.code == "NUPP2144")
            end
            testAssert.eq(env.moduleAccess(env, "app", "library.model.child"), nil)
        end
    )
end

-- Two include roots can each hold a file that names one module, and only one of
-- them can be what `require` finds. Which one the checker saw and which one the
-- build compiled used to depend on the order each walked the files in, so the
-- refusal belongs to every file providing the name: whichever of them is checked
-- says so, whether or not the files spell a `module` line.
function M.twoFilesProvidingOneModuleAreEachRefused()
    local variants = {
        declared = {"module util\nexport const v: integer = 1\n", "module util\nexport const v: string = \"s\"\n"},
        undeclared = {"export const v: integer = 1\n", "export const v: string = \"s\"\n"},
        mixed = {"module util\nexport const v: integer = 1\n", "export const v: string = \"s\"\n"},
    }
    for label, sources in pairs(variants) do
        withProject({["lib/util.nupp"] = sources[1], ["src/util.nupp"] = sources[2]}, function(dir)
            local inc = incremental.new(dir, {config = {include = {"lib", "src"}}})
            for _, root in ipairs({"lib", "src"}) do
                local path = dir .. "/" .. root .. "/util.nupp"
                local found = diagnosticContaining(inc.checkFile(path).diags, "more than one file")
                assert(found, label .. ": " .. root .. "/util.nupp reports the other provider")
                testAssert.eq(found.code, "NUPP1002", label .. " code")
                assert(found.line >= 1 and found.col >= 1, label .. ": the report has a position")
                assert(found.related and found.related[1], label .. ": and names the other file")
            end
        end)
    end
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
            testAssert.eq(#inc.checkFile(app).diags, 0, "initial public import")
            inc.changeDocument(library, "@!internal\nmodule library\nexport const value: integer = 1\n")
            assert(
                diagnosticContaining(inc.checkFile(app).diags, "is internal to package namespace"),
                "changing only module privacy must invalidate the importer"
            )
            inc.changeDocument(library, "module library\nexport const value: integer = 1\n")
            testAssert.eq(#inc.checkFile(app).diags, 0, "making a module public restores access")
        end
    )
end

function M.shippedImplementationModulesAreNotApplicationImports()
    withProject({["src/app.nupp"] = "module app\n"}, function(dir)
        for _, name in ipairs({
            "binary._representation",
            "nupp.compiler.syntax.lexer",
            "nupp.runtime.browser.effects",
            "nupp.codec.json.provider",
            "nupp.codec.json.aot",
            "nupp.serde.internal.json.values",
            "nupp.io.net.internal",
            "nupp.gpu.internal",
            "nupp.gpu.types",
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
            testAssert.eq(#inc.checkFile(app).diags, 0, "compiler-owned replacement")
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
export const message: schema.Message = schema.Message(value = 42)
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
            testAssert.eq(#result.diags, 0, result.diags[1] and result.diags[1].msg)
        end
    )
end

-- A required module is a type namespace, and a declaration it exports is one in turn.
-- `const m = require("m")` then `m.Outer.Inner` asks m for `Outer` and walks the rest
-- through what that nests; reading the whole prefix as a module name instead left a
-- type published inside a record reachable only by importing the record itself.
function M.nestedTypesResolveThroughARequiredModuleBinding()
    withProject(
        {
            [
                "src/shapes.nupp"
            ] = [[
module shapes

export record Canvas
    record Layer
        type Name = string
        label: string
    end

    title: string
end
]],
            [
                "src/draw.nupp"
            ] = [[
module draw

const shapes = require("shapes")

export function labelOf(layer: shapes.Canvas.Layer): string
    return layer.label
end

export function nameOf(name: shapes.Canvas.Layer.Name): string
    return name
end

export function missing(layer: shapes.Canvas.Layer): string
    return layer.absent
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/draw.nupp")
            testAssert.eq(#checked.diags, 1, "only the field the nested record does not have")
            testAssert.eq(checked.diags[1].code, "NUPP2004", checked.diags[1].msg)
            assert(
                diagnosticContaining({checked.diags[1]}, "Layer"),
                "the nested declaration answers rather than being erased"
            )
        end
    )
end

-- Two bindings of the same module name the same declarations, and so the same nested
-- ones, including where the two modules require each other.
function M.nestedTypesKeepTheirIdentityAcrossACircularRequire()
    withProject(
        {
            [
                "src/first.nupp"
            ] = [[
module first

export record Holder
    record Kind
        tag: string
    end
end

export function callOut(kind: Holder.Kind): string
    const second = require("second")
    return second.take(kind) .. second.takeAgain(kind)
end
]],
            [
                "src/second.nupp"
            ] = [[
module second

const one = require("first")
const other = require("first")

export function take(kind: one.Holder.Kind): string
    return kind.tag
end

export function takeAgain(kind: other.Holder.Kind): string
    return kind.tag
end
]],
        },
        function(dir)
            local inc = incremental.new(dir, {config = {include = {"src"}}})
            local checked = inc.checkFile(dir .. "/src/first.nupp")
            testAssert.eq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
        end
    )
end

-- Builtin-root adoption needs an ordinary Nupp callable table, including a
-- generic input/result pack. Keep the current global and library untouched.
function M.aCallableModuleForwardsTheBuiltinAssertContract()
    withProject(
        {
            [
                "src/callableprobe.nupp"
            ] = [[
module callableprobe

local interface Callable
    equal: function(any, any, string?): any
    suite: {
        skip: function(string): never,
        isSkip: function(any): boolean,
        skipReason: function(any): string?,
    }
    metamethod __call: function<A...>(self, A...): A...
end

local type BuiltinAssert = function<A...>(A...): A...
local original = rawget(_G, "assert") as BuiltinAssert
local helper = require("assert")
local value = {
    equal = helper.eq,
    suite = {skip = helper.suite.skip, isSkip = helper.suite.isskip, skipReason = helper.suite.skipreason},
} as Callable

export = setmetatable(value, {__call = function<A...>(_self: Callable, ...: A...): A...
    return original(...)
end})
]],
            [
                "src/callableconsumer.nupp"
            ] = [[
module callableconsumer

local callable = require("callableprobe")
local first: string, second: nil, third: integer = callable("truthy", nil, 42)
callable.equal(first, "truthy")
assert(second == nil)
assert(third == 42)
export const result = true
]],
        },
        function(dir)
            local env = projectEnv(dir)
            local removeLoader = installProject(env)
            local ok, problem = pcall(function()
                local callable = require("callableprobe")
                testAssert.eq(type(callable), "table")
                testAssert.eq(callable.equal, testAssert.eq, "the existing helper keeps its identity")
                testAssert.eq(require("callableconsumer").result, true)

                local function collect(...)
                    return {n = select("#", ...), ...}
                end

                testAssert.deepeq(collect(callable("truthy", nil, 42, nil)), {n = 4, "truthy", nil, 42})
                local _, originalDefault = pcall(assert, false)
                local _, wrappedDefault = pcall(callable, false)
                testAssert.eq(wrappedDefault, originalDefault)
                for _, message in ipairs({"failure", 17, false, {reason = "error object"}}) do
                    local originalOk, originalError = pcall(assert, false, message)
                    local wrappedOk, wrappedError = pcall(callable, false, message)
                    testAssert.eq(wrappedOk, originalOk)
                    testAssert.eq(wrappedError, originalError, "the builtin owns error routing")
                end
                local evaluated = {}

                local function argument(value)
                    evaluated[#evaluated + 1] = #evaluated + 1
                    return value
                end

                local succeeded, failure = pcall(function()
                    callable(argument(false), argument("failure"), argument(42))
                end)
                testAssert.eq(succeeded, false)
                testAssert.matches(failure, "failure")
                testAssert.deepeq(evaluated, {1, 2, 3}, "all arguments run once before failure")
            end)
            removeLoader()
            package.loaded.callableprobe = nil
            package.loaded.callableconsumer = nil
            if not ok then
                error(problem, 0)
            end
        end
    )
end

function M.anArrayModuleKeepsMethodsInItsMetatable()
    withProject(
        {
            [
                "src/argvprobe.nupp"
            ] = [[
module argvprobe

export type TokenKind = string
local methods = {parse = function(value: string): string return value end}
record methods.Candidate
    value: string
end
export type Candidate = methods.Candidate
local type Methods = {parse: function(string): string, Candidate: Type<methods.Candidate>}
local argv = {"one", "two"} as {string} & Methods

export = setmetatable(argv, {__index = methods})
]],
            [
                "src/argvconsumer.nupp"
            ] = [[
module argvconsumer

local argv = require("argvprobe")
const {type TokenKind, type Candidate} = require("argvprobe")
local chosen: Candidate = argv.Candidate(value = "choice")
assert(chosen.value == "choice")
local count: integer = #argv
local word: TokenKind = argv.parse(argv[1])
assert(count == 2)
assert(word == "one")
export const result = true
]],
        },
        function(dir)
            local env = projectEnv(dir)
            local removeLoader = installProject(env)
            local ok, problem = pcall(function()
                local argv = require("argvprobe")
                testAssert.eq(require("argvprobe"), argv, "the exported array has one module identity")
                testAssert.eq(require("argvconsumer").result, true)
                testAssert.eq(rawget(argv, "parse"), nil)
                testAssert.eq(argv.parse, getmetatable(argv).__index.parse)
                testAssert.eq(#argv, 2)
                local sequential = {}
                for index, value in ipairs(argv) do
                    sequential[index] = value
                end
                testAssert.deepeq(sequential, {"one", "two"})
                local json = require("testjson")
                testAssert.eq(json.encode(argv), json.encode({"one", "two"}), "methods stay out of serialization")
                argv[0], argv[-1] = "program", "launcher"
                local raw = {}
                for key, value in pairs(argv) do
                    raw[key] = value
                end
                testAssert.deepeq(raw, {[0] = "program", [-1] = "launcher", "one", "two"})
                testAssert.eq(#argv, 2)
            end)
            removeLoader()
            package.loaded.argvprobe = nil
            package.loaded.argvconsumer = nil
            if not ok then
                error(problem, 0)
            end
        end
    )
end

local ARRAY_PROVIDER = [[
module arrayprovider

local methods = {}
interface methods.Named
    name: function(self): string
end
function methods.derivedName(): string return "derived" end
@comptime function methods.NamedRecord(_info: types.derive.Info): types.derive.Result<methods.Named>
    return types.derive.implement{methods = {name = types.derive.forward{
        helper = types.derive.helper(methods, "derivedName"), arguments = {},
    }}}
end
local argv: {string} = {"one", "two"}
export = setmetatable(argv, {__index = methods})
]]

function M.anArrayExportPublishesItsMethodTableProviders()
    withProject(
        {
            ["src/arrayprovider.nupp"] = ARRAY_PROVIDER,
            [
                "src/arrayconsumer.nupp"
            ] = [[
module arrayconsumer
local api = require("arrayprovider")
const {type Named} = require("arrayprovider")
@derive(api.NamedRecord)
local record Value
    text: string
end
local value: Named = Value(text = "value")
assert(value:name() == "derived")
local word: string = api[1]
local count: integer = #api
assert(word == "one" and count == 2)
export const result = true
]],
        },
        function(dir)
            local parsed = parser.parse(ARRAY_PROVIDER, dir .. "/src/arrayprovider.nupp")
            testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
            local found = header.of(dir .. "/src/arrayprovider.nupp", "arrayprovider", parsed)
            testAssert.eq(found.moduleLocal, "methods")
            testAssert.eq(found.declarations[1].name, "Named")
            testAssert.eq(found.declarations[1].visibility, "module")
            local env = projectEnv(dir)
            local removeLoader = installProject(env)
            local ok, problem = pcall(function()
                local api = require("arrayprovider")
                testAssert.eq(require("arrayprovider"), api)
                testAssert.eq(require("arrayconsumer").result, true)
                testAssert.eq(rawget(api, "NamedRecord"), nil, "the derive provider stays erased")
                testAssert.eq(rawget(api, "derivedName"), nil)
                testAssert.eq(api.derivedName, getmetatable(api).__index.derivedName)
                testAssert.eq(api.derivedName(), "derived")
                testAssert.eq(#api, 2)
                local raw = {}
                for key, value in pairs(api) do
                    raw[key] = value
                end
                testAssert.deepeq(raw, {"one", "two"})
                local json = require("testjson")
                testAssert.eq(json.encode(api), json.encode({"one", "two"}))
            end)
            removeLoader()
            package.loaded.arrayprovider, package.loaded.arrayconsumer = nil, nil
            if not ok then
                error(problem, 0)
            end
        end
    )
end

function M.arbitraryMetatablesDoNotPublishAnotherLocalNamespace()
    for _, change in ipairs({
        {"local argv: {string}", "local argv"},
        {"local argv: {string}", "local argv: table"},
        {
            "export = setmetatable(argv, {__index = methods})",
            "local mt = {__index = methods}\nexport = setmetatable(argv, mt)"
        },
        {"{__index = methods})", "{__index = methods, __len = function(): integer return 2 end})"},
        {
            "local methods = {}",
            "local setmetatable = function(value: {string}, _mt: table): {string} return value end\nlocal methods = {}"
        },
    }) do
        local first, last = assert(ARRAY_PROVIDER:find(change[1], 1, true))
        local source = ARRAY_PROVIDER:sub(1, first - 1) .. change[2] .. ARRAY_PROVIDER:sub(last + 1)
        local parsed = parser.parse(source, "arrayprovider.nupp")
        testAssert.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
        local found = header.of("arrayprovider.nupp", "arrayprovider", parsed)
        testAssert.eq(found.moduleLocal, "argv", change[2])
        for _, declaration in ipairs(found.declarations) do
            testAssert.eq(declaration.name == "Named", false, "the private method namespace stays private")
        end
        withProject({["src/arrayprovider.nupp"] = source}, function(dir)
            local parsedConsumer = parser.parse(
                [[local api = require("arrayprovider")
@derive(api.NamedRecord)
local record Value end
]],
                dir .. "/src/consumer.nupp"
            )
            local diags = check.check(parsedConsumer, dir .. "/src/consumer.nupp", projectEnv(dir))
            assert(diagnosticContaining(diags, "not an exported comptime derive provider"), diags[1] and diags[1].msg)
        end)
    end
end

function M.mergedSpanFacadeKeepsTrustedRangeProofsAndRefusals()
    withProject(
        {
            [
                "src/binary/span.nupp"
            ] = [[
module binary.span
local spans = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")
export type Span<T> = spans.Span<T>
export type WriteSpan<T> = spans.WriteSpan<T>
export type Range = indexed.Range
export const range = indexed.range
export const writecarray = spans.writeCarray
]],
            [
                "src/main.nupp"
            ] = [[
module main
local span = require("binary.span")
export struct Cell value: int32 end
export function work(exclusive output: span.WriteSpan<Cell>): nil
    const values = output
    const rows = span.range(1, #values, values)
    for index = rows.first, rows.last do
        values[index].value += 1
    end
end
export function fill(exclusive storage: Cell[?], count: integer): nil
    const values = span.writecarray(storage, count)
    for index = 1, #values do
        values[index].value = 7
    end
    own.drop(values)
end
]],
        },
        function(dir)
            local env = projectEnv(dir)
            local filename = dir .. "/src/main.nupp"
            local parsed = parser.parse(readFile(filename), filename)
            local diagnostics = check.check(parsed, filename, env)
            testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
            local rangeProof, factoryProof = false, false
            local seen = {}

            local function inspect(node)
                if type(node) ~= "table" or seen[node] then
                    return
                end
                seen[node] = true
                rangeProof = rangeProof or node.indexedRangeCall ~= nil
                factoryProof = factoryProof or node.indexedViewProducer ~= nil
                for _, child in ipairs(node) do
                    inspect(child)
                end
            end

            inspect(parsed.root)
            assert(rangeProof, "the merged facade retains the trusted indexed range")
            assert(factoryProof, "the final factory retains its checked view producer")
            local facadePath = dir .. "/src/binary/span.nupp"
            local facade = parser.parse(readFile(facadePath), facadePath)
            local facadeErrors = check.check(facade, facadePath, env)
            testAssert.eq(#facadeErrors, 0, facadeErrors[1] and facadeErrors[1].msg)
            local loadImage = assert(rawget(_G, "__nupp_load_image"))
            local oldSpan, preloadSpan = package.loaded["binary.span"], package.preload["binary.span"]
            local oldMain, preloadMain = package.loaded.main, package.preload.main
            local ok, problem = pcall(function()
                program.installSourceModules()
                package.loaded["binary.span"] = nil
                package.preload["binary.span"] = assert(loadImage(program.image(facade, "binary.span", facadePath)))
                package.loaded.main = nil
                package.preload.main = assert(loadImage(program.image(parsed, "main", filename)))
                local callerPath = dir .. "/src/consumer.nupp"
                local caller = parser.parse(
                    [[
local main = require("main")
local span = require("binary.span")
const storage = carray(main.Cell, 2)
main.fill(storage, 2)
const values = span.writecarray(storage, 2)
main.work(values)
local result = values[1].value + values[2].value
own.drop(values)
return result
]],
                    callerPath
                )
                testAssert.eq(#caller.errors, 0)
                local callerErrors = check.check(caller, callerPath, env)
                testAssert.eq(#callerErrors, 0, callerErrors[1] and callerErrors[1].msg)
                testAssert.eq(program.run(caller, "span-facade-caller", callerPath), 16)
            end)
            package.loaded["binary.span"], package.preload["binary.span"] = oldSpan, preloadSpan
            package.loaded.main, package.preload.main = oldMain, preloadMain
            assert(ok, problem)
            local invalid = parser.parse(
                [[
local span = require("binary.span")
const rows = span.range(1, 1, {})
]],
                "invalid-span-consumer.nupp"
            )
            local refused = check.check(invalid, "invalid-span-consumer.nupp", env)
            assert(diagnosticContaining(refused, "requires a standard Span or SoA view"))
            local shadow = parser.parse(
                [[
local span = {range = function(first: integer, last: integer, value: table): integer return first end}
const rows = span.range(1, 1, {})
]],
                "shadow-span-consumer.nupp"
            )
            local ordinary = check.check(shadow, "shadow-span-consumer.nupp", env)
            testAssert.eq(#ordinary, 0, ordinary[1] and ordinary[1].msg)
        end
    )
end

return M
