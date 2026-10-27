local testAssert = require("nupp.test")
-- Semantic type reflection and the field codec materialization provider.
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function compile(source, opts)
    local parsed = parser.parse(source, "fieldcodec_materialize_test.nupp")
    testAssert.equal(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "fieldcodec_materialize_test.nupp", env, opts)

    return parsed, diagnostics
end

-- A refused block has no value to type, so a fixture returning it would also be
-- told its module's value needs an annotation. That follows from the refusal and
-- is not what these cases are about, so they check without the floor.
local function errorsOf(source)
    local _, diagnostics = compile(source, {strict = false})
    local codes = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            codes[#codes + 1] = diagnostic.code
        end
    end

    return codes
end

local function run(source)
    local parsed, diagnostics = compile(source)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, source), 2)
        end
    end

    return program.run(parsed, "fieldcodec_materialize_test"), parsed
end

local M = {}

function M.materializesAKeyedRecordCodecFromReflection()
    local result, parsed = run(
        [[
local record Position
    x: number
    y: number
end

const PositionCodec: nupp.reflect.FieldCodec<Position> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end

local encoded = PositionCodec:encode(new Position(x = 10, y = 20))
local decoded, problem = PositionCodec:decode(encoded)
local invalid, invalidProblem = PositionCodec:decode(42 as any)
return {
    x = encoded["x"] as number,
    y = encoded["y"] as number,
    fingerprint = PositionCodec.fingerprint,
    decodedX = decoded and decoded.x,
    decodeProblem = problem,
    decodeType = decoded and getmetatable(decoded) == Position,
    invalid = invalid,
    invalidProblem = invalidProblem,
}
]]
    )
    testAssert.equal(result.x, 10, "x field")
    testAssert.equal(result.y, 20, "y field")
    testAssert.equal(result.fingerprint, "t:x,y", "compatibility fingerprint")
    testAssert.equal(result.decodedX, 10, "decoded field")
    testAssert.equal(result.decodeProblem, nil, "decoded keyed table")
    testAssert.equal(result.decodeType, true, "decoded nominal identity")
    testAssert.equal(result.invalid, nil, "non-table decode result")
    testAssert.equal(result.invalidProblem, "$: expected keyed table", "non-table decode problem")
    local image = program.image(parsed, "fieldcodec_materialize_test")
    assert(image:find("keyed", 1, true), image)
    -- The comptime reflection is folded away entirely: the program carries the codec
    -- the materializer built and none of the machinery that described the type. (The
    -- keyed codec's runtime is installed from `nupp.compiler.runtime.reflect`, which
    -- is not the reflection API.)
    testAssert.equal(image:find("nupp.reflect", 1, true), nil, "reflection erased")
end

function M.passesReflectionThroughATypedComptimeHelper()
    local src = [[
local record Point
    x: number
    y: number
end
@comptime local function keyed(info: nupp.reflect.Info): nupp.reflect.FieldCodecBlueprint
    return nupp.reflect.fieldCodec(info)
end
const Codec: nupp.reflect.FieldCodec<Point> = comptime do
    return keyed(nupp.reflect(Point))
end
local encoded = Codec:encode(new Point(x = 3, y = 4))
return {x = encoded.x as number, y = encoded.y as number}
]]
    local encoded = run(src)
    testAssert.equal(encoded.x, 3, "the reflected helper selects x")
    testAssert.equal(encoded.y, 4, "the reflected helper selects y")
end

function M.namesTheWholePublicReflectionGraphUnderNuppReflect()
    local src = [[
@annotation(targets = {"field"})
local record wire
    name: string?
end
local record User
    @wire(name = "user_id")
    id: integer
end
@comptime local function argumentName(value: const nupp.reflect.AnnotationArgument): string
    return value.name
end
@comptime local function annotationName(value: const nupp.reflect.Annotation): string
    return value.name .. ":" .. argumentName(value.arguments[1])
end
@comptime local function entryName(value: const nupp.reflect.Entry): string
    return value.name as string
end
@comptime local function nodeName(value: const nupp.reflect.Node): string
    return entryName((value.fields as const{nupp.reflect.Entry})[1])
end
@comptime local function fieldName(value: const nupp.reflect.Field): string
    return value.name .. ":" .. annotationName(value.annotations[1])
end
@comptime local function summarize(value: nupp.reflect.Info): string
    return nodeName(value.types[value.root]) .. ":" .. fieldName(value.fields[1])
end
return comptime do return summarize(nupp.reflect(User)) end
]]
    testAssert.equal(run(src), "id:id:wire:name", "reflection graph types share one namespace")
