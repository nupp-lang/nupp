-- Semantic type reflection and the non-PEG materialization provider.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(source)
   local parsed = parser.parse(source, "fieldcodec_materialize_test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, "fieldcodec_materialize_test.g.nupp", env)
   local code, generated = gen.generate(parsed, "fieldcodec_materialize_test")
   for _, diagnostic in ipairs(generated) do diagnostics[#diagnostics + 1] = diagnostic end
   return code, diagnostics
end

local function errorsOf(source)
   local _, diagnostics = compile(source)
   local codes = {}
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         codes[#codes + 1] = diagnostic.code
      end
   end
   return codes
end

local function run(source)
   local code, diagnostics = compile(source)
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, code), 2)
      end
   end
   local chunk, why = loadstring(code, "@fieldcodec_materialize_test")
   assert(chunk, why and (why .. "\n---\n" .. code))
   return chunk(), code
end

local M = {}

function M.materializesAKeyedRecordCodecFromReflection()
   local result, code = run([[
local record Position
    x: number
    y: number
end

const PositionCodec: nupp.FieldCodec.KeyedCodec<Position> = comptime do
    return nupp.fieldcodec.compile(reflect(Position))
end

local encoded = PositionCodec:encode(new Position(x = 10, y = 20))
return {x = encoded["x"], y = encoded["y"], fingerprint = PositionCodec.fingerprint}
]])
   assertEq(result.x, 10, "x field")
   assertEq(result.y, 20, "y field")
   assertEq(result.fingerprint, "t:x,y", "compatibility fingerprint")
   assert(code:find("nupp.fieldcodec.keyed", 1, true), code)
   assertEq(code:find("reflect", 1, true), nil, "reflection erased")
end

function M.passesReflectionThroughATypedComptimeHelper()
   local src = [[
local record Point
    x: number
    y: number
end
@comptime local function keyed(info: TypeInfo): nupp.FieldCodec.Blueprint
    return nupp.fieldcodec.compile(info)
end
const Codec: nupp.FieldCodec.KeyedCodec<Point> = comptime do
    return keyed(reflect(Point))
end
local encoded = Codec:encode(new Point(x = 3, y = 4))
return {x = encoded.x, y = encoded.y}
]]
   local encoded = run(src)
   assertEq(encoded.x, 3, "the reflected helper selects x")
   assertEq(encoded.y, 4, "the reflected helper selects y")
end

function M.inspectsTheImmutableReflectionSchemaInUserComptimeCode()
   local src = [[
local record Pair
    left: string
    right: integer
end
@comptime local function summarize(info: TypeInfo): string
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
return comptime do return summarize(reflect(Pair)) end
]]
   assertEq(run(src), "2:record:2:left:string,right:integer",
      "user comptime code reads the versioned descriptor graph")
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

@comptime local function summarize(info: TypeInfo): string
    local recordName = info.annotations[1].arguments[1].value
    local idName = info.fields[1].annotations[1].arguments[1].value
    local omitted = info.fields[2].annotations[1].arguments[1].value
    return recordName .. ":" .. idName .. ":" .. tostring(omitted)
end

return comptime do return summarize(reflect(User)) end
]]
   assertEq(run(src), "users:user_id:true",
      "typed annotation values cross the worker as immutable semantic data")
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
    local info = reflect(User)
    local edge = info.fields[1].annotations[1].arguments[1].type as integer
    return info.types[edge].name
end
]]
   assertEq(run(src), "StringCodec",
      "annotation type references use the reflection graph instead of source names")
end

function M.rejectsMutationOfReflectionViews()
   local codes = errorsOf([[
local record Pair
    left: string
end
return comptime do
    local info = reflect(Pair)
    info.name = "Changed"
    return info.name
end
]])
   assertEq(codes[1], "NUPP2411", "reflection views reject mutation")
end

function M.rejectsAReflectedTypeAndRuntimeTargetMismatch()
   local codes = errorsOf([[
local record Position x: number end
local record Velocity x: number end
const Bad: nupp.FieldCodec.KeyedCodec<Velocity> = comptime do
    return nupp.fieldcodec.compile(reflect(Position))
end
]])
   assertEq(codes[1], "NUPP2415", "nominal mismatch")
end

function M.requiresATypePositionForReflection()
   local codes = errorsOf([[
local value = 1
const Bad: nupp.FieldCodec.KeyedCodec<any> = comptime do
    return nupp.fieldcodec.compile(reflect(value))
end
]])
   assertEq(codes[1], "NUPP2418", "runtime value reflection")
end

function M.excludesTheCodecHelperFromUnrelatedPrograms()
   local code = compile("return 42")
   assertEq(code:find("__nuppKeyedCodec", 1, true), nil, "unused helper")
end

return M
