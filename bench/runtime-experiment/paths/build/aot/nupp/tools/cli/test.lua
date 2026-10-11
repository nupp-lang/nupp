_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.test\0runtime\0001") };











local ansi = require ( "nupp.cli" )
local cliModule = ansi
local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "test" )




local phasePrediction = {
type = "object" ,
properties = {
planned = { type = "number" , description = "Predicted milliseconds of work in the phase." } ,
lanes = { type = "integer" , description = "How many workers it was packed for." } ,
heaviest = {
type = "number" ,
description = "The single heaviest piece. A piece longer than the fair share is the phase's floor however many lanes there are."

} ,
floor = { type = "number" , description = "The larger of the fair share and the heaviest piece." } ,
} ,
required = { "planned" , "lanes" , "heaviest" , "floor" } ,
}

local REPORT_SCHEMA = {
type = "object" ,
description = "One run: the totals, and a record per test. This is what the bundled runner writes; a project that configures a different test command is the one answering for its --json. `--coverage --report-json` answers with `#/definitions/coverageReport` instead, which is a report rather than a run."



,
properties = {
schemaVersion = {
type = "integer" ,
enum = { 1 } ,
description = "The report's version. `--rerun` reads only a report of its own version."
} ,
ok = { type = "boolean" } ,
total = { type = "integer" } ,
passed = { type = "integer" } ,
skipped = { type = "integer" } ,
notExecuted = { type = "integer" } ,
failed = { type = "integer" } ,
durationMs = { type = "number" , description = "Wall-clock milliseconds for the whole run." } ,
tests = {
type = "array" ,
items = {
type = "object" ,
properties = {
id = {
type = "string" ,
description = "Stable suite/case ID for an ordinary case, or a synthetic ID for an infrastructure failure."
} ,
suite = { type = "string" , description = "The test file, without its extension." } ,
name = { type = "string" } ,
status = { type = "string" , enum = { "passed" , "skipped" , "not-executed" , "failed" } } ,
durationMs = { type = "number" } ,
file = { type = "string" , description = "Where the test is defined." } ,
line = { type = "integer" , description = "1-based, as everywhere else." } ,
failure = {
type = "object" ,
description = "Present only when the test failed." ,
properties = {
message = { type = "string" } ,
file = {
type = "string" ,
description = "Where the error came from, which is often not where the test is defined."


} ,
line = {
type = "integer" ,
description = "1-based. A Lua error carries no column, so none is reported."
} ,
} ,
required = { "message" } ,
} ,
output = {
type = "object" ,
description = "Captured output from a failed test, or from every test under --verbose." ,
properties = { stdout = { type = "string" } , stderr = { type = "string" } , } ,
required = { "stdout" , "stderr" } ,
} ,
skip = {
type = "object" ,
description = "Present when the test was skipped." ,
properties = { reason = { type = "string" } } ,
required = { "reason" } ,
} ,
notExecuted = {
type = "object" ,
description = "Present when the case could not execute on the current runtime." ,
properties = { reason = { type = "string" } } ,
required = { "reason" } ,
} ,
capabilities = { type = "array" , items = { [ "$ref" ] = "#/definitions/testCapability" } } ,
fixtures = { type = "array" , items = { [ "$ref" ] = "#/definitions/testFixture" } } ,
facts = {
type = "array" ,
description = "Structured facts emitted by a passing case." ,
items = { [ "$ref" ] = "#/definitions/testFact" } ,
} ,
metrics = { type = "array" , items = { [ "$ref" ] = "#/definitions/testMetric" } } ,
} ,
required = { "id" , "suite" , "name" , "status" , "durationMs" } ,
} ,
} ,
metrics = {
type = "array" ,
description = "Additive metric totals across every reported case." ,
items = { [ "$ref" ] = "#/definitions/testMetric" } ,
} ,
suites = {
type = "array" ,
description = "One record per suite the run loaded, which is where the time a run waits for actually goes: a suite costs its cases plus what loading it and its lifecycle hooks cost, and neither of those belongs to any case."


,
items = {
type = "object" ,
properties = {
suite = { type = "string" } ,
durationMs = {
type = "number" ,
description = "Wall-clock milliseconds for the whole suite, loading included."
} ,
loadMs = {
type = "number" ,
description = "Compiling a Nupp suite, or running a Lua suite's top level."
} ,
hooksMs = {
type = "number" ,
description = "beforeAll and afterAll. beforeEach and afterEach are counted with the case they ran for."
} ,
casesMs = { type = "number" } ,
tests = { type = "integer" } ,
slowestCase = { type = "string" } ,
slowestCaseMs = { type = "number" } ,
shard = { type = "integer" , description = "Which shard ran it, absent when the run was serial." } ,
alone = { type = "boolean" , description = "Ran on a process worker rather than on a Nupp worker." } ,
executionLane = { type = "string" , enum = { "shared" , "shell" , "isolated" } } ,
} ,
required = { "suite" , "durationMs" } ,
} ,
} ,
shards = {
type = "array" ,
description = "One record per worker lane, empty when the run was serial. Within an execution lane, the busiest shard is the floor more workers cannot lower."

,
items = {
type = "object" ,
properties = {
index = { type = "integer" } ,
specs = {
type = "array" ,
description = "What it was asked to run: a suite name, or 'name#index/count' for one slice of one." ,
items = { type = "string" } ,
} ,
alone = { type = "boolean" , description = "Ran on a process worker rather than on a Nupp worker." } ,
executionLane = { type = "string" , enum = { "shared" , "shell" , "isolated" } } ,
durationMs = { type = "number" } ,
startedAt = { type = "number" , description = "Milliseconds into the run when it was started." } ,
collectedAt = {
type = "number" ,
description = "Milliseconds into the run when the parent finished reading it. Pipes are read in order, so this says more about read order than about the shard."
} ,
tests = { type = "integer" } ,
} ,
required = { "index" , "durationMs" , "executionLane" } ,
} ,
} ,
prediction = {
type = "object" ,
description = "What the packer said each phase could not finish under, from the timings the last run recorded. Absent when the run was serial. A phase whose busiest shard came out far above its floor was packed from stale timings or starved a lane; one that came out at its floor is as short as that much work gets, and only less work shortens it."




,
properties = { processIsolated = phasePrediction , shared = phasePrediction , shell = phasePrediction } ,
} ,
} ,
required = {
"schemaVersion" ,
"ok" ,
"total" ,
"passed" ,
"skipped" ,
"notExecuted" ,
"failed" ,
"durationMs" ,
"tests" ,
"metrics" ,
"suites" ,
"shards" ,
} ,
definitions = {
testCapability = {
type = "object" ,
properties = { name = { type = "string" } , available = { type = "boolean" } , evidence = { } , } ,
required = { "name" , "available" } ,
} ,
testFixture = {
type = "object" ,
properties = {
key = { type = "string" } ,
path = { type = "string" } ,
reused = { type = "boolean" , description = "False only for the case that published the fixture." } ,
} ,
required = { "key" , "path" , "reused" } ,
} ,
testFact = {
type = "object" ,
properties = { name = { type = "string" } , value = { } } ,
required = { "name" , "value" } ,
} ,
testMetric = {
type = "object" ,
properties = { name = { type = "string" } , value = { type = "number" } , unit = { type = "string" } , } ,
required = { "name" , "value" } ,
} ,
coverageMetric = {
type = "object" ,
properties = {
covered = { type = "integer" } ,
total = { type = "integer" } ,
percent = { type = "number" } ,
missing = { type = "array" , items = { type = "string" } } ,
} ,
} ,
coverageSite = {
type = "object" ,
description = "One place the instrumented program counts reaching." ,
properties = {
id = { type = "integer" } ,
kind = { type = "string" , enum = { "statement" , "function" , "branch" } } ,
line = { type = "integer" } ,
count = { type = "integer" , description = "Times this site was reached." } ,
name = {
type = "string" ,
description = "A function site's declared name, absent when it is anonymous." ,
} ,
endLine = { type = "integer" , description = "The last line of a function site's declaration." } ,
trueCount = { type = "integer" , description = "Branch sites only: times the condition held." } ,
falseCount = { type = "integer" , description = "Branch sites only: times it did not." } ,
} ,
required = { "id" , "kind" , "line" , "count" } ,
} ,
coverageReport = {
type = "object" ,
description = "What `--coverage --report-json` prints: the report already written, rather than a run. An editor reads this to draw a gutter, so a site says where it is, how often it was reached, and -- for a branch -- which way it went."


,
properties = {
schemaVersion = {
type = "integer" ,
enum = { 1 } ,
description = "The report's format. A reader refuses any other, naming both."
} ,
warnings = { type = "array" , items = { type = "string" } } ,
summary = { type = "object" } ,
files = {
type = "array" ,
items = {
type = "object" ,
properties = {
path = { type = "string" } ,
status = { type = "string" , enum = { "covered" , "partial" , "uncovered" , "non-executable" } , } ,
lines = { [ "$ref" ] = "#/definitions/coverageMetric" } ,
functions = { [ "$ref" ] = "#/definitions/coverageMetric" } ,
branches = { [ "$ref" ] = "#/definitions/coverageMetric" } ,
sites = { type = "array" , items = { [ "$ref" ] = "#/definitions/coverageSite" } } ,
} ,
required = { "path" , "sites" } ,
} ,
} ,
} ,
required = { "schemaVersion" , "files" , "summary" } ,
} ,
} ,
}

