_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.check\0runtime\0001") };




















local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "check" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = {
type = "boolean" ,
description = "Whether the check ran and found nothing wrong. False always comes with at least one coded error in `diagnostics`: a project that reported one, or a run that never got as far as checking, such as one whose manifest could not be used (NUPP0002)."


,
} ,
diagnostics = require ( "nupp.tools.cli.report" ) . DIAGNOSTICS ,
compat = { type = "string" , enum = { "lua51" } , description = "The enforced source compatibility profile." } ,
platform = { type = "string" } ,
platforms = { type = "array" , items = { type = "object" } } ,
timing = {
type = "object" ,
description = "Where the check's wall-clock time went, and how many of the project's modules were reused from the cache versus rechecked this run, including explicitly named files. `compiledModules = 0` is the authoritative answer that nothing was redone; `slowest` ranks modules by time actually spent regardless of that answer, since confirming a module's cache entry is still valid costs time too, only less of it."




,
properties = {
totalMs = { type = "number" , description = "Wall-clock milliseconds for the whole check." } ,
compiledModules = { type = "integer" } ,
reusedModules = { type = "integer" } ,
specializedBodies = { type = "integer" } ,
parallel = require ( "nupp.tools.cli.report" ) . PARALLEL ,
phases = {
type = "array" ,
description = "Every activity that took measurable time, longest first. One activity is current at a time, so these sum to the whole."
,
items = {
type = "object" ,
properties = { name = { type = "string" } , durationMs = { type = "number" } } ,
required = { "name" , "durationMs" } ,
} ,
} ,
slowest = {
type = "array" ,
description = "The costliest modules, longest first, each charged for its own checking and not for its dependencies'. A module reused from the cache still spends time being confirmed valid, so it can appear here even when `compiledModules` is 0."


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
} ,
required = { "ok" , "diagnostics" } ,
}

local function run ( options ) 
local positional = options . files
local paths = positional
local values = options


local strict = values . strict and true or nil
local _ , compatError = require ( "nupp.compiler.compat" ) . resolve ( values . compat , nil )
if compatError then
return usageError ( compatError )
end
local target = values . target
if ( target or values . platform ) and # paths > 0 then
return usageError ( "--target and --platform cannot be combined with source files" )
end
local asJson = values . format == "json"



local progressMode = values . progress or ( asJson and "never" or nil )
local reportMod = require ( "nupp.tools.cli.report" )
local diagnostics = { }

local progress = require ( "nupp.tools.build.progress" )
local started = progress . now ( )
local timing = { compiledModules = 0 , reusedModules = 0 , specializedBodies = 0 , phases = { } , slowest = { } }

local effectiveCompat = values . compat

local function writeJson ( ok ) 
local total = progress . now ( ) - started
timing . totalMs = total
timing . phases = { { name = "check" , durationMs = total } }
reportMod . write ( {
ok = ok ,
diagnostics = reportMod . diagnosticValues ( diagnostics ) ,
compat = effectiveCompat ,
timing = timing
} )
end

if # paths == 0 then
local project = require ( "nupp.tools.build.project" )
local produced = { }
local code = project . check ( "." , {
strict = strict ,
compat = values . compat ,
target = target ,
platform = values . platform ,
diagnostics = asJson and diagnostics or nil ,
produced = asJson and produced or nil ,
progress = progressMode
} )
if not produced . timing then
local total = progress . now ( ) - started
timing . totalMs = total
timing . phases = { { name = "check" , durationMs = total } }
produced . timing = timing
end
effectiveCompat = produced . compat or effectiveCompat
if asJson then
reportMod . write ( {
ok = code == 0 ,
diagnostics = reportMod . diagnosticValues ( diagnostics ) ,
compat = effectiveCompat ,
platform = produced . platform ,
platforms = produced . platforms ,
timing = produced . timing ,
} )
end
return code
end
local fs = require ( "nupp.compiler.fs" )
local parser = require ( "nupp.compiler.syntax.parser" )
local check = require ( "nupp.compiler.check" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local failed = false





local readable , sources = { } , { }
for _ , path in ipairs ( paths ) do
local source , err = fs . readFile ( path )
if source then
readable [ # readable + 1 ] = path
sources [ path ] = source
else
reportMod . fileFailure (
path ,
err ,
"check that the path exists and is readable" ,
asJson and diagnostics or nil
)
failed = true
end
end











local remaining = readable



local config = nil
if # readable > 0 and fs . exists ( "nupp.lua" ) then
local loaded , loadErr = require ( "nupp.tools.build.manifest" ) . load ( "." )
if not loaded then
if asJson then
diagnostics [
# diagnostics + 1
] = reportMod . runDiagnostic (
reportMod . MANIFEST ,
tostring ( loadErr ) ,
"fix the manifest, or check the file from a directory without one" ,
"nupp.lua"
)
writeJson ( false )
else
io . stderr : write ( tostring ( loadErr ) .. "\n" )
end

return 1
end
config = loaded
end
if config then
local envMod = require ( "nupp.compiler.project.env" )
local roots = envMod . projectRoots ( "." , config )
local mine = { }
for _ , path in ipairs ( readable ) do
if envMod . moduleNameInRoots ( roots , path ) then
mine [ # mine + 1 ] = path
end
end



if # mine > 0 then
local project = require ( "nupp.tools.build.project" )
local unchecked = { }
local produced = { }
local code = project . check ( "." , {
strict = strict ,
compat = values . compat ,
paths = mine ,
unchecked = unchecked ,
diagnostics = asJson and diagnostics or nil ,
produced = produced ,
progress = progressMode ,
} )
if produced . timing then
timing = produced . timing
end
effectiveCompat = produced . compat or effectiveCompat
if code ~= 0 then
failed = true
end
remaining = { }
local handled = { }
for _ , path in ipairs ( mine ) do
handled [ path ] = true
end
for _ , path in ipairs ( unchecked ) do
handled [ path ] = nil
end
for _ , path in ipairs ( readable ) do
if not handled [ path ] then
remaining [ # remaining + 1 ] = path
end
end
end
end
if # remaining == 0 then
if asJson then
writeJson ( not failed )
end

return failed and 1 or 0
end

local env = require ( "nupp.compiler.project.env" ) . new ( "." , { compat = values . compat } )
effectiveCompat = env . compat or effectiveCompat
for _ , path in ipairs ( remaining ) do
timing . compiledModules = timing . compiledModules + 1
local fileStarted = progress . now ( )
local result = parser . parse ( sources [ path ] , path )
if # result . errors > 0 then
if asJson then
for _ , diagnostic in ipairs ( result . errors ) do
diagnostics [ # diagnostics + 1 ] = diagnostic
end
else
diagnosticMod . report ( result . errors )
end
failed = true
else
local diags = check . check ( result , path , env , { strict = strict , compat = values . compat , } )
if asJson then
for _ , diagnostic in ipairs ( diags ) do
diagnostics [ # diagnostics + 1 ] = diagnostic
if diagnosticMod . isFatal ( diagnostic ) then
failed = true
end
end
elseif diagnosticMod . report ( diags ) then
failed = true
end
end
timing . slowest [ # timing . slowest + 1 ] = { module = path , durationMs = progress . now ( ) - fileStarted }
end
table . sort ( timing . slowest , function ( a , b ) 
return a . durationMs > b . durationMs
end )
while # timing . slowest > progress . SLOWEST do
table . remove ( timing . slowest )
end



require ( "nupp.compiler.project.env" ) . persist ( env )
if asJson then
writeJson ( not failed )
end

return failed and 1 or 0
end














local Check = {} Check.__index = Check




































function Check:run() 
return run ( self )
end ;Check.__nuppInit1=function(__nuppT6, a1, a2, a3, a4, a5, a6, a7, a8) if a1 == nil then __nuppT6.strict = false else __nuppT6.strict = a1 end __nuppT6.compat = a2 __nuppT6.target = a3 __nuppT6.platform = a4 __nuppT6.progress = a5 if a6 == nil then __nuppT6.format = "text" else __nuppT6.format = a6 end if a7 == nil then __nuppT6.schema = false else __nuppT6.schema = a7 end if a8 == nil then __nuppT6.files = {} else __nuppT6.files = a8 end return __nuppT6 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Type-check source without emitting Lua.\n\nWith no files, checks the configured project target. Named files are\nchecked with project context when available.\n\nExamples:\n\n    nupp check\n    nupp check src/main.nupp\n    nupp check --strict --json\n    nupp check --target app",["group"]=false,["hidden"]=false,["name"]="check",["summary"]="Type-check source without emitting Lua."},["fieldCount"]=8,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--strict",["documentation"]="Treat strict checker rules as errors.",["field"]="strict",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"strict"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"lua51"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--compat",["documentation"]="Enforce the stock Lua 5.1 source subset without compatibility lowering.",["field"]="compat",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"compat"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PROFILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--target",["documentation"]="Check a named manifest target.",["field"]="target",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"target"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--platform",["documentation"]="Check one configured binary platform, or all.",["field"]="platform",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"platform"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="optionalAttached",["choices"]={"always","never","auto"},["constant"]="always",["constants"]={["q"]="never",["quiet"]="never"},["conversion"]="choice",["destination"]="string",["display"]="--progress",["documentation"]="When to report progress and timing.",["field"]="progress",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"progress","q","quiet"},["optional"]=true,["required"]=false,["role"]="option",["value"]="WHEN"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to check.",["field"]="files",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to check.",["field"]="files",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="e2e17b1f7cd4bb3df801af93359292d645a11dbfcbb7a5248b07cf0b5c8a4af4",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.check:Check:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="check"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Type-check source without emitting Lua."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Check?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Check",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.check:Check:1",Check,__nuppDerived) ;Check["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Check["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("check")end ;Check["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Type-check source without emitting Lua.")end ;Check["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Check,__nuppT1[1],{ })


function Check . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Check } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.check"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.check"]=__nuppExports;return __nuppExports