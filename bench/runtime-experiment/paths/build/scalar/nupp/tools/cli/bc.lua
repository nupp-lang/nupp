_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.bc\0runtime\0001") };





















local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "bc" )
local report = require ( "nupp.tools.cli.report" )
local listing = require ( "nupp.tools.bytecodelisting" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
description = "The bytecode of one Nupp file, by function." ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
file = { type = "string" } ,
optLevel = { type = "integer" } ,
functions = {
type = "array" ,
items = {
type = "object" ,
properties = {
what = { type = "string" , enum = { "chunk" , "function" } } ,
firstLine = { type = "integer" } ,
lastLine = { type = "integer" } ,
instructions = {
type = "array" ,
items = {
type = "object" ,
properties = {
pc = { type = "integer" } ,
op = { type = "string" } ,
text = { type = "string" } ,
line = { type = "integer" } ,
inLoop = { type = "boolean" } ,
unrecordable = {
type = "string" ,
description = "Why a loop holding this cannot be compiled. Absent when it can."
,
} ,
traceReason = { type = "string" } ,
traceClass = { type = "string" , enum = { "blocker" , "risk" , "stop" } } ,
traceReachability = { type = "string" , enum = { "must" , "may" } } ,
} ,
required = { "pc" , "op" , "text" } ,
} ,
} ,
} ,
required = { "what" , "instructions" } ,
} ,
} ,
unrecordable = {
type = "integer" ,
description = "How many instructions sit in a loop that therefore never compiles." ,
} ,
blockers = { type = "integer" } ,
mustBlockers = { type = "integer" } ,
risks = { type = "integer" } ,
bytecodeFingerprint = { type = "string" } ,
traceProfile = { type = "object" } ,
reasonCatalog = { type = "object" } ,
} ,
required = { "ok" , "file" , "diagnostics" , "functions" , "unrecordable" } ,
}







local function width ( options ) 
if options . width ~= nil and options . width > 0 then
return math . floor ( options . width )
end

return cliModule . colorEnabled ( io . stdout ) and cliModule . columns ( io . stdout ) or nil
end











local function palette ( source ) 
local paint = require ( "nupp.tools.terminalhighlight" )
local colors = paint . palette ( cliModule . colorEnabled ( io . stdout ) )
local rows = paint . rows ( source )

return {
source = function ( at , text , column ) 
return paint . paintRow ( rows [ at ] , text , colors , column , listing . TRUNCATED )
end ,
gutter = function ( text ) 
return paint . paint ( colors , "comment" , text )
end ,
instruction = function ( text ) 
return paint . bytecode ( text , colors )
end ,
note = function ( text , must ) 
return paint . paint ( colors , must and "error" or "warning" , text )
end ,
header = function ( text ) 
return paint . paint ( colors , "comment" , text )
end ,
}
end

local function run ( options ) 
local positional = { options . file }
local paths = positional
if # paths ~= 1 then
return usageError ( "exactly one source file is required" )
end
local path = paths [ 1 ]
local asJson = ( options . format or "text" ) == "json"
local collected = asJson and { } or nil



