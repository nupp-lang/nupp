local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local standardsurface = require("nupp.compiler.standardsurface")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local JSON_PROVIDER = "nupp.codec.json.provider"

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

-- One shared env for all stdlib tests (prelude loads once); module tests
-- get an env rooted at the tests directory so fixtures resolve.
local sharedEnv = envMod.new(HERE)

local function diagsOf(src, opts)
    sharedEnv.loaded = {}
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, "test.g.nupp", sharedEnv, opts)
    local out = {}
    for j, d in ipairs(diags) do
        out[j] = d.code .. ":" .. d.line
    end

    return table.concat(out, " "), diags
end

local function assertClean(src, opts)
    local got, diags = diagsOf(src, opts)
    assertEq(got, "", "expected clean check for:\n" .. src .. (diags[1] and ("\nfirst: " .. diags[1].msg) or ""))
end

local M = {}

function M.digestFinalizationConsumesButChecksumReadsDoNot()
    for _, finalizer in ipairs({"digest()", "hexDigest()"}) do
        local _, diagnostics = diagsOf(
            table.concat(
                {
                    "local rolling = nupp.digest.create('sha256')",
                    "local result = rolling:" .. finalizer,
                    "rolling:update('too late')",
                },
                "\n"
            )
        )
        local ownership = false
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.line == 3 and diagnostic.code:match("^NUPP26") then
                ownership = true
            end
        end
        assert(ownership, "finalization must prevent subsequent updates: " .. finalizer)
    end
    assertClean(
        table.concat(
            {
                "local sum = nupp.checksum.create('crc32c')",
                "local before = sum:value()",
                "sum:update('still open')",
                "local after = sum:value()",
            },
            "\n"
        )
    )
end

function M.closedBufferReleasesItsAllocationWhileMetadataSurvives()
    local buffer = require("nupp.io").newBuffer(string.rep("x", 1048576))
    local allocation = setmetatable({buffer._data}, {__mode = "v"})
    buffer:drop()
    collectgarbage("collect")
    collectgarbage("collect")
    assert(buffer._closed, "the closed buffer metadata remains observable")
    assert(allocation[1] == nil, "a closed buffer must release its allocation root")
end

function M.moduleInitializationKeepsManagedAliasesAndRuntimeIdentity()
    local scope = setmetatable({nupp = {}}, {__index = _G})
    scope._G = scope
    local initialize = assert(loadstring(stdlib.bootstrap()))
    setfenv(initialize, scope)
    initialize()
    local manage = scope.nupp.__manage
    local owner = manage(
        {},
        function()
        end,
        "test"
    )
    local alias = owner:alias()
    initialize()
    assert(scope.nupp.__manage == manage, "a module must reuse the installed ownership runtime")
    local recovered, problem = scope.nupp.__recoverAlias(alias)
    assert(recovered == alias and problem == nil, "loading a module must not invalidate an existing alias")
    assert(alias:close() == nil)
end

function M.ownershipInstallerDoesNotRecursivelyLoadItsPrelude()
    local result = parser.parse("module nupp.runtime.managed\nexport function install(): nil end\n", "installer.g.nupp")
    check.check(result, "installer.g.nupp", sharedEnv, {strict = false})
    result.preludeRuntime = 'require("nupp.runtime.managed").install()'
    local code, diagnostics = gen.generate(result, "installer.g.nupp")
    assertEq(#diagnostics, 0, "the ownership installer generates")
    for _, name in ipairs(gen.runtimeModules(code)) do
        assert(name ~= "nupp.runtime.managed", "the installer must not load itself through the prelude")
    end
    assert(not code:find("@nupp-prelude", 1, true), "the intrinsic installer does not execute a dependent prelude")
end

function M.checkerRecordsTheResolvedDialect()
    local default = parser.parse("return 42\n", "default.nupp")
    check.check(default, "default.nupp", sharedEnv)
    assertEq(default.dialect, "luajit", "the checker defaults to the native dialect")

    local portable = parser.parse("return 42\n", "portable.nupp")
    check.check(portable, "portable.nupp", sharedEnv, {dialect = "lua51"})
    assertEq(portable.dialect, "lua51", "the checker records the selected dialect")
end

function M.portableWideIntegersUseFixedOperations()
    local source = [[
local a: int64 = 9223372036854775807LL
local b: int64 = 2LL
local c = (a + b) * b
return c < a, c >> 1LL, ~c
]]
    local nativeTree = parser.parse(source, "native-int64.nupp")
    assertEq(#check.check(nativeTree, "native-int64.nupp", sharedEnv), 0, "native int64 checks")
    local nativeCode = gen.generate(nativeTree, "native-int64.nupp")
    assert(nativeCode:find("9223372036854775807LL", 1, true), "native output keeps cdata literals")
    assert(not nativeCode:find("__nuppInt64", 1, true), "native output has no adapter")

    local portableTree = parser.parse(source, "portable-int64.nupp")
    assertEq(
        #check.check(portableTree, "portable-int64.nupp", sharedEnv, {
            dialect = "lua51",

        }),
        0,
        "portable int64 checks"
    )
    local code, diags = gen.generate(portableTree, "portable-int64.nupp")
    assertEq(#diags, 0, "portable int64 lowers")
    for _, operation in ipairs({"int64", "add", "mul", "compare", "rshift", "bnot"}) do
        assert(code:find("__nuppInt64." .. operation, 1, true), "wide operation lowers through " .. operation)
    end
    assert(not code:find("LL", 1, true), "portable output has no LuaJIT cdata suffix")
end

function M.portableStructsUseTheTargetRepresentation()
    local source = [[
local struct Point
   x: float
   bits: uint8
end
local p = new Point(16777217, 254)
return p
]]
    local nativeTree = parser.parse(source, "native-struct.nupp")
    assertEq(#check.check(nativeTree, "native-struct.nupp", sharedEnv), 0, "native struct checks")
    local nativeCode = gen.generate(nativeTree, "native-struct.nupp")
    assert(nativeCode:find("require(\"ffi\")", 1, true), "native output keeps direct FFI representation")
    assert(not nativeCode:find("__nuppStructvalue", 1, true), "native output pays no provider access")

    local portableTree = parser.parse(source, "portable-struct.nupp")
    assertEq(
        #check.check(portableTree, "portable-struct.nupp", sharedEnv, {
            dialect = "lua51",

        }),
        0,
        "portable struct checks with its contract"
    )
    local portableCode, diags = gen.generate(portableTree, "portable-struct.nupp")
    assertEq(#diags, 0, "portable struct lowers")
    assert(portableCode:find("__nuppStructvalue.define", 1, true), "declaration uses the checked implementation")
    assert(not portableCode:find("require(\"ffi\")", 1, true), "portable struct output carries no FFI")
end

function M.wasmViewsLowerThroughTheOpaqueCheckedSurface()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local struct Sample
   value: float
end
local values = array.new(new Sample(), 2)
local writable = values:write()
writable[1] = new Sample(3)
drop writable
local readable = values:read()
return #readable, readable[1].value
]]
    local tree = parser.parse(source, "wasm-view.nupp")
    assertEq(
        #check.check(tree, "wasm-view.nupp", sharedEnv, {
            dialect = "lua51",

        }),
        0,
        "Wasm views check through both required contracts"
    )
    local code, diags = gen.generate(tree, "wasm-view.nupp")
    assertEq(#diags, 0, "Wasm views lower")
    assert(code:find("writable%s*:set%s*%(%s*1"), code)
    assert(code:find("readable%s*%.count"), code)
    assert(code:find("readable%s*:get%s*%(%s*1%s*%)%s*%.value"), code)
    assert(not code:find("require(\"ffi\")", 1, true), code)
end

function M.poolIsOrdinaryTablesOnEveryDialect()
    assertClean(
        table.concat(
            {
                "local pool = require('nupp.mem.pool')",
                "local record Event",
                "    id: integer",
                "end",
                "local events = pool.new(Event, 4)",
                "local event = events:acquire()",
                "event.id = 1",
                "events:release(event)",
                "return events:free()",
            },
            "\n"
        ),
        {dialect = "lua51"}
    )
end

function M.arenaLowersThroughTheStorageContract()
    local source = table.concat(
        {
            "local arena = require('nupp.mem.arena')",
            "local struct Sample",
            "   value: float",
            "end",
            "local samples = arena.new(Sample, 8)",
            "local sample = samples:acquire()",
            "sample.value = 3",
            "samples:release(sample)",
            "return samples:used()",
        },
        "\n"
    )
    sharedEnv.loaded = {}
    local tree = parser.parse(source, "wasm-arena.nupp")
    local diags = check.check(tree, "wasm-arena.nupp", sharedEnv, {dialect = "lua51",})
    assertEq(#diags, 0, "an arena checks through the storage contract" .. (diags[1] and (": " .. diags[1].msg) or ""))
    local code, genDiags = gen.generate(tree, "wasm-arena.nupp")
    assertEq(#genDiags, 0, "an arena lowers through the storage contract")
    assert(not code:find("require(\"ffi\")", 1, true), code)
end

function M.aComputedRequireArgumentIsChecked()
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local registry = require('nupp.codec.json')", "return require(registry.encode('module.name'))",},
                    "\n"
                )
            )
        ),
        "",
        "a computed name of the right type checks"
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local registry = require('nupp.codec.json')", "return require(registry.absent('data.json'))",},
                    "\n"
                )
            )
        ),
        "NUPP2004:2",
        "a field no value has is reported inside the call"
    )
    assertEq((diagsOf("local n: integer = 5\nreturn require(n)")), "NUPP2006:2", "require takes a string")
    assertEq((diagsOf("return require('nupp.uuid', 'extra')")), "NUPP2007:1", "and takes one of them")
