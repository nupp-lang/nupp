_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.bench\0runtime\0001") };










local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "bench" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local RUN_SCHEMA = {
type = "object" ,
description = "One benchmark-set run, with every fork of every selected benchmark." ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
schema = { type = "integer" } ,
recordedAt = { type = "string" } ,
label = { type = "string" } ,
gpuCostsDirectory = {
type = "string" ,
description = "Unique directory containing this run's per-fork GPU cost records."
} ,
forks = { type = "integer" , description = "Processes each benchmark was run in." } ,
seed = { type = "integer" , description = "Seed for the per-round permutation, so an order can be reproduced." } ,
margin = { type = "number" , description = "Equivalence margin for duration verdicts, as a fraction." } ,
machineKey = {
type = "string" ,
description = "Stable identity of the machine. Durations are only compared across records sharing it." ,
} ,
hostProfile = {
type = "object" ,
description = "Platform facts. These identify a class of machine, not a machine; machineKey does that." ,
} ,
comparison = {
type = "string" ,
description = "interleaved for a paired causal comparison, observational for one against a stored record." ,
} ,
comparisons = {
type = "array" ,
description = "Comparison evidence, serialized after verdicts are calculated. Candidate measurements are in benchmarks." ,
items = {
type = "object" ,
properties = {
kind = { type = "string" , enum = { "interleaved" , "observational" } } ,
source = { type = "string" , description = "Baseline executable or saved record path." } ,
baseline = {
type = "object" ,
description = "Baseline benchmark summaries and every fork's ordered samples, with stored-record provenance when available." ,
} ,
verdicts = {
type = "array" ,
items = {
type = "object" ,
properties = {
case = { type = "string" } ,
name = { type = "string" } ,
change = { type = "number" , description = "Relative duration change as a fraction." } ,
interval = {
type = "object" ,
properties = { low = { type = "number" } , upper = { type = "number" } }
} ,
withheld = { type = "string" , description = "Reason no interval is reported." } ,
pValue = { type = "number" } ,
adjusted = { type = "number" , description = "Benjamini-Hochberg adjusted p-value." } ,
verdict = {
type = "string" ,
enum = { "improved" , "regressed" , "unchanged" , "inconclusive" }
} ,
} ,
required = { "case" , "name" , "change" , "pValue" , "adjusted" , "verdict" } ,
} ,
} ,
} ,
required = { "kind" , "source" , "baseline" , "verdicts" } ,
} ,
} ,
benchmarks = {
type = "array" ,
items = {
type = "object" ,
properties = {
case = { type = "string" , description = "Benchmark program path." } ,
name = { type = "string" , description = "Selected benchmark name." } ,
forks = {
type = "array" ,
description = "One entry per process, in execution order, each keeping its own ordered samples." ,
items = {
type = "object" ,
properties = {
index = { type = "integer" } ,
gpuCosts = {
type = "string" ,
description = "This fork's GPU JSONL cost record, when requested."
} ,
measurement = { type = "object" , description = "That fork's whole measurement." } ,
} ,
required = { "index" , "measurement" } ,
} ,
} ,
summary = {
type = "object" ,
description = "The merged measurement: fork summaries, the interval or why it was withheld, and the unanimous abort sites."
,
} ,
} ,
required = { "case" , "name" , "forks" , "summary" } ,
} ,
} ,
} ,
required = { "ok" , "schema" , "recordedAt" , "benchmarks" } ,
}

local LIST_SCHEMA = {
type = "object" ,
description = "The benchmarks --list selected, without running any." ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
benchmarks = {
type = "array" ,
items = {
type = "object" ,
properties = {
name = { type = "string" } ,
file = { type = "string" } ,
suite = { type = "string" } ,
case = { type = "string" } ,
variant = { type = "string" } ,
parameters = { type = "object" } ,
} ,
required = { "name" , "file" } ,
} ,
} ,
} ,
required = { "ok" , "benchmarks" } ,
}



local REPORT_SCHEMA = {
description = "One run, or with --list the benchmarks a run would select." ,
anyOf = { RUN_SCHEMA , LIST_SCHEMA } ,
}

local function invalidPattern ( patterns ) 
for _ , pattern in ipairs ( patterns or { } ) do
local ok = pcall ( function ( ) 
return ("") : match ( pattern )
end )
if not ok then
return pattern
end
end

return nil
end

