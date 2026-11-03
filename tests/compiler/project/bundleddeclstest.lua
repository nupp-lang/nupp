local testAssert = require("assert")
-- The declarations shipped with the compiler have to survive the consumer's
-- opinions about its own source.
--
-- `loadBundled` discards a declaration that produces any diagnostic, and
-- strictness was inherited from the project's manifest -- so `strict = true`, which
-- is the setting a careful project turns on, made every consumer re-judge nupp's
-- own declarations under a rule they were not written to. `string.buffer` fails
-- it: `put` takes `...: any`, which strict reports on an exported function. The
-- module then resolved to `unknown`, every use of it was silently untyped, and
-- nothing was reported about any of it.
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local T = require("nupp.compiler.types")

local HERE = require("helpers.paths").tests
local ROOT = HERE .. "/.."

-- An environment the strict checks below run in.
--
-- Built once and answered again: every case wants the same one, and building it
-- means checking the prelude from source.
local strict = nil

local function strictEnv()
    strict = strict or envMod.new(ROOT, {config = {include = {"src"}}})

    return strict
end

-- Every module the compiler ships a declaration for.
local BUNDLED = {
    "ffi",
    "string.buffer",
    "jit.util",
    "jit.profile",
    "jit.zone",
    "jit.vmdef",
    "nupp.mem.span",
    "nupp.mem.heap",
    "nupp.mem.array",
    "nupp.util.internal.pool",
    "nupp.mem.arena",
    "events",
    "nupp.runtime.contracts",
    "os.host",
    "os.host.pump",
    "math.random",
}