end

function M.randomUsesPortableBitops()
    assertClean(
        table.concat(
            {
                "local random = require('nupp.random')",
                "local generator = random.newRandom(12345)",
                "return generator:next(), generator:integer(1, 100)",
            },
            "\n"
        ),
        {dialect = "lua51",}
    )
end

function M.digestUsesPortableBitops()
    assertClean(
        table.concat(
            {
                "local digest = require('nupp.digest')",
                "local rolling = digest.create('sha256')",
                "rolling:update('message')",
                "return rolling:hexDigest()",
            },
            "\n"
        ),
        {dialect = "lua51",}
    )
end

function M.oneShotHmacUsesOrdinaryCode()
    assertClean(
        table.concat(
            {
                "local mac = require('nupp.mac')",
                "return mac.hexDigest('hmac-sha256', 'key', 'message'), #mac.digest('hmac-sha256', 'key', 'message')",
            },
            "\n"
        ),
        {dialect = "lua51",}
    )
end

function M.browserHttpProviderHasAPortableDependencyClosure()
    local path = HERE .. "/../src/nupp/runtime/browser/http.g.nupp"
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    local result = parser.parse(source, path)
    assertEq(#result.errors, 0, "syntax errors in browser HTTP provider")
    local root = HERE .. "/.."
    local env = envMod.new(root)
    local diags = check.check(result, path, env, {dialect = "lua51"})
    assertEq(diags[1] and diags[1].msg or "", "", "the browser HTTP provider must not reach a native implementation")
end

function M.browserHttpRejectsUnsupportedClientPolicy()
    local browser = require("providerstate").browserHttp()
    for _, options in ipairs({{userAgent = "nupp-test"}, {connectTimeoutMs = 10}}) do
        local ok, problem = pcall(browser.client, options)
        assert(
            not ok and tostring(problem):find("does not support option", 1, true),
            "unsupported shared options must fail explicitly: " .. tostring(problem)
        )
    end
end

function M.browserHttpTransfersItsBodyToTheReturnedResponse()
    local effects = require("nupp.runtime.browser.effects")
    local ffi = require("ffi")
    local prior = effects.request
    local leases, nextLease = {}, 0
    local memory = {
        lease = function(pointer, count, writable)
            nextLease = nextLease + 1
            leases[nextLease] = {pointer = pointer, count = count, writable = writable}
            return nextLease
        end,
        releaseLease = function(id)
            leases[id] = nil
        end,
    }
    local browser = require("providerstate").browserHttp(memory)
    effects.request = function(_, effect, resume)
        if effect.operation == "read-body" then
            local lease = assert(leases[effect.lease])
            assert(lease.writable and lease.count == 3)
            ffi.copy(lease.pointer, "abc", 3)
            resume({ok = true, value = {bytes = 3}})
        else
            assert(effect.memoryResponse and effect.bodyBase64 == nil)
            local upload = assert(leases[effect.bodyLease])
            assert(not upload.writable and ffi.string(upload.pointer, upload.count) == "upload")
            resume({ok = true, value = {status = 200, body = 1, bodyBytes = 3, headers = {}}})
        end

        return function()
        end
    end
    local ok, problem = pcall(function()
        local client = browser.client()
        local closedUpload = false
        local input = "upload"
        local source = {
            read = function(_, count)
                local bytes = input:sub(1, count);
                input = input:sub(#bytes + 1);
                return bytes
            end,
            close = function()
                closedUpload = true
            end
        }
        local request = setmetatable(
            {
                url = assert(require("nupp.io.uri").newURI("https://example.com/")),
                body = require("nupp.io.http").reader(source, 6),
            },
            require("nupp.io.http.messages").Request
        )
        local response, reason = client:send(request)
        assert(response, reason)
        local destination = require("nupp.io").newBuffer()
        assertEq(response.body:readInto(destination, 0, 2), 2)
        assertEq(destination:getString(), "ab")
        assertEq(response.body:read(3), "c", "the returned response owns a live ordinary reader")
        response:close()
        local bytes, closed = response.body:read(1)
        assertEq(bytes, nil)
        assertEq(closed, "the reader is closed")
        request:close()
        assert(closedUpload, "the request retains its upload close obligation")
        client:close()
        assert(next(leases) == nil, "completed transfers release both leases")
    end)
    effects.request = prior
    assert(ok, problem)
end

function M.stringLibrary()
    assertClean("local s: string = string.format('%d', 3)")
    assertClean("local s: string = string.format('%d', 3)\nreturn string.rep(s, 2)", {dialect = "lua51"})
    assertEq((diagsOf("local n: number = string.format('%d', 3)")), "NUPP2001:1")
    assertEq((diagsOf("string.formt('%d', 3)")), "NUPP2004:1")
    assertClean("local a, b = string.find('abc', 'b')\nlocal x: integer? = a")
end

function M.stringMethods()
    assertClean("local s: string = ('abc'):sub(1, 2)")
    assertClean("local s: string\nlocal u: string = s:upper()")
    assertEq((diagsOf("local s: string\ns:sub('bad')")), "NUPP2006:2")
end

function M.mathAndBit()
    assertClean("local i: integer = math.floor(1.7)")
    assertClean("local n: number = math.max(1, 2, 3)")
    assertClean("local i: integer = bit.band(0xFF, 0x0F)")
    assertEq((diagsOf("math.floor('x')")), "NUPP2006:1")
end

function M.mathRandomOverloadsMatchLuaJitArities()
    assertClean(
        table.concat(
            {
                "local unit: number = math.random()",
                "local upper: number = math.random(10)",
                "local range: number = math.random(1.5, 4.5)",
            },
            "\n"
        )
    )
    assertEq((diagsOf("math.random(nil, 2)")), "NUPP2125:1")

    local unit = math.random()
    local upper = math.random(10)
    local fractional = math.random(1.5, 4.5)
    assert(
        type(unit) == "number" and type(upper) == "number" and type(fractional) == "number",
        "every documented math.random arity returns a Lua number"
    )
    assertEq(pcall(math.random, nil, 2), false, "the rejected nil hole also fails in LuaJIT")
end

function M.mathMinMaxKeepIntegers()
    assertClean(
        table.concat(
            {
                "local xs: {string} = {'a', 'b'}",
                "local n: integer = math.min(#xs, 2)",
                "local m: integer = math.max(1, n)",
                "local s: string = xs[math.min(#xs, 2)]",
            },
            "\n"
        )
    )
    assertClean("local w: number = math.min(1.5, 2)")
    assertEq((diagsOf("local bad: integer = math.min(1.5, 2.5)")), "NUPP2001:1")
    assertEq((diagsOf("math.min('nope', 1)")), "NUPP2116:1")
end

function M.typedVarargElements()
    assertClean(
        table.concat({"local function sum(...: integer): integer", "    return 0", "end", "sum(1, 2, 3)",}, "\n")
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local function sum(...: integer): integer", "    return 0", "end", "sum(1, 'two')",},
                    "\n"
                )
            )
        ),
        "NUPP2006:4"
    )
    assertEq((diagsOf("string.char(65, 'B')")), "NUPP2006:1")
    assertClean(table.concat({"local function anything(...) end", "anything(1, 'two', {})",}, "\n"))