local function asksForJson ( args ) 
for _ , argument in ipairs ( args ) do
if argument == "--json" then
return true
end
end

return false
end





local function preRunnerFailure ( stage , diagnostics ) 
local report = require ( "nupp.tools.cli.report" )
local values = report . diagnosticValues ( diagnostics )
local lines = { }
for _ , value in ipairs ( values ) do
if value . severity == "error" then
local at = value . range and ( ":" .. value . range . start . line .. ":" .. value . range . start . column ) or ""
lines [
# lines + 1
] = (
value . file and value . file .. at .. ": " or ""
) .. ( value . code and value . code .. ": " or "" ) .. value . message
end
end
local first = values [ 1 ]
local failure

= {
message = # lines > 0 and table . concat ( lines , "\n" )
or ( stage == "manifest" and "nupp.lua could not be used" or "the build under test failed" ) ,
file = first and first . file or ( stage == "manifest" and "nupp.lua" or nil ) ,
line = first and first . range and first . range . start . line or nil ,
}
report . write ( {
schemaVersion = 1 ,
ok = false ,
total = 1 ,
passed = 0 ,
skipped = 0 ,
notExecuted = 0 ,
failed = 1 ,
durationMs = 0 ,
tests = {
{
id = "nupp/<" .. stage .. ">" ,
suite = "nupp" ,
name = "<" .. stage .. ">" ,
status = "failed" ,
durationMs = 0 ,
failure = failure ,
} ,
} ,
metrics = { } ,
suites = { } ,
shards = { } ,
} )