-- Checks a strict program against the prelude and answers its diagnostics as
-- "CODE:line" strings, which is what a case about one declaration wants to see.
local function diagsUnderPrelude(source)
    local result = parser.parse(source, "test.nupp")
    testAssert.eq(
        #result.errors,
        0,
        "syntax errors in test source: " .. (result.errors[1] and result.errors[1].msg or "")
    )
    local out = {}
    for _, d in ipairs(check.check(result, "test.nupp", strictEnv(), {strict = true}) or {}) do
        if d.severity == "error" then
            out[#out + 1] = d.code .. ":" .. d.line
        end
    end

    return table.concat(out, " ")
end

local M = {}

function M.tlsOverviewExampleChecksAgainstItsPublicApi()
    local source = assert(require("nupp.compiler.bundled").source("/io/net/init.nupp"))
    local example = assert(source:match("## TLS.-```nupp\n(.-)\n```"))
    testAssert.eq(diagsUnderPrelude(example), "")
end

function M.retiredNamespacesAreNotBundled()
    local env = strictEnv()
    for _, name in ipairs({
        "package.nupp",
        "binary.checksum.spi",
        "binary.digest.spi",
        "binary.mac.spi",
        "binary.compress.spi",
        "serde.json.spi",
        "io.spi",
        "io.files.spi",
        "io.net.spi",
        "io.http.spi",
        "io.gpu.spi",
        "coroutine.sus.spi",
        "coroutine.workers.spi",
        "coroutine.suspension",
        "coroutine.suspension.host",
        "coroutine.suspension.spi",
        "coroutine.suspension.cancellation",
        "io.uri",
        "io.uri.spi",
        "io.path",
        "io.path.spi",
        "io.net.tls",
        "io.net.tls.spi",
        "binary.hash",
        "binary.hash.digest",
        "binary.hash.checksum",
        "binary.hash.mac",
        "nupp.host",
        "nupp.host.pump",
        "nupp.random",
        "nupp.spi"
    }) do
        testAssert.eq(env.bundledImplementation(name), nil, name)
    end
end

function M.reIsNotACompilerProvidedModule()
    local env = envMod.new("/private/tmp/nupp-retired-re-consumer", {
        memoryOnly = true,
        nativeCompilerServices = false,
        typeRoots = {},
    })
    testAssert(not env.bundled.re, "re must not have a bundled declaration")
    testAssert.eq(env.bundledImplementation("re"), nil)
    testAssert.eq(env.resolveModuleExports(env, "re"), nil)
    local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()
    for _, resource in ipairs(manifest.build.targets.dist.resources) do
        if type(resource) == "table" then
            testAssert.ne(resource.source, "src/re.nupp")
            testAssert.ne(resource.source, "src/nupp/compiler/decls/re.d.nupp")
        end
    end
end

function M.compilerCarriesEveryFeatureRuntimeSource()
    local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()
    local resources = {}
    for _, resource in ipairs(manifest.build.targets.dist.resources) do
        if type(resource) == "table" then
            resources[resource.output] = true
        end
    end
    local native = require("nupp.compiler.native")
    for _, effect in ipairs(native.effectNames()) do
        local feature = native.feature(effect)
        local module = feature.runtimeModule
        if module and not module:match("^nupp%.compiler%.") and not module:match("^nupp%.tools%.") then
            local path = "nupp/compiler/" .. module:gsub("%.", "/")
            assert(
                resources[path .. ".nupp"] or resources[path .. "/init.nupp"] or resources[path .. ".lua"],
                effect .. " has no carried runtime source: " .. module
            )
        end
    end
end

function M.movedFacadesKeepTheirTypesOutsideTheCompilerCheckout()
    local env = envMod.new("/private/tmp/nupp-bundled-layout-consumer", {config = {include = {"src"}}, cache = false})
    local sources = {
        ["nupp.runtime.contracts"] = "/nupp/runtime/contracts.nupp",
        ["binary"] = "/binary/init.nupp",
        ["binary.span"] = "/binary/span.nupp",
        ["nupp.runtime.entropy"] = "/nupp/runtime/entropy.nupp",
        ["nupp.runtime.standardtable"] = "/nupp/runtime/standardtable.nupp",
        ["coroutine.sus"] = "/coroutine/sus/init.nupp",
        ["coroutine.sus.cancellation"] = "/coroutine/sus/cancellation.nupp",
        ["coroutine.sus.host"] = "/coroutine/sus/host.nupp",
        ["nupp.suspension.contracts"] = "/nupp/suspension/contracts.nupp",
        ["coroutine.workers"] = "/coroutine/workers/init.nupp",
        ["nupp.workers.contracts"] = "/nupp/workers/contracts.nupp",
        ["io.files"] = "/io/files/init.nupp",
        ["io.files.messages"] = "/io/files/messages.nupp",
        ["io.http"] = "/io/http/init.nupp",
        ["nupp.io.http.contracts"] = "/nupp/io/http/contracts.nupp",
        ["io.net"] = "/io/net/init.nupp",
        ["io.net.internal.contracts"] = "/io/net/internal/contracts.nupp",
        ["io.cli"] = "/io/cli.nupp",
        ["io.net.internal.tls"] = "/io/net/internal/tls.nupp",
        ["nupp.runtime.standardcoroutine"] = "/nupp/runtime/standardcoroutine.nupp",
    }
    for name, path in pairs(sources) do
        testAssert.eq(env.bundledImplementation(name), path, name)
        local loaded = env.loadBundledModule(name)
        assert(loaded and loaded.exports, name .. " has checked carried exports")
    end
    local host = env.loadBundledModule("coroutine.sus.host")
    local privateHost = env.loadBundledModule("nupp.suspension.host")
    local install = host.exports.values.install
    testAssert.eq(install.tag, "func", "install retains its checked signature")
    testAssert.eq(install.rets[1].tag, "affine", "installation requires cleanup")
    testAssert.eq(
        host.exports.types.Handler,
        privateHost.exports.types.Handler,
        "the facade preserves nominal identity"
    )
    local suspension = env.loadBundledModule("coroutine.sus")
    testAssert.eq(suspension.exports.values.handled.rets[1].tag, "boolean")
    testAssert.eq(suspension.exports.values.suspend, nil, "the wait lives on coroutine")
    local coroutineModule = env.loadBundledModule("nupp.runtime.standardcoroutine")
    testAssert.eq(coroutineModule.exports.values.suspend.tag, "func")
end

function M.directSuspendKeepsItsGenericTypeOutsideTheCheckout()
    local env = envMod.new("/private/tmp/nupp-coroutine-sus-consumer", {config = {include = {"src"}}, cache = false})
    local source = [[
local function wait(): string
    return coroutine.suspend("ready", function(resume: function(string), context: coroutine.sus.Context): function()?
        resume("ready")
        return nil
    end)
end
local co = coroutine
local function viaAlias(): integer
    return co.suspend("ready", function(resume: function(integer)): function()?
        resume(42)
        return nil
    end)
end
return wait(), viaAlias()
]]
    local parsed = parser.parse(source, "suspend-consumer.nupp")
    testAssert.eq(#parsed.errors, 0)
    for _, diag in ipairs(check.check(parsed, "suspend-consumer.nupp", env) or {}) do
        testAssert.ne(diag.severity, "error", diag.msg)
    end
    local text, number = program.run(parsed, "suspend-consumer")
    testAssert.eq(text, "ready")
    testAssert.eq(number, 42)
end

function M.finalNamespaceHomesKeepCheckedTypesOutsideTheCheckout()
    local env = envMod.new("/private/tmp/nupp-bundled-layout-consumer", {config = {include = {"src"}}, cache = false})
    local source = [[
local binary = require("binary")
local client: io.net.TlsClientOptions = {hostname = "example.com"}
local server: io.net.TlsServerOptions = {certificate = "certificate", privatekey = "key"}
local function ready(borrows session: io.net.TlsSession): boolean
    return session:isready()
end
local {type Pool, newpool} = require("table")
local record Value
    number: integer
end
local bits: binary.Bitset = new binary.Bitset(64)
local values: Pool<Value> = newpool(Value, 4)
local qualified: table.Pool<Value> = table.newpool(Value, 4)
local bytes: string = os.randombytes(0)
return bits, values, qualified, bytes
]]
    local parsed = parser.parse(source, "final-namespace-homes.nupp")
    testAssert.eq(#parsed.errors, 0)
    local errors = {}
    for _, item in ipairs(check.check(parsed, "final-namespace-homes.nupp", env)) do
        if item.severity == "error" then
            errors[#errors + 1] = item.code .. ": " .. item.msg
        end
    end
    testAssert.eq(table.concat(errors, "\n"), "")
    assert(parsed.effects["runtime.crypto"])
    local binary = env.resolveModuleExports(env, "binary")
    local private = env.resolveModuleExports(env, "nupp.util.internal.bitset")
    testAssert.eq(binary.types.Bitset, private.types.Bitset)
end

function M.providerContractImportErasesWithoutLoadingAnImplementation()
    local parsed = parser.parse(
        [[
module nupp.test.providercontract
local {type ClockProvider} = require("nupp.runtime.contracts")
return function(clock: ClockProvider): number return clock.now() end
]],
        "provider-contract-import.nupp"
    )
    testAssert.eq(#parsed.errors, 0)
    for _, diagnostic in ipairs(
        check.check(parsed, "provider-contract-import.nupp", strictEnv(), {
            moduleName = "nupp.test.providercontract"
        })
    ) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local image = program.image(parsed, "provider_contract_import")
    assert(not program.names(image, "nupp.runtime.contracts"), "a type-only contract import loads nothing")
end

function M.uuidUsesItsContractWithoutNativeCompilerServices()
    local relations = require("nupp.compiler.types.relations")
    local env = envMod.new(".", {memoryOnly = true, nativeCompilerServices = false, typeRoots = {},})
    local result = parser.parse("return os.uuid4", "uuid-contract.nupp")
    testAssert.eq(#result.errors, 0)
    local diagnostics = check.check(result, "uuid-contract.nupp", env)
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local uuid = env.globals.os.t
    local provider = assert(env.resolveModule(env, "nupp.runtime.uuidprovider"))
    testAssert.eq(uuid.byname.uuid4.tag, "func", "uuid4 has a checked function signature")
    testAssert.eq(uuid.byname.uuid4.rets[1].tag, "string", "uuid4 returns a string")
    testAssert.eq(
        relations.isA(uuid.byname.uuid4, provider.byname.uuid4),
        true,
        "uuid4 satisfies the canonical contract signature"
    )
    testAssert.eq(
        relations.isA(uuid.byname.uuid7, provider.byname.uuid7),
        true,
        "uuid7 satisfies the canonical contract signature"
    )
    testAssert.eq(uuid.byname.randomBytes, nil, "unrelated operations are absent")
    local exports = assert(env.resolveModuleExports(env, "os"))
    testAssert.eq(exports.values.uuid4, uuid.byname.uuid4, "module and export resolution agree")
    testAssert.eq(
        rawget(env.bundled, "nupp.runtime.provider.nativeuuid"),
        nil,
        "the native implementation was not loaded"
    )
end

-- What `pcall` hands back on failure is whatever was raised, so the error slot is
-- `unknown`: an unguarded read of it cannot launder into a typed binding, while
-- the correlated `ok` test still reveals the callee's own results.
function M.pcallErrorSlotIsUnknown()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local function g(): integer
    error("boom")
end
local ok, v = pcall(g)
if ok then
    local n: integer = v
    print(n)
else
    print(tostring(v))
end
local ok2, v2 = pcall(g)
local m: integer = v2
print(ok2, m)
]]
        ),
        "NUPP2001:12"
    )
end

-- An iterator function answers nil once it runs out, and `string.gmatch`'s answers
-- a match's captures or nothing, so calling one by hand yields optionals. A
-- `for ... in` loop runs its body only while the first value is not nil, which is
-- why the loop variables are exactly what an iteration holds.
function M.manualIteratorCallsAreOptionalWhereLoopsAreNot()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local lines = io.lines("x")
local line: string = lines()
local matches = ("a=1"):gmatch("(%a+)=(%d+)")
local key: string, value: string = matches()
print(line, key, value)
]]
        ),
        "NUPP2001:2 NUPP2001:4 NUPP2001:4"
    )
    testAssert.eq(
        diagsUnderPrelude(
            [[
for line in io.lines("x") do
    local s: string = line
    print(s)
end
for word in ("a b"):gmatch("%a+") do
    local w: string = word
    print(w)
end
for key, value in ("a=1"):gmatch("(%a+)=(%d+)") do
    local k: string, v: string = key, value
    print(k, v)
end
]]
        ),
        ""
    )