end

function M.coreFunctions()
    assertClean("print('hello', 42)")
    assertClean("local t: string = type({})")
    assertClean("local n: number? = tonumber('42')")
    assertClean("local v: number = assert(tonumber('42'))")
    assertClean("local ok, err = pcall(function() end)\nlocal b: boolean = ok")
    assertClean("local t = setmetatable({}, {__index = {}})")
end

function M.everyFeatureRuntimeIsPortableOrRefused()
    local surface = require("nupp.compiler.standardsurface")
    local portable = {opts = {dialect = "lua51"}}
    for _, effect in ipairs(native.effectNames()) do
        local feature = native.feature(effect)
        local moduleName = feature.runtimeModule
        if moduleName ~= nil and not feature.portableRuntime then
            assert(
                not surface.reachable(portable, moduleName),
                (
                    "%s stages %s for a lua51 target: "
                ):format(
                    effect,
                    moduleName
                ) .. "either say portableRuntime, or classify the module so that target cannot reach it"
            )
        end
    end
end

function M.reachableStandardFacilitiesHaveRuntimeMetadata()
    local surface = require("nupp.compiler.standardsurface")
    local portable = {opts = {dialect = "lua51"}}
    for moduleName, facility in pairs(surface.all()) do
        if facility.effect and surface.reachable(portable, moduleName) then
            local feature = native.feature(facility.effect)
            assert(feature, moduleName .. " has no runtime metadata for " .. facility.effect)
            assert(
                feature.runtimeModule == nil or feature.portableRuntime,
                moduleName .. " cannot be packaged for Lua 5.1"
            )
        end
    end
end

function M.portableFeatureRuntimesAreReachable()
    local surface = require("nupp.compiler.standardsurface")
    local portable = {opts = {dialect = "lua51"}}
    local seen = 0
    for _, effect in ipairs(native.effectNames()) do
        local feature = native.feature(effect)
        if feature.portableRuntime then
            seen = seen + 1
            assert(feature.runtimeModule ~= nil, effect .. " says portableRuntime with no runtime module to compile")
        end
    end
    assert(seen > 0, "some feature runtime is portable")
end

