local test = require("nupp.test")
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
    test.equal(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
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
        test.equal(descriptor.checkedType, declared)
        test.equal(descriptor.pointee, declared.elem)
        test.equal(descriptor.declaration, declared.elem.origin or declared.elem)
        test.equal(descriptor.machineKind, "voidptr")
        test.equal(descriptor.nullable, false)
        test.equal(fn.body.signatureType.paramModes[1], "borrows")
        local reads = fields(fn.body)
        test.equal(#reads, 1)
        local actual = reads[1].obj.inferredType
        test.equal(actual.tag, "borrowed")
        test.equal(actual.inner, declared)
        test.equal(parameter.name.definition.type, actual)
        test.equal(reads[1].unsafeOwnershipOperation, nil)
        test.equal(reads[1].resolvedType, T.uint64)
        test.equal(reads[1].name.definition, declared.elem.fieldDefs.base)
        local qualified = physical.describe(context, actual)
        test.equal(qualified.ownership[1], actual)
        assert(not physical.same(descriptor, qualified))
        refuses(
            function()
                physical.field(qualified, reads[1], false)
            end,
            "lifetime permission proof"
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
    test.equal(header.machineKind, words.machineKind)
    test.equal(header.layout.target, TARGET)
    test.equal(header.layout.abi, layout.ABI)
    assert(not physical.same(header, words))
    assert(not physical.same(header, optional))
    assert(not physical.same(header, borrowed))
    test.equal(optional.valueType, optionalType)
    test.equal(optional.pointee, header.pointee)
    test.equal(optional.nullable, true)
    test.equal(borrowed.ownership[1], borrowedType)
    assert(not physical.same(header, physical.describe(physical.new(TARGET), declared)))
    assert(not physical.same(header, physical.describe(context, T.voidptr)))
    local narrow = physical.describe(physical.new("wasm32-unknown-emscripten"), declared)
    test.equal(narrow.storageBytes, 4)
    test.equal(header.storageBytes, 8)
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
        test.equal(#accesses, 2)
        for _, node in ipairs(accesses) do
            local write = name == "write"
            local access = physical.field(descriptor, node, write)
            local kind = node.name.text == "kind"
            test.equal(access.width, kind and 1 or 4)
            test.equal(access.offset, kind and 0 or 4)
            test.equal(access.storage.storageType, kind and T.uint8 or T.uint32)
            test.equal(access.storage.valueType, T.uint32)
            test.equal(access.storage.valueType, fixed.loaded(access.storage.storageType))
            test.equal(access.storage.machineKind, "uint32")
            test.equal(access.storage.arithmetic, false)
            test.equal(access.signed, false)
            test.equal(access.declaration, descriptor.pointee.fieldDefs[node.name.text])
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
        "lifetime permission proof"
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
    test.equal(pointer.pointee, empty)
    test.equal(pointer.storageBytes, 8)
    test.equal(#pointer.layout.fields, 0)
    refuses(
        function()
            physical.describe(context, empty)
        end,
        "unsupported physical value type"
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
