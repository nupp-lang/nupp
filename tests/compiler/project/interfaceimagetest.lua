local testAssert = require("assert")
local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.types.generics")
local interfaceimage = require("nupp.compiler.project.interfaceimage")
local reflection = require("nupp.compiler.reflection")
local stable = require("nupp.compiler.stable")

local HERE = require("helpers.paths").tests
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
    testAssert.eq(got.declarationKey, node.declarationKey, "declaration identity")
    testAssert.eq(got.byname.next.members[2], got, "recursive edge")
    testAssert.eq(got.typeParams[1].identity, element.identity, "generic binder identity")
    testAssert.eq(got.paramDefaults[1], T.string, "nominal generic default")
    testAssert.eq(got.predicate.path[1], "value", "refinement predicate")
    testAssert.eq(got.associatedRequirements[1].bound, T.string, "associated bound")
    testAssert.eq(got.associatedRequirements[1].definition.name, "Item", "associated requirement definition")
    testAssert.eq(got.associatedAnswers.Item.type, T.string, "associated answer")
    testAssert.eq(got.associatedAnswers.Item.kind, "default", "associated provenance")
    testAssert.eq(got.associatedAnswers.Item.definition.name, "Item", "associated answer definition")
    testAssert.eq(got.fieldDefs.value.annotations[1].name, "wire", "field annotations")
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
    testAssert.eq(fn.paramNames[1], "source", "parameter name")
    testAssert.eq(fn.paramModes[1], "borrows", "parameter mode")
    testAssert.eq(fn.predicate.param, 1, "predicate parameter")
    testAssert.eq(fn.borrowsParam, 1, "borrow source")
    testAssert.eq(fn.borrowsSelf, true, "receiver borrow")
    testAssert.eq(fn.noYield, true, "suspension contract")
    testAssert.eq(fn.foreign, true, "foreign contract")
    testAssert.eq(fn.sendable, true, "sendability contract")
    testAssert.eq(fn.ffiOut[1].success, "zero", "foreign output success policy")
    testAssert.eq(fn.ffiOut[1].cleanups[1].name, "close", "foreign output cleanup")
    testAssert.eq(got.methodEntries.read[1].member, 3, "overload runtime member")
    testAssert.eq(got.methodEntries.read[1].definition.name, "read", "overload definition")
    testAssert.eq(got.overloadedMethods.read, true, "overload marker")
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
    testAssert.eq(second.consumer.exports.types.Value, first.producer.exports.types.Value, "mounted arena identity")

    local decoded, problem = interfaceimage.decode(consumer, {arenas = {}})
    testAssert.eq(decoded, nil, "missing arena")
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
    testAssert.eq(exports.nominalEffectFingerprint, "effects", "nominal effect fingerprint")
    testAssert.eq(exports.deriveInterfaceFingerprint, "derives", "derive interface fingerprint")
    testAssert.eq(exports.comptimeFunctionFingerprint, "comptime", "comptime fingerprint")
    testAssert.eq(exports.callGuarantees.value.effects[1], "io.read", "call effects")
    testAssert.eq(exports.callGuarantees.value.callableEffects.summary.raisesBeyondBounds, false)
    testAssert.eq(exports.callGuarantees.value.callableRelations.accesses[1].index, 2)
    testAssert.eq(exports.callGuarantees.value.inlineBody.expression.position, 1)
    testAssert.eq(exports.callGuarantees.value.representation.parameters[1].mode, "borrowed")
    testAssert.eq(exports.typeDefs.Value.deprecated.replacement, "Other", "type definition metadata")
    testAssert.eq(exports.typeDefs.Value.exactCallExport.identity, "sample.Value", "exact call export")
    testAssert.eq(exports.valueDefs.value.comptimeOnly, true, "value definition metadata")
    testAssert.eq(exports.comptimeFunctions.Make.signature.tag, "func", "comptime signature")
    testAssert.eq(exports.comptimeFunctions.Make.deriveInterface.tag, "shape", "derive interface")
    testAssert.eq(exports.comptimeFunctions.Make.runtimeHelpers[1], "runtime.helper", "runtime helpers")
    testAssert.eq(decoded.diags[1].code, "NUPP2001", "diagnostics")
    testAssert.eq(decoded.source, "return sample", "source")
end