function M.nativeFeaturesAreResolvedEffects()
    local function effectsOf(source)
        local result = parser.parse(source, "native-effects")
        assertEq(#result.errors, 0, "native-effects source parses")
        check.check(result, "native-effects", sharedEnv)
        return result.effects or {}
    end

    assertEq(
        (diagsOf("local location: NuppPath")),
        "NUPP2101:1",
        "qualified nominals do not leak into the ambient type namespace"
    )

    local lpeg = effectsOf("local parser = require('lpeg')")
    assert(lpeg["native.lpeg"], "require('lpeg') records its native effect")
    local re = effectsOf("local parser = require('re')")
    assert(re["stdlib.lpeg.re"], "require('re') records its reference-module effect")
    assert(native.expand(re)["native.lpeg"], "the re module brings native LPeg")

    local json = effectsOf("local json = require('nupp.codec.json')")
    assert(json["native.json"], "require('nupp.codec.json') records its JSON effect")

    local test = effectsOf("local test = require('nupp.test')")
    assert(test["runtime.test"], "require('nupp.test') carries the assertion module")

    local process = effectsOf("local process = require('nupp.io.process')")
    assert(process["runtime.process"], "the process module records its facade dependency")
    assert(not process["native.process"], "provider choice follows target catalog resolution")
    local workers = effectsOf("local workers = require('nupp.workers')")
    assert(workers["runtime.workers"], "the workers module records its facade dependency")
    local http = effectsOf("local http = require('nupp.io.http')")
    assert(http["runtime.http"], "the HTTP module records its facade dependency")

    local shadowed = effectsOf(
        table.concat({"local nupp = {digest = {hexDigest = function() end}}", "nupp.digest.hexDigest()",}, "\n")
    )
    assert(not shadowed["native.sha256"], "a local nupp is not the global facility")

    local shadowedIO = effectsOf(
        table.concat({"local nupp = {io = {path = {separator = function() end}}}", "nupp.io.path.separator()",}, "\n")
    )
    assert(not shadowedIO["native.path"], "a local nupp.io is not the global facility")

    local shadowedRequire = effectsOf(
        table.concat({"local require = function(_) return {} end", "require('lpeg')",}, "\n")
    )
    assert(not shadowedRequire["native.lpeg"], "a local require is not the native module loader")

    local expected = {
        ["nupp.codec.json.encode({answer = 42})"] = "native.json",
        ["nupp.codec.json.pull('{}', {answer = true})"] = "native.json",
        ["nupp.text.utf8.length('hello')"] = "runtime.data_utf8",
        ["nupp.io.newBuffer('hello')"] = "stdlib.io",
        ["nupp.math.lerp(10, 20, 0.25)"] = "stdlib.math",
        ["nupp.math.vec2.length(3, 4)"] = "stdlib.math",
        ["nupp.io.path.separator()"] = "runtime.path",
        ["nupp.io.uri.newURI('https://example.com')"] = "runtime.uri",
        ["nupp.uuid.v7()"] = "runtime.uuid",
        ["nupp.system.availableParallelism()"] = "runtime.system",
    }
    for source, effect in pairs(expected) do
        local found = effectsOf(source)
        assert(found[effect], source .. " records " .. effect)
        local count = 0
        for _ in pairs(found) do
            count = count + 1
        end
        assertEq(count, 1, source .. " records only its own facility")
    end

    assertClean(
        table.concat(
            {
                "const {Path} = require('nupp.io.path')",
                "local source: nupp.io.path.Path = nupp.io.path.newPath('src', 'main.nupp')",
                "local components: nupp.io.uri.Components = nil as any",
                "local URIOf: function(",
                "    value: string | nupp.io.uri.Components",
                "): (nupp.io.uri.URI?, string?) = nupp.io.uri.newURI",
                "local address: nupp.io.uri.URI? = URIOf(components)",
                "print(source, address)",
            },
            "\n"
        )
    )

    local aliased = effectsOf(
        table.concat({"const system = require('nupp.system')", "system.availableParallelism()",}, "\n")
    )
    assert(aliased["runtime.system"], "requiring a facility records its feature")
    assert(not aliased["runtime.uuid"], "separate facilities do not share effects")

    local namespaceOnly = effectsOf("local store = nupp.store")
    assert(next(namespaceOnly) == nil, "reaching a namespace alone has no effect")
end

function M.processViewsSatisfyTheSharedContracts()
    assertClean(
        table.concat(
            {
                "local process = require('nupp.io.process')",
                "local child = new process.Process({args = {'true'}} as process.Options)",
                "local running = child",
                "print(running.pid)",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "local process = require('nupp.io.process')",
                "local child = nil as process.Process",
                "local input = child.stdin as process.Writer",
                "local output = child.stdout as process.Reader",
                "local function useReader(borrows value: nupp.io.Reader) value:read(1) end",
                "local function useWriter(borrows value: nupp.io.Writer) value:write('x') end",
                "local reader = process.asReader(output)",
                "local writer = process.asWriter(input)",
                "useReader(reader)",
                "useWriter(writer)",
            },
            "\n"
        )
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local process = require('nupp.io.process')",
                        "local child = nil as process.Process",
                        "local output = child.stdout as process.Reader",
                        "local leaked: nupp.io.Reader? = nil",
                        "leaked = process.asReader(output)",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:5 NUPP2608:5",
        "a view cannot escape its borrowed process stream"
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local process = require('nupp.io.process')",
                        "local impossible: process.ReaderView = nil as any",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2101:2",
        "the view constructor is not part of the public surface"
    )
end

function M.processSurfaceIsBundledOutsideThisCheckout()
    local isolated = envMod.new(os.tmpname() .. "-nupp-process-surface")
    local source = table.concat(
        {
            "local process = require('nupp.io.process')",
            "local child = new process.Process({args = {'true'}} as process.Options)",
            "assert(child:isRunning() or not child:isRunning())",
        },
        "\n"
    )
    local result = parser.parse(source, "outside.g.nupp")
    assertEq(#result.errors, 0, "the external consumer parses")
    local diags = check.check(result, "outside.g.nupp", isolated)
    assertEq(#diags, 0, "the shipped process source supplies its typed surface")
end

function M.randomSurfaceIsBundledOutsideThisCheckout()
    local isolated = envMod.new(os.tmpname() .. "-nupp-random-surface")
    local source = table.concat(
        {
            "local random = require('nupp.random')",
            "local generator = random.newRandom(12345)",
            "assert(generator:next() >= 0)",
        },
        "\n"
    )
    local result = parser.parse(source, "outside.g.nupp")
    assertEq(#result.errors, 0, "the external consumer parses")
    local diags = check.check(result, "outside.g.nupp", isolated)
    assertEq(#diags, 0, "the shipped random source supplies its typed surface")
end

function M.digestAndMacSurfacesAreBundledOutsideThisCheckout()
    local isolated = envMod.new(os.tmpname() .. "-nupp-streaming-hash-surface")
    local source = table.concat(
        {
            "local digest = require('nupp.digest')",
            "local mac = require('nupp.mac')",
            "local rolling = digest.create('sha256')",
            "rolling:update('message')",
            "assert(#rolling:digest() == 32)",
            "assert(#mac.hexDigest('hmac-sha256', 'key', 'message') == 64)",
        },
        "\n"
    )
    local result = parser.parse(source, "outside.g.nupp")
    assertEq(#result.errors, 0, "the external consumer parses")
    local diags = check.check(result, "outside.g.nupp", isolated)
    assertEq(#diags, 0, "the shipped streaming hash source supplies its typed surface")
end

function M.optimizedDeadCodeDropsItsNativeFeatures()
    local source = table.concat(
        {"if false then", "    print(nupp.system.availableParallelism())", "else", "    print(nupp.uuid.v4())", "end",},
        "\n"
    )
    local result = parser.parse(source, "dead-native-feature")
    check.check(result, "dead-native-feature", sharedEnv)
    assert(result.effects["runtime.system"] and result.effects["runtime.uuid"], "checking sees both source-level uses")
    optimize.run(result, {level = 1})
    local live = optimize.liveEffects(result)
    assert(not live["runtime.system"], "a folded-away branch loses its provider")
    assert(live["runtime.uuid"], "the selected branch retains its provider")
end

function M.generatedBootstrapFollowsWhatCodegenEmits()
    local source = table.concat(
        {"if false then", "    print(nupp.system.availableParallelism())", "else", "    print(nupp.uuid.v4())", "end",},
        "\n"
    )
    local result = parser.parse(source, "generated-runtime-features")
    assertEq(#result.errors, 0, "generated-runtime-features source parses")
    check.check(result, "generated-runtime-features", sharedEnv)
    assert(
        result.effects["runtime.system"] and result.effects["runtime.uuid"],
        "checking retains the complete source-level feature inventory"
    )
    optimize.run(result, {level = 1})

    local code, diagnostics, _, emitted = gen.generate(result, "generated-runtime-features")
    assertEq(#diagnostics, 0, "the optimized feature fragment generates")
    assert(
        not emitted["runtime.system"] and emitted["runtime.uuid"],
        "generation reports only features whose consumers it wrote"
    )
    assert(not code:find("availableParallelism", 1, true), "the dead system branch loses its member access")
    assert(code:find("v4", 1, true), "the live UUID branch keeps its member access")
end

function M.compilerProvidedPureLibraries()
    local bootstrap = stdlib.bootstrap({["stdlib.math"] = true,})
    local previous = rawget(_G, "nupp")
    _G.nupp = nil
    local chunk = assert(
        loadstring(
            bootstrap
            .. [[
      local io = require("nupp.io")
      local buffer = io.newBuffer("hello")
      local writer = buffer:newWriter()
      assert(writer:write("world"))
      assert(buffer:getString() == "world")
      local viewReader = buffer:view():newReader()
      assert(not pcall(function() viewReader:read(0) end))
      assert(viewReader:read(1) == "w")
      local reader = buffer:newReader()
      assert(reader:read(3) == "wor")
      assert(reader:read(8) == "ld")
      assert(reader:read(1) == "")
      assert(not pcall(function() reader:read(0) end))
      local x, y = nupp.math.vec2.normalize(3, 4)
      assert(math.abs(x - 0.6) < 0.000001 and math.abs(y - 0.8) < 0.000001)
      assert(nupp.math.lerp(10, 20, 0) == 10)
      assert(nupp.math.lerp(10, 20, 0.25) == 12.5)
      assert(nupp.math.lerp(10, 20, 1) == 20)
      assert(nupp.math.lerp(10, 20, 1.5) == 25)
      local hash = require("nupp.hash")
      local checksum = require("nupp.checksum")
      local digest = require("nupp.digest")
      local uuid = require("nupp.uuid")
      assert(hash.fnv1a64("hello") == "a430d84680aabd0b")
      assert(checksum.value("crc32-ieee", "123456789") == 3421780262ULL)
      assert(digest.hexDigest("sha256", "abc") ==
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
      local uuid4 = uuid.v4()
      local uuid7 = uuid.v7()
      assert(uuid4:match("^[0-9a-f]+%-[0-9a-f]+%-4[0-9a-f]+%-[89ab][0-9a-f]+%-[0-9a-f]+$")
         and #uuid4 == 36)
      assert(uuid7:match("^[0-9a-f]+%-[0-9a-f]+%-7[0-9a-f]+%-[89ab][0-9a-f]+%-[0-9a-f]+$")
         and #uuid7 == 36)
   ]]
        )
    )
    local ok, problem = pcall(chunk)
    _G.nupp = previous
    assert(ok, problem)
end

function M.bitsetsReachTheCheckedModule()
    local chunk = assert(
        loadstring(
            [[
      local data = require("nupp.bitset")
      local function bitset(bits) return data.Bitset.__nuppCtor1(bits) end
      local set = bitset(64)
      assert(set:count() == 0)
      set:set(5)
      set:setRange(40, 70)
      assert(set:count() == 32)
      assert(set:get(5) and set:get(70) and not set:get(71))

      local other = bitset(64)
      other:setRange(0, 50)
      set:andWith(other)
      assert(set:count() == 12)
      assert(set:nextSetBit(0) == 5)

      local ffi = require("ffi")
      local target = ffi.new("int32_t[?]", 4)
      local written, resume = set:positionsInto(target, 4, 0)
      assert(written == 4, "positionsInto filled the destination")
      assert(target[0] == 5, "first position")
      assert(resume == 43, "and reported where to carry on")

      assert(data.WORD_BITS == 32)
      assert(set:wordAt(0) == 32)
      assert(bitset(8) ~= bitset(8))
   ]]
        )
    )
    local ok, problem = pcall(chunk)
    assert(ok, problem)
end

function M.openFilesAreOwnersOverTheSharedReaderContract()
    local gen = require("nupp.compiler.gen")

    assertClean(
        table.concat(
            {
                "const files = require('nupp.io.files')",
                "do",
                "    local file = files.open('input.txt') as nupp.io.files.File",
                "    local reader = file:newReader()",
                "    local writer = file:newWriter()",
                "    local bytes: string? = reader:read(16)",
                "    local wrote: boolean = writer:write('x')",
                "end",
            },
            "\n"
        )
    )

    assertClean(
        table.concat(
            {
                "local buffer = nupp.io.newBuffer()",
                "local reader = nupp.io.newStringReader('abc')",
                "local moved: integer? = reader:readInto(buffer)",
                "local info = nupp.io.files.info('x')",
                "local size: integer? = info and info.size",
            },
            "\n"
        )
    )

    assertEq((diagsOf("local n: number = nupp.io.files.read('x')")), "NUPP2001:1")
    assertClean("local paths: {string} = assert(nupp.io.files.glob('src/**/*.nupp'))")
    assertEq((diagsOf("nupp.io.files.info(42)")), "NUPP2006:1")
    assertEq((diagsOf("nupp.io.files.open('x')")), "NUPP2605:1")
    assertEq((diagsOf("nupp.io.files.createTemporaryFile()")), "NUPP2605:1")

    local source = table.concat(
        {"local file = nupp.io.files.open('input.txt') as nupp.io.files.File", "print(file)",},
        "\n"
    )
    local parsed = parser.parse(source, "owned.g.nupp")
    assertEq(#parsed.errors, 0, "syntax errors in the ownership fragment")
    sharedEnv.loaded = {}
    check.check(parsed, "owned.g.nupp", sharedEnv)
    local code = gen.generate(parsed, "owned")
    assert(
        code:find("nupp.io.files#destroyOwner", 1, true),
        "an open file is dropped at the end of its scope, through its module's terminal"
    )
end

function M.luaFilesAndPublicResourcesUseAffineConstructors()
    assertEq((diagsOf("io.open('input.txt')")), "NUPP2605:1")
    assertEq((diagsOf("io.popen('true')")), "NUPP2605:1")
    assertEq((diagsOf("io.tmpfile()")), "NUPP2605:1")
    assertClean(
        table.concat(
            {
                "do",
                "    local file = assert(io.open('input.txt'))",
                "    local text: string? = file:read('*a')",
                "end",
            },
            "\n"
        )
    )

    local source = "do\n    local file = assert(io.open('input.txt'))\nend"
    local parsed = parser.parse(source, "lua-file-owner.g.nupp")
    assertEq(#parsed.errors, 0, "syntax errors in the Lua file ownership fragment")
    sharedEnv.loaded = {}
    check.check(parsed, "lua-file-owner.g.nupp", sharedEnv)
    local code = gen.generate(parsed, "lua-file-owner")
    assert(code:find("__nuppCloseFile", 1, true), "a Lua file is closed automatically at the end of its scope")

    assertClean(
        table.concat(
            {
                "const http = require('nupp.io.http')",
                "const io = require('nupp.io')",
                "const uri = require('nupp.io.uri')",
                "const process = require('nupp.io.process')",
                "do local client = http.client() end",
                "do",
                "    local request = new http.Request(",
                "        url = assert(uri.newURI('https://example.com')),",
                "        body = http.reader(io.newStringReader('body'), 4, nil)",
                "    )",
                "end",
                "do local child = new process.Process({args = {'true'}} as process.Options) end",
            },
            "\n"
        )
    )
    assertEq((diagsOf(table.concat({"const http = require('nupp.io.http')", "http.newClient()",}, "\n"))), "NUPP2004:2")
    assertEq(
        (
            diagsOf(
                table.concat({"const process = require('nupp.io.process')", "process.new({args = {'true'}})",}, "\n")
            )
        ),
        "NUPP2004:2"
    )

    assertClean(
        table.concat(
            {
                "const path = require('nupp.io.path')",
                "local source: path.Path = path.newPath('src', 'main.nupp')",
                "print(source)",
            },
            "\n"
        )
    )
    assertEq(
        (diagsOf(table.concat({"const path = require('nupp.io.path')", "local value = new path.Path()",}, "\n"))),
        "NUPP2209:2"
    )

    local path = require("nupp.io.path")
    local first = path.newPath("cache", "first")
    assert(rawequal(first, path.newPath("cache", "first")), "path.newPath interns equal path text")
    assert(path.Path.__nuppCtor1 == nil, "Path exposes no generated constructor")
    for index = 1, 1024 do
        path.newPath("cache", tostring(index))
    end
    assert(
        not rawequal(first, path.newPath("cache", "first")),
        "path.newPath evicts the least recently used path after 1024 entries"
    )

    assertClean(
        table.concat(
            {
                "const uri = require('nupp.io.uri')",
                "local endpoint: uri.URI = assert(uri.newURI('https://example.com/api'))",
                "print(endpoint)",
            },
            "\n"
        )
    )
    assertEq(
        (diagsOf(table.concat({"const uri = require('nupp.io.uri')", "local value = new uri.URI()",}, "\n"))),
        "NUPP2209:2"
    )

    local uri = require("nupp.io.uri")
    local firstURI = assert(uri.newURI("https://example.com/cache/first"))
    assert(
        rawequal(firstURI, assert(uri.newURI("https://example.com/cache/first"))),
        "uri.newURI interns equal normalized URI text"
    )
    assert(uri.URI.__nuppCtor1 == nil, "URI exposes no generated constructor")
    local base = assert(uri.newURI("https://example.com/base"))
    assert(
        rawequal(base:withPath("/derived"), assert(uri.newURI("https://example.com/derived"))),
        "URI-producing operations share the uri.newURI cache"
    )
    for index = 1, 1024 do
        assert(uri.newURI("https://example.com/cache/" .. tostring(index)))
    end
    assert(
        not rawequal(firstURI, assert(uri.newURI("https://example.com/cache/first"))),
        "uri.newURI evicts the least recently used URI after 1024 entries"
    )
end

function M.bufferAppendsInAmortizedConstantTime()
    local chunk = assert(
        loadstring(
            [[
      local io = require("nupp.io")
      local buffer = io.newBuffer()
      local writer = buffer:newWriter()
      local piece = string.rep("x", 64)
      for _ = 1, 100000 do assert(writer:write(piece)) end
      assert(buffer:length() == 6400000, "every write landed")
      assert(buffer:capacity() >= buffer:length(), "capacity covers the length")
      assert(buffer:getString(6399936, 64) == piece, "the last write is intact")
      buffer:clear()
      assert(buffer:length() == 0 and buffer:capacity() >= 6400000,
         "clearing keeps the reserved bytes")
      buffer:setString("tail", 6)
      assert(buffer:getString() == string.char(0):rep(6) .. "tail",
         "a gap past the length reads as zeros, not as stale bytes")
   ]]
        )
    )
    local ok, problem = pcall(chunk)
    assert(ok, problem)
end

function M.theUtf8ModuleNeedsNoNativeModule()
    local loadedRock = package.loaded["lua-utf8"]
    local loadedModule = package.loaded["nupp.text.utf8"]
    package.loaded["lua-utf8"] = nil
    package.loaded["nupp.text.utf8"] = nil
    local ok, problem = pcall(function()
        local utf8 = require("nupp.text.utf8")
        assert(package.loaded["lua-utf8"] == nil, "requiring the module opened no rock")
        assert(utf8.length("A\226\130\172") == 2)
        assert(utf8.isValid("A\226\130\172"))
        assert(not utf8.isValid("\255"))
        assert(utf8.encode(8364) == "\226\130\172")
        local codepoint, nextAt = utf8.decodeAt("A\226\130\172", 2)
        assert(codepoint == 8364 and nextAt == 5, "decodes the second codepoint")
        assert(utf8.truncate("A\226\130\172", 3) == "A", "never cuts through a codepoint")
    end)
    package.loaded["lua-utf8"] = package.loaded["lua-utf8"] or loadedRock
    package.loaded["nupp.text.utf8"] = package.loaded["nupp.text.utf8"] or loadedModule
    assert(ok, problem)
end

function M.theJsonModuleLoadsItsNuppProviderOnRequire()
    local loadedProvider = package.loaded[JSON_PROVIDER]
    local loadedModule = package.loaded["nupp.codec.json"]
    package.loaded[JSON_PROVIDER] = nil
    package.loaded["nupp.codec.json"] = nil
    local ok, problem = pcall(function()
        local json = require("nupp.codec.json")
        assert(package.loaded[JSON_PROVIDER] ~= nil, "requiring the module loaded the provider contract")
        assert(json.encode({answer = 42}):find('"answer":42', 1, true))
        assert(json.encode(json.EMPTY_ARRAY) == "[]")
        assert(json.encode(json.EMPTY_OBJECT) == "{}")
        assert(json.encode(json.asArray({})) == "[]")
        assert(json.decode("[1,null,2]")[2] == 2)
        assert(json.decode("null", json.NULL) == json.NULL)
        local buffer = require("string.buffer").new()
        local name = json.encodedString('quoted"key')
        assert(name == json.encodedString('quoted"key'), "encoded keys are interned")
        local writer = json.writer(buffer)
        writer:startObject():key(name):write(json.verified("4.20e1")):endObject()
        writer:close()
        assert(buffer:tostring() == [[{"quoted\"key":4.20e1}]])

        local partial = require("string.buffer").new()
        local streaming = json.writer(partial)
        streaming:startArray():write(1)
        streaming:flush()
        assert(partial:tostring() == "[1", "flush publishes an incomplete batch")
        streaming:write(json.verified("2")):endArray()
        streaming:close()
        assert(partial:tostring() == "[1,2]", "close publishes the completed root")
        assert(not pcall(streaming.write, streaming, 3), "a closed writer stays stale")

        local incomplete = json.writer(require("string.buffer").new())
        incomplete:startObject()
        assert(not pcall(incomplete.close, incomplete), "close rejects an incomplete root")
        assert(not pcall(incomplete.endObject, incomplete), "a failed consuming close still leaves a terminal writer")

        local replacement = json.writer(require("string.buffer").new())
        replacement:write(true)
        replacement:close()
        assert(not pcall(streaming.write, streaming, false), "a stale identity cannot reach pooled backing state")
        local invalid = '"\255"'
        assert(
            not pcall(function()
                json.verifiedString(invalid)
            end),
            "a verified key must contain valid UTF-8"
        )
        assert(
            not pcall(function()
                json.verifiedString("42")
            end),
            "a verified key must be a JSON string"
        )
    end)
    package.loaded[JSON_PROVIDER] = package.loaded[JSON_PROVIDER] or loadedProvider
    package.loaded["nupp.codec.json"] = package.loaded["nupp.codec.json"] or loadedModule
    assert(ok, problem)
end

function M.utf8EncodingCoversEveryBoundary()
    local utf8 = require("nupp.text.utf8")
    local boundaries = {
        {0, "\0"},
        {1, "\1"},
        {0x7F, "\127"},
        {0x80, "\194\128"},
        {0x7FF, "\223\191"},
        {0x800, "\224\160\128"},
        {0xD7FF, "\237\159\191"},
        {0xD800, "\237\160\128"}, -- a surrogate half encodes; `isValid` refuses it
        {0xDFFF, "\237\191\191"},
        {0xE000, "\238\128\128"},
        {0xFFFF, "\239\191\191"},
        {0x10000, "\240\144\128\128"},
        {0x10FFFF, "\244\143\191\191"},
        {0x24, "$"},
        {0xA2, "\194\162"},
        {0x20AC, "\226\130\172"},
        {0x1F600, "\240\159\152\128"},
    }
    for _, case in ipairs(boundaries) do
        assertEq(utf8.encode(case[1]), case[2], ("the encoding of U+%04X"):format(case[1]))
    end
    assertEq(utf8.isValid(utf8.encode(0xD800)), false, "an encoded surrogate half is not valid UTF-8")
    assertEq(utf8.decodeAt(utf8.encode(0x1F600), 1), 0x1F600, "a four-byte scalar decodes back")
    for _, outside in ipairs({-1, 0x110000, 0.5}) do
        assert(not pcall(utf8.encode, outside), tostring(outside) .. " is not a codepoint")
    end
end

local UTF8_SHAPES = {
    {"A", true},
    {"caf\xc3\xa9", true, "a two-byte scalar"},
    {"\xe2\x82\xac", true, "a three-byte scalar"},
    {"\xf0\x9f\x8d\xb0", true, "a four-byte scalar"},
    {"\xed\x9f\xbf", true, "the scalar just below the surrogates"},
    {"\xee\x80\x80", true, "the scalar just above the surrogates"},
    {"\xf4\x8f\xbf\xbf", true, "the highest scalar"},
    {"say \"\xe2\x82\xac\"\n", true, "escapes beside a scalar", '"say \\"\xe2\x82\xac\\"\\n"'},
    {"\x80", false, "a continuation byte alone"},
    {"\xbf", false, "the last continuation byte alone"},
    {"\xc0\xaf", false, "an overlong two-byte solidus"},
    {"\xc1\xbf", false, "the last overlong two-byte form"},
    {"\xc3", false, "a two-byte sequence the string ends inside"},
    {"\xc3(", false, "a two-byte sequence whose second byte is not a continuation"},
    {"\xe0\x80\xaf", false, "an overlong three-byte solidus"},
    {"\xed\xa0\x80", false, "a high surrogate half"},
    {"\xed\xbf\xbf", false, "a low surrogate half"},
    {"\xe2\x82", false, "a three-byte sequence the string ends inside"},
    {"\xe2\x28\xac", false, "a three-byte sequence whose second byte is not a continuation"},
    {"\xf0\x80\x80\xaf", false, "an overlong four-byte solidus"},
    {"\xf4\x90\x80\x80", false, "the first scalar past the maximum"},
    {"\xf5\x80\x80\x80", false, "a lead byte no scalar starts with"},
    {"\xf0\x9f\x8d", false, "a four-byte sequence the string ends inside"},
    {"\xff", false, "a byte UTF-8 never uses"},
}

function M.jsonEncodingRefusesEveryMalformedUtf8Shape()
    local json = require("nupp.codec.json.aot")
    for _, case in ipairs(UTF8_SHAPES) do
        local value, valid = case[1], case[2]
        local what = case[3] or ("%q"):format(value)
        local ok, result = pcall(json.encode, value)
        assertEq(ok, valid, "encoding " .. what)
        if valid then
            assertEq(result, case[4] or ('"' .. value .. '"'), "the encoding of " .. what)
        else
            assert(tostring(result):find("invalid UTF-8", 1, true), "a refusal says what was wrong with " .. what)
        end
        -- The same bytes as an object key take the same route as a value.
        assertEq(pcall(json.encode, {[value] = 1}), valid, "encoding " .. what .. " as a key")
    end
end

function M.utf8ValidationCoversEveryShape()
    local utf8 = require("nupp.text.utf8")
    for _, case in ipairs(UTF8_SHAPES) do
        local value, valid = case[1], case[2]
        local what = case[3] or ("%q"):format(value)
        assertEq(utf8.isValid(value), valid, "validating " .. what)
        -- The longest valid prefix within every budget the value admits.
        for budget = 0, #value do
            local length = utf8.validPrefixLength(value, budget)
            assert(length <= budget, "a prefix of " .. what .. " overran its budget")
            assert(utf8.isValid(value:sub(1, length)), ("prefix %d of %s is not valid"):format(length, what))
            if length < budget then
                assert(
                    not utf8.isValid(value:sub(1, length + 1)),
                    ("prefix %d of %s was not maximal"):format(length, what)
                )
            end
        end
        if valid then
            assertEq(utf8.truncate(value, #value), value, "a whole valid value truncates to itself")
        end
    end
end

function M.nativeProvidersOpenOnlyWhenTheirModuleLoads()
    local bootstrap = stdlib.bootstrap({["native.path"] = true})
    assert(not bootstrap:find("__nuppIO", 1, true), "the bootstrap no longer reserves an io namespace")
    assert(not bootstrap:find("nuppPathJoin", 1, true), "the path ABI belongs to the module that calls it")

    local loadedFFI = package.loaded.ffi
    local loadedPath = package.loaded["nupp.io.pathimpl"]
    package.loaded["nupp.io.pathimpl"] = nil
    local chunk = assert(loadstring(bootstrap .. " return package.loaded.ffi"))
    assertEq(chunk(), loadedFFI, "installing the bootstrap opens no provider")
    package.loaded["nupp.io.pathimpl"] = loadedPath
end

function M.theBootstrapCarriesNoNativeAbi()
    local abi = {
        "nuppUuid4",
        "nuppSha256",
        "nuppPathJoin",
        "nuppUriParse",
        "NuppFileInfo",
        "nuppBytesData",
        "nuppProcessSpawnBegin",
        "nuppHttpClientCreate",
        "typedef struct NuppUri NuppUri",
    }
    for _, feature in ipairs({
        "native.uuid",
        "native.sha256",
        "native.path",
        "native.uri",
        "native.files",
        "native.process",
        "native.http",
    }) do
        local installed = stdlib.bootstrap({[feature] = true})
        for _, absent in ipairs(abi) do
            assert(
                not installed:find(absent, 1, true),
                feature .. " leaves " .. absent .. " to the module that calls it"
            )
        end
    end
end

function M.pureAndNativeRuntimeFeaturesComposeAsLua()
    local bootstrap = stdlib.bootstrap({["stdlib.peg"] = true, ["native.path"] = true,})
    assert(not bootstrap:find(";;", 1, true), "adjacent runtime installers do not emit an empty Lua statement")
    local previous = rawget(_G, "nupp")
    _G.nupp = nil
    local chunk = assert(loadstring(bootstrap .. " return type(nupp.peg), next(nupp.peg), rawget(nupp, 'io')"))
    local pegType, pegField, io = chunk()
    _G.nupp = previous
    assertEq(pegType, "table", "the pure PEG runtime is installed")
    assertEq(pegField, nil, "internal PEG helpers are not public fields")
    assertEq(io, nil, "selecting a native facility installs no ambient io namespace")
end

function M.lpegAndReUseTheNativeRuntime()
    local previousNupp = rawget(_G, "nupp")
    local previousLoaded = package.loaded.lpeg
    local previousPreload = package.preload.lpeg
    local previousReLoaded = package.loaded.re
    local previousRePreload = package.preload.re
    package.loaded.lpeg, package.loaded.re = nil, nil
    package.preload.lpeg, package.preload.re = nil, nil
    _G.nupp = nil
    local source = stdlib.bootstrap({
        ["stdlib.lpeg.re"] = true
    })
        .. [=[
local lpeg = require("lpeg")
local P, R, V = lpeg.P, lpeg.R, lpeg.V
local C, Cc, Cp, Ct, Cg, Cb, Cs =
    lpeg.C, lpeg.Cc, lpeg.Cp, lpeg.Ct, lpeg.Cg, lpeg.Cb, lpeg.Cs
local identifier = C((R("az", "AZ") + P("_"))
    * (R("az", "AZ", "09") + P("_"))^0)
local fields = Ct(C(R("09")^1) * (P(",") * C(R("09")^1))^0)
local same = Cg(C(R("az")^1), "word") * P(":") * Cb("word")
local grammar = P({"value", value = P("x") + P("(") * V("value") * P(")")})
local substitution = Cs((C(R("09")^1) / "[%0]" + P(1))^0)
local positions = Ct(Cp() * Cc("tag") * C(P("ok")) * Cp())
local re = require("re")
return identifier:match("name9"), fields:match("1,22,333"),
    same:match("echo:rest"), lpeg.match(grammar * -P(1), "((x))"),
    substitution:match("a12b"), positions:match("ok"), lpeg.version,
    re.match("item:42", "{[a-z]+} ':' {[0-9]+} !.")
]=]
    local identifier, fields, same, recursive, substitution, positions, version, reFirst, reSecond = assert(
        loadstring(source)
    )()
    package.loaded.lpeg = previousLoaded
    package.preload.lpeg = previousPreload
    package.loaded.re = previousReLoaded
    package.preload.re = previousRePreload
    _G.nupp = previousNupp
    assertEq(identifier, "name9", "LPeg facade substring capture")
    assertEq(fields[3], "333", "LPeg facade table capture")
    assertEq(same, "echo", "LPeg facade back capture")
    assertEq(recursive, 6, "LPeg facade recursive grammar")
    assertEq(substitution, "a[12]b", "LPeg facade substitution")
    assertEq(positions[1], 1, "LPeg facade first position")
    assertEq(positions[4], 3, "LPeg facade final position")
    assertEq(version, "LPeg 1.1.0", "LPeg facade version field")
    assertEq(reFirst, "item", "bundled re first capture")
    assertEq(reSecond, "42", "bundled re second capture")
end

function M.nativeFeatureOverridesAreTriState()
    local automatic = {["native.tls"] = true, ["native.json"] = true}
    local resolved = native.resolve(automatic, {tls = false, path = true})
    assert(not resolved["native.tls"], "false removes a detected feature")
    assert(resolved["native.json"], "an absent override remains automatic")
    assert(resolved["runtime.path"], "true adds an undetected feature")

    local external = native.sourceEffects("local lpeg = require('lpeg')", "rock.lua", sharedEnv)
    assert(external["native.lpeg"], "bundled Lua contributes native LPeg")
end

function M.selectOverloadsSeparateCountFromPackSelection()
    assertClean(
        table.concat(
            {
                "local count: integer = select('#', 1, 'two', true)",
                "local text, flag = select(2, 1, 'two', true)",
                "local s: string = text",
                "local b: boolean = flag",
            },
            "\n"
        )
    )
    assertEq((diagsOf("select('bad', 1, 2)")), "NUPP2125:1")

    assertEq(select("#", 1, "two", true), 3, "the count overload matches LuaJIT")
    local text, flag = select(2, 1, "two", true)
    assertEq(text, "two", "the numeric overload starts at its index")
    assertEq(flag, true, "and preserves the rest of the pack")
    assertEq(pcall(select, "bad", 1, 2), false, "the rejected selector also fails in LuaJIT")
end

function M.collectgarbageOverloadsTrackResultKinds()
    assertClean(
        table.concat(
            {
                "local collected: number = collectgarbage()",
                "local size: number = collectgarbage('count')",
                "local oldPause: number = collectgarbage('setpause', 200)",
                "local stepped: boolean = collectgarbage('step', 0)",
                "local running: boolean = collectgarbage('isrunning')",
            },
            "\n"
        )
    )
    assertEq((diagsOf("collectgarbage('unknown')")), "NUPP2125:1")

    assertEq(type(collectgarbage()), "number", "the default collection reports a number")
    assertEq(type(collectgarbage("count")), "number", "count reports a number")
    assertEq(type(collectgarbage("step", 0)), "boolean", "step reports a boolean")
    assertEq(type(collectgarbage("isrunning")), "boolean", "isrunning reports a boolean")
    assertEq(pcall(collectgarbage, "unknown"), false, "the rejected operation also fails in LuaJIT")
end

function M.pairsTyping()
    assertClean(
        table.concat(
            {
                "local m: {[string]: number} = {}",
                "for k, v in pairs(m) do",
                "   local s: string = k",
                "   local n: number = v",
                "end",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "local list: {string} = {}",
                "for i, s in ipairs(list) do",
                "   local n: integer = i",
                "   local t: string = s",
                "end",
            },
            "\n"
        )
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local m: {[string]: number} = {}", "for k, v in pairs(m) do", "   local n: number = k", "end",},
                    "\n"
                )
            )
        ),
        "NUPP2001:3"
    )
end

function M.tableLibrary()
    assertClean("local t: {number} = {}\ntable.insert(t, 5)")
    assertClean("local s: string = table.concat({'a', 'b'}, ',')")
    assertClean("local t = table.new(16, 0)")
    assertClean("local t = table.new(16, 0)\ntable.clear(t)")
    assertEq((diagsOf("table.clear = function() end")), "NUPP2009:1")
end

function M.stringBufferModule()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local b = buffer.new()",
                "b:put('a', 1):put('b')",
                "local s: string = b:tostring()",
                "local joined: string = b .. 'x'",
                "local size: integer = #b",
            },
            "\n"
        )
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local buffer = require('string.buffer')", "local b = buffer.new()", "b:putt('x')",},
                    "\n"
                )
            )
        ),
        "NUPP2004:3"
    )
    assertEq(
        (
            diagsOf(
                table.concat({"local buffer = require('string.buffer')", "local n: number = buffer.encode({})",}, "\n")
            )
        ),
        "NUPP2001:2"
    )
end

function M.stringBufferTypeIsNameable()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local function render(out: buffer.Buffer): buffer.Buffer borrows (out)",
                "   return out:putf('%d', 1)",
                "end",
                "local b = buffer.new(64)",
                "local s: string = render(b):tostring()",
            },
            "\n"
        )
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local buffer = require('string.buffer')",
                        "local b: buffer.Buffer = buffer.new()",
                        "local n: number = b",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:3"
    )
end

function M.stringBufferCoversTheWholeApi()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local b = buffer.new(64, {dict = {'k'}})",
                "b:reset():put('a', 1):putf('%s', 'x'):skip(1)",
                "b:set('abc')",
                "b:encode({1})",
                "local decoded = b:decode()",
                "do",
                "   local ptr, len = b:reserve(8)",
                "end",
                "b:commit(0)",
                "do",
                "   local base, size = b:ref()",
                "   local n: integer = #b",
                "   local all: string = b:tostring()",
                "end",
                "local text: string = b:get(1)",
                "b:free()",
                "local encoded: string = buffer.encode(decoded)",
                "local back = buffer.decode(encoded)",
                "local ffi = require('ffi')",
                "b:putcdata(ffi.new('uint8_t[4]'), 4)",
            },
            "\n"
        )
    )
end

function M.stringBufferBorrowBlocksInvalidation()
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local buffer = require('string.buffer')",
                        "local b = buffer.new()",
                        "local base, size = b:ref()",
                        "b:reset()",
                        "print(size)",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2607:4"
    )
