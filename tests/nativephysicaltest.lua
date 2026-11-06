local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local provider = require("nupp.compiler.syntax.triviaarena.table")
local T = require("nupp.compiler.types")
local fixed = require("nupp.compiler.types.fixedwidth")
local layout = require("nupp.compiler.targetlayout")
local physical = require("nupp.compiler.vm.nativephysical")
local M = {}
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local TARGET = "aarch64-apple-darwin"
local cachedHeap

local function checked(source, path)
    trivia.installDefault(provider)
    local parsed = parser.parse(source, path)
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(ROOT, {cache = false, nativeCompilerServices = false, config = {include = {"src"}}})
    for _, diagnostic in ipairs(checker.check(parsed, path, env, {lints = {["unused-binding"] = "off"}})) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end

    return parsed
end

local function heap()
    if not cachedHeap then
        local path = ROOT .. "/src/nupp/runtime/vm/heap.nupp"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        cachedHeap = checked(source, path)
    end

    return cachedHeap
end

local function findFunction(tree, name)
    for _, block in ipairs(tree.root.blocks) do
        for _, stat in ipairs(block.stats) do
            local node = stat.kind == "exportStmt" and stat.stat or stat
            if node and (node.kind == "localFuncStmt" or node.kind == "funcStmt") then
                local found = node.kind == "localFuncStmt" and node.name.text or node.name.base.text
                if found == name then
                    return node
                end
            end
        end
    end
    error("missing checked function " .. name)
end

