local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local HERE = require("helpers.paths").tests
local environment = envMod.new(HERE .. "/..")
local M = {}

local function errors(source, selectedEnvironment, moduleName)
    local result = parser.parse(source, "typed-interface.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    local found = {}
    for _, diagnostic in ipairs(
        check.check(result, "typed-interface.nupp", selectedEnvironment or environment, {
            moduleName = moduleName
        })
    ) do
        if diagnostic.severity == "error" then
            found[#found + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
    end

    return table.concat(found, "\n")
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

function M.httpResponseBodiesRetainOwnedIoSignatures()
    local found = errors(
        [[
local contracts = require("io.http")
local io = require("io")
local function copy(borrows response: contracts.Response): nil
local destination = io.newbuffer()
response.body:readinto(destination, 0, 8)
local lease = destination:reservewrite(0, 8)
local output = lease:span()
response.body:readspan(output)
own.drop(output)
lease:commit(8)
local writer = destination:writer()
response.body:transferto(writer)
writer:close()
end
return true
]]
    )
    assert(found == "", found)
end

function M.bundledAliasesShareStagedNominalTypes()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.project.incremental")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir .. "/src/string"))
    assert(fs.writeFile(dir .. "/nupp.lua", 'return {include = {"src"}}'))
    local declaration = assert(require("nupp.compiler.bundled").source("/decls/stringbuffer.d.nupp"))
    local typePath = dir .. "/src/string/buffer.d.nupp"
    assert(fs.writeFile(typePath, declaration))
    assert(fs.mkdir(dir .. "/src/nupp/test"))
    local main = dir .. "/src/nupp/test/aliases.nupp"
    assert(
        fs.writeFile(
            main,
            [[
module nupp.test.aliases
local {type Buffer} = require("string.buffer")
local contracts = require("serde.json.internal.contracts")
local function writer(exclusive out: string.buffer.Buffer, nullValue: any?): any
    out:put("value")
    return nil
end
local checked: function(exclusive out: Buffer, nullValue: any?): any = writer
local provider: contracts.Provider = {newwriter = writer} as any
local canonical: function(exclusive out: Buffer, nullvalue: any?): any = provider.newwriter
print(checked, canonical)
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
    require("io.files").remove(dir, true)
    assert(ok, problem)
end

function M.declarationModulesKeepDistinctNominalMethodSlots()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.project.incremental")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    assert(fs.writeFile(dir .. "/nupp.lua", 'return {include = {"."}}'))
    local declaration = "record Value\nend\nreturn {Value = Value}\n"
    assert(fs.writeFile(dir .. "/left.d.nupp", declaration))
    assert(fs.writeFile(dir .. "/right.d.nupp", declaration))
    local main = dir .. "/main.nupp"
    assert(
        fs.writeFile(
            main,
            [[
local {type Value as Left} = require("left")
local {type Value as Right} = require("right")
local record Reader
    function read(self, value: Left): string return "left" end
    function read(self, value: Right): string return "right" end
end
local reader = new Reader()
return reader:read({} as any as Left) .. reader:read({} as any as Right)
]]
        )
    )
    local ok, problem = pcall(function()
        local checked = incremental.new(dir).checkFile(main)
        for _, diagnostic in ipairs(checked.diags) do
            assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
        end
        local answer = require("program").run(checked.result, "main", main)
        assert(answer == "leftright", "same-named declaration nominals keep distinct methods: " .. tostring(answer))
    end)
    require("io.files").remove(dir, true)
    assert(ok, problem)
end

function M.providerIdentityAndGenericsSurviveModuleCaches()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.project.incremental")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    local files = {
        ["nupp.lua"] = 'return {include = {"."}}',
        [
            "contract.nupp"
        ] = [[
module contract
export record Token
    text: string
end
export interface Provider
    make: function(): Token
    mark: function<T is table>(takes value: T): T preserves value
    optional: (function(): string)?
end
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
const call: @nosuspend function(): string = assembled.call
const contract = require("contract")
const provider = require("provider")
const selected: contract.Provider = provider
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
    require("io.files").remove(dir, true)
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

function M.genericMethodsPreserveTheirOwnBindersAndBorrowRelations()
    local accepted = errors(
        [[
local m = {}
interface m.Mapper
    @readonly map: function<T>(borrows self: m.Mapper, element: ctype<T>, value: T): T
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
    @readonly map: function<T>(borrows self: m.Mapper, element: ctype<T>, value: T): T
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
    @readonly range: function(borrows self: m.Owner): m.Range borrows (self)
end
record m.Unrooted is m.Owner
    range: function(borrows self: m.Unrooted): m.Range
end
return m
]]
    )
    assert(rejected:find("NUPP2118", 1, true), rejected)
end

function M.applicationImportsCannotReachBuiltinImplementationContracts()
    for _, name in ipairs({
        "nupp.runtime.contracts",
        "binary.checksum.internal.contracts",
        "binary.digest.internal.contracts",
        "binary.mac.internal.contracts",
        "binary.compress.internal.contracts",
        "serde.json.internal.contracts",
        "io.internal.contracts",
        "io.files.internal.contracts",
        "io.net.internal.contracts",
        "nupp.io.net.contracts",
        "nupp.io.http.contracts",
        "nupp.suspension.contracts",
        "nupp.workers.contracts",
        "nupp.gpu.contracts",
        "io.internal.process.contracts",
    }) do
        local found = errors(("module application\nlocal contract = require(%q)\nreturn contract"):format(name))
        assert(found:find("NUPP2144", 1, true), name .. ": " .. found)
    end
end

function M.runtimeImplementationContractsRemainTyped()
    local found = errors(
        [[
module nupp.test.contracts
local contracts = require("nupp.runtime.contracts")
local function implementations(entropy: contracts.EntropyProvider,
    system: contracts.SystemProvider, clock: contracts.ClockProvider,
    uuid: contracts.UuidProvider,
    host: contracts.HostProvider, storage: contracts.CstorageProvider,
    structs: contracts.StructvalueProvider): nil
end
local function helpers(late: contracts.Late, policy: contracts.Policy, cast: contracts.CastElements): nil
    late(policy, cast)
end
export = {implementations = implementations, helpers = helpers}
]],
        nil,
        "nupp.test.contracts"
    )
    assert(found == "", found)
end

return M
