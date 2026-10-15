_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppV:close();  end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.run\0runtime\0001") };

















local errors = require ( "nupp.tools.cli.error" )
local usageError = errors . forCommand ( "run" )
local report = require ( "nupp.tools.cli.report" )
local cliModule = require ( "nupp.cli" )

local SITE_LOCATION = {
type = "object" ,
description = "Where recording stopped, or where its root trace started. The range covers that line, and is absent when the file cannot be read."
,
properties = { file = { type = "string" } , range = report . RANGE } ,
required = { "file" } ,
}

local REPORT_SCHEMA = {
type = "object" ,
description = "Normalized LuaJIT trace aborts observed while one program ran." ,
properties = {
durationMs = { type = "number" , description = "How long the trace session was open." } ,
totalAborts = { type = "integer" } ,
blacklisted = { type = "integer" } ,
traceProfile = {
type = "object" ,
properties = {
id = { type = "string" } ,
luajitRevision = { type = "string" } ,
luajitVersion = { type = "integer" } ,
architecture = { type = "string" } ,
operatingSystem = { type = "string" } ,
enabledRecorderFeatures = { type = "array" , items = { type = "string" } } ,
bytecodeSchema = { type = "string" } ,
supported = { type = "boolean" } ,
} ,
required = { "id" , "luajitRevision" , "architecture" , "operatingSystem" , "bytecodeSchema" } ,
} ,
reasonCatalog = {
type = "object" ,
properties = { id = { type = "string" } , version = { type = "integer" } } ,
required = { "id" , "version" } ,
} ,
sites = {
type = "array" ,
items = {
type = "object" ,
properties = {
count = { type = "integer" } ,
reason = { type = "string" } ,
reasonId = { type = "string" } ,
class = {
type = "string" ,
enum = { "blocker" , "risk" , "stop" } ,
description = "What kind of stop this is: one the recorder refuses, one that depends on runtime facts, or ordinary trace formation."

} ,
blacklisted = {
type = "boolean" ,
description = "Whether LuaJIT stopped retrying this trace for the rest of the process."
} ,
rawReason = { type = "string" } ,
location = SITE_LOCATION ,
rootLocation = SITE_LOCATION ,
zone = { type = "string" } ,
} ,
required = { "count" , "reason" , "reasonId" , "class" , "blacklisted" , "rawReason" , "location" , "zone" } ,
} ,
} ,
} ,
required = { "durationMs" , "totalAborts" , "blacklisted" , "traceProfile" , "reasonCatalog" , "sites" } ,
}



