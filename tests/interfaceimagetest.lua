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

function M.copyabilityIsPreservedAcrossInterfaceImages()
    local copyable = indexed("Copyable", "/project/sample.nupp", "interface")
    copyable.intrinsicCopyable = true
    local loaded = roundTrip(copyable)
    assert(loaded.intrinsicCopyable == true)
    local relations = require("nupp.compiler.types.relations")
    assert(relations.isA(T.string, loaded))
    assert(not relations.isA(T.borrowed(T.string), loaded))
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
    local gen = require("nupp.compiler.lua.gen")
    local check = require("fragment")
    local envMod = require("nupp.compiler.project.env")
    local env = envMod.new(HERE .. "/..")

    local function compile(source)
        local parsed = parser.parse(source, "model.g.nupp")
        testAssert.equal(#parsed.errors, 0, "syntax errors")
        local diagnostics = check.check(parsed, "model.g.nupp", env)
        testAssert.equal(#diagnostics, 0, "diagnostics")
        local code = gen.generate(parsed, "model")
        local stat = parsed.root.blocks[1].stats[1]
        while stat and stat.kind == "pragmaStmt" do
            stat = stat.stat
        end

        return code, assert(stat.hoistedType)
    end

    local source = [[
@derive(nupp.derive.Debug)
local record Model
    value: integer
end
]]
    local code, nominal = compile(source)
    local movedCode, moved = compile("-- a comment above the record\n\n" .. source)
    local descriptor = reflection.describe(nominal, "Model")
    for _, text in ipairs({stable(descriptor), code, movedCode}) do
        assert(not text:find("declarationKey", 1, true), "transport state reached the public descriptor")
        assert(not text:find("privateFields", 1, true), "transport state reached the public descriptor")
    end
    testAssert.equal(
        reflection.describe(moved, "Model").fingerprint,
        descriptor.fingerprint,
        "fingerprint after moving"
    )
end

return M
