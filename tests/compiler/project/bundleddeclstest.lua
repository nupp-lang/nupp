local testAssert = require("assert")
-- The declarations shipped with the compiler have to survive the consumer's
-- opinions about its own source.
--
-- `loadBundled` discards a declaration that produces any diagnostic, and
-- strictness was inherited from the project's manifest -- so `strict = true`, which
-- is the setting a careful project turns on, made every consumer re-judge nupp's
-- own declarations under a rule they were not written to. Foreign declarations
-- can legitimately accept any; strict consumers must still receive their types.
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local gen = require("nupp.compiler.lua.gen")
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
    "jit.util",
    "jit.profile",
    "jit.zone",
    "jit.vmdef",
    "nupp.mem.span",
    "nupp.array",
    "nupp.array.internal.api",
    "nupp.util.internal.pool",
    "nupp.util.internal.structpool",
    "bytes.internal.sharedbytes",
    "events",
    "nupp.runtime.contracts",
    "os.host",
    "debug.profile.zone",
    "debug.profile",
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

function M.byteStorageMovesWithoutChangingItsNominalIdentity()
    local env = envMod.new("/private/tmp/nupp-bytes-consumer", {cache = false})
    local storage = assert(env.resolveModuleExports(env, "nupp.io.internal.bytes"))
    local public = assert(env.resolveModuleExports(env, "bytes"))
    local streams = assert(env.resolveModuleExports(env, "nupp.runtime.standardio"))
    testAssert.eq(T.unwrapOwnership(public.types.Buffer), T.unwrapOwnership(storage.types.Buffer))
    testAssert.eq(T.unwrapOwnership(public.types.BufferWriteLease), T.unwrapOwnership(storage.types.BufferWriteLease))
    testAssert.eq(streams.types.Buffer, nil)
    testAssert.eq(streams.values.Buffer, nil)
    testAssert.eq(streams.types.SharedBytes, nil)
    testAssert(not env.bundled["binary"])
    testAssert(not env.bundled["binary.span"])
    testAssert.eq(T.unwrapOwnership(streams.types.Reader), T.unwrapOwnership(storage.types.Reader))
    testAssert.eq(T.unwrapOwnership(streams.types.Writer), T.unwrapOwnership(storage.types.Writer))
    testAssert.eq(
        diagsUnderPrelude(
            [[
local buffer = bytes.Buffer.create("hello")
bytes.Buffer.writeu8(buffer, 0, 72)
buffer:put("!")
do
    local view = buffer:span()
    assert(#view == 6)
    assert(view[1] == 72)
end
buffer:close()
]]
        ),
        ""
    )
end

function M.compressionFactoriesAndTypesLiveOnBytes()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local {compress, formats, type CompressionFormat,
    type CompressionReaderOptions, type CompressionWriterOptions} = require("bytes")
local gzip: CompressionFormat = compress("gzip")
local writerOptions: CompressionWriterOptions = {gzip = {level = 6}}
local readerOptions: CompressionReaderOptions = {maxoutputbytes = 1024}
assert(gzip:decompress(gzip:compress("hello", writerOptions), readerOptions) == "hello")
assert(#formats("compression") == 3)
assert(gzip is bytes.CompressionFormat)
]]
        ),
        ""
    )
end

function M.bytesDescriptorsAndFamilyEnumCheckOutsideTheCheckout()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local {digest, checksum, mac, formats, type FormatKind,
    type DigestFormat, type ChecksumFormat, type MacFormat} = require("bytes")
local sha: DigestFormat = digest("sha256")
local crc: ChecksumFormat = checksum("crc32c")
local hmac: MacFormat = mac("hmac-sha256")
local kind: FormatKind = "digest"
assert(#formats(kind) > 0)
assert(#sha:computehex("hello") == 64)
assert(crc:compute("123456789") == 0xe3069283ULL)
assert(#hmac:compute("key", "hello") == 32)
]]
        ),
        ""
    )
    assert(diagsUnderPrelude('bytes.formats("unknown")'):find("NUPP2006", 1, true))
    for _, expression in ipairs({
        "bytes.compression",
        "bytes.compressionformats",
        "bytes.Digest.create",
        "bytes.Checksum.compute",
        "bytes.Mac.Algorithm"
    }) do
        assert(diagsUnderPrelude("return " .. expression):find("NUPP2004", 1, true), expression)
    end
end

