local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local spi = require("nupp.services")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local environment = envMod.new(HERE .. "/..")
local sequence = 0
local namespace = tostring({})
local M = {}

local function define(default)
    sequence = sequence + 1
    return spi.define("test.service." .. namespace .. "." .. sequence, 1, default)
end

local function fails(body, message)
    local ok, problem = pcall(body)
    assert(not ok, "expected failure: " .. message)
    assert(tostring(problem):find(message, 1, true), tostring(problem))
end

function M.namedProvidersLoadOnceAndKeepTheirIdentity()
    local service = define()
    local calls = 0
    local value = {answer = 42}
    service:register("z", function()
        calls = calls + 1;
        return value
    end)
    service:register("a", function()
        return {answer = 7}
    end)
    assert(table.concat(service:list(), ",") == "a,z")
    assert(calls == 0)
    assert(service:lookup("missing") == nil)
    assert(service:require("z") == value)
    assert(service:lookup("z") == value)
    assert(calls == 1)
end

function M.selectionWinsAndFreezesWhenResolved()
    local defaults = 0
    local service
    service = define(function()
        defaults = defaults + 1
        return service:require("native")
    end)
    service:register("native", function()
        return {answer = 1}
    end)
    service:register("custom", function()
        return {answer = 2}
    end)
    service:select("custom")
    local value = service:require()
    assert(value.answer == 2 and defaults == 0)
    assert(service:require() == value)
    fails(
        function()
            service:select("native")
        end,
        "already resolved"
    )
end

function M.defaultAssemblyRunsOnceAndDoesNotSearchDuringCalls()
    local resolutions = 0
    local service
    service = define(function()
        resolutions = resolutions + 1
        return service:require("portable")
    end)
    service:register("portable", function()
        return {
            add = function(a, b)
                return a + b
            end
        }
    end)
    local module = service:require()
    local lookup = service.lookup
    service.lookup = function()
        error("operation performed an SPI lookup")
    end
    for index = 1, 1000 do
        assert(module.add(index, 3) == index + 3)
    end
    service.lookup = lookup
    assert(resolutions == 1)
end

function M.optionalAbsenceIsFixedForTheLoadedModule()
    local service = define()
    assert(service:lookup() == nil)
    service:register("late", function()
        return {}
    end)
    assert(service:lookup() == nil)
    fails(
        function()
            service:select("late")
        end,
        "already resolved"
    )
end

function M.explicitMissingProviderDoesNotFallBack()
    local service = define(function()
        error("fallback ran")
    end)
    service:select("absent")
    fails(
        function()
            service:require()
        end,
        "/absent"
    )
end

function M.failedLoaderDoesNotPublishAPartialValue()
    local service = define()
    local calls = 0
    service:register("retry", function()
        calls = calls + 1
        if calls == 1 then
            error("initialization failed")
        end

        return {ready = true}
    end)
    fails(
        function()
            service:require("retry")
        end,
        "initialization failed"
    )
    assert(service:require("retry").ready)
    assert(calls == 2)
end

function M.cyclesReportProviderNamesAndReleaseLoadingState()
    local a, b = define(), define()
    a:register("a", function()
        return b:require("b")
    end)
    b:register("b", function()
        return a:require("a")
    end)
    fails(
        function()
            a:require("a")
        end,
        "provider cycle"
    )
    local independent = define()
    independent:register("ok", function()
        return {}
    end)
    assert(independent:require("ok"))
end

function M.duplicateDefinitionsAndNamesAreRejected()
    local service = define()
    service:register("one", function()
        return {}
    end)
    fails(
        function()
            service:register("one", function()
                return {}
            end)
        end,
        "duplicate provider"
    )
    fails(
        function()
            spi.define(service.id, 2)
        end,
        "duplicate contract"
    )
end

function M.assemblyChecksRunBeforePublishingAndCanBeRetried()
    local service = define()
    local value = {valid = false}
    local checks = 0
    service:register("chosen", function()
        return value
    end)
    service:select("chosen")
    local function check(provider)
        checks = checks + 1
        fails(
            function()
                service:select("chosen")
            end,
            "already resolved"
        )
        assert(provider.valid, "incompatible representation")
    end

    fails(
        function()
            service:assemble(
                function()
                    error("default ran")
                end,
                check
            )
        end,
        "incompatible representation"
    )
    value.valid = true
    assert(
        service:assemble(
            function()
                error("default ran")
            end,
            check
        ) == value
    )
    assert(checks == 2)
    assert(service:require() == value)
    assert(checks == 2)