end

function M.tableIteratorCallsAreOptionalWhereLoopsAreNot()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local keyed = pairs({one = 1})
local key: string, value: integer = keyed()
local indexed = ipairs({1})
local index: integer, item: integer = indexed()
print(key, value, index, item)
]]
        ),
        "NUPP2001:2 NUPP2001:2 NUPP2001:4 NUPP2001:4"
    )
    testAssert.eq(
        diagsUnderPrelude(
            [[
for key, value in pairs({one = 1}) do
    local name: string, count: integer = key, value
    print(name, count)
end
for index, item in ipairs({1}) do
    local at: integer, value: integer = index, item
    print(at, value)
end
]]
        ),
        ""
    )
end

-- A metatable the receiver declared nothing for still has the fields Lua reads:
-- `__index` is a table or a function, and it may be absent.
function M.aMetatableExposesItsIndexHandlers()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local t = setmetatable({}, {__metatable = "locked"})
local mt = getmetatable(t)
if mt then
    local handler = mt.__index
    if type(handler) == "table" then
        print(handler)
    end
    local n: integer = mt.__index
    print(n)
end
]]
        ),
        "NUPP2001:8"
    )
end

-- A computed module name is a boundary nothing declared, so a strict file gets
-- `unknown` back and has to narrow or cast before reading anything from it.
function M.aDynamicRequireIsUnknownUnderStrict()
    testAssert.eq(
        diagsUnderPrelude([[
local name: string = "os"
local m = require(name)
local s: string = m.nothing
print(s)
]]),
        "NUPP2004:3"
    )