end

function M.stringBufferPointersBecomeCheckedSpans()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local spans = require('nupp.mem.span')",
                "local b = buffer.new()",
                "local available: integer = 0",
                "do",
                "   local ptr, reserved = b:reserve(64)",
                "   available = reserved",
                "   do",
                "      local writable = spans.writeCarray(ptr, reserved as integer)",
                "      writable[1] = 65",
                "      drop writable",
                "   end",
                "end",
                "b:commit(1)",
                "local len: integer = 0",
                "do",
                "   local base, readable = b:ref()",
                "   len = readable",
                "   local view = spans.fromCarray(base, readable as integer)",
                "   local first: integer = view[1]",
                "end",
                "b:skip(len)",
                "local total: integer = available + len",
            },
            "\n"
        )
    )
end

function M.profileSessionProtocolPreservesItsReportType()
    assertClean(
        table.concat(
            {
                "local profile = require('nupp.profile')",
                "local function finish<S is profile.Session>(session: S): S.Report",
                "   return session:stop()",
                "end",
                "local sample: profile.SampleReport = finish(profile.sample())",
                "local trace: profile.TraceReport = finish(profile.trace())",
            },
            "\n"
        )
    )

    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local profile = require('nupp.profile')",
                        "local function finish<S is profile.Session>(session: S): S.Report",
                        "   return session:stop()",
                        "end",
                        "local wrong: profile.TraceReport = finish(profile.sample())",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:5"
    )