local function fields(node, out)
    out = out or {}
    if type(node) ~= "table" or not node.kind then
        return out
    end
    if node.kind == "dotIndex" and node.obj.inferredType and T.unwrapOwnership(node.obj.inferredType).tag == "ptr" then
        out[#out + 1] = node
    end
    for _, child in ipairs(node) do
        fields(child, out)
    end

    return out
end

local function refuses(fn, text)
    local ok, message = pcall(fn)
    assert(not ok)
    assert(tostring(message):find(text, 1, true), tostring(message))
end

function M.existingWordServicesRetainBorrowedBindingAuthority()
    local context = physical.new(TARGET)
    local first
    for _, name in ipairs({"wordAt", "setWordAt"}) do
        local fn = findFunction(heap(), name)
        local parameter = fn.body.params[1]
        local declared = parameter.type.resolvedType
        local descriptor = physical.describe(context, declared)
        test.eq(descriptor.checkedType, declared)
        test.eq(descriptor.pointee, declared.elem)
        test.eq(descriptor.declaration, declared.elem.origin or declared.elem)
        test.eq(descriptor.machineKind, "voidptr")
        test.eq(descriptor.nullable, false)
        test.eq(fn.body.signatureType.paramModes[1], "borrows")
        local reads = fields(fn.body)
        test.eq(#reads, 1)
        local actual = reads[1].obj.inferredType
        test.eq(actual.tag, "borrowed")
        test.eq(actual.inner, declared)
        test.eq(parameter.name.definition.type, actual)
        test.eq(reads[1].unsafeOwnershipOperation, nil)
        test.eq(reads[1].resolvedType, T.uint64)
        test.eq(reads[1].name.definition, declared.elem.fieldDefs.base)
        local qualified = physical.describe(context, actual)
        test.eq(qualified.ownership[1], actual)
        assert(not physical.same(descriptor, qualified))
        refuses(
            function()
                physical.field(qualified, reads[1], false)
            end,
            "qualified access requires checked owner"
        )
        refuses(
            function()
                physical.field(descriptor, reads[1], false)
            end,
            "receiver checked type differs"
        )
        if first then
            assert(physical.same(first, descriptor))
        end
        first = descriptor
    end
end

-- A raw ABI can still contain an ordinary checked dependent local. The
-- original owner supplies occurrence authority; no fake parameter signature
-- is needed to read/write that local's fields.
function M.rawAbiDependentLocalsRetainExactFieldOwner()
    local unit = require("nupp.compiler.vm.nativeunit")
    local lower = require("nupp.compiler.vm.lower")
    local profile = require("nupp.compiler.vm.nativegraph")
    local graph = require("nupp.compiler.vm.graph")
    local fs = require("nupp.compiler.fs")
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src/nupp/test'") == 0)
    local path = dir .. "/src/nupp/test/fieldowner.nupp"
    local file = assert(io.open(path, "wb"))
    file:write(
        [[
module nupp.test.fieldowner
const native = require("nupp.runtime.vm.intrinsics")
local struct Box
    value: uint64
end
local function keep(borrows pointer: Box*): Box* borrows (pointer)
    return pointer
end
local function formal(borrows pointer: Box*): uint64
    return pointer.value
end
local function read(address: uint64): uint64
    @unsafe do
        local pointer = native.pointer(address) as Box*
        local borrowed = keep(pointer)
        return borrowed.value
    end
end
local function write(address: uint64, seed: uint64): uint64
    @unsafe do
        local pointer = native.pointer(address) as Box*
        local borrowed = keep(pointer)
        borrowed.value = native.asWord(seed == 0ULL or seed == 1ULL)
        return borrowed.value
    end
end
]]
    )
    file:close()
    local ok, problem = pcall(function()
        trivia.installDefault(provider)
        local session = unit.session(dir, {{path = path, moduleName = "nupp.test.fieldowner"}}, TARGET, {
            "src",
            fs.absolute(ROOT .. "/src")
        })
        local owners = session.module("nupp.test.fieldowner").functions

        local function copy(value)
            local result = {}
            for key, item in pairs(value) do
                result[key] = item
            end

            return result
        end

        local function descriptor(owner)
            for _, node in ipairs(unit.occurrences(owner)) do
                if node.kind == "call"
                    and node.obj.kind == "name"
                    and node.obj.token.definition == owners.keep.definition
                then
                    return physical.signature(owners.keep, unit.ownerContext(owner), node, owner).result
                end
            end
            error("missing original dependent call")
        end

        for _, name in ipairs({"read", "write"}) do
            local owner = owners[name]
            -- This raw-pointer fixture checks source descriptors and graph-owner
            -- issuance only. Its plain argument has no runtime borrow proof;
            -- actual heapentry.run covers acquired owners in a complete graph.
            refuses(
                function()
                    lower.functionGraph(owner, session.options(owner, "leaf"), profile)
                end,
                "dependent call argument root differs"
            )
            local g = profile.initialize(owner, session.options(owner, "leaf"))
            g.source = {path = owner.scope.path, module = owner.scope.name, name = owner.name}
            assert(g.nativePhysical.signature == nil and physical.graphOwner(g) == owner)
            local value = descriptor(owner)
            assert(physical.qualifiedGraphValue(g, value))
            local forged = graph.newNative(owner.paramKinds, owner.resultKind, "leaf")
            forged.nativePhysical = {context = physical.new(TARGET), values = {}}
            refuses(
                function()
                    physical.bindGraphOwner(forged, owner)
                end,
                "physical graph owner target context differs"
            )
            refuses(
                function()
                    physical.qualifiedGraphValue(copy(g), value)
                end,
                "qualified graph value requires original checked owner"
            )
            local sidecar = g.nativePhysical
            g.nativePhysical = copy(sidecar)
            refuses(
                function()
                    physical.graphOwner(g)
                end,
                "physical graph owner sidecar changed"
            )
            g.nativePhysical = sidecar
            local context = sidecar.context
            sidecar.context = physical.new(TARGET)
            refuses(
                function()
                    physical.graphOwner(g)
                end,
                "physical graph owner sidecar changed"
            )
            sidecar.context = context
            sidecar.signature = physical.signature(owners.keep, context)
            refuses(
                function()
                    physical.graphOwner(g)
                end,
                "physical graph owner sidecar changed"
            )
            sidecar.signature = nil
            local sourceName = g.source.name
            g.source.name = owners.keep.name
            refuses(
                function()
                    physical.graphOwner(g)
                end,
                "physical graph owner source changed"
            )
            g.source.name = sourceName
            owner.name = owners.keep.name
            refuses(
                function()
                    physical.graphOwner(g)
                end,
                "physical graph owner source changed"
            )
            owner.name = sourceName
            local foreign = descriptor(owners[name == "read" and "write" or "read"])
            refuses(
                function()
                    physical.qualifiedGraphValue(g, foreign)
                end,
                "occurrence is outside checked owner"
            )
            refuses(
                function()
                    physical.qualifiedGraphValue(g, physical.describe(context, value.checkedType))
                end,
                "qualified graph local lacks checked dependency"
            )
            local count = 0
            for _, node in ipairs(unit.occurrences(owner)) do
                if node.kind == "dotIndex" and node.obj.kind == "name" and node.obj.token.text == "borrowed" then
                    local access = physical.field(value, node, node.assignmentTarget == true, nil, owner)
                    count = count + 1
                    assert(access.borrowSignature == nil and physical.validateField(access))
                    refuses(
                        function()
                            physical.field(value, node, access.write)
                        end,
                        "qualified access requires checked owner"
                    )
                    refuses(
                        function()
                            physical.field(value, node, access.write, nil, {})
                        end,
                        "unknown occurrence owner"
                    )
                    refuses(
                        function()
                            physical.field(value, node, access.write, nil, owners.keep)
                        end,
                        "occurrence is outside checked owner"
                    )
                    refuses(
                        function()
                            physical.field(value, node, access.write, physical.signature(owners.keep, context), owner)
                        end,
                        "qualified access owner/signature differs"
                    )
                end
            end
            assert(count > 0)
        end
        local owner = owners.formal
        local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)

        local function refuseTypedClone()
            assert(g.nativePhysical.signature and physical.graphOwner(g) == owner)
            local clone = {}
            for key, value in pairs(g) do
                clone[key] = value
            end
            refuses(
                function()
                    graph.verify(clone)
                end,
                "qualified unit graph requires original checked owner"
            )
        end

        refuseTypedClone()
        local access
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativeFieldLoad" then
                    access = block.args[index][2]
                end
            end
        end
        assert(access and access.borrowSignature == g.nativePhysical.signature)
        local object = access.node.obj
        local facts = object.capabilityFacts
        object.capabilityFacts = nil
        local accepted, message = pcall(physical.field, access.receiver, access.node, false, nil, owner)
        object.capabilityFacts = facts
        assert(
            not accepted and tostring(message):find("borrowed formal access requires checked signature", 1, true),
            tostring(message)
        )
        graph.verify(g)
        graph.prune(g)
        graph.verify(g)
        refuseTypedClone()
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(problem, 0)
    end
end

function M.pointerResultsAndOptionalityDoNotCollapseToMachineKind()
    local context = physical.new(TARGET)
    local fn = findFunction(heap(), "objectHeader")
    local declared = fn.body.signatureType.rets[1]
    local header = physical.describe(context, declared)
    local words = physical.describe(context, findFunction(heap(), "wordAt").body.params[1].type.resolvedType)
    local optionalType = T.optional(declared)
    local optional = physical.describe(context, optionalType)
    local borrowedType = T.borrowed(declared)
    local borrowed = physical.describe(context, borrowedType)
    test.eq(header.machineKind, words.machineKind)
    test.eq(header.layout.target, TARGET)
    test.eq(header.layout.abi, layout.ABI)
    assert(not physical.same(header, words))
    assert(not physical.same(header, optional))
    assert(not physical.same(header, borrowed))
    test.eq(optional.valueType, optionalType)
    test.eq(optional.pointee, header.pointee)
    test.eq(optional.nullable, true)
    test.eq(borrowed.ownership[1], borrowedType)
    assert(not physical.same(header, physical.describe(physical.new(TARGET), declared)))
    assert(not physical.same(header, physical.describe(context, T.voidptr)))
    local narrow = physical.describe(physical.new("wasm32-unknown-emscripten"), declared)
    test.eq(narrow.storageBytes, 4)
    test.eq(header.storageBytes, 8)
end

local function headerFixture()
    return checked(
        [[
local heap = require("nupp.runtime.vm.heap")
local native = require("nupp.runtime.vm.intrinsics")
local function read(address: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do return (h.kind as uint64) + (h.epoch as uint64) end
end
local function write(address: uint64): nil
    local h = native.pointer(address) as heap.Header*
    @unsafe do h.kind = 3; h.epoch = 42 end
end
]],
        "=nativephysicalfixture.nupp"
    )
end

function M.headerStorageWidthIsSeparateFromCheckedLoadedType()
    local tree, context = headerFixture(), physical.new(TARGET)
    for _, name in ipairs({"read", "write"}) do
        local fn = findFunction(tree, name)
        local descriptor = physical.describe(context, fields(fn.body)[1].obj.inferredType)
        local accesses = fields(fn.body)
        test.eq(#accesses, 2)
        for _, node in ipairs(accesses) do
            local write = name == "write"
            local access = physical.field(descriptor, node, write)
            local kind = node.name.text == "kind"
            test.eq(access.width, kind and 1 or 4)
            test.eq(access.offset, kind and 0 or 4)
            test.eq(access.storage.storageType, kind and T.uint8 or T.uint32)
            test.eq(access.storage.valueType, T.uint32)
            test.eq(access.storage.valueType, fixed.loaded(access.storage.storageType))
            test.eq(access.storage.machineKind, "uint32")
            test.eq(access.storage.arithmetic, false)
            test.eq(access.signed, false)
            test.eq(access.declaration, descriptor.pointee.fieldDefs[node.name.text])
        end
    end
end

function M.fieldAccessRequiresCheckedReceiverMemberAndUnsafeEvidence()
    local tree, context = headerFixture(), physical.new(TARGET)
    local fn = findFunction(tree, "read")
    local node = fields(fn.body)[1]
    local descriptor = physical.describe(context, fields(fn.body)[1].obj.inferredType)
    local marker = node.unsafeOwnershipOperation
    node.unsafeOwnershipOperation = nil
    refuses(
        function()
            physical.field(descriptor, node, false)
        end,
        "checked unsafe pointer access"
    )
    node.unsafeOwnershipOperation = marker
    local definition = node.name.definition
    node.name.definition = descriptor.pointee.fieldDefs.epoch
    refuses(
        function()
            physical.field(descriptor, node, false)
        end,
        "field declaration identity"
    )
    node.name.definition = definition
    refuses(
        function()
            physical.field(physical.describe(context, T.voidptr), node, false)
        end,
        "typed struct pointer"
    )
    refuses(
        function()
            physical.field(physical.describe(context, T.optional(descriptor.checkedType)), node, false)
        end,
        "nonnull refinement"
    )
    refuses(
        function()
            physical.field(physical.describe(context, T.borrowed(descriptor.checkedType)), node, false)
        end,
        "qualified access requires checked owner"
    )
    local store = fields(findFunction(tree, "write").body)[1]
    store.fixedWidthPhysicalStore = nil
    refuses(
        function()
            physical.field(descriptor, store, true)
        end,
        "checked physical store"
    )
end

function M.opaquePointerIsLazyAndUnsupportedStorageRefuses()
    local empty = T.nominal("Opaque", "struct", "nativephysicaltest:opaque")
    local context = physical.new(TARGET)
    local pointer = physical.describe(context, T.ptr(empty))
    test.eq(pointer.pointee, empty)
    test.eq(pointer.storageBytes, 8)
    test.eq(#pointer.layout.fields, 0)
    refuses(
        function()
            physical.describe(context, empty)
        end,
        "an empty struct has no C layout"
    )
    refuses(
        function()
            physical.describe(context, T.union({T.ptr(empty), T.voidptr}))
        end,
        "only one optional pointer"
    )
    refuses(
        function()
            physical.new("invented-target")
        end,
        "explicit supported target"
    )
end

function M.validationRecomputesTypeAndLayoutAuthority()
    local tree, context = headerFixture(), physical.new(TARGET)
    local fn = findFunction(tree, "read")
    local node = fields(fn.body)[1]
    local descriptor = physical.describe(context, fields(fn.body)[1].obj.inferredType)
    local access = physical.field(descriptor, node, false)
    assert(physical.validate(descriptor))
    assert(physical.validateField(access))

    local function changed(object, key, value, validate, message)
        local previous = object[key]
        object[key] = value
        refuses(validate, message)
        object[key] = previous
        validate()
    end

    changed(
        descriptor,
        "pointee",
        T.uint64,
        function()
            physical.validate(descriptor)
        end,
        "pointee changed"
    )
    changed(
        descriptor,
        "nullable",
        true,
        function()
            physical.validate(descriptor)
        end,
        "nullable changed"
    )
    changed(
        context,
        "target",
        "wasm32-unknown-emscripten",
        function()
            physical.validate(descriptor)
        end,
        "target context changed"
    )
    changed(
        descriptor,
        "storageBytes",
        4,
        function()
            physical.validate(descriptor)
        end,
        "storageBytes changed"
    )
    changed(
        descriptor.layout,
        "alignment",
        1,
        function()
            physical.validate(descriptor)
        end,
        "descriptor layout changed"
    )
    changed(
        access,
        "width",
        8,
        function()
            physical.validateField(access)
        end,
        "field width changed"
    )
    changed(
        access,
        "offset",
        16,
        function()
            physical.validateField(access)
        end,
        "field offset changed"
    )
    changed(
        access,
        "declaration",
        descriptor.pointee.fieldDefs.epoch,
        function()
            physical.validateField(access)
        end,
        "field declaration changed"
    )
    changed(
        access.layout.fields[1],
        "offset",
        16,
        function()
            physical.validateField(access)
        end,
        "field layout changed"
    )
    changed(
        node.name,
        "definition",
        descriptor.pointee.fieldDefs.epoch,
        function()
            physical.validateField(access)
        end,
        "field declaration identity differs"
    )
    changed(
        descriptor.pointee.fieldDefs.kind,
        "bitWidth",
        1,
        function()
            physical.field(descriptor, node, false)
        end,
        "bitfield access is unsupported"
    )
end

return M