local function run ( options ) 
local positional = { }
if # positional > 0 then
return usageError ( "unexpected argument " .. positional [ 1 ] )
end
local values = options
if values . accept and not values . baseline then
return usageError ( "--accept needs --baseline PATH" )
end
if values . list
and (
values . baseline
or values . accept
or values . history
or values . label
or values . geo
or values . profile
or values . gpuCosts
or values . profileIntervalMs
or values . profileZone
or values . forks
or values . margin
or values . pilot
or values . against
)
then
return usageError ( "--list cannot be combined with result, baseline, history, or profile options" )
end
local forks = nil
if values . forks then
local given = tonumber ( values . forks )
if not given or given < 1 or given ~= math . floor ( given ) then
return usageError ( "--forks needs a positive whole number" )
end
forks = math . floor ( given )
end
local margin = nil
if values . margin then
local given = tonumber ( values . margin )
if not given or given <= 0 then
return usageError ( "--margin needs a positive percentage" )
end
margin = given / 100
end
if values . margin and not values . baseline and not values . against then
return usageError ( "--margin needs --baseline PATH or --against PATH to compare against" )
end
if values . against and not values . margin then
return usageError ( "--against needs --margin PERCENT, the margin its verdicts are judged against" )
end
if values . pilot and ( values . forks or values . baseline or values . margin or values . against ) then
return usageError ( "--pilot runs its own forks and reports no result, so it takes no forks, baseline or margin" )
end
local timeoutMs = nil
if values . timeoutMs then
local given = tonumber ( values . timeoutMs )
if not given or given < 1 or given ~= math . floor ( given ) then
return usageError ( "--timeout-ms needs a positive whole number" )
end
timeoutMs = math . floor ( given )
end
local profileIntervalMs = nil
if values . profileIntervalMs then
local given = tonumber ( values . profileIntervalMs )
if not given or given < 1 or given ~= math . floor ( given ) then
return usageError ( "--profile-interval-ms needs a positive whole number" )
end
profileIntervalMs = math . floor ( given )
end
if ( values . profileIntervalMs or values . profileZone ) and not values . profile then
return usageError ( "--profile-interval-ms and --profile-zone need --profile DIR" )
end
for _ , entry in ipairs ( {
{ name = "--case" , patterns = values . caseGmatch } ,
{ name = "--parameter" , patterns = values . parameter } ,
{ name = "--variant" , patterns = values . variant } ,
} ) do
local invalid = invalidPattern ( entry . patterns )
if invalid then
return usageError ( entry . name .. " has an invalid Lua pattern: " .. invalid )
end
end
local compilerRoot = os . getenv ( "NUPP_COMPILER_ROOT" )
local hosted = rawget ( _G , "__NUPP_EXECUTABLE" )
local executable = compilerRoot and compilerRoot .. "/bin/nupp"
or type ( hosted ) == "string" and hosted
or tostring ( arg [ 0 ] or "nupp" )

local runner = require ( "nupp.tools.benchrunner" )

return runner . run (
{
executable = executable ,
baseline = values . baseline ,
accept = values . accept ,
json = values . json ,
geo = values . geo ,
casePatterns = values . caseGmatch ,
parameterPatterns = values . parameter ,
variantPatterns = values . variant ,
file = values . file ,
history = values . history ,
label = values . label ,
timeoutMs = timeoutMs ,
list = values . list ,
profileDir = values . profile ,
gpuCostsDir = values . gpuCosts ,
profileIntervalMs = profileIntervalMs ,
profileZone = values . profileZone ,
forks = forks ,
seed = values . seed ,
margin = margin ,
pilot = values . pilot ,
against = values . against ,
}
)
end














local Bench = {} Bench.__index = Bench




















































































