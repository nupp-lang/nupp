_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.build\0runtime\0001") };









const files = require ( "nupp.io.files" )

local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "build" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
description = "What a build reported and what it produced." ,
properties = {
diagnostics = require ( "nupp.tools.cli.report" ) . DIAGNOSTICS ,
target = {
type = "string" ,
description = "The manifest target that was built. Absent for a build of explicitly named source files."

} ,
platform = { type = "string" , description = "The selected binary platform for a one-platform build." } ,
compat = { type = "string" , enum = { "lua51" } , description = "The enforced source compatibility profile." } ,
distributionReady = {
type = "boolean" ,
description = "Whether the selected platform output is ready for public distribution."
} ,
notice = { type = "string" } ,
platforms = {
type = "array" ,
description = "Per-platform outcomes for --platform all." ,
items = {
type = "object" ,
properties = {
platform = { type = "string" } ,
status = { type = "string" , enum = { "built" , "failed" } } ,
outputs = { type = "array" , items = { type = "string" } } ,
error = { type = "string" } ,
distributionReady = { type = "boolean" } ,
notice = { type = "string" } ,
} ,
required = { "platform" , "status" , "outputs" } ,
} ,
} ,
written = {
type = "array" ,
items = { type = "string" } ,
description = "Every output path the build produced, sorted."
} ,
artifact = {
type = "string" ,
description = "The transportable artifact written by a bundle, binary, or component target."
} ,
aotManifest = {
type = "string" ,
description = "The packaged Wasm AOT manifest beside the transportable artifact."
} ,
spi = {
type = "array" ,
description = "Discovered SPI implementations in dependency order; selection belongs to the use site." ,
items = {
type = "object" ,
properties = {
interface = { type = "string" } ,
implementation = { type = "string" } ,
dependency = { type = "string" } ,
} ,
required = { "interface" , "implementation" , "dependency" } ,
} ,
} ,

materializations = {
type = "array" ,
description = "Materialized expressions and their versioned provider and backend facts." ,
items = {
type = "object" ,
properties = {
source = { type = "string" } ,
line = { type = "integer" } ,
column = { type = "integer" } ,
provider = { type = "string" } ,
schema = { type = "integer" } ,
fingerprint = { type = "string" } ,
digest = { type = "string" } ,
backend = { type = "string" } ,
blueprintSize = { type = "integer" } ,
generatedSize = { type = "integer" } ,
runtimeFeatures = { type = "array" , items = { type = "string" } } ,
abis = { type = "object" } ,
} ,
required = {
"source" ,
"line" ,
"column" ,
"provider" ,
"schema" ,
"fingerprint" ,
"backend" ,
"blueprintSize" ,
"generatedSize" ,
"runtimeFeatures" ,
"abis"
} ,
} ,
} ,
derives = {
type = "array" ,
description = "Closed derive recipes and their bounded generation facts." ,
items = {
type = "object" ,
properties = {
provider = { type = "string" } ,
owner = { type = "string" } ,
semanticFingerprint = { type = "string" } ,
generatedMembers = { type = "integer" } ,
canonicalBytes = { type = "integer" } ,
renderedBytes = { type = "integer" } ,
effects = { type = "array" , items = { type = "string" } } ,
cached = { type = "boolean" } ,
durationMs = { type = "number" } ,
generatedLocals = { type = "integer" } ,
maxGeneratedUpvalues = { type = "integer" } ,
} ,
required = {
"provider" ,
"owner" ,
"semanticFingerprint" ,
"generatedMembers" ,
"canonicalBytes" ,
"renderedBytes" ,
"effects" ,
"cached" ,
"durationMs" ,
"generatedLocals" ,
"maxGeneratedUpvalues"
} ,
} ,
} ,
timing = {
type = "object" ,
description = "Where the build's wall-clock time went. Absent when a diagnostic stopped the build, since a run that did not finish has no account of itself to give."

,
properties = {
totalMs = { type = "number" , description = "Wall-clock milliseconds for the whole build." } ,
compiledModules = { type = "integer" } ,
reusedModules = { type = "integer" } ,
specializedBodies = {
type = "integer" ,
description = "Logical const-specialized bodies emitted independently of module count." ,
} ,
parallel = require ( "nupp.tools.cli.report" ) . PARALLEL ,
phases = {
type = "array" ,
description = "Every activity that took measurable time, longest first. One activity is current at a time, so these sum to the whole. A target with an ahead-of-time policy accounts for it separately under aot:lookup, aot:check, aot:lower, aot:verify, aot:emit, aot:reuse, aot:compile and aot:link -- respectively testing whether a completed policy may be reused, checking the sources that carry an @aot body, lowering them, verifying the lowered IR against the target, writing the LLVM IR and the bindings, deciding what may be reused, compiling objects or Wasm modules in process, and archiving or linking what it produced. Plain aot is whatever the policy did besides those."









,
items = {
type = "object" ,
properties = { name = { type = "string" } , durationMs = { type = "number" } } ,
required = { "name" , "durationMs" } ,
} ,
} ,
aot = {
type = "object" ,
description = "What the ahead-of-time policy did. Absent when the target has none. externalCommands counts every external toolchain process the policy started, version probes included, so an unchanged build reports zero."


,
properties = {
units = {
type = "integer" ,
description = "LLVM IR units the policy emitted, one per source and target tier." ,
} ,
checkedSources = {
type = "integer" ,
description = "Sources checked by the AOT policy in this build." ,
} ,
loweredPrograms = {
type = "integer" ,
description = "Programs lowered by the AOT policy in this build." ,
} ,
optimizedPrograms = {
type = "integer" ,
description = "Programs optimized by the AOT policy in this build." ,
} ,
emittedUnits = {
type = "integer" ,
description = "Source-tier LLVM IR units emitted by the AOT policy in this build." ,
} ,
reusedObjects = {
type = "integer" ,
description = "Native objects taken from the last build unchanged." ,
} ,
compiledObjects = {
type = "integer" ,
description = "Native objects the code generator compiled in this build." ,
} ,
reusedModules = {
type = "integer" ,
description = "Wasm modules taken from the last build unchanged." ,
} ,
compiledModules = {
type = "integer" ,
description = "Wasm modules the code generator compiled in this build." ,
} ,
linked = { type = "boolean" , description = "Whether an archiver or a linker ran." , } ,
externalCommands = {
type = "integer" ,
description = "External toolchain processes the policy started." ,
} ,
} ,
required = {
"units" ,
"checkedSources" ,
"loweredPrograms" ,
"optimizedPrograms" ,
"emittedUnits" ,
"reusedObjects" ,
"compiledObjects" ,
"reusedModules" ,
"compiledModules" ,
"linked" ,
"externalCommands"
} ,
} ,
slowest = {
type = "array" ,
description = "The costliest modules, longest first, each charged for its own checking and generation and not for its dependencies'."
,
items = {
type = "object" ,
properties = { module = { type = "string" } , durationMs = { type = "number" } } ,
required = { "module" , "durationMs" } ,
} ,
} ,
} ,
required = { "totalMs" , "compiledModules" , "reusedModules" , "specializedBodies" , "phases" , "slowest" , } ,
} ,
ok = { type = "boolean" , description = "Whether the build completed. False when a diagnostic stopped it." } ,
} ,
required = { "ok" , "diagnostics" , "written" , "materializations" , "derives" } ,
}



