local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local projection = require("nupp.compiler.vm.scalartypeof")
local types = require("nupp.compiler.types")
local M = {}
local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
local provider
local unitsEnvironment

local function checked(source, path, name)
    if unitsEnvironment == nil then
        unitsEnvironment = environment.new(root .. "/native/core/tests/units")
    end
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, path, unitsEnvironment, {
        moduleName = name,
        strict = true,
        lints = {["unused-binding"] = "off"}
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end

    return {name = name, path = path, parsed = parsed, diagnostics = diagnostics}
end

local function actualprovider()
    if provider == nil then
        local path = root .. "/src/nupp/runtime/provider/heapstorage.nupp"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        provider = checked(source, path, projection.MODULE)
    end

    return provider
end

local function fixture(body)
    local name = "nupp.runtime.scalartypeoffixture"
    return checked("module " .. name .. "\n" .. body, "=scalar-typeof-fixture.nupp", name)
end

local function catalog(module)
    return program.describe({actualprovider(), module}, module.name)
end

local function compile(module)
    local described = catalog(module)
    local graphs = {}
    for _, owner in ipairs(described.owners) do
        if owner.scope.name == module.name
            or owner.scope.name == projection.MODULE and (owner.kind == "module" or owner.name == projection.MEMBER)
        then
            graphs[#graphs + 1] = program.functionGraph(described, owner, tagged.forVersion(8))
        end
    end

    return described, {graphs = graphs}
end

local function refused(operation)
    local okay, why = pcall(operation)
    assert(not okay and why ~= nil, "unsupported scalar witness must refuse")
    return tostring(why)
end

function M.realPhysicalScalarWitnessesCallTheActualCanonicalFactory()
    local kinds = {"uint8", "int8", "uint16", "int16", "uint32", "int32", "uint64", "int64", "float32", "float64"}
    local lines = {"local ffi=require('ffi')"}
    for index, kind in ipairs(kinds) do
        lines[
            #lines + 1
        ] = "export function witness" .. index .. "(): ctype<" .. kind .. "> return ffi.typeof<" .. kind .. ">() end"
    end
    local module = fixture(table.concat(lines, "\n"))
    local described, built = compile(module)
    local imported = assert(next(described.scalartypes.imports))
    assert(described.requireByNode[imported].module == projection.MODULE)
    local seen = {}
    for _, graph in ipairs(built.graphs) do
        if graph.module == module.name then
            for _, block in ipairs(graph.blocks) do
                local term = block.term
                if term and term.kind == "invoke" then
                    local contract = term.contract
                    assert(contract.owner.scope.name == projection.MODULE and contract.owner.name == "scalar")
                    assert(contract.body == contract.owner.body)
                    assert(contract.owner.scope.path == root .. "/src/nupp/runtime/provider/heapstorage.nupp")
                    seen[contract.call.args.exprs[1].token.text] = true
                end
            end
        end
    end
    for _, kind in ipairs(kinds) do
        assert(seen[string.format("%q", kind == "float64" and "number" or kind)])
    end
end

function M.separateLexicalImportsKeepTheirOwnCheckedDeclarations()
    local module = fixture(
        [[export function first(): ctype<uint16>
 local ffi=require("ffi")
 return ffi.typeof<uint16>()
end
export function second(): ctype<uint32>
 local ffi=require("ffi")
 return ffi.typeof<uint32>()
end]]
    )
    local described = compile(module)
    local seen = {}
    local count = 0
    for _, site in pairs(described.scalartypes.witnesses) do
        assert(site.definition.name == "ffi" and site.definition.requiredModule == "ffi")
        assert(not seen[site.definition])
        seen[site.definition] = true
        count = count + 1
    end
    assert(count == 2)
end

function M.scalarWitnessesKeepSingleResultSemanticsWhenAdjustedOrDiscarded()
    compile(
        fixture(
            [[local ffi=require('ffi')
export function entry(): ctype<uint32>
 ffi.typeof<uint16>()
 local first, unused = ffi.typeof<uint32>()
 assert(unused == nil)
 return first
end]]
        )
    )
end

function M.ordinaryMixedDynamicAndStructFfiStayRefused()
    local bodies = {
        [[local ffi=require("ffi")
export function entry(): ctype<uint8*> return ffi.typeof<uint8*>() end]],
        [[local ffi=require("ffi")
local function touch(): integer return 1 end
export function entry(): ctype<uint16> return ffi.typeof<uint16>(touch()) end]],
        [[local ffi=require('ffi')
export function entry(): integer return ffi.sizeof<uint16>() end]],
        [[local ffi=require('ffi')
export function entry(): ctype<uint16>
 local size=ffi.sizeof<uint16>()
 assert(size > 0)
 return ffi.typeof<uint16>()
end]],
        [[local ffi=require('ffi')
export function entry(name: string): any return ffi.typeof(name) end]],
        [[local ffi=require('ffi')
local struct Row
 value: uint16
end
export function entry(): ctype<Row> return ffi.typeof<Row>() end]]
    }
    for _, body in ipairs(bodies) do
        local module = fixture(body)
        assert(#projection.imports(module.parsed.root) == 0)
        assert(
            refused(function()
                catalog(module)
            end):find("required checked module is missing: ffi", 1, true)
        )
    end
end

function M.shadowedOrUnrelatedNamespacesDoNotAcquireWitnessAuthority()
    local bodies = {
        [[local ffi={typeof=function<T>(): ctype<T> error('shadow') end}
export function entry(): ctype<uint16> return ffi.typeof<uint16>() end]],
        [[local ffi=require('nupp.runtime.provider.heapstorage')
export function entry(): ctype<uint16> return ffi.typeof<uint16>() end]]
    }
    for _, body in ipairs(bodies) do
        local module = fixture(body)
        assert(#projection.imports(module.parsed.root) == 0)
        refused(function()
            compile(module)
        end)
    end
end

function M.witnessAndFactoryMetadataCannotChangeAfterDiscovery()
    local described = catalog(
        fixture([[local ffi=require('ffi')
export function entry(): ctype<uint16> return ffi.typeof<uint16>() end]])
    )
    local _, witness = next(described.scalartypes.witnesses)
    assert(witness)
    local node = witness.node
    local savedType = node.inferredType
    node.inferredType = types.ctype(types.uint8)
    refused(function()
        program.verify(described)
    end)
    node.inferredType = savedType
    local savedText = witness.call.args.exprs[1].token.text
    witness.call.args.exprs[1].token.text = '"uint8"'
    refused(function()
        program.verify(described)
    end)
    witness.call.args.exprs[1].token.text = savedText
    local savedDefinition = node.obj.obj.token.definition
    node.obj.obj.token.definition = {requiredModule = "ffi", lexical = true}
    refused(function()
        program.verify(described)
    end)
    node.obj.obj.token.definition = savedDefinition
    assert(program.verify(described))
end

function M.equivalentLiteralsRetainTheirDecodedCheckedImport()
    for _, literal in ipairs({'"f\\102i"', '[=[ffi]=]'}) do
        local module = fixture(
            "local ffi=require("
            .. literal
            .. ")\nexport function entry(): ctype<uint16> return ffi.typeof<uint16>() end"
        )
        local described = compile(module)
        local _, imported = next(described.scalartypes.imports)
        assert(imported and imported.loader.requiredModule == "ffi" and imported.definition.requiredModule == "ffi")
    end
    compile(fixture([[local ffi=require 'ffi'
export function entry(): ctype<uint32> return ffi.typeof<uint32>() end]]))
end

function M.mismatchedOrIncompleteLiteralMetadataCannotAcquireAnImport()
    local described = catalog(
        fixture([[local ffi=require('ffi')
export function entry(): ctype<uint16> return ffi.typeof<uint16>() end]])
    )
    local _, imported = next(described.scalartypes.imports)
    local token = imported.loader.args.exprs[1].token
    local saved = token.text
    for _, wrong in ipairs({'"other"', '[[ffi]] trailing', '[=[ffi]]', '[[ffi]]]]'}) do
        token.text = wrong
        refused(function()
            program.verify(described)
        end)
    end
    token.text = saved
    assert(program.verify(described))
    local lexer = require("nupp.compiler.syntax.lexer")
    assert(lexer.literalstring('[=[ffi]=]') == "ffi")
    assert(lexer.literalstring('"f\\102i"') == "ffi")
    assert(lexer.literalstring('[[ffi]] trailing') == nil)
    assert(lexer.literalstring('[=[ffi]]') == nil)
    assert(lexer.literalstring('[[ffi]]]]') == nil)
end

function M.implicitTypeofKeepsCheckerSemanticsWithoutInventingAnImport()
    local module = fixture([[export function entry(): ctype<uint16> return ffi.typeof<uint16>() end]])
    assert(#projection.imports(module.parsed.root) == 0)
    refused(function()
        catalog(module)
    end)
end

return M