function Bench:run() 
return run ( self )
end ;Bench.__nuppInit1=function(__nuppT6, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22) if a1 == nil then __nuppT6.list = false else __nuppT6.list = a1 end __nuppT6.file = a2 if a3 == nil then __nuppT6.caseGmatch = {} else __nuppT6.caseGmatch = a3 end if a4 == nil then __nuppT6.parameter = {} else __nuppT6.parameter = a4 end if a5 == nil then __nuppT6.variant = {} else __nuppT6.variant = a5 end if a6 == nil then __nuppT6.geo = false else __nuppT6.geo = a6 end __nuppT6.forks = a7 __nuppT6.seed = a8 __nuppT6.margin = a9 if a10 == nil then __nuppT6.pilot = false else __nuppT6.pilot = a10 end __nuppT6.against = a11 __nuppT6.timeoutMs = a12 __nuppT6.gpuCosts = a13 __nuppT6.profile = a14 __nuppT6.profileIntervalMs = a15 __nuppT6.profileZone = a16 __nuppT6.baseline = a17 if a18 == nil then __nuppT6.accept = false else __nuppT6.accept = a18 end __nuppT6.history = a19 __nuppT6.label = a20 if a21 == nil then __nuppT6.json = false else __nuppT6.json = a21 end if a22 == nil then __nuppT6.schema = false else __nuppT6.schema = a22 end return __nuppT6 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Run isolated benchmark programs.\n\nSelectors are Lua string patterns. Repeated patterns within one dimension\nare alternatives; the command interprets and validates those strings.\n\nExamples:\n\n    nupp bench --list\n    nupp bench --file bench/optparser.bench.nupp --forks 15\n    nupp bench --case mixed-argv --variant record-token --json\n    nupp bench --against ./build/baseline/bin/nupp --margin 2",["group"]=false,["hidden"]=false,["name"]="bench",["summary"]="Run isolated benchmark programs."},["fieldCount"]=22,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--list",["documentation"]="List benchmark names and source files without running.\n\nAn aligned table, or the same listing as JSON under `--json`.",["field"]="list",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"list"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--file",["documentation"]="Inspect and run only one benchmark program.",["field"]="file",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"file"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--case",["documentation"]="Run logical case names matching a Lua pattern.",["field"]="caseGmatch",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"case"},["repeated"]=true,["required"]=false,["role"]="option",["value"]="PATTERN"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--parameter",["documentation"]="Run parameter text matching a Lua pattern.",["field"]="parameter",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"parameter"},["repeated"]=true,["required"]=false,["role"]="option",["value"]="PATTERN"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--variant",["documentation"]="Run variant names matching a Lua pattern.",["field"]="variant",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"variant"},["repeated"]=true,["required"]=false,["role"]="option",["value"]="PATTERN"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--geo",["documentation"]="Include geometric-mean variant comparisons.",["field"]="geo",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"geo"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--forks",["documentation"]="Processes to run each benchmark in.",["field"]="forks",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"forks"},["optional"]=true,["required"]=false,["role"]="option",["value"]="INTEGER"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--seed",["documentation"]="Seed for the per-round permutation.",["field"]="seed",["hidden"]=false,["index"]=8,["long"]=true,["names"]={"seed"},["optional"]=true,["required"]=false,["role"]="option",["value"]="INTEGER"},{["arity"]="required",["constants"]={},["conversion"]="number",["destination"]="number",["display"]="--margin",["documentation"]="Practical equivalence margin, as a percentage, for duration verdicts.",["field"]="margin",["hidden"]=false,["index"]=9,["long"]=true,["names"]={"margin"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PERCENT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--pilot",["documentation"]="Estimate variance and report the forks a precision would need.",["field"]="pilot",["hidden"]=false,["index"]=10,["long"]=true,["names"]={"pilot"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--against",["documentation"]="Another nupp executable to measure beside this one, interleaved and paired.",["field"]="against",["hidden"]=false,["index"]=11,["long"]=true,["names"]={"against"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--timeout-ms",["documentation"]="Child deadline in milliseconds.",["field"]="timeoutMs",["hidden"]=false,["index"]=12,["long"]=true,["names"]={"timeout-ms"},["optional"]=true,["required"]=false,["role"]="option",["value"]="INTEGER"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--gpu-costs",["documentation"]="Write GPU JSONL cost records per case and fork in a unique run directory.",["field"]="gpuCosts",["hidden"]=false,["index"]=13,["long"]=true,["names"]={"gpu-costs"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--profile",["documentation"]="Write one collapsed-stack profile per case under this directory.",["field"]="profile",["hidden"]=false,["index"]=14,["long"]=true,["names"]={"profile"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--profile-interval-ms",["documentation"]="Sampling interval in milliseconds.",["field"]="profileIntervalMs",["hidden"]=false,["index"]=15,["long"]=true,["names"]={"profile-interval-ms"},["optional"]=true,["required"]=false,["role"]="option",["value"]="INTEGER"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--profile-zone",["documentation"]="Keep profile samples under this zone subtree.",["field"]="profileZone",["hidden"]=false,["index"]=16,["long"]=true,["names"]={"profile-zone"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PREFIX"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--baseline",["documentation"]="Compare deterministic counters with this baseline.",["field"]="baseline",["hidden"]=false,["index"]=17,["long"]=true,["names"]={"baseline"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--accept",["documentation"]="Replace the named baseline after a complete run.",["field"]="accept",["hidden"]=false,["index"]=18,["long"]=true,["names"]={"accept"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--history",["documentation"]="Append the complete record as one NDJSON line.",["field"]="history",["hidden"]=false,["index"]=19,["long"]=true,["names"]={"history"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--label",["documentation"]="Attach a label to the record and history entry.",["field"]="label",["hidden"]=false,["index"]=20,["long"]=true,["names"]={"label"},["optional"]=true,["required"]=false,["role"]="option",["value"]="TEXT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--json",["documentation"]="Write only the merged JSON record to stdout, or the listing under `--list`.",["field"]="json",["hidden"]=false,["index"]=21,["long"]=true,["names"]={"json"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=22,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"}},["positionals"]={},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="d838368723879b7c15fa61bf51ffd3f92059b129131206e5481426c458e00f3a",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.bench:Bench:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="bench"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Run isolated benchmark programs."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Bench?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Bench",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.bench:Bench:1",Bench,__nuppDerived) ;Bench["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Bench["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("bench")end ;Bench["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Run isolated benchmark programs.")end ;Bench["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Bench,__nuppT1[1],{ })


function Bench . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Bench } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.bench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.bench"]=__nuppExports;return __nuppExports