local function configuredTarget ( name ) 
local project = require ( "nupp.tools.build.project" )
local config = project . loadManifest ( "." )
local targets = config and config . build and config . build . targets or { }

return targets [ name ] ~= nil
end

local function run ( options ) 
local positional = options . paths
local values = options
local _ , compatError = require ( "nupp.compiler.compat" ) . resolve ( values . compat , nil )
if compatError then
return usageError ( compatError )
end
local paths = positional


local outDir = # paths > 0 and values . output or nil
local projectOutDir = # paths == 0 and values . output or nil
local target = values . target
if values . remarksOut == "" then
return usageError ( "--remarks-out= requires a file name" )
end
if # paths > 0 and ( target or values . platform or values . standalone or values . host ) then
return usageError ( "--target, --platform, --host and --standalone cannot be used with explicit source files" )
end




for _ , path in ipairs ( paths ) do
if not files . isFile ( path ) and configuredTarget ( path ) then
return usageError (
("%s names a build target rather than a source file; build it with --target %s") : format ( path , path )
)
end
end
local reportMod = require ( "nupp.tools.cli.report" )
local asJson = values . format == "json"


local diagnostics = { }
local compile = require ( "nupp.tools.cli.compile" )
local settings = compile . settings ( values , asJson and diagnostics or nil )