function M.retiredNamespacesAreNotBundled()
    local env = strictEnv()
    for _, name in ipairs({
        "nupp.text",
        "nupp.text.internal.buffer",
        "nupp.mem.arena",
        "nupp.mem",
        "nupp.mem.array",
        "nupp.mem.heap",
        "nupp.mem.soa",
        "nupp.mem.sharedbytes",
        "package.nupp",
        "bytes.checksum.spi",
        "bytes.digest.spi",
        "bytes.mac.spi",
        "bytes.compress",
        "bytes.compress.internal.contracts",
        "bytes.compress.spi",
        "serde.json.spi",
        "io.spi",
        "io.files.spi",
        "io.files",
        "io.files.messages",
        "io.net.spi",
        "io.http.spi",
        "io.gpu.spi",
        "coroutine.sus",
        "coroutine.sus.host",
        "coroutine.sus.spi",
        "coroutine.workers.spi",
        "coroutine.workers",
        "coroutine.sus.cancellation",
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
        "bytes.hash",
        "bytes.hash.digest",
        "bytes.hash.checksum",
        "bytes.hash.mac",
        "nupp.host",
        "nupp.host.pump",
        "os.host.pump",
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
    for _, resource in ipairs(manifest.build.targets.compiler.resources) do
        if type(resource) == "table" then
            testAssert.ne(resource.source, "src/re.nupp")
            testAssert.ne(resource.source, "src/nupp/compiler/decls/re.d.nupp")
        end
    end
end

function M.compilerCarriesEveryFeatureRuntimeSource()
    local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()
    local resources = {}
    for _, resource in ipairs(manifest.build.targets.compiler.resources) do
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

function M.applicationDirectoriesReturnTheUnifiedPathOutsideTheCheckout()
    local env = envMod.new("/private/tmp/nupp-app-path-consumer", {config = {include = {"src"}}, cache = false})
    local source = [[
os.setappid("example", "notes")
local root: io.Path = assert(os.appdir("data"))
local path: io.Path = assert(root:resolve("draft.txt")):withfilename("notes.txt")
local named: os.Path = path
local file = assert(io.open(named, "w"))
assert(file:write("notes"))
]]
    local parsed = parser.parse(source, "app-path.nupp")
    testAssert.eq(#parsed.errors, 0)
    local diagnostics = check.check(parsed, "app-path.nupp", env)
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local public = assert(env.loadBundledModule("nupp.runtime.standardos"))
    testAssert.eq(public.exports.types.AppPath, nil, "the separate public type is removed")
end

function M.movedFacadesKeepTheirTypesOutsideTheCompilerCheckout()
    local env = envMod.new("/private/tmp/nupp-bundled-layout-consumer", {config = {include = {"src"}}, cache = false})
    local sources = {
        ["nupp.runtime.contracts"] = "/nupp/runtime/contracts.nupp",
        ["debug.profile"] = "/debug/profile/init.nupp",
        ["debug.profile.zone"] = "/debug/profile/zone.nupp",
        ["bytes"] = "/bytes/init.nupp",
        ["bytes.span"] = "/bytes/span.nupp",
        ["nupp.runtime.entropy"] = "/nupp/runtime/entropy.nupp",
        ["nupp.runtime.standardtable"] = "/nupp/runtime/standardtable.nupp",
        ["coroutine.host"] = "/coroutine/host.nupp",
        ["nupp.suspension.contracts"] = "/nupp/suspension/contracts.nupp",
        ["nupp.workers.contracts"] = "/nupp/workers/contracts.nupp",
        ["io.internal.files"] = "/io/internal/files/init.nupp",
        ["io.internal.files.messages"] = "/io/internal/files/messages.nupp",
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
    local host = env.loadBundledModule("coroutine.host")
    local privateHost = env.loadBundledModule("nupp.suspension.host")
    local install = host.exports.values.install
    testAssert.eq(install.tag, "func", "install retains its checked signature")
    testAssert.eq(install.rets[1].tag, "affine", "installation requires cleanup")
    testAssert.eq(
        host.exports.types.Handler,
        privateHost.exports.types.Handler,
        "the facade preserves nominal identity"
    )
    local coroutineModule = env.loadBundledModule("nupp.runtime.standardcoroutine")
    testAssert.eq(coroutineModule.exports.values.handled, nil, "handler introspection stays internal")
    testAssert.eq(coroutineModule.exports.values.poll, nil, "polling belongs to hosts")
    testAssert.eq(coroutineModule.exports.values.source.tag, "func")
    testAssert.eq(host.exports.values.poll.tag, "func")
    testAssert.eq(coroutineModule.exports.values.suspend.tag, "func")
    local workerContract = env.loadBundledModule("nupp.workers.contracts")
    testAssert.eq(coroutineModule.exports.types.Worker, workerContract.exports.types.Worker)
    testAssert.eq(coroutineModule.exports.values.newcancellation.tag, "func")
    testAssert.eq(coroutineModule.exports.values.iscancellation.rets[1].tag, "boolean")
end

function M.directSuspendKeepsItsGenericTypeOutsideTheCheckout()
    local env = envMod.new("/private/tmp/nupp-coroutine-sus-consumer", {config = {include = {"src"}}, cache = false})
    local source = [[
local function wait(): string
    return coroutine.suspend("ready", function(resume: function(string), context: coroutine.Context): function()?
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
    local code, diagnostics = gen.generate(parsed, "suspend-consumer.nupp")
    testAssert.eq(#diagnostics, 0)
    testAssert(code:find("nupp.runtime.standardcoroutine", 1, true) ~= nil)
    local text, number = assert(loadstring(code))()
    testAssert.eq(text, "ready")
    testAssert.eq(number, 42)
end

function M.finalNamespaceHomesKeepCheckedTypesOutsideTheCheckout()
    local env = envMod.new("/private/tmp/nupp-bundled-layout-consumer", {config = {include = {"src"}}, cache = false})
    local source = [[
local bytes = require("bytes")
local client: io.net.TlsClientOptions = {hostname = "example.com"}
local server: io.net.TlsServerOptions = {certificate = "certificate", privatekey = "key"}
local function ready(borrows session: io.net.TlsSession): boolean
    return session:isready()
end
local {type Pool} = require("table")
local {Pool} = require("table")
local record Value
    number: integer
end
local bits: bytes.Bitset = bytes.Bitset(64)
local values: Pool<Value> = Pool(Value, 4)
local qualified: table.Pool<Value> = table.Pool(Value, 4)
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
    local bytes = env.resolveModuleExports(env, "bytes")
    local private = env.resolveModuleExports(env, "nupp.util.internal.bitset")
    testAssert.eq(bytes.types.Bitset, private.types.Bitset)
end

function M.providerContractImportErasesWithoutLoadingAnImplementation()
    local parsed = parser.parse(
        [[
module nupp.test.providercontract
local {type ClockProvider} = require("nupp.runtime.contracts")
export function now(clock: ClockProvider): number return clock.now() end
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
    local code = gen.generate(parsed, "provider_contract_import")
    assert(not code:find('nupp.runtime.contracts', 1, true), code)
end

function M.profilingCollectorAndRegistryKeepDistinctQualifiedTypes()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local profile = debug.profile
local version: integer = profile.catalogversion
local session = profile.trace()
local report: profile.TraceReport = session:stop()
return version, report.aborts
]]
        ),
        ""
    )
end

function M.uuidUsesItsContractWithoutNativeCompilerServices()
    local env = envMod.new(".", {memoryOnly = true, nativeCompilerServices = false, typeRoots = {},})
    local result = parser.parse(
        "local function make(version: 4 | 7): string return os.uuid(version) end\nreturn make(4), make(7)",
        "uuid-contract.nupp"
    )
    testAssert.eq(#result.errors, 0)
    local diagnostics = check.check(result, "uuid-contract.nupp", env)
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local uuid = env.globals.os.t
    testAssert.eq(uuid.byname.uuid.tag, "func", "uuid has a checked function signature")
    testAssert.eq(T.tostring(uuid.byname.uuid.params[1]), "4 | 7", "uuid accepts only supported versions")
    testAssert.eq(uuid.byname.uuid.rets[1].tag, "string", "uuid returns a string")
    testAssert.eq(uuid.byname.uuid4, nil, "the retired version 4 entry is absent")
    testAssert.eq(uuid.byname.uuid7, nil, "the retired version 7 entry is absent")
    for _, source in ipairs({
        "return os.uuid(5)",
        "return os.uuid(4.5)",
        'return os.uuid("4")',
        "local function make(version: integer): string return os.uuid(version) end\nreturn make(4)",
    }) do
        local refused = parser.parse(source, "uuid-invalid-version.nupp")
        testAssert.eq(#refused.errors, 0)
        local rejected = false
        for _, diagnostic in ipairs(check.check(refused, "uuid-invalid-version.nupp", env)) do
            rejected = rejected or diagnostic.code == "NUPP2006"
        end
        assert(rejected, "unsupported UUID version type was accepted: " .. source)
    end
    local exports = assert(env.resolveModuleExports(env, "os"))
    testAssert.eq(exports.values.uuid, uuid.byname.uuid, "module and export resolution agree")
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
const sb = require("bytes")
const b = sb.Buffer.create()
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

function M.anEmbeddedCompilerDoesNotProbeDiskForMissingDeclarations()
    local instances = require("helpers.providerstate")
    local host = {
        open = function(path)
            error("embedded declaration lookup reached disk: " .. path)
        end
    }
    for _, prefix in ipairs({"/compiler", "/nupp/compiler"}) do
        local load = instances.instance(
            {["nupp.compiler.bundled"] = true},
            {["nupp.runtime.standardio"] = {value = host},},
            {
                ["nupp.embedded"] = function()
                    return {[prefix .. "/coroutine.nupp"] = "module coroutine"}
                end,
            },
            {io = host, __nuppCleanupRegistry = {}}
        )
        local bundled = load("nupp.compiler.bundled")
        testAssert.eq(bundled.source("/coroutine/init.nupp"), nil)
        testAssert.eq(bundled.source("/coroutine.nupp"), "module coroutine")
        testAssert.eq(bundled.source("/missing.nupp"), nil)
    end
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
    for _, relative in ipairs({"/decls/prelude.d.nupp", "/nupp/mem/span.nupp",}) do
        assert(bundled.source(relative), "the compiler carries " .. relative)
    end
    local stale = bundled.staleDeclarations()
    testAssert.eq(#stale, 0, "a tree whose build is current reports " .. table.concat(stale, ", "))
end

function M.everyCarriedDeclarationResolvesToItsSource()
    -- The mapping restates what the manifest says rather than reading it, so a file
    -- it points at the wrong place is one nothing would ever report on. Both shapes
    -- are here on purpose: `/decls` comes from under `src/nupp/compiler`, and
    -- everything else keeps the path it has under `src`.
    local bundled = require("nupp.compiler.bundled")
    for _, relative in ipairs({"/decls/prelude.d.nupp", "/decls/jit/util.d.nupp", "/nupp/mem/span.nupp",}) do
        local path = bundled.sourcePathFor(relative)
        assert(path, "a checkout was found for " .. relative)
        local file = io.open(path, "rb")
        assert(file, relative .. " maps to " .. tostring(path) .. ", which is not there")
        file:close()
    end
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
do
    local file, reason = io.open("input.txt")
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
    local code = gen.generate(parsed, "files-owner")
    assert(code:find("__nuppCloseFile", 1, true), "the public File terminal runs at lexical scope exit")
end

function M.fileByteViewsAreAffineOwners()
    for _, method in ipairs({"reader", "writer"}) do
        local diagnostics = diagsUnderPrelude(
            ([[
local file = assert(io.open("input.bin", "r+"))
file:%s()
]]):format(method)
        )
        assert(diagnostics:find("NUPP26", 1, true), method .. ": " .. diagnostics)
    end
end

function M.fileByteViewsCannotEscapeTheirLocalFile()
    for _, view in ipairs({{method = "reader", name = "Reader"}, {method = "writer", name = "Writer"}}) do
        local diagnostics = diagsUnderPrelude(
            (
                [[
local function escape(): affine(io.%s)
    local file = assert(io.open("input.bin", "r+"))
    return file:%s()
end
]]
            ):format(view.name, view.method)
        )
        assert(diagnostics:find("NUPP26", 1, true), view.method .. ": " .. diagnostics)
    end
end

function M.liveExclusiveFileViewsPreventClosingTheirFile()
    for _, view in ipairs({
        {method = "reader", operation = "read(1)"},
        {method = "writer", operation = "write('x')"}
    }) do
        local diagnostics = diagsUnderPrelude(
            (
                [[
local file = assert(io.open("input.bin", "r+"))
local view = file:%s()
file:close()
view:%s
view:close()
]]
            ):format(view.method, view.operation)
        )
        assert(diagnostics:find("NUPP26", 1, true), view.method .. ": " .. diagnostics)
    end
end

function M.closingByteViewsAllowsReusingTheirFile()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local file = assert(io.open("input.bin", "r+"))
local reader = file:reader()
reader:read(1)
reader:close()
file:seek("set", 0)
local writer = file:writer()
writer:write("x")
writer:close()
file:flush()
file:close()
]]
        ),
        ""
    )
end

function M.fileByteViewsCanBeConsumedByBoundedLines()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local file = assert(io.open("input.bin", "rb"))
local reader = file:reader()
local lines = reader:lines(32)
local line, reason = lines:read()
if line == nil then assert(reason == nil, reason) end
lines:close()
file:seek("set", 0)
file:close()
]]
        ),
        ""
    )
end

function M.fileParametersGetByteViewsWithoutAnAcquisitionExpression()
    local source = [[
local function useFile(exclusive file: io.File): nil
    local reader = file:reader()
    reader:read(1)
    reader:close()
    local writer = file:writer()
    writer:write("x")
    writer:close()
end
return useFile
]]
    testAssert.eq(diagsUnderPrelude(source), "")
    local parsed = parser.parse(source, "file-parameter.nupp")
    testAssert.eq(#parsed.errors, 0)
    for _, diagnostic in ipairs(check.check(parsed, "file-parameter.nupp", strictEnv(), {strict = true}) or {}) do
        testAssert.ne(diagnostic.severity, "error", diagnostic.msg)
    end
    local code, diagnostics = gen.generate(parsed, "file-parameter.nupp")
    testAssert.eq(#diagnostics, 0)
    assert(code:find("nupp.runtime.standardio", 1, true), "byte view calls carry their runtime installer")
end

function M.standardStreamsExposeTheSameByteViewTypes()
    testAssert.eq(
        diagsUnderPrelude(
            [[
local function acceptReader(exclusive reader: io.Reader): nil end
local function acceptWriter(exclusive writer: io.Writer): nil end
local reader = io.stdin:reader()
acceptReader(reader)
reader:close()
local output = io.stdout:writer()
acceptWriter(output)
output:close()
local errors = io.stderr:writer()
acceptWriter(errors)
errors:close()
]]
        ),
        ""
    )
end

function M.boundedFileLinesCannotEscapeTheirLocalFile()
    local diagnostics = diagsUnderPrelude(
        [[
local function escape(): affine(io.Lines)
    local file = assert(io.open("input.bin", "rb"))
    local reader = file:reader()
    return reader:lines(32)
end
]]
    )
    assert(diagnostics:find("NUPP26", 1, true), diagnostics)
end

function M.movedPrivateBundledSourcesKeepFileAndTreePrivacyDistinct()
    local bundled = require("nupp.compiler.bundled")
    local originalSource = bundled.source
    local originalEnv = package.loaded["nupp.compiler.project.env"]
    -- This fixture tests each child marker independently of the shipped root.
    local overrides = {
        ["/nupp/init.nupp"] = "const nupp = {}\nreturn nupp\n",
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
        local env = fresh.new("/private/tmp/nupp-bundled-privacy-consumer", {
            config = {include = {"src"}},
            cache = false
        })
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
    local bytes = assert(env.resolveModuleExports(env, "bytes"))
    local bitset = assert(env.resolveModuleExports(env, "nupp.util.internal.bitset"))
    testAssert.eq(bytes.types.Bitset, bitset.types.Bitset)
    testAssert.eq(bytes.values.WORD_BITS, nil)
    testAssert.eq(bitset.values.WORD_BITS, nil)
end

function M.bootstrapFilesystemAdaptersKeepCurrentPrivateTypes()
    local environment = envMod.new(ROOT)
    local prior = assert(environment.resolveModuleExports(environment, "io.files.internal.contracts"))
    local current = assert(environment.resolveModuleExports(environment, "io.internal.files.contracts"))
    testAssert.eq(T.unwrapOwnership(prior.types.File), T.unwrapOwnership(current.types.File))
    testAssert.eq(prior.types.Provider, current.types.Provider)
    testAssert.eq(T.unwrapOwnership(prior.types.TemporaryPath), T.unwrapOwnership(current.types.TemporaryPath))
    local tree = parser.parse('return require("io.files")', "bootstrap-adapter-consumer.nupp")
    local refused = false
    for _, diagnostic in ipairs(check.check(tree, "bootstrap-adapter-consumer.nupp", environment)) do
        refused = refused or diagnostic.code == "NUPP2144"
    end
    assert(refused, "the bootstrap path must remain private")
end

return M