end

function M.everyBundledDeclarationResolvesUnderStrict()
    local env = strictEnv()
    local lost = {}
    for _, name in ipairs(BUNDLED) do
        local t = env.resolveModule(env, name)
        if not t or t == T.any or t.tag == "unknown" then
            lost[#lost + 1] = name
        end
    end
    testAssert.eq(
        #lost,
        0,
        "a project's strictness must not discard the compiler's own declarations; " .. "lost: " .. table.concat(
            lost,
            ", "
        )
    )
    local util = assert(env.resolveModule(env, "jit.util"))
    testAssert.eq(util.byname.traceir.rets[1].hasNil, true, "an absent trace has no IR mode")
    testAssert.eq(util.byname.tracek.rets[2].hasNil, true, "an absent IR constant has no type")
    testAssert.eq(util.byname.ircalladdr.rets[1].hasNil, true, "an absent IR call has no address")
end

function M.stringBufferKeepsItsMembersUnderStrict()
    -- The one that actually failed, checked through a program rather than through
    -- the module type, because the symptom was at the use site.
    local env = strictEnv()
    local result = parser.parse(
        [[
const sb = require("string.buffer")
const b = sb.new()
b:put("x")
return b:tostring()
]],
        "test"
    )
    testAssert.eq(#result.errors, 0, "syntax errors")
    for _, d in ipairs(check.check(result, "test", env, {strict = true}) or {}) do
        if d.severity == "error" then
            error(("%s: %s"):format(d.code, d.msg), 2)
        end
    end
end

function M.aStrictProjectStillJudgesItsOwnSource()
    -- The fix must not turn strictness off for the project itself.
    local env = strictEnv()
    local result = parser.parse([[
local m = {}

function m.leaky(x: any): any
    return x
end

return m
]], "test")
    testAssert.eq(#result.errors, 0, "syntax errors")
    local found = false
    for _, d in ipairs(check.check(result, "test", env, {strict = true}) or {}) do
        if d.severity == "error" then
            found = true
        end
    end
    testAssert.eq(found, true, "an exported signature mentioning any is still reported")
end

-- A declaration the build copied beside the compiled modules goes stale the moment
-- `src` changes it, and the compiler then checks today's source against yesterday's
-- interface. That surfaces as an ordinary type error about a field that is plainly
-- in the file, so the compiler says which carried file it is instead of leaving it
-- to be worked out. Twice now that has cost an afternoon.

function M.aTreeInSyncReportsNothingStale()
    -- The risk this carries is the false positive: it would nag on every command in
    -- every checkout, which is worse than the error it explains.
    local bundled = require("nupp.compiler.bundled")
    for _, relative in ipairs({"/decls/prelude.d.nupp", "/decls/stringbuffer.d.nupp", "/nupp/mem/span.nupp",}) do
        assert(bundled.source(relative), "the compiler carries " .. relative)
    end
    local stale = bundled.staleDeclarations()
    testAssert.eq(#stale, 0, "a tree whose build is current reports " .. table.concat(stale, ", "))
end

function M.embeddedListingsNormalizeBothPackagingRoots()
    local bundled = require("nupp.compiler.bundled")
    local found = bundled.embeddedUnder(
        {
            ["/compiler/decls/first.d.nupp"] = "first",
            ["/nupp/compiler/decls/second.d.nupp"] = "second",
            ["/compiler/decls/shared.d.nupp"] = "shared",
            ["/nupp/compiler/decls/shared.d.nupp"] = "shared",
            ["/other/file"] = "other",
        },
        "/decls"
    )
    table.sort(found)
    testAssert.eq(
        table.concat(found, ","),
        "/decls/first.d.nupp,/decls/second.d.nupp,/decls/shared.d.nupp",
        "both bundle roots list the same relative paths"
    )
end

-- A public standard module the compiler ships but cannot load the types of
-- resolves to `unknown` at every consumer, and a field read on `unknown` says
-- "no field X in unknown" rather than naming the module that was never loaded.
-- That is how `nupp.io.net` and `io.net` sat unresolvable: both were
-- staged into the distribution and classified as public, and neither was in
-- the table the checker loads types from. A consumer got `unknown` for the
-- whole module, so a call to a function that does not exist read the same as
-- one that does.
--
-- The list is derived rather than restated. Both of the tables that drifted
-- were hand-maintained, so a test naming its own modules would drift the same
-- way and pass while the next addition went missing.

function M.everyPublicStandardModuleResolves()
    local surface = require("nupp.compiler.standardsurface")
    local env = strictEnv()
    local lost = {}
    for name, classification in pairs(surface.all()) do
        -- `members` classifies a namespace that holds no module of its own, and
        -- the compiler's own internals are not something a project requires.
        local public = name:match("^nupp%.")
            and classification.kind ~= "members"
            and not name:match("^nupp%.compiler%.")
            and not name:match("^nupp%.runtime%.")
            and not name:match("^nupp%.browser%.")
        if public then
            local resolved = env.resolveModule(env, name)
            if not resolved or resolved == T.any or resolved.tag == "unknown" then
                lost[#lost + 1] = name
            end
        end
    end
    table.sort(lost)
    testAssert.eq(
        #lost,
        0,
        "a module classified public must have loadable types; unresolvable: " .. table.concat(lost, ", ")
    )
end

function M.openFilesKeepTheirLexicalCleanupAcrossThePublicFacade()
    local source = [[
const files = require("io.files")
do
    local file, reason = files.open("input.txt")
    if file == nil then error(reason) end
    print(file)
end
]]
    local parsed = parser.parse(source, "files-owner.nupp")
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "files-owner.nupp", strictEnv(), {strict = true}) or {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            error(("%s: %s"):format(diagnostic.code, diagnostic.msg), 2)
        end
    end
    -- The program never names `close`; the image carries it because the lowering
    -- runs the File terminal at lexical scope exit.
    local image = program.image(parsed, "files-owner")
    assert(program.names(image, "close"), "the public File terminal runs at lexical scope exit")
end

function M.runnerResourceMapsToItsManifestSource()
    local bundled = require("nupp.compiler.bundled")
    local saved = debug.getinfo
    debug.getinfo = function()
        return {source = "@" .. ROOT .. "/build/nupp/compiler/bundled.lua"}
    end
    local ok, path = pcall(bundled.sourcePathFor, "/nupp/test/runner.lua")
    debug.getinfo = saved
    assert(ok, path)
    testAssert.eq(path, ROOT .. "/tests/run.lua", "the carried runner maps to the manifest source")
end

function M.movedPrivateBundledSourcesKeepFileAndTreePrivacyDistinct()
    local bundled = require("nupp.compiler.bundled")
    local originalSource = bundled.source
    local originalEnv = package.loaded["nupp.compiler.project.env"]
    local overrides = {
        ["/nupp/io/init.nupp"] = false,
        ["/nupp/io.nupp"] = "@!internal\nmodule nupp.io\nexport record Token value: integer end\n",
        ["/nupp/io/child/init.nupp"] = "module nupp.io.child\nexport const answer: integer = 29\n",
        ["/nupp/tasks.nupp"] = false,
        ["/nupp/tasks/init.nupp"] = "@!internal\nmodule nupp.tasks\nexport record Token value: integer end\n",
    }
    bundled.source = function(path)
        if overrides[path] ~= nil then
            return overrides[path] or nil
        end
        return originalSource(path)
    end
    package.loaded["nupp.compiler.project.env"] = nil
    local ok, problem = pcall(function()
        local fresh = require("nupp.compiler.project.env")
        local env = fresh.new("/private/tmp", {config = {include = {"no-bundled-layout-fixture"}}, cache = false})
        local ioModule = env.loadBundledModule("nupp.io")
        assert(ioModule and ioModule.exports.types.Token)
        testAssert.eq(ioModule.exports.types.Token.moduleName, "nupp.io")
        testAssert.eq(ioModule.resource, "/nupp/io.nupp")
        testAssert.eq(env.bundledImplementation("nupp.io"), "/nupp/io.nupp")
        assert(env.moduleAccess(env, "application", "nupp.io"))
        testAssert.eq(env.moduleAccess(env, "application", "nupp.io.child"), nil)
        testAssert.eq(env.moduleAccess(env, "io.facade", "nupp.io"), nil)
        local tasks = env.loadBundledModule("nupp.tasks")
        assert(tasks and tasks.exports.types.Token)
        testAssert.eq(tasks.resource, "/nupp/tasks/init.nupp")
        testAssert.eq(env.bundledImplementation("nupp.tasks"), "/nupp/tasks/init.nupp")
        assert(env.moduleAccess(env, "application", "nupp.tasks.child"))
    end)
    package.loaded["nupp.compiler.project.env"] = originalEnv
    bundled.source = originalSource
    assert(ok, problem)
end

function M.retiredUtilRootIsNotCarriedButItsPrivateOwnersRemain()
    local env = envMod.new("/private/tmp/nupp-retired-util-consumer", {
        memoryOnly = true,
        nativeCompilerServices = false,
        typeRoots = {},
    })
    testAssert(not env.bundled["nupp.util"], "retired module is not bundled: nupp.util")
    testAssert(
        not env.bundled["nupp.util.internal.protected"],
        "retired module is not bundled: nupp.util.internal.protected"
    )
    testAssert.eq(env.resolveModuleExports(env, "nupp.util"), nil)
    local binary = assert(env.resolveModuleExports(env, "binary"))
    local bitset = assert(env.resolveModuleExports(env, "nupp.util.internal.bitset"))
    testAssert.eq(binary.types.Bitset, bitset.types.Bitset)
    testAssert.eq(binary.values.WORD_BITS, nil)
    testAssert.eq(bitset.values.WORD_BITS, nil)
end

return M