local progressMode = values . progress or ( asJson and "never" or nil )
local materializations = { }
local derives = { }



local function finish ( code , produced ) 



compile . writeRemarks ( settings )
if asJson then
reportMod . write ( {
ok = code == 0 ,
diagnostics = reportMod . diagnosticValues ( diagnostics ) ,
target = produced . target ,
compat = produced . compat or settings . compat ,
platform = produced . platform ,
platforms = produced . platforms ,
distributionReady = produced . distributionReady ,
notice = produced . notice ,
written = produced . outputs or { } ,
artifact = produced . artifact ,
aotManifest = produced . aotManifest ,
materializations = produced . materializations or materializations ,
derives = produced . derives or derives ,
spi = produced . spi or { } ,
timing = code == 0 and produced . timing or nil ,
} )
end

return code
end

if # paths == 0 then
local project = require ( "nupp.tools.build.project" )
local produced = { }
local code = project . build ( "." , {
outDir = projectOutDir ,
target = target ,
platform = values . platform ,
standalone = values . standalone ,
compat = values . compat ,
host = values . host ,
strict = settings . strict ,
optLevel = settings . optLevel ,
remarks = settings . remarks ,
remarksFile = settings . remarksFile ,
disabled = settings . disabled ,
diagnostics = asJson and diagnostics or nil ,
produced = ( asJson or settings . remarksOut ~= nil ) and produced or nil ,
progress = progressMode
} )
if settings . remarksOut then
settings . optLevel = produced . optLevel or settings . optLevel
settings . collectedRemarks = produced . optimizationRemarks or { }
settings . collectedAllocationSites = produced . allocationSites or { }
settings . accountedModules = produced . accountedModules or 0
end
return finish ( code , produced )
end
local fs = require ( "nupp.compiler.fs" )
outDir = outDir or "build"
if outDir and not fs . mkdir ( outDir ) then
reportMod . fileFailure (
outDir ,
"cannot create output directory " .. outDir ,
"check that the directory can be created" ,
asJson and diagnostics or nil
)
return finish ( 1 , { } )
end
local envMod = require ( "nupp.compiler.project.env" )
local env = envMod . new ( "." , { compat = values . compat } )
settings . compat = env . compat
settings . materializations = materializations
settings . derives = derives
settings . specializedBodies = 0



local progressMod = require ( "nupp.tools.build.progress" )
local report = progressMod . new ( progressMode )
local failed = false
local written = { }
local outputs = { }
local runtimeNames = { }
local runtimeDone = { }
local gen = require ( "nupp.compiler.lua.gen" )
local carried = require ( "nupp.compiler.bundled" )





local function emitModule ( givenPath , moduleName , sourceOverride ) 
local path = fs . normalize ( givenPath )
if written [ path ] then
return true
end
written [ path ] = true
report : at ( "compile" )
report : step ( "compiling " .. path )
local startedAt = progressMod . now ( )
local before = settings . specializedBodies
local code = compile . module ( path , env , settings , moduleName , sourceOverride )
report : addSpecialized ( ( settings . specializedBodies ) - before )
report : spent ( path , progressMod . now ( ) - startedAt )
report : resolved ( )
if not code then
report : clear ( )
return false
end
for _ , name in ipairs ( gen . runtimeModules ( code ) ) do
if name == "nupp.runtime.managed" then
runtimeNames [ name ] = true
end
end
local outPath
if outDir then






