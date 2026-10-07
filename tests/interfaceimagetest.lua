local T = require("nupp.compiler.types")
local interfaceimage = require("nupp.compiler.project.interfaceimage")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

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
        projectPaths = {"/project/producer.nupp", "/project/consumer.nupp"},
    }
end

local function roundTrip(value)
    local image, encodeProblem = interfaceimage.encode({sample = semantic("sample", value)})
    assert(image, encodeProblem)
    local decoded, _, decodeProblem = interfaceimage.decode(image)
    assert(decoded, decodeProblem)

    return decoded.sample.exports.types.Value, image
end

local M = {}

function M.roundTripsRecursiveNominalMetadata()
    local self = T.typevar("self", "interface-image:self")
    local element = T.typevar("Element", "interface-image:element")
    local node = T.nominal("Node", "record", "/project/sample.nupp\0module\0type\0Node")
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
    assertEq(got.declarationKey, node.declarationKey, "declaration identity")
    assertEq(got.byname.next.members[2], got, "recursive edge")
    assertEq(got.typeParams[1].identity, element.identity, "generic binder identity")
    assertEq(got.paramDefaults[1], T.string, "nominal generic default")
    assertEq(got.predicate.path[1], "value", "refinement predicate")
    assertEq(got.associatedRequirements[1].bound, T.string, "associated bound")
    assertEq(got.associatedRequirements[1].definition.name, "Item", "associated requirement definition")
    assertEq(got.associatedAnswers.Item.type, T.string, "associated answer")
    assertEq(got.associatedAnswers.Item.kind, "default", "associated provenance")
    assertEq(got.associatedAnswers.Item.definition.name, "Item", "associated answer definition")
    assertEq(got.fieldDefs.value.annotations[1].name, "wire", "field annotations")
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
    local api = T.nominal("Api", "interface", "/project/sample.nupp\0module\0type\0Api")
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
    assertEq(fn.paramNames[1], "source", "parameter name")
    assertEq(fn.paramModes[1], "borrows", "parameter mode")
    assertEq(fn.predicate.param, 1, "predicate parameter")
    assertEq(fn.borrowsParam, 1, "borrow source")
    assertEq(fn.borrowsSelf, true, "receiver borrow")
    assertEq(fn.noYield, true, "suspension contract")
    assertEq(fn.foreign, true, "foreign contract")
    assertEq(fn.sendable, true, "sendability contract")
    assertEq(fn.ffiOut[1].success, "zero", "foreign output success policy")
    assertEq(fn.ffiOut[1].cleanups[1].name, "close", "foreign output cleanup")
    assertEq(got.methodEntries.read[1].member, 3, "overload runtime member")
    assertEq(got.methodEntries.read[1].definition.name, "read", "overload definition")
    assertEq(got.overloadedMethods.read, true, "overload marker")
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
    local producer = assert(interfaceimage.encode({producer = semantic("producer", shared)}, origins, encodedArenas))
    local consumer = assert(interfaceimage.encode({consumer = semantic("consumer", shared)}, origins, encodedArenas))
    local external = false
    for _, node in ipairs(consumer.descriptor.types) do
        external = external or node.kind == "external" and node.arena == producer.fingerprint
    end
    assert(external, "the consumer references the producer arena")

    local decodedArenas, decodedOrigins = {}, {}
    local first = assert(interfaceimage.decode(producer, {}, decodedArenas, decodedOrigins))
    local second = assert(interfaceimage.decode(consumer, {}, decodedArenas, decodedOrigins))
    assertEq(second.consumer.exports.types.Value, first.producer.exports.types.Value, "mounted arena identity")
end

function M.roundTripsDefinitionsComptimeProgramsEffectsAndDiagnostics()
    local value = T.func({T.string}, {T.integer}, false, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, {"text"})
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
    sample.exports.callGuarantees = {value = {noYield = true, effects = {"io.read"}},}
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

    local image = assert(interfaceimage.encode({sample = sample}))
    local decoded = assert(interfaceimage.decode(image)).sample
    local exports = decoded.exports
    assertEq(exports.nominalEffectFingerprint, "effects", "nominal effect fingerprint")
    assertEq(exports.deriveInterfaceFingerprint, "derives", "derive interface fingerprint")
    assertEq(exports.comptimeFunctionFingerprint, "comptime", "comptime fingerprint")
    assertEq(exports.callGuarantees.value.effects[1], "io.read", "call effects")
    assertEq(exports.typeDefs.Value.deprecated.replacement, "Other", "type definition metadata")
    assertEq(exports.typeDefs.Value.exactCallExport.identity, "sample.Value", "exact call export")
    assertEq(exports.valueDefs.value.comptimeOnly, true, "value definition metadata")
    assertEq(exports.comptimeFunctions.Make.signature.tag, "func", "comptime signature")
    assertEq(exports.comptimeFunctions.Make.deriveInterface.tag, "shape", "derive interface")
    assertEq(exports.comptimeFunctions.Make.runtimeHelpers[1], "runtime.helper", "runtime helpers")
    assertEq(decoded.diags[1].code, "NUPP2001", "diagnostics")
    assertEq(decoded.source, "return sample", "source")
end

function M.rejectsUnknownSchemasCorruptionAndMissingArenas()
    local image = select(2, roundTrip(T.string))
    local schema = image.schema
    image.schema = schema + 1
    local decoded, _, problem = interfaceimage.decode(image)
    assertEq(decoded, nil, "unknown schema")
    assert(problem:find("malformed", 1, true), problem)
    image.schema = schema

    local fingerprint = image.fingerprint
    image.fingerprint = string.rep("0", #fingerprint)
    decoded, _, problem = interfaceimage.decode(image)
    assertEq(decoded, nil, "corrupt fingerprint")
    assert(problem:find("fingerprint", 1, true), problem)
end

return M