local function fail ( code , message ) 
if collected then
if code ~= nil then
collected [ # collected + 1 ] = report . runDiagnostic ( code , message or "" , nil , path )
end
return report . failure ( REPORT_SCHEMA , collected , { file = path } )
end
if message ~= nil then
io . stderr : write ( require ( "nupp.tools.cli.error" ) . message ( message ) .. "\n" )
end

return 1
end

local ok = pcall ( require , "jit.util" )
local okBc = pcall ( require , "jit.bc" )
if not ok or not okBc then
return fail ( report . TOOL_FAILED , "bytecode needs LuaJIT's jit.util and jit.bc" )
end

local fs = require ( "nupp.compiler.fs" )
local source , readErr = fs . readFile ( path )
if not source then
report . fileFailure ( path , readErr , "check that the path exists and is readable" , collected )
return fail ( )
end

local compile = require ( "nupp.tools.cli.compile" )
local env = require ( "nupp.compiler.project.env" ) . new ( "." )
local settings = compile . settings ( options )
settings . diagnostics = collected
local folding = ( options . format or "text" ) == "text" and not options . prologue
local boundary = folding and listing . BOUNDARY or nil
settings . bytecodeBoundary = boundary
local code , compileErr = compile . module ( path , env , settings )
if not code then

return collected and fail ( ) or fail ( nil , tostring ( compileErr ) )
end
local chunk , loadErr = loadstring ( code , "@" .. path )
if not chunk then
return fail ( "NUPP3005" , "generated code did not load: " .. tostring ( loadErr ) )
end

local analysis = require ( "nupp.tools.tracebytecode" ) . analyze ( chunk )
local functions = analysis . functions

local boundaryPc = nil
local boundaryFunction = nil
if boundary ~= nil then
boundaryFunction , boundaryPc = listing . boundary ( functions )
if boundaryPc == nil then
return fail ( report . TOOL_FAILED , "generated bytecode has no preamble boundary marker" )
end
end

local unrecordable = 0
for _ , fn in ipairs ( functions ) do
for _ , ins in ipairs ( fn . instructions ) do
if ins . unrecordable then
unrecordable = unrecordable + 1
end
end
end



local blocked = options . check and analysis . mustBlockers > 0
if collected and blocked then
local trace = require ( "nupp.profile.trace" )
for _ , fn in ipairs ( functions ) do
for _ , ins in ipairs ( fn . instructions ) do
if ins . traceReachability == "must" then
local reason = trace . reason ( ins . traceReason or "" )
collected [
# collected + 1
] = {
filename = path ,
line = ins . line ,
code = reason and reason . lint or "NUPP2515" ,
msg = tostring ( ins . unrecordable or ins . traceReason ) ,
help = reason and reason . repair ,
}
end
end
end
end

if asJson then


io . write (
report . encode ( {
ok = not blocked ,
diagnostics = report . diagnosticValues ( collected or { } ) ,
file = path ,
optLevel = settings . optLevel or 0 ,
functions = functions ,
unrecordable = unrecordable ,
blockers = analysis . blockers ,
mustBlockers = analysis . mustBlockers ,
risks = analysis . risks ,
bytecodeFingerprint = analysis . bytecodeFingerprint ,
traceProfile = analysis . profile ,
reasonCatalog = analysis . reasonCatalog ,
} ) .. "\n"
)
else
io . write (
( listing . render ( functions , source , {
check = options . check and true or false ,
boundaryFunction = boundaryFunction ,
boundaryPc = boundaryPc ,
palette = palette ( source ) ,
width = width ( options ) ,
} ) )
)
end

if blocked then
if asJson then
return 1
end
io . stderr : write (
("nupp: %d instruction%s in a loop that cannot compile\n")

: format ( analysis . mustBlockers , analysis . mustBlockers == 1 and "" or "s" )
)
return 1
end

return 0
end













local Bytecode = {} Bytecode.__index = Bytecode
































function Bytecode:run() 
return run ( self )
end ;Bytecode.__nuppInit1=function(__nuppT12, a1, a2, a3, a4, a5, a6, a7) if a1 == nil then __nuppT12.format = "text" else __nuppT12.format = a1 end __nuppT12.optLevel = a2 if a3 == nil then __nuppT12.check = false else __nuppT12.check = a3 end if a4 == nil then __nuppT12.prologue = false else __nuppT12.prologue = a4 end if a5 == nil then __nuppT12.width = 0 else __nuppT12.width = a5 end if a6 == nil then __nuppT12.schema = false else __nuppT12.schema = a6 end __nuppT12.file = a7 return __nuppT12 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Show the bytecode a Nupp file compiles to.\n\nSource lines are shown beside their instructions. `--check` identifies\noperations which prevent a containing loop from being recorded by LuaJIT.\n\nExamples:\n\n    nupp bc src/main.nupp\n    nupp bc --check src/hot-loop.nupp\n    nupp bc --json src/main.nupp",["group"]=false,["hidden"]=false,["name"]="bc",["summary"]="Show the bytecode a Nupp file compiles to."},["fieldCount"]=7,["fields"]={{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="required",["choices"]={"0","1","2"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="-O0, -O1, -O2",["displayOverride"]="-O0, -O1, -O2",["documentation"]="Optimization level, matching run and build (default -O0).",["field"]="optLevel",["hidden"]=false,["index"]=2,["long"]=false,["matchKey"]="O",["names"]={},["optional"]=true,["pattern"]="^%-O([0-2])$",["required"]=false,["role"]="option",["value"]="LEVEL"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--check",["documentation"]="Report bytecode a loop cannot compile.",["field"]="check",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"check"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--prologue",["documentation"]="Include the generated runtime preamble.",["field"]="prologue",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"prologue"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--width",["documentation"]="Columns the listing may use. Defaults to the terminal's width.",["field"]="width",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"width"},["required"]=false,["role"]="option",["value"]="COLUMNS"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file to inspect.",["field"]="file",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file to inspect.",["field"]="file",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="996237bfb2f5e0335e26bde417d42a906d225b43de99aa819250b7c49f1f6f0a",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.bc:Bytecode:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="bc"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Show the bytecode a Nupp file compiles to."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Bytecode?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Bytecode",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.bc:Bytecode:1",Bytecode,__nuppDerived) ;Bytecode["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Bytecode["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("bc")end ;Bytecode["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Show the bytecode a Nupp file compiles to.")end ;Bytecode["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Bytecode,__nuppT1[1],{ })


function Bytecode . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Bytecode } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.bc"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.bc"]=__nuppExports;return __nuppExports