local testAssert = require("nupp.test")
local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.types.generics")
local reflection = require("nupp.compiler.reflection")
local json = require("testjson")

local function recursiveNode(valueType)
    local node = T.nominal("Node", "record")
    node.byname = {value = valueType, next = T.optional(node)}
    node.writeByname = {value = valueType, next = T.optional(node)}
    node.fieldOrder = {"value", "next"}

    return node
end

local M = {}

function M.serializesRecursiveTypesAsAcyclicIndexedGraphs()
    local descriptor = reflection.describe(recursiveNode(T.string), "Node")
    testAssert.equal(descriptor.schema, 6, "reflection schema")
    testAssert.equal(descriptor.root, 1, "root index")
    testAssert.equal(descriptor.fields[1].name, "value", "declaration order begins with value")
    testAssert.equal(descriptor.fields[2].name, "next", "declaration order retains next")
    local encoded = json.encode(descriptor)
    assert(#encoded > 0, "the recursive descriptor is plain JSON data")
    local reachesRoot = false
    for _, entry in ipairs(descriptor.types) do
        for _, member in ipairs(entry.members or {}) do
            if member == descriptor.root then
                reachesRoot = true
            end
        end
    end
    assert(reachesRoot, "the recursive edge refers back to the root index")
end

function M.reflectsAssociatedRequirementsAndTheirAnswers()
    local lines = T.nominal("Lines", "interface")
    lines.associatedRequirements = {{name = "Item", bound = T.string}}
    lines.associatedAnswers = {Item = {type = T.string, kind = "default"}}
    local descriptor = reflection.describe(lines, "Lines")
    local associated = descriptor.types[descriptor.root].associatedTypes
    testAssert.equal(#associated, 1, "the associated requirement is reflected")
    testAssert.equal(associated[1].name, "Item", "associated name")
    testAssert.equal(descriptor.types[associated[1].bound].kind, "string", "associated bound")
    testAssert.equal(descriptor.types[associated[1].answer].kind, "string", "associated answer")
    testAssert.equal(associated[1].default, true, "a default answer is marked as one")
end

function M.reflectsExplicitTransferOnlyAffinity()
    local descriptor = reflection.describe(T.affine(T.string, nil, true), "OpaqueString")
    local root = descriptor.types[descriptor.root]
    testAssert.equal(root.kind, "affine")
    testAssert.equal(root.transferOnly, true, "reflection erased explicit transfer-only affinity")
end

function M.reflectsFieldDefaultsAndFingerprintsTheirValues()
    local first = recursiveNode(T.string)
    first.fieldDefaults = {value = {value = "first"}}
    local same = recursiveNode(T.string)
    same.fieldDefaults = {value = {value = "first"}}
    local changed = recursiveNode(T.string)
    changed.fieldDefaults = {value = {value = "second"}}
    local absent = recursiveNode(T.string)
    local firstDescriptor = reflection.describe(first, "Node")
    testAssert.equal(firstDescriptor.fields[1].hasDefault, true, "default presence")
    testAssert.equal(firstDescriptor.fields[1].defaultValue, "first", "default value")
    testAssert.equal(reflection.describe(absent, "Node").fields[1].hasDefault, false, "missing default")
    testAssert.equal(
        firstDescriptor.fingerprint,
        reflection.describe(same, "Node").fingerprint,
        "equal defaults fingerprint equally"
    )
    assert(
        firstDescriptor.fingerprint ~= reflection.describe(changed, "Node").fingerprint,
        "changing a default changes the fingerprint"
    )
end

function M.omitsPrivateFieldsFromSemanticReflection()
    local node = recursiveNode(T.string)
    node.privateFields = {next = true}
    node.moduleName = "models"
    local descriptor = reflection.describe(node, "Node")
    testAssert.equal(#descriptor.fields, 1, "only the public field is reflected")
    testAssert.equal(descriptor.fields[1].name, "value", "the reflected field is public")
end

function M.hiddenConstructionRequiresAnExplicitFactory()
    local node = recursiveNode(T.string)
    node.privateFields = {next = true}
    local description = reflection.describe(node, "Node")
    local construction = description.types[description.root].construction
    testAssert.equal(construction.requiresFactory, true)
    testAssert.equal(#construction.params, 1)
    assert(not description.fields[2], "private fields must stay hidden")
end

function M.storageFactsComeFromDeclarationsRatherThanFunctionTypes()
    local node = recursiveNode(T.string)
    local callback = T.func({}, {T.string}, false)
    node.byname.callback, node.byname.method = callback, callback
    node.writeByname.callback = callback
    node.fieldOrder[#node.fieldOrder + 1] = "callback"
    local description = reflection.describe(node, "Node")
    local stored = {}
    for _, field in ipairs(description.fields) do
        stored[field.name] = field.stored
    end
    testAssert.equal(stored.callback, true)
    testAssert.equal(stored.method, false)
    testAssert.equal(description.types[description.root].construction.requiresFactory, false)
end

function M.declaredConstructionRetainsItsEntryAndResult()
    local node = recursiveNode(T.string)
    node.privateFields = {next = true}
    local signature = T.func({T.string}, {node}, false)
    signature.paramNames = {"text"}
    node.constructorEntries = {{index = 2, signature = signature, result = node}}
    local description = reflection.describe(node, "Node")
    local construction = description.types[description.root].construction
    testAssert.equal(construction.declared, true)
    testAssert.equal(construction.requiresFactory, false)
    testAssert.equal(construction.index, 2)
    testAssert.equal(construction.result, description.root)
    testAssert.equal(construction.params[1].name, "text")
end

function M.fingerprintsSemanticsRatherThanNominalAllocationIdentity()
    local first = reflection.describe(recursiveNode(T.string), "Node")
    local second = reflection.describe(recursiveNode(T.string), "Node")
    local changed = reflection.describe(recursiveNode(T.number), "Node")
    testAssert.equal(first.fingerprint, second.fingerprint, "equivalent declarations ignore process-local nominal ids")
    assert(first.fingerprint ~= changed.fingerprint, "changing a reflected field changes the semantic fingerprint")
end

function M.fingerprintsResolvedDeclarationAndFieldAnnotations()
    local function annotated(recordName, fieldName)
        local node = recursiveNode(T.string)
        node.annotations = {{name = "json", arguments = {{name = "name", kind = "value", value = recordName},}}}
        node.fieldDefs = {
            value = {annotations = {{name = "json", arguments = {{name = "name", kind = "value", value = fieldName},}}}}
        }

        return reflection.describe(node, "Node")
    end

    local first = annotated("nodes", "payload")
    local same = annotated("nodes", "payload")
    local changedRecord = annotated("items", "payload")
    local changedField = annotated("nodes", "value")
    testAssert.equal(first.fingerprint, same.fingerprint, "equivalent semantic annotations fingerprint identically")
    assert(first.fingerprint ~= changedRecord.fingerprint, "record annotation values enter the fingerprint")
    assert(first.fingerprint ~= changedField.fingerprint, "field annotation values enter the fingerprint")
    testAssert.equal(first.annotations[1].arguments[1].value, "nodes", "record annotations are reflected")
    testAssert.equal(first.fields[1].annotations[1].arguments[1].value, "payload", "field annotations are reflected")
end

function M.coversStructuralFunctionsCollectionsAndCapabilities()
    local callback = T.func(
        {
            T.array(
                T.union({
                    T.string,
                    T.integer
                })
            )
        },
        {
            T.shape({
                {name = "readable", read = T.string},
                {name = "writable", write = T.number},
            })
        },
        false,
        {"borrows"},
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        true,
        {"values"}
    )
    local descriptor = reflection.describe(callback, "Callback")
    local kinds = {}
    for _, entry in ipairs(descriptor.types) do
        kinds[entry.kind] = true
    end
    for _, kind in ipairs({"func", "array", "union", "shape", "string", "integer", "number"}) do
        assert(kinds[kind], "descriptor includes " .. kind)
    end
    local fn = descriptor.types[descriptor.root]
    testAssert.equal(fn.parameters[1].name, "values", "parameter name")
    testAssert.equal(fn.parameters[1].mode, "borrows", "parameter mode")
    testAssert.equal(fn.noYield, true, "suspension guarantee")
    local result = descriptor.types[fn.returns[1]]
    testAssert.equal(result.fields[1].name, "readable", "shape fields are canonical")
    testAssert.equal(result.fields[1].readable, true, "read capability")
    testAssert.equal(result.fields[1].writable, false, "read-only capability")
    testAssert.equal(result.fields[2].readable, false, "write-only capability")
    testAssert.equal(result.fields[2].writable, true, "write capability")
end

function M.carriesConstBindersAndArrayTermsInTheSharedDescriptorVocabulary()
    local size = T.constvar("Size", "integer", "reflection:const")
    local count = T.constOp("*", {size, T.constLiteral("integer", 2)})
    local alias = T.genericAlias("Buffer", T.carray(T.uint8, nil, count), nil, nil, nil, {size}, {"const"})
    local descriptor = reflection.describe(alias, "Buffer")
    local root = descriptor.types[descriptor.root]
    testAssert.equal(root.parameterKinds[1], "const", "generic parameter kind")
    local parameter = descriptor.types[root.constParameters[1]]
    testAssert.equal(parameter.kind, "constVar", "const binder descriptor")
    testAssert.equal(parameter.domain, "integer", "const binder domain")
    local body = descriptor.types[root.body]
    local term = descriptor.types[body.countTerm]
    testAssert.equal(term.kind, "constOp", "C array count term")
    testAssert.equal(term.operation, "*", "C array count operation")
end

function M.carriesNominalPackParametersAndArguments()
    local results = T.packvar("Results", "reflection:results")
    local matcher = T.nominal("Matcher", "interface")
    matcher.packParams = {results}
    matcher.paramKinds = {"pack"}
    local concrete = generics.instantiate(matcher, {[results] = T.pack({T.string, T.integer}),})

    local declaration = reflection.describe(matcher, "Matcher")
    local declarationRoot = declaration.types[declaration.root]
    testAssert.equal(declarationRoot.parameterKinds[1], "pack", "nominal parameter kind")
    local parameter = declaration.types[declarationRoot.packParameters[1]]
    testAssert.equal(parameter.kind, "packvar", "nominal pack binder")

    local application = reflection.describe(concrete, "Matcher<(string, integer)>")
    local applicationRoot = application.types[application.root]
    local argument = application.types[applicationRoot.packArguments[1]]
    testAssert.equal(argument.kind, "pack", "nominal pack argument")
    testAssert.equal(#argument.head, 2, "nominal pack arity")
end

function M.carriesNominalTypeAndConstParametersAndArguments()
    local element = T.typevar("Element", "reflection:element")
    local size = T.constvar("Size", "integer", "reflection:size")
    local buffer = T.nominal("Buffer", "struct")
    buffer.typeParams = {element}
    buffer.typeBounds = {T.any}
    buffer.constParams = {size}
    buffer.paramKinds = {"type", "const"}

    local declaration = reflection.describe(buffer, "Buffer")
    local declarationRoot = declaration.types[declaration.root]
    testAssert.equal(declaration.types[declarationRoot.typeParameters[1]].kind, "typevar", "nominal type binder")
    testAssert.equal(declaration.types[declarationRoot.typeBounds[1]].kind, "any", "nominal type bound")
    testAssert.equal(declaration.types[declarationRoot.constParameters[1]].kind, "constVar", "nominal const binder")

    local concrete = generics.instantiate(buffer, {[element] = T.string, [size] = T.constLiteral("integer", 16),})
    local application = reflection.describe(concrete, "Buffer<string, 16>")
    local applicationRoot = application.types[application.root]
    testAssert.equal(application.types[applicationRoot.typeArguments[1]].kind, "string", "nominal type argument")
    local constArgument = application.types[applicationRoot.constArguments[1]]
    testAssert.equal(constArgument.kind, "constLiteral", "nominal const argument")
    testAssert.equal(constArgument.value, 16, "nominal const argument value")
end

function M.ordersNamedMetadataAndExcludesSourceIdentityFromFingerprints()
    local function described(reverse)
        local node = T.nominal("Node", "record")
        node.moduleName = "models"
        node.byname = reverse and {z = T.number, a = T.string} or {a = T.string, z = T.number}
        node.writeByname = reverse and {z = T.number, a = T.string} or {a = T.string, z = T.number}
        node.fieldOrder = {"z", "a"}
        node.staticByname = reverse and {z = T.number, a = T.string} or {a = T.string, z = T.number}
        node.staticWriteByname = reverse and {z = T.number, a = T.string} or {a = T.string, z = T.number}
        node.metamethods = reverse and {__tostring = T.string, __len = T.integer}
            or {__len = T.integer, __tostring = T.string}
        node.nestedTypes = reverse and {Zed = T.number, Alpha = T.string} or {Alpha = T.string, Zed = T.number}

        return reflection.describe(node, "models.Node", true)
    end

    local first = described(false)
    local second = described(true)
    testAssert.equal(
        first.fingerprint,
        second.fingerprint,
        "map insertion order does not change the semantic fingerprint"
    )
    testAssert.equal(first.fields[1].name, "z", "ordinary fields retain declaration order")
    local root = first.types[first.root]
    testAssert.equal(root.staticFields[1].name, "a", "static fields sort by name")
    testAssert.equal(root.metamethods[1].name, "__len", "metamethods sort by name")
    testAssert.equal(root.nestedTypes[1].name, "Alpha", "nested types sort by name")
    testAssert.equal(
        root.referenceFingerprint,
        reflection.describe(first.sources[first.root]).fingerprint,
        "source references carry their semantic fingerprint"
    )
    assert(root.nominalIdentity ~= nil, "source references retain sealed declaration identity")
end

return M