end

function M.moduleRequireTyped()
    assertClean(
        table.concat(
            {"local geom = require('fixtures.geom')", "local p = geom.make(1, 2)", "local d: number = geom.dist2(p)",},
            "\n"
        )
    )
    assertEq(
        (diagsOf(table.concat({"local geom = require('fixtures.geom')", "geom.make('a', 2)",}, "\n"))),
        "NUPP2006:2"
    )
    assertEq((diagsOf(table.concat({"local geom = require('fixtures.geom')", "geom.nope()",}, "\n"))), "NUPP2004:2")
end

function M.moduleRequireDeclarationFile()
    assertClean(
        table.concat(
            {
                "local clib = require('fixtures.clib')",
                "local n: number = clib.add(1, 2)",
                "local s: string = clib.greet('hi')",
            },
            "\n"
        )
    )
    assertEq(
        (diagsOf(table.concat({"local clib = require('fixtures.clib')", "clib.add('x', 2)",}, "\n"))),
        "NUPP2006:2"
    )
end

function M.moduleUnresolvedIsAnyUnlessStrict()
    local src = "local value: number = require('no.such.module')"
    assertClean(src)
    assertEq((diagsOf(src, {strict = true})), "NUPP2001:1")
    assertClean("local value = require('no.such.module') as number", {strict = true})
