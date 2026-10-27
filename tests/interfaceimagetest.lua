local testAssert = require("nupp.test")
local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.types.generics")
local interfaceimage = require("nupp.compiler.project.interfaceimage")
local reflection = require("nupp.compiler.reflection")
local stable = require("nupp.compiler.stable")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local PROJECT_PATHS = {"/project/producer.nupp", "/project/consumer.nupp", "/project/sample.nupp"}

local function semantic(name, exported)
    return {
        interface = {
            type = T.shape({
                {name = "value", read = exported}
            }),
        },
        exports = {
            types = {Value = exported},
            typeDefs = {},
            values = {value = exported},
            valueDefs = {},
            comptimeFunctions = {},
            callGuarantees = {},
        },
        path = "/project/" .. name:gsub("%.", "/") .. ".nupp",
    }
end

local function encode(semantics, options)
    options = options or {}
    options.projectPaths = options.projectPaths or PROJECT_PATHS
    return interfaceimage.encode(semantics, options)
end

-- The key the project index gives the first module-visible record `name` in `path`.
local function indexKey(path, name)
    return path .. "\0" .. name .. "\0record\0module\01"
end

local function indexed(name, path, kind)
    local nominal = T.nominal(name, kind or "record", indexKey(path, name))
    nominal.indexedPath = path
    nominal.fieldOrder = {}
    nominal.fieldDefs, nominal.writeFieldDefs = {}, {}
    nominal.staticFieldDefs, nominal.staticWriteFieldDefs = {}, {}

    return nominal
end

local function roundTrip(value)
    local image, encodeProblem = encode({sample = semantic("sample", value)})
    assert(image, encodeProblem)
    local decoded, decodeProblem = interfaceimage.decode(image)
    assert(decoded, decodeProblem)

    return decoded.sample.exports.types.Value, image
end

local M = {}

function M.roundTripsStructBitWidths()
    local packed = indexed("Packed", "/project/sample.nupp", "struct")
    packed.byname = {ready = T.boolean}
    packed.writeByname = {ready = T.boolean}
    packed.fieldOrder = {"ready"}
    packed.fieldDefs = {ready = {name = "ready", bitWidth = 1}}
    packed.writeFieldDefs = packed.fieldDefs
    local loaded = roundTrip(packed)
    testAssert.equal(loaded.fieldDefs.ready.bitWidth, 1, "stored bit width")
    testAssert.equal(loaded.writeFieldDefs.ready.bitWidth, 1, "writable bit width")
end

function M.vmLayoutsSupportUnionsAndRejectGenericStructs()
    local metadata = require("nupp.compiler.vm.metadata")
    local aggregate = indexed("Foreign", "/project/sample.nupp", "struct")
    aggregate.runtimeDeclarationKey = "sample\0runtime\0" .. "1"
    aggregate.byname = {value = T.int32}
    aggregate.fieldOrder = {"value"}
    aggregate.cdefKind = "union"
    local foreign = metadata.structLayout({resolvedType = aggregate}, "aarch64-apple-darwin")
    assert(foreign.supported and foreign.size == 4 and foreign.kind == "union")
    testAssert.equal(foreign.fields[1].offset, 0)
    aggregate.cdefKind = nil
    aggregate.typeParams = {T.typevar("Unused", "vm-layout:unused")}
    local generic = metadata.structLayout({resolvedType = aggregate}, "aarch64-apple-darwin")
    assert(not generic.supported and generic.size == nil)
    assert(generic.error:find("generic struct", 1, true))
end