return 1
end

local function applyTestColor ( args ) 
local color = nil
for _ , argument in ipairs ( args ) do
local asked = argument == "--color" and "always"
or argument == "--no-color" and "never"
or argument : match ( "^%-%-color=(.*)$" )
if asked ~= nil then
if asked ~= "always" and asked ~= "never" and asked ~= "auto" then
io . stderr : write ( "nupp: --color must be always, never, or auto\n" )
return 2
end
if color ~= nil and color ~= asked then
io . stderr : write ( "nupp: color was both asked for and refused\n" )
return 2
end
color = asked
end
end
if color ~= nil then
ansi . setColorMode ( color )
end

return nil
end

local function runCoverage ( options ) 
local fs = require ( "nupp.compiler.fs" )
local outDir = options . coverageOut or "build/reports/coverage"
if options . reportJson then
local existing , _ , err = require ( "nupp.tools.coverage" ) . read ( outDir .. "/coverage.json" )
if not existing then
io . stderr : write ( "nupp: " .. tostring ( err ) .. "\n" )
return 1
end
io . write ( existing )
if existing : sub ( -1 ) ~= "\n" then
io . write ( "\n" )
end
return 0
end

local raw = outDir .. "/raw.json"
if not fs . mkdir ( outDir ) then
io . stderr : write ( "nupp: cannot create coverage output " .. outDir .. "\n" )
return 1
end
local project = require ( "nupp.tools.build.project" )
local testCode = project . test ( "." , options . arguments , {
coverage = true ,
outDir = "build/coverage" ,
env = { NUPP_COVERAGE = "1" , NUPP_COVERAGE_BUILD = "build/coverage" , NUPP_COVERAGE_FILE = raw }
} )
local report = require ( "nupp.tools.coverage" )
local model = report . collect ( "build/coverage/.nupp-state.json" , raw )
local summary = report . write ( model , outDir )
local output = asksForJson ( options . arguments ) and io . stderr or io . stdout
output : write (
("coverage: lines %.2f%%, functions %.2f%%, branches %.2f%%\n")

: format ( summary . lines . percent , summary . functions . percent , summary . branches . percent )
)
output : write ( "coverage: report written to " .. outDir .. "/index.html\n" )
if # model . warnings > 0 and testCode == 0 then
io . stderr : write ( "nupp: coverage data is incomplete\n" )
return 1
end