end

function M.removesTheOldAmbientAndFieldcodecNames()
    local ambient = errorsOf(
        [[
@comptime local function old(info: TypeInfo): string return info.name end
return "unused"
]]
    )
    testAssert.equal(ambient[1], "NUPP2101", "TypeInfo is no longer ambient")

    local fieldcodec = errorsOf(
        [[
local record User id: integer end
const Codec: nupp.fieldcodec.KeyedCodec<User> = comptime do
    return nupp.fieldcodec.compile(nupp.reflect(User))
end
return Codec
]]
    )
    testAssert.equal(fieldcodec[1], "NUPP2101", "nupp.fieldcodec is no longer public")
end

function M.inspectsTheImmutableReflectionSchemaInUserComptimeCode()
    local src = [[
local record Pair
    left: string
    right: integer
end
@comptime local function summarize(info: nupp.reflect.Info): string
    local names = {}
    for index, field in ipairs(info.fields) do
        names[index] = field.name .. ":" .. field.kind
    end
    assert(type(info) == "table")
    assert(info.types == info.types)
    assert(nil ~= info.types)
    return info.schema .. ":" .. info.types[info.root].kind
        .. ":" .. #info.fields .. ":" .. table.concat(names, ",")
end
return comptime do return summarize(nupp.reflect(Pair)) end
]]
    testAssert.equal(
        run(src),
        "6:record:2:left:string,right:int64",
        "user comptime code reads the versioned descriptor graph"
    )
end

function M.exposesCheckedTypedAnnotationsToComptimeReflection()
    local src = [[
@annotation(targets = {"record", "field"})
local record wire
    name: string?
    omitIfNil: boolean?
end

@wire(name = "users")
local record User
    @wire(name = "user_id")
    id: integer
    @wire(omitIfNil = true)
    nickname: string?
end

@comptime local function summarize(info: nupp.reflect.Info): string
    local recordName = info.annotations[1].arguments[1].value
    local idName = info.fields[1].annotations[1].arguments[1].value
    local omitted = info.fields[2].annotations[1].arguments[1].value
    return recordName .. ":" .. idName .. ":" .. tostring(omitted)
end

return comptime do return summarize(nupp.reflect(User)) end
]]
    testAssert.equal(
        run(src),
        "users:user_id:true",
        "typed annotation values cross the worker as immutable semantic data"
    )
end

function M.exposesAnnotationTypeReferencesAsDescriptorEdges()
    local src = [[
@annotation(targets = {"field"})
local record jsonWith
    @ref
    codec: any
end

local record StringCodec
end

local record User
    @jsonWith(codec = StringCodec)
    name: string
end

return comptime do
    local info = nupp.reflect(User)
    local edge = info.fields[1].annotations[1].arguments[1].type as integer
    return info.types[edge].name
end
]]
    testAssert.equal(
        run(src),
        "StringCodec",
        "annotation type references use the reflection graph instead of source names"
    )
end

function M.rejectsMutationOfReflectionViews()
    local codes = errorsOf(
        [[
local record Pair
    left: string
end
return comptime do
    local info = nupp.reflect(Pair)
    info.name = "Changed"
    return info.name
end
]]
    )
    testAssert.equal(codes[1], "NUPP2411", "reflection views reject mutation")
end

function M.rejectsAReflectedTypeAndRuntimeTargetMismatch()
    local codes = errorsOf(
        [[
local record Position x: number end
local record Velocity x: number end
const Bad: nupp.reflect.FieldCodec<Velocity> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end
]]
    )
    testAssert.equal(codes[1], "NUPP2415", "nominal mismatch")
end

function M.rejectsDistinctQualifiedRecordsWithTheSameLocalShape()
    local codes = errorsOf(
        [[
local left = {}
record left.Item value: string end
local right = {}
record right.Item value: string end
const Bad: nupp.reflect.FieldCodec<right.Item> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(left.Item))
end
return Bad
]]
    )
    testAssert.equal(codes[1], "NUPP2415", "qualified nominal mismatch")
end

function M.requiresATypePositionForReflection()
    local codes = errorsOf(
        [[
local value = 1
const Bad: nupp.reflect.FieldCodec<any> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(value))
end
]]
    )
    testAssert.equal(codes[1], "NUPP2418", "runtime value reflection")
end

return M