end

function M.publicResourceAliasesKeepConstructionAndPrivacy()
    assertClean(
        [[const http = require("nupp.io.http")
const uri = require("nupp.io.uri")
local request = new http.Request(url = assert(uri.newURI("https://example.com/")))
request:close()
]]
    )
    local diagnostics = diagsOf(
        [[const gpu = require("nupp.gpu")
local function expose(borrows context: gpu.Context): nil
    local hook = context.compileGenerated
end
]]
    )
    assert(
        diagnostics:find("NUPP2004", 1, true),
        "generated GPU hooks must be inaccessible to application source: " .. diagnostics
    )
    diagnostics = diagsOf(
        [[const process = require("nupp.io.process")
local function expose(borrows child: process.Process): nil
    local handle = child.handle
end
]]
    )
    assert(diagnostics:find("NUPP2209", 1, true), "process handles must be inaccessible to application source")
end

function M.applicationResourcesHideLifecycleAndTransportMachinery()
    for _, example in ipairs({
        {"nupp.io.process", "Reader", "release"},
        {"nupp.io.process", "Writer", "release"},
        {"nupp.io.http", "Body", "release"},
        {"nupp.io.http", "Body", "_transfer"},
        {"nupp.io.http", "Response", "_packed"},
        {"nupp.io.http", "Client", "_native"},
        {"nupp.io.http", "Client", "_retainSource"},
        {"nupp.gpu", "Buffer<uint32>", "_handle"},
        {"nupp.gpu", "Shared<uint32>", "_values"},
        {"nupp.gpu", "Phases", "_size"},
        {"nupp.workers", "Scope", "_scheduler"},
        {"nupp.workers", "Scope", "_cancelAll"},
    }) do
        local diagnostics = diagsOf(
            (
                'const api = require(%q)\nlocal function expose(borrows value: api.%s): nil\nlocal hidden = value.%s\nend\n'
            ):format(example[1], example[2], example[3])
        )
        assert(
            diagnostics:find(
                "NUPP2209",
                1,
                true
            ) or diagnostics:find("NUPP2004", 1, true) or diagnostics:find("NUPP2006", 1, true),
            table.concat(example, ".") .. " must be inaccessible: " .. diagnostics
        )
    end
