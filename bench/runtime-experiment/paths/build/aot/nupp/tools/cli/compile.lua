_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.compile\0runtime\0001") };











local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local fs = require ( "nupp.compiler.fs" )

local compile = { }


compile.Settings = {} compile.Settings.__index = compile.Settings ;_G.nupp.__reflect.link(compile.Settings,__nuppT1[1],{ })










































































local LEVELS = { [ "0" ] = 0 , [ "1" ] = 1 , [ "2" ] = 2 }



function compile . settings ( values , collected ) 
return ( _G.setmetatable({ strict =
values . strict ,  compat =
values . compat ,  optLevel =
LEVELS [ values . optLevel ] ,  remarks =
values . remarks and true or false ,  remarksFile =
values . remarksFor ,  disabled =
values . disabled or { } ,  diagnostics =
collected ,  coverage =
os . getenv ( "NUPP_COVERAGE" ) == "1" ,  bytecodeBoundary =
nil ,  remarksOut =
values . remarksOut ,  collectedRemarks =
( values . remarksOut or values . profile and values . remarks ) and { } or nil ,  sampledHeat =
nil ,  collectedAllocationSites =
values . remarksOut and { } or nil ,  accountedModules =
values . remarksOut and 0 or nil }, compile.Settings) )

end

function compile . selectRemarks ( remarks , path ) 
if not path then
return remarks
end
local selected = { }
for _ , entry in ipairs ( remarks ) do
if fs . absolute ( entry . filename or "" ) == fs . absolute ( path ) then
selected [ # selected + 1 ] = entry
end
end

return selected
end



function compile . attachSamples (
settings ,
samples ,
totalSamples ,
intervalMs
) 
local byFile = { }
local attributed = 0
for _ , sample in ipairs ( samples ) do
local file = fs . absolute ( sample . file )
local lines = byFile [ file ] or { }
byFile [ file ] = lines
lines [ sample . line ] = ( lines [ sample . line ] or 0 ) + sample . samples
attributed = attributed + sample . samples
end
settings . sampledHeat = {
intervalMs = intervalMs ,
totalSamples = totalSamples ,
attributedSamples = attributed ,
unattributedSamples = totalSamples - attributed ,
sourceSamples = samples
}
for _ , entry in ipairs ( settings . collectedRemarks or { } ) do
if entry . filename
and byFile [ fs . absolute ( entry . filename ) ]
and entry . line
and entry . line > 0
and entry . status ~= "unavailable"
and not ( entry . code or "" ) : match ( "^AOT" )
then
local last = math . max ( entry . line , entry . sourceEndLine or entry . line )
local count = 0
for line , hits in pairs ( byFile [ fs . absolute ( entry . filename ) ] or { } ) do
if line >= entry . line and line <= last then
count = count + hits
end
end
entry . hotness = "sampled"
entry . hotnessSamples = count
entry . hotnessRange = { startLine = entry . line , endLine = last }
end
end
end













function compile . writeRemarks ( settings ) 
local out = settings . remarksOut
local collected = settings . collectedRemarks
if not out or not collected then
return false
end



if ( settings . accountedModules or 0 ) == 0 then
io . stderr : write ( "nupp: --remarks-out wrote nothing: this build accounted for no module\n" )

return false
end
local report = require ( "nupp.tools.cli.report" )
local codes = { }
for code in pairs ( settings . disabled ) do
codes [ # codes + 1 ] = code
end
table . sort ( codes )
local document = {
schema = 1 ,
executionProfile = { optLevel = settings . optLevel or 0 , disabled = table . concat ( codes , "," ) , } ,
compiler = {
version = require ( "nupp.tools.version" ) . VERSION ,



digest = require ( "nupp.tools.build.cache" ) . moduleCompilerFingerprint ( ) ,
} ,
remarks = report . diagnosticValues ( compile . selectRemarks ( collected , settings . remarksFile ) ) ,
allocationSites = settings . collectedAllocationSites or { } ,
sampling = settings . sampledHeat ,
}
local wrote , writeErr = require ( "nupp.compiler.fs" ) . writeFile ( out , report . encode ( document ) .. "\n" )
if not wrote then
io . stderr : write ( "nupp: " .. tostring ( writeErr ) .. "\n" )

return false
end

return true
end








function compile . check ( path , env , opts , collected ) 
local function report ( diagnostics ) 
if not collected then
return diagnosticMod . report ( diagnostics )
end
local failed = false
for _ , diagnostic in ipairs ( diagnostics ) do
collected [ # collected + 1 ] = diagnostic
failed = failed or diagnosticMod . severityOf ( diagnostic ) == "error"
end

return failed
end

local source , readErr = fs . readFile ( path )
if not source then
local cliReport = require ( "nupp.tools.cli.report" )
cliReport . fileFailure ( path , readErr , "check that the path exists and is readable" , collected )
return nil
end
local result = require ( "nupp.compiler.syntax.parser" ) . parse ( source , path )
if # result . errors > 0 then
report ( result . errors )
return nil
end
local diags = require ( "nupp.compiler.check" ) . check ( result , path , env , opts )
if report ( diags ) then
return nil
end

return result , source
end





function compile . module (
path ,
env ,
settings ,
moduleName ,
sourceOverride
) 
local collected = settings . diagnostics



local function say ( values ) 
if not collected then
return diagnosticMod . report ( values )
end
local fatal = false
for _ , diagnostic in ipairs ( values ) do
collected [ # collected + 1 ] = diagnostic
if diagnosticMod . isFatal ( diagnostic ) then
fatal = true
end
end

return fatal
end

local source = sourceOverride
local readErr = nil
if source == nil then
source , readErr = fs . readFile ( path )
end
if not source then
require (
"nupp.tools.cli.report"
) . fileFailure ( path , readErr , "check that the path exists and is readable" , collected )
return nil , readErr
end
local parser = require ( "nupp.compiler.syntax.parser" )



local result = parser . parse ( source , path )
if # result . errors > 0 then
say ( result . errors )
return nil , "syntax errors"
end
local check = require ( "nupp.compiler.check" )
local diags = check . check ( result , path , env , {
strict = settings . strict ,
compat = settings . compat ,
moduleName = moduleName ,
} )
if settings . materializations then
local observations = require (
"nupp.compiler.comptime.materialize.observe"
) . public ( require ( "nupp.compiler.comptime.materialize.observe" ) . collect ( result . root , path ) )
for _ , observation in ipairs ( observations ) do
settings . materializations [ # settings . materializations + 1 ] = observation
end
end
if settings . derives then
for _ , observation in ipairs ( result . deriveObservations or { } ) do
settings . derives [ # settings . derives + 1 ] = observation
end
end
if say ( diags ) then
return nil , "type errors"
end
local remarks , specializedBodies = require ( "nupp.compiler.lua.optimize" ) . run ( result , {
level = settings . optLevel or 0 ,
filename = path ,
disabled = settings . disabled
} )


if settings . specializedBodies ~= nil then
settings . specializedBodies = ( settings . specializedBodies ) + specializedBodies
end
if ( settings . remarks or settings . remarksOut or settings . collectedRemarks ) and ( settings . optLevel or 0 ) == 0 then
remarks [
# remarks + 1
] = {
code = "OPT-0" ,
severity = "note" ,
status = "unavailable" ,
hotness = "unknown" ,
filename = path ,
line = 1 ,
col = 1 ,
offset = 1 ,
length = 0 ,
msg = "optimizer unavailable at -O0; select -O1 or -O2 to request optimization"
}
end
if settings . collectedRemarks then
local collectedRemarks = settings . collectedRemarks
for _ , entry in ipairs ( remarks ) do
collectedRemarks [ # collectedRemarks + 1 ] = entry
end
end
if settings . accountedModules ~= nil then
settings . accountedModules = ( settings . accountedModules ) + 1
end
if settings . collectedAllocationSites then
local collectedSites = settings . collectedAllocationSites

for _ , site in ipairs ( require ( "nupp.compiler.lua.optimize" ) . allocationSites ( result ) ) do
collectedSites [ # collectedSites + 1 ] = { file = path , kind = site . kind , line = site . line , col = site . col , }
end
end
if settings . remarks then
say ( compile . selectRemarks ( remarks , settings . remarksFile ) )
end
local gen = require ( "nupp.compiler.lua.gen" )
local code , genDiags = gen . generate (
result ,
path ,
settings . coverage and { path = path } or nil ,
nil ,
settings . bytecodeBoundary
)
if # genDiags > 0 then
say ( genDiags )
return nil , "code generation errors" , code
end

return code
end

local __nuppExportValue= compile ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.compile"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.compile"]=__nuppExports;return __nuppExports