local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local environment = envMod.new(HERE .. "/..")
local M = {}

local function errors(source, selectedEnvironment)
    local result = parser.parse(source, "typed-interface.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    local found = {}
    for _, diagnostic in ipairs(check.check(result, "typed-interface.nupp", selectedEnvironment or environment)) do
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
local contracts = require("nupp.io.http.spi")
local io = require("nupp.io")
local function copy(borrows response: contracts.Response): nil
local destination = io.newBuffer()
response.body:readInto(destination, 0, 8)
local lease = destination:reserveWrite(0, 8)
local output = lease:span()
response.body:readSpan(output)
nupp.drop(output)
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

function M.bundledAliasesShareStagedNominalTypes()
    local fs = require("nupp.compiler.fs")
    local incremental = require("nupp.compiler.project.incremental")
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir .. "/src/nupp/text/internal"))
    assert(fs.writeFile(dir .. "/nupp.lua", 'return {include = {"src"}}'))
    local declaration = assert(require("nupp.compiler.bundled").source("/nupp/text/internal/buffer.d.nupp"))
    local typePath = dir .. "/src/nupp/text/internal/buffer.d.nupp"
    assert(fs.writeFile(typePath, declaration))
    local main = dir .. "/src/main.g.nupp"
    assert(
        fs.writeFile(
            main,
            [[
local {type Buffer} = require("nupp.text")
local contracts = require("nupp.codec.json.spi")
local function writer(exclusive out: nupp.text.Buffer, nullValue: any?): any
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
local spi = require("nupp.spi")
const selected: contract.Provider = assert(spi.load(contract.Provider)())
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

function M.runtimeImplementationInterfacesArePublic()
    local found = errors(
        [[
module application
local spi = require("nupp.spi")
local {type BitopsProvider} = require("nupp.runtime.bitops.spi")
local {type CstorageProvider, type Int64Provider} = require("nupp.runtime.representation.spi")
local {type UuidProvider} = require("nupp.runtime.uuid.spi")
local bits = spi.load(BitopsProvider)
local storage = spi.load(CstorageProvider)
local integers = spi.load(Int64Provider)
local uuids = spi.load(UuidProvider)
export = {bits = bits, storage = storage, integers = integers, uuids = uuids}
]]
    )
    assert(found == "", found)
end

return M