end

function M.defaultCyclesIncludeTheWholeDependencyChain()
    local a, b = define(), define()
    fails(
        function()
            a:assemble(function()
                return b:assemble(function()
                    return a:require()
                end)
            end)
        end,
        "default cycle"
    )
    local value = {}
    a:register("ready", function()
        return value
    end)
    a:select("ready")
    assert(a:require() == value)
end

local function errors(source, selectedEnvironment)
    local result = parser.parse(source, "typed-service.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    local found = {}
    for _, diagnostic in ipairs(check.check(result, "typed-service.nupp", selectedEnvironment or environment)) do
        if diagnostic.severity == "error" then
            found[#found + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
    end

    return table.concat(found, "\n")
end

function M.providerTypeIsInferredFromTheAnnotatedHandle()
    local found = errors(
        [[
local services = require("nupp.services")
local interface Provider
    answer: function(): string
end
const service: services.Service<Provider> = services.define("typed.answer", 1)
service:register("one", function(): Provider
    return {answer = function(): string return "one" end}
end)
const provider: Provider = service:require("one")
const answer: string = provider.answer()
return answer
]]
    )
    assert(found == "", found)
end

function M.handlesAreInvariantAndRejectWrongProviderSignatures()
    local found = errors(
        [[
local services = require("nupp.services")
local interface Provider
    answer: function(): string
end
local interface Other
    answer: function(): number
end
const service: services.Service<Provider> = services.define("typed.answer", 1)
const other: services.Service<Other> = service
service:register("wrong", function(): Other
    return {answer = function(): number return 1 end}
end)
return other
]]
    )
    assert(found:find("NUPP2001", 1, true), found)
    assert(found:find("NUPP2006", 1, true) or found:find("argument", 1, true), found)
end

function M.genericPackContractsCompareByTheirParameterPositions()
    local accepted = errors(
        [[
local type Expected = function<A..., R...>(body: function(A...): R...): thread
local function create<Inputs..., Outputs...>(body: function(Inputs...): Outputs...): thread
    return coroutine.create(body)
end
const implementation: Expected = create
return implementation
]]
    )
    assert(accepted == "", accepted)
    local rejected = errors(
        [[
local type Expected = function<A..., R...>(body: function(A...): R...): thread
local value: function<A..., R...>(body: function(R...): A...): thread
const implementation: Expected = value
return implementation
]]
    )
    assert(rejected:find("NUPP2001", 1, true), rejected)
end

function M.genericProviderCtypesRetainTheirBinderIdentity()
    local accepted = errors(
        [[
local type Expected = function<T>(element: ctype<T>): string
local function cast<U>(element: ctype<U>): string return "ok" end
const implementation: Expected = cast
return implementation
]]
    )
    assert(accepted == "", accepted)
    local rejected = errors(
        [[
local type Expected = function<T>(element: ctype<T>): string
local function cast<U>(element: ctype<uint32>): string return "ok" end
const implementation: Expected = cast
return implementation
]]
    )
    assert(rejected:find("NUPP2001", 1, true), rejected)
end

function M.runtimeValidationUsesRequiredAndOptionalContractMembers()
    sequence = sequence + 1
    local service = spi.define("test.shape." .. namespace .. sequence, 1, nil, {
        {name = "call", kinds = {"func"}},
        {name = "optional", kinds = {"func", "nil"}},
    })
    service:register("bad", function()
        return {call = 4}
    end)
    service:register("badOptional", function()
        return {
            call = function()
            end,
            optional = false
        }
    end)
    service:register("valid", function()
        return {
            call = function()
                return 9
            end,
            extra = true
        }
    end)
    fails(
        function()
            service:require("bad")
        end,
        ".call has type number"
    )
    fails(
        function()
            service:require("badOptional")
        end,
        ".optional has type boolean"
    )
    assert(service:require("valid").call() == 9)
end

function M.httpResponseBodiesRetainOwnedIoSignatures()
    local found = errors(
        [[
local contracts = require("nupp.runtime.services.http")
local io = require("nupp.io")
local function copy(borrows response: contracts.Response): nil
local destination = io.newBuffer()
response.body:readInto(destination, 0, 8)
local lease = destination:reserveWrite(0, 8)
local output = lease:span()
response.body:readSpan(output)
drop output
lease:commit(8)
local writer = destination:newWriter()
response.body:transferTo(writer)
writer:close()
end
return true
]]
    )
    assert(found == "", found)
end

function M.bundledContractsRetainGenericHandlesAndSharedTypes()
    local bundled = envMod.new(os.tmpname(), {cache = false})
    local found = errors(
        [[
const services = require("nupp.services")
const contracts = require("nupp.runtime.services.contracts")
const handle: services.Service<contracts.JsonProvider> = contracts.json
const provider: contracts.JsonProvider = handle:require()
const value = {answer = "yes"}
const marked: {answer: string} = provider.asArray(value)
const answer: string = marked.answer
const uri: contracts.UriParts? = nil
return answer, uri
]],
        bundled
    )
    assert(found == "", found)
    local declaration = bundled.bundled["nupp.runtime.services.contracts"]
    assert(declaration and declaration.exports.types.JsonProvider, "bundled provider interface")
    assert(declaration.exports.types.UriParts, "bundled shared nominal type")
end

function M.bundledAliasesShareStagedNominalTypes()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.incremental")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir .. "/src/nupp/text/buffer"))
    assert(fs.writeFile(dir .. "/nupp.lua", 'return {include = {"src"}}'))
    local declaration = assert(require("nupp.compiler.bundled").source("/nupp/text/buffer/types.d.nupp"))
    local typePath = dir .. "/src/nupp/text/buffer/types.d.nupp"
    assert(fs.writeFile(typePath, declaration))
    local main = dir .. "/src/main.g.nupp"
    assert(
        fs.writeFile(
            main,
            [[
local {type Buffer} = require("nupp.text.buffer.types")
local contracts = require("nupp.runtime.services.contracts")
local function writer(exclusive out: nupp.text.buffer.Buffer, nullValue: any?): any
    out:put("value")
    return nil
end
local checked: function(exclusive out: Buffer, nullValue: any?): any = writer
local provider: contracts.JsonProvider = {writer = writer} as any
local canonical: function(exclusive out: Buffer, nullValue: any?): any = provider.writer
return checked, canonical
]]
        )
    )
    local ok, problem = pcall(function()
        local function checked(graph)
            for _, diagnostic in ipairs(graph.checkFile(main).diags) do
                assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
            end
        end

        local graph = incremental.new(dir)
        checked(graph)
        checked(graph)
        graph.persist()
        checked(incremental.new(dir))
        graph.changeDocument(typePath, declaration .. "\n")
        checked(graph)
    end)
    require("nupp.io.files").remove(dir, true)
    assert(ok, problem)
end

function M.providerIdentityAndGenericsSurviveModuleCaches()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.incremental")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    local files = {
        ["nupp.lua"] = 'return {include = {"."}}',
        [
            "contract.nupp"
        ] = [[
module contract
const services = require("nupp.services")
export record Token
    text: string
end
export interface Provider
    make: function(): Token
    mark: function<T is table>(takes value: T): T preserves value
    optional: (function(): string)?
end
export const service: services.Service<Provider> = services.define("example.cache", 1)
]],
        ["provider.d.nupp"] = [[
const contract = require("contract")
local value: contract.Provider
return value
]],
        [
            "assembled.nupp"
        ] = [[
module assembled
local provider = {ready = true, label = "fixture", call = function(): string return "yes" end}
function provider.extra(): number return 1 end
export = provider
]],
        [
            "main.nupp"
        ] = [[
const assembled = require("assembled")
const ready: boolean = assembled.ready
const label: string = assembled.label
const call: nosuspend function(): string = assembled.call
const contract = require("contract")
const provider = require("provider")
contract.service:register("fixture", function(): contract.Provider return provider end)
const selected: contract.Provider = contract.service:require("fixture")
const token: contract.Token = selected.make()
const marked: {text: string} = selected.mark({text = token.text})
return marked.text
]],
    }
    for name, source in pairs(files) do
        assert(fs.writeFile(fs.join(dir, name), source))
    end
    local ok, problem = pcall(function()
        local cold = incremental.new(dir)
        local function checked(graph)
            local result = graph.checkFile(fs.join(dir, "main.nupp"))
            for _, diagnostic in ipairs(result.diags) do
                assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
            end
        end

        checked(cold)
        checked(cold)
        cold.persist()
        local restored = incremental.new(dir)
        checked(restored)
        assert(restored.headerStore.stats.hits >= 2, "serialized module interfaces were read")
        restored.changeDocument(
            fs.join(dir, "main.nupp"),
            files["main.nupp"]:gsub("const token: contract.Token", "const token: string")
        )
        local rejected = restored.checkFile(fs.join(dir, "main.nupp"))
        local found = false
        for _, diagnostic in ipairs(rejected.diags) do
            found = found or diagnostic.code == "NUPP2001"
        end
        assert(found, "restored providers keep their nominal return type")
    end)
    require("nupp.io.files").remove(dir, true)
    if not ok then
        error(problem, 0)
    end
end

function M.catalogDiscoveryFollowsOnlyTheTargetDependencyClosure()
    local fs = require("nupp.compiler.fs")
    local catalogs = require("nupp.compiler.build.services")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    assert(
        fs.writeFile(
            fs.join(dir, "capabilities.json"),
            [[
{"schema":2,"capabilities":[{"kind":"service","service":"example.transitive","name":"fixture","api":1,"contract":"fixture.contract","export":"service","entry":"fixture.provider"}]}
]]
        )
    )
    local ok, problem = pcall(function()
        local config = {
            dependencies = {
                parent = {kind = "types", dependencies = {"child"}},
                child = {kind = "luarocks"},
                tool = {kind = "luarocks"},
            }
        }
        local target = {dependencies = {"parent"}, compileDependencies = {"tool"}}
        local records = {
            child = {typeRoot = dir, usage = "target"},
            ["compile:tool"] = {typeRoot = dir, usage = "compile"},
            ["tool:tool"] = {typeRoot = dir, usage = "tool"},
        }
        local written, why, found, entries = catalogs.write(dir, "out", config, target, records)
        assert(written, why)
        assert(found and #entries == 1)
        assert(entries[1].dependency == "child")
        assert(entries[1].service == "example.transitive")
    end)
    require("nupp.io.files").remove(dir, true)
    assert(ok, problem)
end

function M.catalogCheckingRejectsIdentityAndSignatureConflictsWithoutLoadingCode()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.incremental")
    local catalogs = require("nupp.compiler.build.services")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    assert(fs.writeFile(fs.join(dir, "nupp.lua"), 'return {include = {"."}}'))
    assert(
        fs.writeFile(
            fs.join(dir, "contract.nupp"),
            [[
module contract
const spi = require("nupp.services")
export interface Provider
    answer: function(): string
    release: nosuspend function(): nil
    mark: function<T is table>(takes value: T): T preserves value
end
export const service: spi.Service<Provider> = spi.define("example.codec", 3)
]]
        )
    )
    local providerPath = fs.join(dir, "provider.d.nupp")
    local valid = [[
local value: {
    answer: function(): string,
    release: nosuspend function(): nil,
    mark: function<T is table>(takes value: T): T preserves value,
    extra: integer
}
return value
]]
    assert(fs.writeFile(providerPath, valid))
    local entry = {
        service = "example.codec",
        name = "fixture",
        api = 3,
        contract = "contract",
        export = "service",
        entry = "provider"
    }
    local inc = incremental.new(dir)
    inc.env.roots[#inc.env.roots + 1] = fs.join(dir, "out/generated")
    local session = {
        inc = inc,
        stageBundled = function()
            return nil
        end
    }
    local ok, problem = pcall(function()
        local accepted, why = catalogs.check(session, {entry}, dir, "out")
        assert(accepted, why)
        entry.api = 2
        accepted, why = catalogs.check(session, {entry}, dir, "out")
        assert(not accepted and why:find("identity or API", 1, true), why)
        entry.api = 3
        entry.service = "example.other"
        accepted, why = catalogs.check(session, {entry}, dir, "out")
        assert(not accepted and why:find("identity or API", 1, true), why)
        entry.service = "example.codec"
        for _, invalid in ipairs({
            (valid:gsub("answer: function%(%)%: string", "answer: function(): number")),
            (valid:gsub("release: nosuspend", "release:")),
            (valid:gsub(" preserves value", "")),
        }) do
            inc.changeDocument(providerPath, invalid)
            accepted, why = catalogs.check(session, {entry}, dir, "out")
            assert(not accepted and why:find("NUPP", 1, true), why)
        end
        inc.closeDocument(providerPath)
        assert(fs.writeFile(fs.join(dir, "untyped.lua"), 'error("provider code executed")'))
        inc.diskChanged(fs.join(dir, "untyped.lua"), 1)
        entry.entry = "untyped"
        accepted, why = catalogs.check(session, {entry}, dir, "out")
        assert(not accepted and why:find(".d.nupp", 1, true), why)
    end)
    require("nupp.io.files").remove(dir, true)
    if not ok then
        error(problem, 0)
    end
end

function M.portableBufferMatchesNativeFifoOperations()
    local implementations = {
        require("nupp.runtime.provider.tablebuffer"),
        require("nupp.runtime.provider.nativebuffer"),
    }
    for _, implementation in ipairs(implementations) do
        local value = implementation.new()
        assert(value:put("a", 12) == value)
        assert(value:putf("%02d", 3) == value)
        assert(#value == 5 and value:tostring() == "a1203")
        local first, second = value:get(1, 2)
        assert(first == "a" and second == "12")
        assert(value:skip(1) == value and value:get() == "3")
        assert(value:set("x\0yz") == value)
        assert(value:reset() == value and #value == 0)
        value:put("again")
        assert(value:free() == value and #value == 0)
    end
end

function M.childConfigurationContainsCatalogNamesAndSetupModules()
    local isolated = require("providerstate").services({
        dialect = "luajit",
        providers = {
            {
                service = "test.child",
                api = 1,
                name = "named",
                entry = "never.loaded",
                contract = "test.contract",
                export = "service"
            },
        }
    })
    local service = isolated.define("test.child", 1)
    service:select("named")
    isolated.setupWorkers("test.setup")
    local configuration = isolated.workerConfiguration()
    local setup = assert(configuration:find('require("test.setup")', 1, true))
    local selection = assert(configuration:find('require("test.contract")["service"]:select("named")', 1, true))
    assert(setup < selection, "destination setup precedes catalog selection")
    assert(not configuration:find("never.loaded", 1, true), "provider instances are not loaded or serialized")
    assert(isolated.workerConfiguration() == configuration)
    fails(
        function()
            isolated.setupWorkers("late")
        end,
        "already"
    )
end

function M.runtimeRegistrationsNeedAnExplicitDestinationSetup()
    local isolated = require("providerstate").services()
    local service = isolated.define("test.local", 1)
    service:register("local", function()
        error("loader must not execute")
    end)
    service:select("local")
    fails(
        function()
            isolated.workerConfiguration()
        end,
        "requires an explicit worker setup"
    )
    isolated.setupWorkers("test.setup")
    assert(isolated.workerConfiguration() == 'require("test.setup")')
end

function M.genericMethodsPreserveTheirOwnBindersAndBorrowRelations()
    local accepted = errors(
        [[
local m = {}
interface m.Mapper
    readonly map: function<T>(borrows self: m.Mapper, element: ctype<T>, value: T): T
end
record m.Implementation is m.Mapper
    map: function<U>(borrows self: m.Implementation, element: ctype<U>, value: U): U
end
record m.Range
    anchor: any
    count: integer
end
record m.Owner
    range: function(borrows self: m.Owner): m.Range borrows (self)
end
local function range(borrows self: m.Owner): m.Range borrows (self)
    return new m.Range(anchor = self, count = 1)
end
return new m.Owner(range = range)
]]
    )
    assert(accepted == "", accepted)
    for _, signature in ipairs({
        "function<U>(borrows self: m.Implementation, element: ctype<U>, value: string): U",
        "function<U>(borrows self: m.Implementation, element: ctype<U>, value: U): string",
    }) do
        local rejected = errors(
            (
                [[
local m = {}
interface m.Mapper
    readonly map: function<T>(borrows self: m.Mapper, element: ctype<T>, value: T): T
end
record m.Implementation is m.Mapper
    map: %s
end
return m
]]
            ):format(signature)
        )
        assert(rejected:find("NUPP2118", 1, true), rejected)
    end
    local rejected = errors(
        [[
local m = {}
record m.Range
    anchor: any
    count: integer
end
interface m.Owner
    readonly range: function(borrows self: m.Owner): m.Range borrows (self)
end
record m.Unrooted is m.Owner
    range: function(borrows self: m.Unrooted): m.Range
end
return m
]]
    )
    assert(rejected:find("NUPP2118", 1, true), rejected)
end

return M