end

function M.tensorLayoutAlgebraDoesNotSelectAGpu()
    assertClean("local layout = require('nupp.gpu.layout')", {dialect = "lua51"})
    assertEq(native.forModule("nupp.gpu.layout"), "runtime.gpu_layout", "layout algebra is a portable module")
    local selected = native.expand({["runtime.gpu_layout"] = true})
    assert(not selected["native.gpu"], "layout algebra must not select a device provider")
end

function M.ioFacadeKeepsRichContractsAndPrivateState()
    assertClean(
        [[const io = require("nupp.io")
local function copy(borrows source: io.Reader, exclusive target: io.Buffer): nil
    source:readInto(target, 0, 16)
end
local function write(exclusive target: io.Writer, borrows source: nupp.mem.span.ByteSpan): nil
    target:writeSpan(source)
end
]]
    )
    for _, example in ipairs({{"ScalarReader", "_pending"}, {"ScalarWriter", "_buffer"}}) do
        local diagnostics = diagsOf(
            (
                'const io = require("nupp.io")\nlocal function leak(borrows value: io.%s): nil\nlocal state = value.%s\nend'
            ):format(example[1], example[2])
        )
        assert(
            diagnostics:find("NUPP2004", 1, true),
            "scalar state must not belong to its public contract: " .. diagnostics
        )
    end
    for _, name in ipairs({
        "nupp.io.internal.bytes",
        "nupp.io.internal.scalars",
        "nupp.io.internal.lines",
        "nupp.io.http.internal.transport"
    }) do
        local diagnostics = diagsOf(('local hidden = require(%q)'):format(name))
        assert(diagnostics:find("NUPP2144", 1, true), name .. " must reject application imports: " .. diagnostics)
    end
end

return M