local relative = path
if path : sub ( 1 , 1 ) == "/" or path : match ( "^[A-Za-z]:/" ) then
relative = path : match ( "([^/]+)$" ) or path
end
outPath = outDir .. "/" .. relative : gsub ( "%.g%.nupp$" , "" ) : gsub ( "%.nupp$" , "" ) .. ".lua"
else
outPath = path : gsub ( "%.g%.nupp$" , "" ) : gsub ( "%.nupp$" , "" ) .. ".lua"
end
report : at ( "write" )
local wrote , err = fs . writeFile ( outPath , code )
if not wrote then
reportMod . fileFailure ( outPath , err , "check that the output path is writable" , asJson and diagnostics or nil )
return false
end
outputs [ # outputs + 1 ] = outPath

return true
end

for _ , path in ipairs ( paths ) do
if not emitModule ( path ) then
failed = true
end
end





local pending = true
while pending do
pending = false
local reached = { }
for _ , record in pairs ( env . loaded or { } ) do
if record . path then
reached [ # reached + 1 ] = record . path
end
end



local runtime = { }
for name in pairs ( runtimeNames ) do
if not runtimeDone [ name ] then
runtime [ # runtime + 1 ] = name
end
end
table . sort ( runtime )
for _ , name in ipairs ( runtime ) do
runtimeDone [ name ] = true
local path = envMod . findRuntimeModulePath ( env , name )
if path and path : match ( "%.nupp$" ) then
pending = true
if not emitModule ( path , name ) then
failed = true
end
elseif path == nil or path : match ( "%.lua$" ) then
for _ , suffix in ipairs ( { ".nupp" , ".g.nupp" , "/init.nupp" , "/init.g.nupp" } ) do
local relative = name : gsub ( "%." , "/" ) .. suffix
local source = carried . source ( "/" .. relative )
if source then
pending = true
if not emitModule ( relative , name , source ) then
failed = true
end
do break end
end
end
end
end
table . sort ( reached )
for _ , path in ipairs ( reached ) do
if path : match ( "%.nupp$" ) and not path : match ( "%.d%.nupp$" ) and not written [ path ] then
pending = true
if not emitModule ( path ) then
failed = true
end
end
end
end
table . sort ( outputs )
report : counted ( # outputs , 0 )



if not failed then
report : finish ( "built" )
end

return finish ( failed and 1 or 0 , { outputs = outputs , timing = report : timing ( ) } )
end




















local Build = {} Build.__index = Build
















































































function Build:run() 
return run ( self )
end ;Build.__nuppInit1=function(__nuppT7, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16) __nuppT7.target = a1 __nuppT7.platform = a2 if a3 == nil then __nuppT7.standalone = false else __nuppT7.standalone = a3 end __nuppT7.output = a4 if a5 == nil then __nuppT7.strict = false else __nuppT7.strict = a5 end __nuppT7.host = a6 __nuppT7.compat = a7 __nuppT7.optLevel = a8 if a9 == nil then __nuppT7.remarks = false else __nuppT7.remarks = a9 end __nuppT7.remarksFor = a10 __nuppT7.remarksOut = a11 if a12 == nil then __nuppT7.disabled = {} else __nuppT7.disabled = a12 end __nuppT7.progress = a13 if a14 == nil then __nuppT7.format = "text" else __nuppT7.format = a14 end if a15 == nil then __nuppT7.schema = false else __nuppT7.schema = a15 end if a16 == nil then __nuppT7.paths = {} else __nuppT7.paths = a16 end return __nuppT7 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Build source files or a configured project target.\n\nWith files, emits those modules and their dependencies. Without files,\nbuilds the manifest's default or selected target.\nManifest target options cannot be combined with explicit source files.\nThe optimization level is part of the build key, so changing it rebuilds\nrather than mixing artifacts compiled at two levels. JSON output carries\ndiagnostics, written artifacts, materialization facts, and timing data.\nProgress and timing stay on standard error so machine-readable standard\noutput remains one document.\n\nExamples:\n\n    nupp build\n    nupp build --target app\n    nupp build -O2 --remarks\n    nupp build -o build/generated src/main.nupp",["group"]=false,["hidden"]=false,["name"]="build",["summary"]="Build source files or a configured project target."},["fieldCount"]=16,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--target",["documentation"]="Build a named manifest target.",["field"]="target",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"target"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--platform",["documentation"]="Build one configured binary platform, or all.",["field"]="platform",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"platform"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--standalone",["documentation"]="Link native FFI and AOT code into the binary host.",["field"]="standalone",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"standalone"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--output",["documentation"]="Output directory, overriding the target's.",["field"]="output",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"output","o"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--strict",["documentation"]="Treat strict checker rules as errors.",["field"]="strict",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"strict"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"native","browser"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--host",["documentation"]="Runtime host services.",["field"]="host",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"host"},["optional"]=true,["required"]=false,["role"]="option",["value"]="HOST"},{["arity"]="required",["choices"]={"lua51"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--compat",["documentation"]="Enforce the stock Lua 5.1 source subset without compatibility lowering.",["field"]="compat",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"compat"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PROFILE"},{["arity"]="required",["choices"]={"0","1","2"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="-O0, -O1, -O2",["displayOverride"]="-O0, -O1, -O2",["documentation"]="Optimization level.",["field"]="optLevel",["hidden"]=false,["index"]=8,["long"]=false,["matchKey"]="O",["names"]={},["optional"]=true,["pattern"]="^%-O([0-2])$",["required"]=false,["role"]="option",["value"]="LEVEL"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--remarks",["documentation"]="Report what the optimizer did and what it declined to do.",["field"]="remarks",["hidden"]=false,["index"]=9,["long"]=true,["names"]={"remarks"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--remarks-for",["documentation"]="Only report optimizer decisions for this source file.",["field"]="remarksFor",["hidden"]=false,["index"]=10,["long"]=true,["names"]={"remarks-for"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FILE"},{["arity"]="optionalAttached",["constant"]="build/remarks.json",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--remarks-out",["documentation"]="Write the optimizer's account to a file, build/remarks.json by default.",["field"]="remarksOut",["hidden"]=false,["index"]=11,["long"]=true,["names"]={"remarks-out"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="attachedOnly",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--Zno-opt",["displayOverride"]="-Zno-opt=CODE",["documentation"]="Turn off one optimizer pass by stable code.",["field"]="disabled",["hidden"]=false,["index"]=12,["long"]=false,["names"]={"Zno-opt"},["repeated"]=true,["required"]=false,["role"]="option",["set"]=true,["value"]="CODE"},{["arity"]="optionalAttached",["choices"]={"always","never","auto"},["constant"]="always",["constants"]={["q"]="never",["quiet"]="never"},["conversion"]="choice",["destination"]="string",["display"]="--progress",["documentation"]="When to report progress and timing.",["field"]="progress",["hidden"]=false,["index"]=13,["long"]=true,["names"]={"progress","q","quiet"},["optional"]=true,["required"]=false,["role"]="option",["value"]="WHEN"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=14,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=15,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to build.",["field"]="paths",["hidden"]=false,["index"]=16,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to build.",["field"]="paths",["hidden"]=false,["index"]=16,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="72b8a1197e487904e801aef786dd22e895db889c6f9453fba7d3bfc57aff2877",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.build:Build:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="build"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Build source files or a configured project target."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Build?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Build",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.build:Build:1",Build,__nuppDerived) ;Build["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Build["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("build")end ;Build["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Build source files or a configured project target.")end ;Build["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Build,__nuppT1[1],{ })


function Build . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Build } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.build"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.build"]=__nuppExports;return __nuppExports