function M.rejectsUnknownSchemasAndMalformedGraphs()
    local image = select(2, roundTrip(T.string))
    local schema = image.schema
    image.schema = schema + 1
    local decoded, problem = interfaceimage.decode(image)
    testAssert.eq(decoded, nil, "unknown schema")
    assert(problem:find("malformed", 1, true), problem)
    image.schema = schema

    image.descriptor.types[#image.descriptor.types + 1] = {kind = "tuple", members = {#image.descriptor.types + 7}}
    decoded, problem = interfaceimage.decode(image)
    testAssert.eq(decoded, nil, "dangling edge")
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
            testAssert.eq(node.declarationKey, indexKey(producerPath, "Shared"), "declaration key")
            testAssert.eq(node.fields, nil, "an external declaration carries no members")
            external = true
        end
    end
    assert(external, "the image references the declaration")

    local decoded, problem = interfaceimage.decode(image, {nominals = {}})
    testAssert.eq(decoded, nil, "an unindexed reader")
    assert(problem:find("unavailable declaration", 1, true), problem)

    local own = indexed("Shared", producerPath)
    own.selfType = T.typevar("self", "interface-image:shared-self")
    local loaded = assert(interfaceimage.decode(image, {nominals = {[indexKey(producerPath, "Shared")] = own}}))
    testAssert.eq(loaded.consumer.exports.types.Value, own, "the reader's own declaration")

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
    testAssert.eq(first.declarationKey, second.declarationKey, "declaration key")
    testAssert.eq(T.nestedDeclarationKey(first, 12), first.declarationKey .. "\0nested\0" .. "12", "nested key")
    testAssert.eq(T.nestedDeclarationKey(T.nominal("Keyless", "record"), 12), nil, "keyless owner")
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
            testAssert.eq(node.fields, nil, "an application is its declaration and arguments")
            testAssert.eq(node.declarationKey, nil, "an application has no declaration key")
        end
    end
    local exports = assert(interfaceimage.decode(image)).sample.exports
    local decodedBox = exports.types.Box
    local decodedApplied = exports.types.Value
    assert(decodedBox ~= box, "the reader allocated its own declaration")
    testAssert.eq(decodedApplied.origin, decodedBox, "application origin")
    testAssert.eq(decodedApplied.typeArgs[1], T.integer, "application argument")
    testAssert.eq(
        generics.instantiate(decodedBox, {
            [decodedBox.typeParams[1]] = T.integer
        }),
        decodedApplied,
        "the reader's own application is the decoded one"
    )
    testAssert.eq(decodedApplied.byname.value, T.integer, "members come from the declaration")
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
    testAssert.eq(binder.bound.tag, "shape", "self-referential bound")
end

function M.keepsDefaultsAfterAHole()
    local first = T.typevar("First", "interface-image:hole-first")
    local second = T.typevar("Second", "interface-image:hole-second")
    local pair = indexed("Pair", "/project/sample.nupp")
    pair.typeParams = {first, second}
    pair.paramKinds = {"type", "type"}
    pair.paramDefaults = {[2] = T.string}
    local got = roundTrip(pair)
    testAssert.eq(got.paramDefaults[1], nil, "parameter without a default")
    testAssert.eq(got.paramDefaults[2], T.string, "default after a hole")
end

function M.keepsTransportStateOutOfThePublicDescriptor()
    local parser = require("nupp.compiler.syntax.parser")
    local gen = require("nupp.compiler.lua.gen")
    local check = require("helpers.fragment")
    local envMod = require("nupp.compiler.project.env")
    local env = envMod.new(HERE .. "/..")

    local function compile(source)
        local parsed = parser.parse(source, "model.nupp")
        testAssert.eq(#parsed.errors, 0, "syntax errors")
        local diagnostics = check.check(parsed, "model.nupp", env)
        testAssert.eq(#diagnostics, 0, "diagnostics")
        local code = gen.generate(parsed, "model")
        local stat = parsed.root.blocks[1].stats[1]
        while stat and stat.kind == "pragmaStmt" do
            stat = stat.stat
        end

        return code, assert(stat.hoistedType)
    end

    local source = [[
@derive(types.debug)
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
    testAssert.eq(reflection.describe(moved, "Model").fingerprint, descriptor.fingerprint, "fingerprint after moving")
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
        testAssert.eq(application.byname.value, T.integer)
        testAssert.eq(application.byname.next, exports["Application" .. (index % count + 1)])
        testAssert.eq(application.byname.method.params[1], T.integer)
    end
    local declaration = exports.Declaration1
    declaration.byname.late = T.string
    local application = generics.instantiate(declaration, {[declaration.typeParams[1]] = T.integer})
    testAssert.eq(application, exports.Application1)
    testAssert.eq(application.byname.late, T.string, "post-batch changes remain visible")
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
            testAssert.eq(retried.byname.late, T.string, "failed nested visits must not leak")
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
    testAssert.eq(outerRefreshes, 1, "nested failure restores the enclosing visited set")
    first.byname.afterFailure = T.boolean
    testAssert.eq(generics.instantiate(first, bindings).byname.afterFailure, T.boolean)
end

return M
