local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local projection = require("nupp.compiler.vm.scalartypeof")
local types = require("nupp.compiler.types")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local M = {}
local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
local actualModules = {}
local unitsEnvironment
local coroutineProjection

local function checked(source, path, name)
    if unitsEnvironment == nil then
        unitsEnvironment = environment.new(root .. "/tests/core/units")
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

local function actualmodule(name)
    if actualModules[name] == nil then
        local path = root .. "/src/" .. name:gsub("%.", "/") .. ".nupp"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        actualModules[name] = checked(source, path, name)
    end

    return actualModules[name]
end

local function fixture(body)
    local name = "nupp.runtime.scalartypeoffixture"
    return checked("module " .. name .. "\n" .. body, "=scalar-typeof-fixture.nupp", name)
end

local function catalog(module)
    -- Supply the unrelated builtin projection; the real scalar factory and
    -- its checked source below remain authoritative.
    coroutineProjection = coroutineProjection
        or checked(
            "module nupp.runtime.luacoroutine\nexport const value: table = {}",
            "=scalar-coroutine-projection.nupp",
            "nupp.runtime.luacoroutine"
        )

    return program.describe(
        {actualmodule("nupp.runtime.libraryvalues"), coroutineProjection, actualmodule(projection.MODULE), module},
        module.name
    )
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

local function validated(module)
    local described = catalog(module)
    local complete = program.compile(described, tagged.forVersion(8))
    executable.validate(executable.fromChecked(complete, 8))
    return described
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

function M.scalarWitnessesSurviveCompleteProgramAndExecutableValidation()
    local described = catalog(
        fixture([[local ffi=require('ffi')
export function entry(): ctype<uint32> return ffi.typeof<uint32>() end]])
    )
    local complete = program.compile(described, tagged.forVersion(8))
    assert(#complete.graphs == #described.owners)
    local output = executable.fromChecked(complete, 8)
    executable.validate(output)
    assert(#output.functions == #described.owners)
end

function M.syntheticScalarCallsitesRetainTheirSourceOwnerAndFactory()
    local described = catalog(
        fixture([[local ffi=require('ffi')
export function entry(): ctype<uint16> return ffi.typeof<uint16>() end]])
    )
    local _, witness = next(described.scalartypes.witnesses)
    local site = assert(described.callByNode[witness.call])
    assert(site.scalarWitness == witness and site.owner == witness.owner)
    assert(described.calls[site.id + 1] == site)
    assert(site.definition == witness.target.definition)

    described.callByNode[witness.call] = nil
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness lacks its checked callsite", 1, true)
    )
    local canonical = described.calls[site.id + 1]
    described.calls[site.id + 1] = nil
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness lacks its checked callsite", 1, true)
    )
    described.calls[site.id + 1] = canonical
    described.callByNode[witness.call] = site

    local owner = site.owner
    site.owner = witness.target.id
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness callsite differs", 1, true)
    )
    witness.owner = site.owner
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar callsite lacks its checked source witness", 1, true)
    )
    site.owner, witness.owner = owner, owner

    local base = witness.base
    witness.base = {kind = "name", token = base.token}
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness identity differs", 1, true)
    )
    witness.base = base

    local definition = site.definition
    site.definition = witness.definition
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness callsite differs", 1, true)
    )
    site.definition = definition

    site.scalarWitness = {}
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness callsite differs", 1, true)
    )
    site.scalarWitness = witness

    local node = site.node
    site.node = witness.node
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness callsite differs", 1, true)
    )
    site.node = node

    described.calls[site.id + 1] = {}
    assert(
        refused(function()
            program.verify(described)
        end):find("scalar witness callsite differs", 1, true)
    )
    described.calls[site.id + 1] = site
    assert(program.verify(described))
end

function M.scalarExecutableImportsRejectForeignTargetsAndChangedSourceSites()
    local described = catalog(
        fixture([[local ffi=require('ffi')
export function entry(): ctype<uint32> return ffi.typeof<uint32>() end]])
    )
    local complete = program.compile(described, tagged.forVersion(8))
    local loader, imported = next(described.scalartypes.imports)
    local site = assert(described.requireByNode[loader])
    local source = site.scalarImport
    site.scalarImport = {}
    refused(function()
        executable.fromChecked(complete, 8)
    end)
    site.scalarImport = source

    local target = site.target
    site.target = described.entry
    refused(function()
        executable.fromChecked(complete, 8)
    end)
    site.target = target

    local mapped = described.scalartypes.definitions[imported.definition]
    described.scalartypes.definitions[imported.definition] = nil
    refused(function()
        executable.fromChecked(complete, 8)
    end)
    described.scalartypes.definitions[imported.definition] = mapped

    local binding
    for _, item in ipairs(described.imports) do
        if described.bindings[item.binding + 1].definition == imported.definition then
            binding = item
        end
    end
    assert(binding)
    local savedTarget = binding.target
    binding.target = described.entry
    refused(function()
        executable.fromChecked(complete, 8)
    end)
    binding.target = savedTarget
    executable.validate(executable.fromChecked(complete, 8))
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
    local missing = "unresolved executable reference required checked module ffi (not carried)"
    local unresolved = "unresolved executable reference ffi at "
    local failures = {missing, missing, unresolved, unresolved, unresolved, missing}
    for index, body in ipairs(bodies) do
        local module = fixture(body)
        assert(#projection.imports(module.parsed.root) == 0)
        local problem = refused(function()
            validated(module)
        end)
        assert(problem:find(failures[index], 1, true), "control " .. index .. ": " .. problem)
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
        local described = validated(module)
        assert(next(described.scalartypes.witnesses) == nil)
        assert(next(described.scalartypes.imports) == nil)
        assert(next(described.scalartypes.definitions) == nil)
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
    local problem = refused(function()
        validated(module)
    end)
    assert(problem:find("unresolved executable reference ffi at ", 1, true))
end

return M