-- A record's stored fields are its slots and the order its construction takes
-- them in. Its methods are members too, but neither: a decoded record that
-- counted them reflected a construction contract with a parameter for every
-- method, and a VM image lowered against it described a different record.
function M.storedFieldOrderLeavesMethodsOut()
    local command = indexed("Command", "/project/sample.nupp")
    command.byname = {verbose = T.boolean, run = T.func({}, {T.integer}), file = T.string,}
    command.writeByname = {verbose = T.boolean, run = T.func({}, {T.integer}), file = T.string}
    command.fieldOrder = {"verbose", "file"}
    local loaded = roundTrip(command)
    assert(
        table.concat(loaded.fieldOrder, ",") == "verbose,file",
        "decoded stored fields: " .. table.concat(loaded.fieldOrder, ",")
    )
    local checked = reflection.describe(command, "Command")
    local decoded = reflection.describe(loaded, "Command")
    local before = checked.types[checked.root].construction.params
    local after = decoded.types[decoded.root].construction.params
    assert(#before == 2 and #after == #before, "a method became a construction parameter")
end

function M.copyabilityIsPreservedAcrossInterfaceImages()
    local copyable = indexed("Copyable", "/project/sample.nupp", "interface")
    copyable.intrinsicCopyable = true
    local loaded = roundTrip(copyable)
    assert(loaded.intrinsicCopyable == true)
    local relations = require("nupp.compiler.types.relations")
    assert(relations.isA(T.string, loaded))
    assert(not relations.isA(T.borrowed(T.string), loaded))
end

-- One producer image may be restored into several independent environments.
local function selfBinderImage(name)
    local path = "/project/self-binder-" .. name .. ".nupp"
    local producer = indexed(name, path)
    local binder = T.typevar(name, path .. ":49:self:producer")
    producer.selfType, binder.bound = binder, producer
    local image, problem = encode({sample = semantic("sample", producer)})
    assert(image, problem)

    return image, producer, binder, path
end

function M.restoringASelfBinderDoesNotRebindItsProducer()
    local image, producer, binder, path = selfBinderImage("ProducerIsolation")
    local recipient = indexed("ProducerIsolation", path)
    assert(recipient ~= producer, "a separate environment owns its nominal")
    local decoded, problem = interfaceimage.decode(image, {nominals = {[producer.declarationKey] = recipient}})
    assert(decoded, problem)
    assert(binder.bound == producer, "restoring must not rebind the producer environment")
    assert(recipient.selfType ~= binder, "the recipient owns a separate self binder")
    assert(recipient.selfType.bound == recipient, "restored self binds the receiving nominal")
    assert(decoded.sample.exports.types.Value == recipient, "the exported edge uses the receiving nominal")
end

function M.restoringASelfBinderReusesTheSameRecipient()
    local image, producer, binder, path = selfBinderImage("RecipientReuse")
    local recipient = indexed("RecipientReuse", path)
    local options = {nominals = {[producer.declarationKey] = recipient}}
    local decoded, problem = interfaceimage.decode(image, options)
    assert(decoded, problem)
    local self = recipient.selfType
    decoded, problem = interfaceimage.decode(image, options)
    assert(decoded, problem)
    assert(recipient.selfType == self, "restoring into one recipient reuses its self binder")
    assert(self.bound == recipient, "the reused binder stays bound to its recipient")
    assert(binder.bound == producer, "repeated restore leaves the producer bound unchanged")
end

function M.restoringASelfBinderKeepsTwoRecipientsIsolated()
    local image, producer, binder, path = selfBinderImage("RecipientIsolation")
    local first = indexed("RecipientIsolation", path)
    local second = indexed("RecipientIsolation", path)
    assert(first ~= second and first ~= producer and second ~= producer)
    local decoded, problem = interfaceimage.decode(image, {nominals = {[producer.declarationKey] = first}})
    assert(decoded, problem)
    local firstSelf = first.selfType
    decoded, problem = interfaceimage.decode(image, {nominals = {[producer.declarationKey] = second}})
    assert(decoded, problem)
    assert(first.selfType == firstSelf and firstSelf.bound == first, "a later recipient leaves the first unchanged")
    assert(second.selfType ~= firstSelf and second.selfType.bound == second, "the second owns its self binder")
    assert(binder.bound == producer, "both recipients leave the producer bound unchanged")
end

function M.restoringDuplicateSelfIdentitiesKeepsEachOwnerBound()
    local firstPath = "/project/duplicate-self-first.nupp"
    local secondPath = "/project/duplicate-self-second.nupp"
    local first = indexed("DuplicateFirst", firstPath)
    local second = indexed("DuplicateSecond", secondPath)
    local firstBinder = T.typevar("DuplicateFirst", firstPath .. ":49:self:producer")
    local secondBinder = T.typevar("DuplicateSecond", secondPath .. ":49:self:producer")
    first.selfType, firstBinder.bound = firstBinder, first
    second.selfType, secondBinder.bound = secondBinder, second
    local image, problem = encode({first = semantic("first", first), second = semantic("second", second)})
    assert(image, problem)
    local sharedIdentity = "/project/duplicate-self:49:self:unbound"
    local binders = 0
    for _, node in ipairs(image.descriptor.types) do
        if node.kind == "typevar"
            and (node.identity == firstBinder.identity or node.identity == secondBinder.identity)
        then
            node.identity = sharedIdentity
            binders = binders + 1
        end
    end
    assert(binders == 2, "the fixture gives two reciprocal self binders one raw identity")
    local json = require("nupp.codec.json")
    local before = json.encode(image)
    local firstRecipient = indexed("DuplicateFirst", firstPath)
    local secondRecipient = indexed("DuplicateSecond", secondPath)
    local decoded
    decoded, problem = interfaceimage.decode(image, {
        nominals = {[first.declarationKey] = firstRecipient, [second.declarationKey] = secondRecipient,}
    })
    assert(decoded, problem)
    assert(
        firstRecipient.selfType ~= secondRecipient.selfType,
        "owners do not share an initially unbound interned binder"
    )
    assert(firstRecipient.selfType.bound == firstRecipient and secondRecipient.selfType.bound == secondRecipient)
    assert(firstBinder.bound == first and secondBinder.bound == second, "producer bounds remain unchanged")
    assert(json.encode(image) == before, "decoding does not rewrite the serialized payload")
end

function M.roundTripsRecursiveNominalMetadata()
    local self = T.typevar("self", "interface-image:self")
    local element = T.typevar("Element", "interface-image:element")
    local node = indexed("Node", "/project/sample.nupp")
    node.selfType = self
    node.typeParams = {element}
    node.typeBounds = {T.any}
    node.paramKinds = {"type"}
    node.paramDefaults = {T.string}
    node.byname = {value = element, next = T.optional(node)}
    node.writeByname = {value = element, next = T.optional(node)}
    node.fieldOrder = {"value", "next"}
    node.fieldDefs = {
        value = {
            name = "value",
            annotations = {{name = "wire", arguments = {{name = "name", kind = "value", value = "payload"},}},},
        },
    }
    node.writeFieldDefs = {}
    node.staticFieldDefs = {}
    node.staticWriteFieldDefs = {}
    node.predicate = {op = "truthy", path = {"value"}}
    node.associatedRequirements = {{name = "Item", bound = T.string, selfBinder = self, definition = {name = "Item"}}}
    node.associatedAnswers = {
        Item = {type = T.string, selfBinder = self, kind = "default", definition = {name = "Item"}},
    }

    local got = roundTrip(node)
    assert(got ~= node, "the decoder allocated its own nominal declaration")
    testAssert.equal(got.declarationKey, node.declarationKey, "declaration identity")
    testAssert.equal(got.byname.next.members[2], got, "recursive edge")
    testAssert.equal(got.typeParams[1].identity, element.identity, "generic binder identity")
    testAssert.equal(got.paramDefaults[1], T.string, "nominal generic default")
    testAssert.equal(got.predicate.path[1], "value", "refinement predicate")
    testAssert.equal(got.associatedRequirements[1].bound, T.string, "associated bound")
    testAssert.equal(got.associatedRequirements[1].definition.name, "Item", "associated requirement definition")
    testAssert.equal(got.associatedAnswers.Item.type, T.string, "associated answer")
    testAssert.equal(got.associatedAnswers.Item.kind, "default", "associated provenance")
    testAssert.equal(got.associatedAnswers.Item.definition.name, "Item", "associated answer definition")
    testAssert.equal(got.fieldDefs.value.annotations[1].name, "wire", "field annotations")
end

function M.roundTripsCallableContractsAndOverloadProvenance()
    local cleanup = T.methodCleanup("close")
    local signature = T.func(
        {T.ptr(T.string)},
        {T.string},
        false,
        {"borrows"},
        {param = 1, type = T.ptr(T.string)},
        nil,
        nil,
        1,
        true,
        {1},
        {
            {
                kind = "affine",
                name = "output",
                cleanups = {cleanup},
                transferOnly = true,
                valueType = T.string,
                cIndex = 2,
                hasStatus = true,
                success = "zero",
                sourceParams = {1},
                returnIndex = 1,
            }
        },
        nil,
        false,
        nil,
        nil,
        nil,
        nil,
        nil,
        true,
        {"source"},
        {1},
        true,
        nil,
        nil,
        nil,
        false,
        {[1] = true},
        true,
        1
    )
    local api = indexed("Api", "/project/sample.nupp", "interface")
    api.byname = {read = signature}
    api.writeByname = {}
    api.staticByname = {}
    api.staticWriteByname = {}
    api.fieldOrder = {"read"}
    api.fieldDefs = {read = {name = "read"}}
    api.writeFieldDefs = {}
    api.staticFieldDefs = {}
    api.staticWriteFieldDefs = {}
    api.methodEntries = {
        read = {{signature = signature, member = 3, parameterKey = "source", definition = {name = "read"},}},
    }
    api.methodDispatchEntries = api.methodEntries
    api.staticEntries = {}
    api.overloadedMethods = {read = true}
    api.overloadedStatics = {}
    api.defaultEntries = {}

    local got = roundTrip(api)
    local fn = got.byname.read
    testAssert.equal(fn.paramNames[1], "source", "parameter name")
    testAssert.equal(fn.paramModes[1], "borrows", "parameter mode")
    testAssert.equal(fn.predicate.param, 1, "predicate parameter")
    testAssert.equal(fn.borrowsParam, 1, "borrow source")
    testAssert.equal(fn.borrowsSelf, true, "receiver borrow")
    testAssert.equal(fn.noYield, true, "suspension contract")
    testAssert.equal(fn.foreign, true, "foreign contract")
    testAssert.equal(fn.sendable, true, "sendability contract")
    testAssert.equal(fn.ffiOut[1].success, "zero", "foreign output success policy")
    testAssert.equal(fn.ffiOut[1].cleanups[1].name, "close", "foreign output cleanup")
    testAssert.equal(got.methodEntries.read[1].member, 3, "overload runtime member")
    testAssert.equal(got.methodEntries.read[1].definition.name, "read", "overload definition")
    testAssert.equal(got.overloadedMethods.read, true, "overload marker")
end

function M.referencesPreviouslyLoadedStructuralArenas()
    local origins, encodedArenas = {}, {}
    local shared = T.func(
        {T.string},
        {T.integer},
        false,
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
        nil,
        nil,
        {"text"}
    )
    local producer = assert(
        encode({producer = semantic("producer", shared)}, {
            origins = origins,
            arenas = encodedArenas
        })
    )
    local consumer = assert(
        encode({consumer = semantic("consumer", shared)}, {
            origins = origins,
            arenas = encodedArenas
        })
    )
    assert(producer.fingerprint ~= consumer.fingerprint, "each image names its own arena")
    local external = false
    for _, node in ipairs(consumer.descriptor.types) do
        external = external or node.kind == "external" and node.arena == producer.fingerprint
    end
    assert(external, "the consumer references the producer arena")

    local decodedArenas, decodedOrigins = {}, {}
    local first = assert(
        interfaceimage.decode(producer, {
            nominals = {},
            arenas = decodedArenas,
            origins = decodedOrigins
        })
    )
    local second = assert(
        interfaceimage.decode(consumer, {
            nominals = {},
            arenas = decodedArenas,
            origins = decodedOrigins
        })
    )
    testAssert.equal(second.consumer.exports.types.Value, first.producer.exports.types.Value, "mounted arena identity")

    local decoded, problem = interfaceimage.decode(consumer, {arenas = {}})
    testAssert.equal(decoded, nil, "missing arena")
    assert(problem:find("unavailable arena", 1, true), problem)
end

function M.roundTripsDefinitionsComptimeProgramsEffectsAndDiagnostics()
    local value = T.func(
        {T.string},
        {T.integer},
        false,
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
        nil,
        nil,
        {"text"}
    )
    local sample = semantic("sample", value)
    sample.exports.typeDefs.Value = {
        filename = "/project/sample.nupp",
        name = "Value",
        kind = "type",
        deprecated = {reason = "old", replacement = "Other"},
        exactCallExport = {module = "sample", member = "Value", identity = "sample.Value"},
    }
    sample.exports.valueDefs.value = {
        filename = "/project/sample.nupp",
        name = "value",
        kind = "value",
        comptimeOnly = true,
    }
    sample.exports.nominalEffectFingerprint = "effects"
    sample.exports.deriveInterfaceFingerprint = "derives"
    sample.exports.comptimeFunctionFingerprint = "comptime"
    sample.exports.callGuarantees = {
        value = {
            noYield = true,
            effects = {"io.read"},
            callableEffects = {summary = {raises = true, raisesBeyondBounds = false}, paramNames = {"view", "index"}},
            callableRelations = {
                version = 1,
                complete = true,
                accesses = {{view = 1, index = 2}},
                result = {view = 1, alternative = "non-nil"}
            },
            inlineBody = {
                version = 1,
                params = {{name = "value", type = "number"}},
                expression = {kind = "parameter", position = 1},
                size = 1
            },
            representation = {
                version = 1,
                parameters = {{position = 1, mode = "borrowed", stableCount = true, alias = "unknown"}}
            }
        }
    }
    sample.exports.comptimeFunctions.Make = {
        sealedTypeFunction = true,
        identity = "sample.Make",
        main = "return 1",
        serializedHelpers = {"helper"},
        signature = value,
        definition = {filename = "/project/sample.nupp", name = "Make", kind = "function"},
        bodyFingerprint = "body",
        deriveProvider = true,
        deriveInterface = T.shape({{name = "made", read = T.string}}),
        providerModule = "sample.provider",
        providerModuleLocal = "provider",
        runtimeHelpers = {"runtime.helper"},
    }
    sample.diags = {{code = "NUPP2001", msg = "fixture diagnostic"}}
    sample.source = "return sample"

    local image = assert(encode({sample = sample}))
    local decoded = assert(interfaceimage.decode(image)).sample
    local exports = decoded.exports
    testAssert.equal(exports.nominalEffectFingerprint, "effects", "nominal effect fingerprint")
    testAssert.equal(exports.deriveInterfaceFingerprint, "derives", "derive interface fingerprint")
    testAssert.equal(exports.comptimeFunctionFingerprint, "comptime", "comptime fingerprint")
    testAssert.equal(exports.callGuarantees.value.effects[1], "io.read", "call effects")
    testAssert.equal(exports.callGuarantees.value.callableEffects.summary.raisesBeyondBounds, false)
    testAssert.equal(exports.callGuarantees.value.callableRelations.accesses[1].index, 2)
    testAssert.equal(exports.callGuarantees.value.inlineBody.expression.position, 1)
    testAssert.equal(exports.callGuarantees.value.representation.parameters[1].mode, "borrowed")
    testAssert.equal(exports.typeDefs.Value.deprecated.replacement, "Other", "type definition metadata")
    testAssert.equal(exports.typeDefs.Value.exactCallExport.identity, "sample.Value", "exact call export")
    testAssert.equal(exports.valueDefs.value.comptimeOnly, true, "value definition metadata")
    testAssert.equal(exports.comptimeFunctions.Make.signature.tag, "func", "comptime signature")
    testAssert.equal(exports.comptimeFunctions.Make.deriveInterface.tag, "shape", "derive interface")
    testAssert.equal(exports.comptimeFunctions.Make.runtimeHelpers[1], "runtime.helper", "runtime helpers")
    testAssert.equal(decoded.diags[1].code, "NUPP2001", "diagnostics")
    testAssert.equal(decoded.source, "return sample", "source")
end

function M.rejectsUnknownSchemasAndMalformedGraphs()
    local image = select(2, roundTrip(T.string))
    local schema = image.schema
    image.schema = schema + 1
    local decoded, problem = interfaceimage.decode(image)
    testAssert.equal(decoded, nil, "unknown schema")
    assert(problem:find("malformed", 1, true), problem)
    image.schema = schema

    image.descriptor.types[#image.descriptor.types + 1] = {kind = "tuple", members = {#image.descriptor.types + 7}}
    decoded, problem = interfaceimage.decode(image)
    testAssert.equal(decoded, nil, "dangling edge")
    assert(problem:find("invalid type edge", 1, true), problem)
end

function M.referencesAnotherFilesIndexedDeclarationByKey()
    local producerPath = "/project/producer.nupp"
    local declared = indexed("Shared", producerPath)
    local image = assert(encode({consumer = semantic("consumer", declared)}))
    local external = false
    for _, node in ipairs(image.descriptor.types) do
        if node.nominal then
            assert(node.external, "an indexed declaration of another file is not described again")
            testAssert.equal(node.declarationKey, indexKey(producerPath, "Shared"), "declaration key")
            testAssert.equal(node.fields, nil, "an external declaration carries no members")
            external = true
        end
    end
    assert(external, "the image references the declaration")

    local decoded, problem = interfaceimage.decode(image, {nominals = {}})
    testAssert.equal(decoded, nil, "an unindexed reader")
    assert(problem:find("unavailable declaration", 1, true), problem)

    local own = indexed("Shared", producerPath)
    own.selfType = T.typevar("self", "interface-image:shared-self")
    local loaded = assert(interfaceimage.decode(image, {nominals = {[indexKey(producerPath, "Shared")] = own}}))
    testAssert.equal(loaded.consumer.exports.types.Value, own, "the reader's own declaration")

    -- The same declaration owned by the image is described in full.
    local owned = assert(encode({producer = semantic("producer", declared)}))
    for _, node in ipairs(owned.descriptor.types) do
        if node.nominal then
            assert(not node.external, "an image describes its own declarations")
        end
    end
end

function M.givesEveryNominalItsOwnIdWhateverItsKey()
    local first = T.nominal("Twin", "record", "/project/sample.nupp\0" .. "1\0record")
    local second = T.nominal("Twin", "record", "/project/sample.nupp\0" .. "1\0record")
    assert(first.id ~= second.id, "two nominals with one key share an id")
    testAssert.equal(first.declarationKey, second.declarationKey, "declaration key")
    testAssert.equal(T.nestedDeclarationKey(first, 12), first.declarationKey .. "\0nested\0" .. "12", "nested key")
    testAssert.equal(T.nestedDeclarationKey(T.nominal("Keyless", "record"), 12), nil, "keyless owner")
end

function M.decodesApplicationsThroughGenerics()
    local element = T.typevar("Element", "interface-image:box-element")
    local box = indexed("Box", "/project/sample.nupp")
    box.typeParams = {element}
    box.paramKinds = {"type"}
    box.byname = {value = element, next = nil}
    box.writeByname = {value = element}
    box.fieldOrder = {"value", "next"}
    local applied = generics.instantiate(box, {[element] = T.integer})
    -- A declaration that mentions an application of itself.
    box.byname.next = T.optional(applied)
    box.writeByname.next = T.optional(applied)
    applied = generics.instantiate(box, {[element] = T.integer})
    local sample = semantic("sample", applied)
    sample.exports.types.Box = box

    local image = assert(encode({sample = sample}))
    for _, node in ipairs(image.descriptor.types) do
        if node.instantiation then
            testAssert.equal(node.fields, nil, "an application is its declaration and arguments")
            testAssert.equal(node.declarationKey, nil, "an application has no declaration key")
        end
    end
    local exports = assert(interfaceimage.decode(image)).sample.exports
    local decodedBox = exports.types.Box
    local decodedApplied = exports.types.Value
    assert(decodedBox ~= box, "the reader allocated its own declaration")
    testAssert.equal(decodedApplied.origin, decodedBox, "application origin")
    testAssert.equal(decodedApplied.typeArgs[1], T.integer, "application argument")
    testAssert.equal(
        generics.instantiate(decodedBox, {
            [decodedBox.typeParams[1]] = T.integer
        }),
        decodedApplied,
        "the reader's own application is the decoded one"
    )
    testAssert.equal(decodedApplied.byname.value, T.integer, "members come from the declaration")
    local recursive = false
    for _, member in ipairs(decodedApplied.byname.next.members) do
        recursive = recursive or member == decodedApplied
    end
    assert(recursive, "recursive application")
end

function M.completesSharedRecursiveApplicationsInOneDecodeWalk()
    local count = 16
    local parameter = T.typevar("Element", "interface-image:refresh-batch")
    local declarations, open, concrete = {}, {}, {}
    for index = 1, count do
        local declaration = indexed("Batch" .. index, "/project/sample.nupp")
        declaration.typeParams, declaration.paramKinds = {parameter}, {"type"}
        declaration.fieldOrder = {"value", "next", "method"}
        declarations[index] = declaration
        open[index] = generics.reserveInstantiation(declaration, {[parameter] = parameter})
    end
    for index, declaration in ipairs(declarations) do
        declaration.byname = {
            value = parameter,
            next = open[index % count + 1],
            method = T.func({parameter}, {
                parameter
            }),
        }
        declaration.writeByname = {value = parameter, next = open[index % count + 1]}
    end
    for index, declaration in ipairs(declarations) do
        concrete[index] = generics.instantiate(declaration, {[parameter] = T.integer})
    end
    local sample = semantic("sample", concrete[1])
    for index, declaration in ipairs(declarations) do
        sample.exports.types["Declaration" .. index] = declaration
        sample.exports.types["Application" .. index] = concrete[index]
    end
    local image = assert(encode({sample = sample}))
    local instantiate, visits = generics.instantiate, 0
    generics.instantiate = function(declaration, bindings)
        visits = visits + 1
        assert(visits <= count * 8, "interface completion repeats overlapping generic walks")
        return instantiate(declaration, bindings)
    end
    local ok, decoded = pcall(interfaceimage.decode, image)
    generics.instantiate = instantiate
    assert(ok and decoded, tostring(decoded))
    local exports = decoded.sample.exports.types
    for index = 1, count do
        local application = exports["Application" .. index]
        testAssert.equal(application.byname.value, T.integer)
        testAssert.equal(application.byname.next, exports["Application" .. (index % count + 1)])
        testAssert.equal(application.byname.method.params[1], T.integer)
    end
    local declaration = exports.Declaration1
    declaration.byname.late = T.string
    local application = generics.instantiate(declaration, {[declaration.typeParams[1]] = T.integer})
    testAssert.equal(application, exports.Application1)
    testAssert.equal(application.byname.late, T.string, "post-batch changes remain visible")
end

function M.failedCompletionBatchesRestoreEnclosingRefreshScope()
    local parameter = T.typevar("Element", "interface-image:failed-batch")
    local first, nested = T.nominal("OuterBatch", "record"), T.nominal("InnerBatch", "record")
    first.typeParams, nested.typeParams = {parameter}, {parameter}
    first.byname.method = T.func({parameter}, {parameter})
    nested.byname.value = parameter
    local trigger, failure = T.nominal("BatchTrigger", "record"), T.nominal("BatchFailure", "record")
    local bindings = {[parameter] = T.integer}
    local instantiate, funcWith, outerRefreshes = generics.instantiate, T.funcWith, 0
    T.funcWith = function(fn, overrides)
        if fn == first.byname.method then
            outerRefreshes = outerRefreshes + 1
        end
        return funcWith(fn, overrides)
    end
    generics.instantiate = function(declaration, map)
        if declaration == failure then
            error("completion failure", 0)
        elseif declaration == trigger then
            local ok, problem = pcall(generics.completeInstantiations, {
                {origin = nested, map = bindings},
                {origin = failure, map = {}},
            })
            assert(not ok and tostring(problem):find("completion failure", 1, true))
            nested.byname.late = T.string
            local retried = generics.instantiate(nested, bindings)
            testAssert.equal(retried.byname.late, T.string, "failed nested visits must not leak")
        end

        return instantiate(declaration, map)
    end
    local ok, problem = pcall(generics.completeInstantiations, {
        {origin = first, map = bindings},
        {origin = trigger, map = {}},
        {origin = first, map = bindings},
        {origin = failure, map = {}},
    })
    generics.instantiate, T.funcWith = instantiate, funcWith
    assert(not ok and tostring(problem):find("completion failure", 1, true))
    testAssert.equal(outerRefreshes, 1, "nested failure restores the enclosing visited set")
    first.byname.afterFailure = T.boolean
    testAssert.equal(generics.instantiate(first, bindings).byname.afterFailure, T.boolean)
end

function M.loadsABinderWhoseBoundMentionsItself()
    local item = T.typevar("Item", "interface-image:self-bound")
    item.bound = T.shape({{name = "next", read = T.optional(item)}})
    local signature = T.func({item}, {item}, false, nil, nil, {item}, {item.bound})
    local got = roundTrip(signature)
    local binder = got.typeParams[1]
    testAssert.equal(binder.bound.tag, "shape", "self-referential bound")
end

function M.keepsDefaultsAfterAHole()
    local first = T.typevar("First", "interface-image:hole-first")
    local second = T.typevar("Second", "interface-image:hole-second")
    local pair = indexed("Pair", "/project/sample.nupp")
    pair.typeParams = {first, second}
    pair.paramKinds = {"type", "type"}
    pair.paramDefaults = {[2] = T.string}
    local got = roundTrip(pair)
    testAssert.equal(got.paramDefaults[1], nil, "parameter without a default")
    testAssert.equal(got.paramDefaults[2], T.string, "default after a hole")
end

function M.keepsTransportStateOutOfThePublicDescriptor()
    local parser = require("nupp.compiler.syntax.parser")
    local program = require("program")
    local check = require("fragment")
    local envMod = require("nupp.compiler.project.env")
    local env = envMod.new(HERE .. "/..")

    local function compile(source)
        local parsed = parser.parse(source, "model.nupp")
        testAssert.equal(#parsed.errors, 0, "syntax errors")
        local diagnostics = check.check(parsed, "model.nupp", env)
        testAssert.equal(#diagnostics, 0, "diagnostics")
        local stat = parsed.root.blocks[1].stats[1]
        while stat and stat.kind == "pragmaStmt" do
            stat = stat.stat
        end

        local nominal = assert(stat.hoistedType)

        return program.image(parsed, "model"), nominal
    end

    local source = [[
@derive(nupp.derive.Debug)
local record Model
    value: integer
end
]]
    local image, nominal = compile(source)
    local movedImage, moved = compile("-- a comment above the record\n\n" .. source)
    local descriptor = reflection.describe(nominal, "Model")
    for _, text in ipairs({stable(descriptor), image, movedImage}) do
        assert(not text:find("declarationKey", 1, true), "transport state reached the public descriptor")
        assert(not text:find("privateFields", 1, true), "transport state reached the public descriptor")
    end
    testAssert.equal(
        reflection.describe(moved, "Model").fingerprint,
        descriptor.fingerprint,
        "fingerprint after moving"
    )
end

function M.vmMetadataLiteralsPreserveBinaryIdentity()
    local metadata = require("nupp.compiler.vm.metadata")
    for _, value in ipairs({"module\0runtime\0" .. "1", "\1" .. "23", "\255\0\"\\"}) do
        local literal = metadata.literal(value)
        testAssert.equal(assert(loadstring("return " .. literal.token.text))(), value)
    end
end

function M.fragmentRuntimeIdentitiesBelongToTheCheckedModule()
    local parser = require("nupp.compiler.syntax.parser")
    local check = require("fragment")
    local program = require("program")
    local env = require("nupp.compiler.project.env").new(HERE .. "/..")
    local source = [[
local struct Value
    x: int32
end
local original = new Value(7)
local function read(): int32
    return original.x
end
local function matches(value: unknown): boolean
    return value is Value
end
return {value = original, read = read, matches = matches}
]]

    local function fresh(moduleName, text)
        local filename = moduleName .. ".nupp"
        local parsed = parser.parse(text or source, filename)
        testAssert.equal(#parsed.errors, 0, "fixture parses")
        local diagnostics = check.check(parsed, filename, env, {moduleName = moduleName})
        testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].code .. ": " .. diagnostics[1].msg)

        return parsed, parsed.root.blocks[1].stats[1].resolvedType
    end

    local first, nominalA = fresh("fragment_identity_a")
    local keyA = nominalA.runtimeDeclarationKey
    local imageA = program.image(first, "fragment_identity_a")
    testAssert.equal(#check.check(first, "fragment_identity_a.nupp", env, {moduleName = "fragment_identity_a"}), 0)
    testAssert.equal(program.image(first, "fragment_identity_a"), imageA, "same-unit AST recheck is deterministic")
    local a = program.run(first, "fragment_identity_a")
    local second, nominalB = fresh("fragment_identity_b")
    assert(nominalA ~= nominalB, "independent units must not share checker-owned nominal facts")
    assert(keyA ~= nominalB.runtimeDeclarationKey, "identical source under two unit names must have distinct keys")
    testAssert.equal(nominalA.runtimeDeclarationKey, keyA, "checking another unit must not mutate the first nominal")
    local b = program.run(second, "fragment_identity_b")
    testAssert.equal(a.read(), 7, "old native values remain live after loading another unit")
    testAssert.equal(b.read(), 7)
    testAssert.equal(a.matches(a.value), true)
    testAssert.equal(a.matches(b.value), false, "matching layouts do not make independent nominal types identical")
    local repeated = fresh("fragment_identity_a")
    testAssert.equal(
        program.image(repeated, "fragment_identity_a"),
        imageA,
        "fresh same-unit checking is deterministic"
    )
    if program.onVm() then
        local changed = fresh("fragment_identity_a", source:gsub("int32", "float64"))
        local ok, problem = pcall(program.run, changed, "fragment_identity_a")
        assert(not ok and tostring(problem):find("conflicting native struct declaration", 1, true), tostring(problem))
        testAssert.equal(a.read(), 7, "a rejected layout replacement preserves old values")
    end
end

return M