local function siteLocation ( text ) 
if text == nil then
return nil
end
local file , line = text : match ( "^(.*):(%d+)$" )
local number = tonumber ( line )
if not file or not number or number < 1 then
return { file = file or text }
end
local source = require ( "nupp.compiler.fs" ) . readFile ( file )
if not source then
return { file = file }
end
local start , current = 1 , 1
while current < number do
local newline = source : find ( "\n" , start , true )
if not newline then
return { file = file }
end
start , current = newline + 1 , current + 1
end
local finish = source : find ( "\n" , start , true ) or ( # source + 1 )

return {
file = file ,
range = {
start = { line = number , column = 1 , offset = start } ,
[ "end" ] = { line = number , column = finish - start + 1 , offset = finish } ,
} ,
}
end

local DEFAULT_INTERVAL_MS = 10

local function configureGpuCosts ( path ) 
local ok , problem = pcall ( require ( "nupp.runtime.provider.nativegpu" ) . costsOutput , path )
return ok , not ok and tostring ( problem ) or nil
end

local function run ( options ) 
local positional = { options . file }
for _ , value in ipairs ( options . arguments ) do
positional [ # positional + 1 ] = value
end
local values = options
local profiling = values . profile == true
if values . gpuCosts == "" then
return usageError ( "--gpu-costs needs an output path" )
end
local intervalMs = 10
if values . profileIntervalMs ~= nil then
local given = tonumber ( values . profileIntervalMs )
if not given or given < 1 or given ~= math . floor ( given ) then
return usageError ( "--profile-interval-ms needs a positive whole number" )
end
if not profiling then
return usageError ( "--profile-interval-ms sets how often --profile samples, which was not asked for" )
end
intervalMs = math . floor ( given )
end
if values . remarksOut == "" then
return usageError ( "--remarks-out= requires a file name" )
end



if values . profileOut and not profiling then
return usageError ( "--profile-out names where --profile writes, which was not asked for" )
end
local profileOut = values . profileOut or "profile.out"
local tracingAborts = values . jitAborts ~= nil
if values . json and not tracingAborts then
return usageError ( "--json describes --jit-aborts, which was not asked for" )
end
if values . jitAborts == "" then
return usageError ( "--jit-aborts= requires a file name" )
end
local abortsOut = values . jitAborts == "\0" and ( values . json and "jit-aborts.json" or "jit-aborts.csv" )
or values . jitAborts

local path = positional [ 1 ]
if not path then
return usageError ( "a program file is required" )
end
local watching = values . watch == true
if watching and not path : find ( "%.nupp$" ) then
return usageError ( "--watch requires a .nupp program" )
end
if watching and values . optLevel and values . optLevel ~= "0" then
return usageError ( "--watch supports -O0 only; run a normal optimized build before release" )
end
local programArgs = { }
for index = 2 , # positional do
programArgs [ # programArgs + 1 ] = positional [ index ]
end

local compile = require ( "nupp.tools.cli.compile" )
local settings = compile . settings ( values )
local sampledRemarks = profiling and settings . remarks
if sampledRemarks then
settings . remarks = false
end
local projectEnv = require ( "nupp.compiler.project.env" ) . new ( "." )
local chunk , err
local watch = nil
if watching then
local session , diagnostics = require ( "nupp.tools.cli.watch" ) . open ( path )
if not session then
require ( "nupp.compiler.diagnostics" ) . report ( diagnostics or { } )
return 1
end
watch = session
chunk , err = loadstring ( session . entryCode , "@" .. path )
elseif path : find ( "%.nupp$" ) then
local code = compile . module ( path , projectEnv , settings )
if not code then
return 1
end
chunk , err = loadstring ( code , "@" .. path )
else
chunk , err = loadfile ( path )
end
if not chunk then
io . stderr : write ( errors . message ( err ) .. "\n" )
return 1
end






compile . writeRemarks ( settings )

local sampling , tracing = nil , nil
local runtime = require ( "nupp.compiler.runtime" )
local compileLoaded , loaded
if watch then
compileLoaded , loaded = watch . compileLoaded , watch . loaded
else
compileLoaded = function ( modulePath , env ) 
local code , problem = compile . module ( modulePath , env , settings )

return code , problem
end
end
local checkPlain = function ( modulePath , env ) 
return compile . check ( modulePath , env , { } ) ~= nil
end





local toolArg = rawget ( _G , "arg" )
local programArg = { [ 0 ] = path }
for index , value in ipairs ( programArgs ) do
programArg [ index ] = value
end
local compileProgram , checkProgram = compileLoaded , checkPlain
compileLoaded = function ( modulePath , env ) 
local current = rawget ( _G , "arg" )
rawset ( _G , "arg" , toolArg )
local ok , code , problem = pcall ( compileProgram , modulePath , env )
rawset ( _G , "arg" , current )
if not ok then
error ( code , 0 )
end

return code , problem
end
checkPlain = function ( modulePath , env ) 
local current = rawget ( _G , "arg" )
rawset ( _G , "arg" , toolArg )
local ok , clean = pcall ( checkProgram , modulePath , env )
rawset ( _G , "arg" , current )
if not ok then
error ( clean , 0 )
end

return clean
end
local preparationDepth = 0

local function preparing ( active ) 
preparationDepth = preparationDepth + ( active and 1 or -1 )
if preparationDepth > 0 then
if tracing then
tracing : pause ( )
end
if sampling then
sampling : pause ( )
end
else
if sampling then
sampling : resume ( )
end
if tracing then
tracing : resume ( )
end
end
end

if values . gpuCosts ~= nil then
local directory = require ( "nupp.compiler.fs" ) . dirname ( values . gpuCosts )
local made , makeErr = require ( "nupp.io.files" ) . createDirectory ( directory )
if not made then
io . stderr : write ( errors . message ( makeErr ) .. "\n" )
return 1
end
local configured , configureErr = configureGpuCosts ( values . gpuCosts )
if not configured then
io . stderr : write ( errors . message ( configureErr ) .. "\n" )
return 1
end
end
local removeLoader
if profiling or tracingAborts then
removeLoader = runtime . install ( projectEnv , compileLoaded , loaded , checkPlain , preparing )
else
removeLoader = runtime . install ( projectEnv , compileLoaded , loaded , checkPlain )
end



local previousRemarksOut = _G . __nuppRemarksOut
_G . __nuppRemarksOut = settings . remarksOut


if profiling or tracingAborts then
local profile = require ( "nupp.profile" )
if profiling then


sampling = profile . sample ( { intervalMs = intervalMs , root = path } )
end
if tracingAborts then
tracing = profile . trace ( { includeBenign = true } )
end
end

rawset ( _G , "arg" , programArg )
local ok , runErr = pcall ( chunk , unpack ( programArgs ) )
rawset ( _G , "arg" , toolArg )
if tracing then
tracing : pause ( )
end
if sampling then
sampling : pause ( )
end
local gpuCostsError = nil
if values . gpuCosts ~= nil then
local closed , closeErr = configureGpuCosts ( nil )
if not closed then
gpuCostsError = closeErr
end
end
_G . __nuppRemarksOut = previousRemarksOut
removeLoader ( )
if watch then
watch . finish ( ok )
end




if sampling then
local summary = sampling : stop ( profileOut )
do __nuppDrop1( sampling ) end
compile . attachSamples ( settings , summary . sourceSamples , summary . samples , summary . intervalMs )
if sampledRemarks then
require (
"nupp.compiler.diagnostics"
) . report ( compile . selectRemarks ( settings . collectedRemarks or { } , settings . remarksFile ) )
end
io . stderr : write (
("nupp: %d samples on %d stacks every %dms, written to %s\n")

: format ( summary . samples , summary . stacks , summary . intervalMs , profileOut )
)
end

compile . writeRemarks ( settings )
if tracing then



local summary = tracing : stop ( )
do __nuppDrop1( tracing ) end
local content
if values . json then
local sites = { }
for _ , site in ipairs ( summary . sites ) do
sites [
# sites + 1
] = {
count = site . count ,
reason = site . reason ,
reasonId = site . reasonId ,
class = site . reasonClass ,
blacklisted = site . severity == "blacklist" ,
rawReason = site . rawReason ,
location = siteLocation ( site . location ) ,
rootLocation = siteLocation ( site . rootLocation ) ,
zone = site . zonePath ,
}
end
local document = {
durationMs = summary . durationSec * 1000 ,
totalAborts = summary . totalAborts ,
blacklisted = summary . blacklisted ,
traceProfile = summary . traceProfile ,
reasonCatalog = { id = summary . reasonCatalogId , version = summary . reasonCatalogVersion , } ,
sites = sites ,
}



content = report . encode ( document ) .. "\n"
else
content = tostring ( summary )
end
local wrote , writeErr = require ( "nupp.compiler.fs" ) . writeFile ( abortsOut , content )
if not wrote then
io . stderr : write ( errors . message ( writeErr ) .. "\n" )


if not ok then
io . stderr : write ( errors . message ( runErr ) .. "\n" )
end

return 1
end
io . stderr : write (
("nupp: %d trace aborts, %d blacklisted, written to %s\n")

: format ( summary . totalAborts , summary . blacklisted , abortsOut )
)
end

if gpuCostsError ~= nil then
io . stderr : write ( errors . message ( gpuCostsError ) .. "\n" )
end
if not ok then
io . stderr : write ( errors . message ( runErr ) .. "\n" )
return 1
end

return gpuCostsError ~= nil and 1 or 0
end


















local Run = {} Run.__index = Run






























































function Run:run() 
return run ( self )
end ;Run.__nuppInit1=function(__nuppT11, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) __nuppT11.optLevel = a1 if a2 == nil then __nuppT11.remarks = false else __nuppT11.remarks = a2 end __nuppT11.remarksFor = a3 __nuppT11.remarksOut = a4 if a5 == nil then __nuppT11.disabled = {} else __nuppT11.disabled = a5 end if a6 == nil then __nuppT11.watch = false else __nuppT11.watch = a6 end if a7 == nil then __nuppT11.profile = false else __nuppT11.profile = a7 end __nuppT11.profileIntervalMs = a8 __nuppT11.profileOut = a9 __nuppT11.gpuCosts = a10 __nuppT11.jitAborts = a11 if a12 == nil then __nuppT11.json = false else __nuppT11.json = a12 end if a13 == nil then __nuppT11.schema = false else __nuppT11.schema = a13 end __nuppT11.file = a14 if a15 == nil then __nuppT11.arguments = {} else __nuppT11.arguments = a15 end return __nuppT11 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Compile and run a Nupp or Lua program.\n\nThe program path divides compiler options from arguments passed to the\nloaded chunk. Profiling and trace-abort reports cover the program only.\nUse `--` before a program path beginning with a dash. `--profile` writes\ncollapsed-stack samples, while `--jit-aborts` records where LuaJIT stopped\ntracing. `--watch` is development-only, uses `-O0`, and applies valid\nchanged-body patches at cooperative poll boundaries.\n\nExamples:\n\n    nupp run src/main.nupp\n    nupp run src/main.nupp first second\n    nupp run --profile --profile-interval-ms 2 --profile-out hot.txt src/main.nupp\n    nupp run --jit-aborts=jit-aborts.csv src/main.nupp",["group"]=false,["hidden"]=false,["name"]="run",["summary"]="Compile and run a Nupp or Lua program."},["fieldCount"]=15,["fields"]={{["arity"]="required",["choices"]={"0","1","2"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="-O0, -O1, -O2",["displayOverride"]="-O0, -O1, -O2",["documentation"]="Optimization level.",["field"]="optLevel",["hidden"]=false,["index"]=1,["long"]=false,["matchKey"]="O",["names"]={},["optional"]=true,["pattern"]="^%-O([0-2])$",["required"]=false,["role"]="option",["value"]="LEVEL"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--remarks",["documentation"]="Report what the optimizer did and what it declined to do.",["field"]="remarks",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"remarks"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--remarks-for",["documentation"]="Only report optimizer decisions for this source file.",["field"]="remarksFor",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"remarks-for"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FILE"},{["arity"]="optionalAttached",["constant"]="build/remarks.json",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--remarks-out",["documentation"]="Write the optimizer's account to a file, build/remarks.json by default.",["field"]="remarksOut",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"remarks-out"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="attachedOnly",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--Zno-opt",["documentation"]="Turn off one optimizer pass by stable code.",["field"]="disabled",["hidden"]=false,["index"]=5,["long"]=false,["names"]={"Zno-opt"},["repeated"]=true,["required"]=false,["role"]="option",["set"]=true,["value"]="CODE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--watch",["documentation"]="Keep named function identities patchable at poll points.",["field"]="watch",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"watch"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--profile",["documentation"]="Sample the program.",["field"]="profile",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"profile"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--profile-interval-ms",["documentation"]="Sampling interval in milliseconds.",["field"]="profileIntervalMs",["hidden"]=false,["index"]=8,["long"]=true,["names"]={"profile-interval-ms"},["optional"]=true,["required"]=false,["role"]="option",["value"]="MS"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--profile-out",["documentation"]="File which receives profiling samples.",["field"]="profileOut",["hidden"]=false,["index"]=9,["long"]=true,["names"]={"profile-out"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--gpu-costs",["documentation"]="Write GPU operation costs and device timestamps to this JSONL file.",["field"]="gpuCosts",["hidden"]=false,["index"]=10,["long"]=true,["names"]={"gpu-costs"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="optionalAttached",["constant"]="\0",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--jit-aborts",["documentation"]="Record JIT aborts, optionally naming an attached output path.",["field"]="jitAborts",["hidden"]=false,["index"]=11,["long"]=true,["names"]={"jit-aborts"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--json",["documentation"]="Write JIT aborts as JSON rather than CSV.",["field"]="json",["hidden"]=false,["index"]=12,["long"]=true,["names"]={"json"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=13,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Program to compile and run.",["field"]="file",["hidden"]=false,["index"]=14,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments passed to the program.",["field"]="arguments",["hidden"]=false,["index"]=15,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Program to compile and run.",["field"]="file",["hidden"]=false,["index"]=14,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments passed to the program.",["field"]="arguments",["hidden"]=false,["index"]=15,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"}},["preserveUnknown"]=false,["remainder"]={["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments passed to the program.",["field"]="arguments",["hidden"]=false,["index"]=15,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"},["stopAtFirstArgument"]=true}},["effects"]={},["fields"]={},["fingerprint"]="75d3a87e1ff3c75a5e28af5b42096c4a47cf39a129d1e4c575d76745f3a6fb74",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.run:Run:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="run"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Compile and run a Nupp or Lua program."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Run?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Run",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.run:Run:1",Run,__nuppDerived) ;Run["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Run["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("run")end ;Run["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Compile and run a Nupp or Lua program.")end ;Run["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Run,__nuppT1[1],{ })


function Run . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Run } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.run"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.run"]=__nuppExports;return __nuppExports