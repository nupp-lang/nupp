_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

local spec = require ( "nupp.compiler.cli.spec" )
local fs = require ( "nupp.compiler.fs" )

local command = spec . command {
name = "coverage" ,
summary = "Run tests and write a source coverage report" ,
usage = { "nupp coverage [--out DIR] [--json] [test arguments...]" , "nupp coverage --report-json [--out DIR]" } ,
stopAtPositional = true ,
options = {
{ name = "--out" , value = "DIR" , help = "Directory for the HTML, JSON, and LCOV report" } ,
{ name = "--json" , key = "json" , help = "Write the aggregate summary as JSON" } ,
{ name = "--report-json" , key = "reportJson" , help = "Print an existing full JSON report; do not run tests" } ,
} ,
schema = {
type = "object" ,
description = "Aggregate Nupp coverage totals." ,
properties = { lines = { type = "object" } , functions = { type = "object" } , branches = { type = "object" } , } ,
required = { "lines" , "functions" , "branches" } ,
} ,
detail = [[Coverage uses a separate build/coverage artifact, so normal generated
Lua and its cache are never instrumented. The static report opens at
build/reports/coverage/index.html and also writes coverage.json and lcov.info.

`--report-json` prints the complete machine-readable coverage.json already in
the report directory, without rebuilding or rerunning tests.]] ,
}

local function run ( parsed )
local outDir = parsed . values . out or "build/reports/coverage"
if parsed . values . reportJson then
if parsed . values . json then
io . stderr : write ( "nupp: --report-json already writes JSON; remove --json\n" )
return 2
end
local existing , err = fs . readFile ( outDir .. "/coverage.json" )
if not existing then
io . stderr : write (
"nupp: cannot read coverage report " .. outDir .. "/coverage.json: " .. tostring ( err ) .. "\n"
)
return 1
end
io . write ( existing )
if existing : sub ( - 1 ) ~= "\n" then
io . write ( "\n" )
end
return 0
end
local buildDir = "build/coverage"
local raw = outDir .. "/raw.json"
if not fs . mkdir ( outDir ) then
io . stderr : write ( "nupp: cannot create coverage output " .. outDir .. "\n" )
return 1
end
local project = require ( "nupp.compiler.build.project" )
local testCode = project . test ( "." , parsed . positional , {
coverage = true ,
outDir = buildDir ,
env = { NUPP_COVERAGE = "1" , NUPP_COVERAGE_BUILD = buildDir , NUPP_COVERAGE_FILE = raw }
} )
local report = require ( "nupp.compiler.coverage" )
local model = report . collect ( buildDir .. "/.nupp-state.json" , raw )
local summary = report . write ( model , outDir )
if parsed . values . json then
require ( "nupp.compiler.cli.report" ) . write ( summary )
else
io . write (
(
"coverage: lines %.2f%%, functions %.2f%%, branches %.2f%%\n"
) : format ( summary . lines . percent , summary . functions . percent , summary . branches . percent )
)
io . write ( "coverage: report written to " .. outDir .. "/index.html\n" )
end
if # model . warnings > 0 and testCode == 0 then
io . stderr : write ( "nupp: coverage data is incomplete\n" )
return 1
end

return testCode
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