return testCode
end
























local Test = {} Test.__index = Test

















function Test:run() 
if self . arguments [ 1 ] == "--internal-runner" then
local runnerArguments = { }
for index = 2 , # self . arguments do
runnerArguments [ # runnerArguments + 1 ] = self . arguments [ index ]
end
return require ( "nupp.tools.cli.testrunner" ) . run ( runnerArguments )
end
if self . coverageOut ~= nil and not self . coverage then
return usageError ( "--coverage-out requires --coverage" )
elseif self . reportJson and not self . coverage then
return usageError ( "--report-json requires --coverage" )
elseif self . reportJson and # self . arguments > 0 then
return usageError ( "--report-json does not run tests or accept test arguments" )
end
local colorCode = applyTestColor ( self . arguments )
if colorCode ~= nil then
return colorCode
elseif self . coverage then
return runCoverage ( self )
end

if asksForJson ( self . arguments ) then
local diagnostics = { }
local code , stopped = require ( "nupp.tools.build.project" ) . test ( "." , self . arguments , {
diagnostics = diagnostics
} )
if stopped ~= nil then
return preRunnerFailure ( stopped , diagnostics )
end

return code
end

return ( require ( "nupp.tools.build.project" ) . test ( "." , self . arguments ) )
end ;Test.__nuppInit1=function(__nuppT7, a1, a2, a3, a4, a5) if a1 == nil then __nuppT7.coverage = false else __nuppT7.coverage = a1 end __nuppT7.coverageOut = a2 if a3 == nil then __nuppT7.reportJson = false else __nuppT7.reportJson = a3 end if a4 == nil then __nuppT7.schema = false else __nuppT7.schema = a4 end if a5 == nil then __nuppT7.arguments = {} else __nuppT7.arguments = a5 end return __nuppT7 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Build and run project tests.\n\nCoverage options belong to Nupp. Every other argument is preserved in\norder for the bundled runner or the project's configured test command.\nThe bundled runner accepts suite names, `--json`, `--verbose`, `--jobs=N`,\nrepeated `--group=NAME`, `--exclude=SUITE`, `--exclude-group=NAME`, one of\n`--lane=shared|shell|isolated`, `--list-suites`, `--list-cases`,\n`--list-groups`, `--case=SUITE/CASE`, `--rerun=REPORT`, and\n`--timings[=N]`. Those remain forwarded arguments rather than fields of this\ncommand because a project may configure a different test executable.\n\nCoverage uses `build/coverage` without changing the ordinary build cache\nand writes under `build/reports/coverage` by default. `--report-json` reads\nthat report without rebuilding or rerunning tests.\n\nExamples:\n\n    nupp test\n    nupp test clitest doctest\n    nupp test --group=docs --json\n    nupp test --coverage clitest",["group"]=false,["hidden"]=false,["name"]="test",["summary"]="Build and run project tests."},["fieldCount"]=5,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--coverage",["documentation"]="Run against a separately instrumented build.",["field"]="coverage",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"coverage"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--coverage-out",["documentation"]="Directory for coverage HTML, JSON, and LCOV files.",["field"]="coverageOut",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"coverage-out"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--report-json",["documentation"]="Print an existing coverage report without running tests.",["field"]="reportJson",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"report-json"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments owned by the selected test command.",["field"]="arguments",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments owned by the selected test command.",["field"]="arguments",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"}},["preserveUnknown"]=true,["remainder"]={["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments owned by the selected test command.",["field"]="arguments",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"},["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="110669473a50cbeda2d07b90fb66f08dcaab28cb9ae16fb1372bc6ccf9c3ccf1",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.test:Test:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="test"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Build and run project tests."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Test?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Test",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.test:Test:1",Test,__nuppDerived) ;Test["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Test["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("test")end ;Test["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Build and run project tests.")end ;Test["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Test,__nuppT1[1],{ })


function Test . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Test } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.test"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.test"]=__nuppExports;return __nuppExports