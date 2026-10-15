_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT13={}; local function __nuppT10(...) return {n=select("#",...),...} end; local __nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20,__nuppT21=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT11(value) return value end; local function __nuppT12(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT19({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT20(v.primary) for _,reason in __nuppT21(v.suppressed) do text=text.."\ncleanup: "..__nuppT20(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()










local clock = require ( "nupp.time" )
local envMod = require ( "nupp.compiler.project.env" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local fs = require ( "nupp.compiler.fs" )
local modules = require ( "nupp.tools.build.modules" )
local protocol = require ( "nupp.tools.build.parallelcheckprotocol" )
local workerchannel = require ( "nupp.compiler.workerchannel" )

local normalize , join = fs . normalize , fs . join
local readFile = fs . readFile

local service = { }


local function noRefusals ( _ , _ , _ ) 
return { } , false
end

local function noAotKey ( ) 
return ""
end


local workerContext = nil
local identityLane = nil


local function scanBatch ( request ) 
local parser = require ( "nupp.compiler.syntax.parser" )
local header = require ( "nupp.compiler.project.header" )
local moduleobject = require ( "nupp.tools.build.moduleobject" )
local objects = { }
local index = { declaredModules = request . declaredModules , supportedModules = request . supportedModules , }
for _ , source in ipairs ( request . sources or { } ) do
local path = normalize ( source . path )
local text , readProblem = readFile ( path )
if text == nil then
return { ok = false , problem = "parallel graph source disappeared: " .. tostring ( readProblem or path ) , }
end
local parsed = parser . parse ( text , path )
objects [ # objects + 1 ] = moduleobject . emit ( path , parsed , header . of ( path , source . name , parsed ) , index )
end

return { ok = true , objects = objects , }
end

local function openContext ( init ) 
local declared = { }
for _ , path in ipairs ( init . projectPaths or { } ) do
declared [ normalize ( path ) ] = true
end
local context = {
declared = declared ,
assigned = { } ,
nominals = { } ,
interfaceArenas = { } ,
interfaceOrigins = { } ,
imports = { } ,
root = init . root ,
outDir = init . outDir ,
projectPaths = init . projectPaths ,
config = init . config ,
target = init . target ,
build = init . build == true ,
constSelection = init . constSelection ,
linked = { } ,
}
for _ , name in ipairs ( init . linked or { } ) do
context . linked [ name ] = true
end
context . session = modules . session (
init . root ,
init . outDir ,
init . config ,
init . target ,
init . state . dependencies ,
nil ,
context . nominals ,
true ,
function ( path ) 
local normalized = normalize ( path )
if context . declared [ normalized ] and not context . assigned [ normalized ] then
context . checkedOutside = normalized
error ( "parallel worker recursively checked " .. normalized , 0 )
end
end
)
for _ , entry in ipairs ( init . staged or { } ) do
context . session . stageBundled ( entry . name , entry . replaceTypeOnly )
end

return context
end






local function checkBatch ( request ) 
local batchStarted = clock . now ( )
if request . init ~= nil then
workerContext = openContext ( request . init )
end
local context = workerContext
if context == nil then
return { ok = false , problem = "parallel check worker has no session" }
end



local assigned = { }
for _ , source in ipairs ( request . sources or { } ) do
assigned [ normalize ( source . path ) ] = true
end
context . assigned = assigned
context . checkedOutside = nil
local session = context . session
local interfaceimage = require ( "nupp.compiler.project.interfaceimage" )
local contentDigest = fingerprint . contentDigest ( true )

local newlyImported = { }
local decodeStarted = clock . now ( )
for _ , import in ipairs ( request . imports or { } ) do
local image , problem = protocol . decode ( import . bytes or "" )
if image == nil or image . fingerprint ~= import . fingerprint then
return { ok = false , problem = "interface bundle: " .. tostring ( problem or "fingerprint mismatch" ) }
end
local semantics , decodeProblem = interfaceimage . decode ( image , {
nominals = context . nominals ,
arenas = context . interfaceArenas ,
origins = context . interfaceOrigins ,
} )
if semantics == nil then
return { ok = false , problem = "import bundle: " .. tostring ( decodeProblem ) }
end
for name , semantic in pairs ( semantics ) do
if not context . imports [ name ] then
newlyImported [ name ] = semantic
context . imports [ name ] = true
end
end
end
session . inc . importModules ( newlyImported )
local decodedAt = clock . now ( )




local emptySpecializationHash = contentDigest ( "" )
local records = { }
local codes = { }
local diagnostics = { }
local unchecked = { }
local checkStarted = clock . now ( )
local semanticMs = 0
local recordMs = 0
for _ , source in ipairs ( request . sources or { } ) do
local path = normalize ( source . path )
local name = source . name
local sourceHash = source . hash
if name == nil or sourceHash == nil then
unchecked [ # unchecked + 1 ] = path
else
local semanticStarted = clock . now ( )
local result = session . inc . checkReadyFile ( path )
semanticMs = semanticMs + clock . now ( ) - semanticStarted
local recordStarted = clock . now ( )
for _ , diagnostic in ipairs ( result . diags or { } ) do
diagnostics [ # diagnostics + 1 ] = diagnostic
end
local compiled = modules . compileChecked ( {
name = name ,
path = path ,
sourceHash = sourceHash ,
checked = result ,
inc = session . inc ,
root = context . root ,
outDir = context . outDir ,
config = context . config ,
target = context . target ,
checkOnly = not context . build ,
external = path : match ( "%.d%.nupp$" ) ~= nil
or envMod . isDependencyTypePath ( session . inc . env , path ) and not context . linked [ name ] ,
constSelection = context . constSelection ,
specializationHash = emptySpecializationHash ,
rewritten = false ,
authoredLints = nil ,
aotRefusals = noRefusals ,
aotKey = noAotKey ,
compilerRuntime = nil ,
contentDigest = contentDigest ,
generating = nil ,
} )
records [ name ] = compiled . record
if compiled . code ~= nil and compiled . record . artifactHash ~= nil then
codes [ name ] = compiled . code
end
recordMs = recordMs + clock . now ( ) - recordStarted
end
end
if context . checkedOutside ~= nil then
return {
ok = false ,
problem = "recursive check of " .. tostring ( context . checkedOutside ) ,
diagnostics = diagnostics ,
}
end
local checkedAt = clock . now ( )

local interfaces = { }
local interfaceNames = { }
for _ , source in ipairs ( request . sources or { } ) do
local path = normalize ( source . path )
local name = source . name


if name and not path : match ( "%.lua$" ) then
local semantic = session . inc . moduleSemantic ( name , path )
semantic . path = path
interfaces [ name ] = semantic
interfaceNames [ # interfaceNames + 1 ] = name
end
end
table . sort ( interfaceNames )
local interfaceAt = clock . now ( )
local produced = nil
local nodes = 0
if # interfaceNames > 0 then
local bundle , imageProblem = interfaceimage . encode ( interfaces , {
origins = context . interfaceOrigins ,
arenas = context . interfaceArenas ,
projectPaths = context . projectPaths ,
} )
if bundle == nil then
return { ok = false , problem = "interface bundle: " .. tostring ( imageProblem ) }
end
local prerequisites = { }
local seenPrerequisite = { }
for _ , node in ipairs ( bundle . descriptor and bundle . descriptor . types or { } ) do
if node . kind == "external" and not seenPrerequisite [ node . arena ] then
seenPrerequisite [ node . arena ] = true
prerequisites [ # prerequisites + 1 ] = node . arena
end
end
table . sort ( prerequisites )
local bytes = protocol . encode ( bundle )
if os . getenv ( "NUPP_TEST_PARALLEL_CHECK_FAILURE" ) == "interface" then
bytes = bytes .. "\0injected damage"


local image , problem = protocol . decode ( bytes )
if image == nil then
return { ok = false , problem = "interface bundle: " .. tostring ( problem ) }
end
end
nodes = # ( bundle . descriptor . types or { } )
produced = {
fingerprint = bundle . fingerprint ,
bytes = bytes ,
prerequisites = prerequisites ,
names = interfaceNames ,
}
end
local encodedAt = clock . now ( )

local importedCount = 0
for _ in pairs ( newlyImported ) do
importedCount = importedCount + 1
end

return {
ok = true ,
modules = records ,
codes = codes ,
interface = produced ,
diagnostics = diagnostics ,
stats = {
checkedModules = # ( request . sources or { } ) ,
importedModules = importedCount ,
interfaceNodes = nodes ,
setupMs = decodeStarted - batchStarted ,
decodeMs = decodedAt - decodeStarted ,
checkMs = checkedAt - checkStarted ,
semanticMs = semanticMs ,
recordMs = recordMs ,
interfaceMs = interfaceAt - checkedAt ,
encodeMs = encodedAt - interfaceAt ,
totalMs = encodedAt - batchStarted ,
} ,
unchecked = unchecked ,
}
end



local function serve ( request ) 
local lane = request . initializer
if identityLane == nil and type ( lane ) == "number" then
require ( "nupp.compiler.types" ) . setIdentityNamespace ( "cold" , lane )
identityLane = lane
end
if request . kind == "scan" then
return scanBatch ( request )
end

return checkBatch ( request )
end

local function encoded ( value ) 
local ok , answer = pcall ( protocol . encode , value )
if ok then
return answer
end

return protocol . encode ( {
schema = 1 ,
requestId = value . requestId ,
ok = false ,
problem = "parallel check worker could not encode its response: " .. tostring ( answer )
} )
end

local function note ( path ) local __nuppT9;
if path == nil then
return
end
do const  __nuppT28= io . open ( path , "ab" ) ; __nuppT9=__nuppT9 or {} ; local __nuppT29=__nuppT9[1]; if not __nuppT29 then __nuppT29=function(file) do
if file ~= nil then
file : write ( tostring ( require ( "nupp.compiler.fs" ) . processId ( ) or 0 ) , "\n" )
file : close ( )
end end; return "normal" end; __nuppT9[1]=__nuppT29 end; const __nuppT23,__nuppT24,__nuppT25=__nuppT15(__nuppT29,__nuppT11,__nuppT28); const __nuppT22=1; local __nuppT26={}; local __nuppT27=0; if __nuppT22>=1 and __nuppT28~=nil then  local __nuppT30,__nuppT31=__nuppT14(__nuppCleanup1,__nuppT28);  if not __nuppT30 then __nuppT27=__nuppT27+1; __nuppT26[__nuppT27]=__nuppT31 end; end; if not __nuppT23 then if __nuppT27>0 then __nuppT16(__nuppT12(__nuppT24,__nuppT26,1),0) else __nuppT16(__nuppT24,0) end end; if __nuppT27>0 then if __nuppT27>1 then __nuppT16(__nuppT12(__nuppT26[1],__nuppT26,2),0) else __nuppT16(__nuppT26[1],0) end end; if __nuppT24=="return" then  return __nuppT17(__nuppT25,1,__nuppT25.n)  end; end
end




local function injectedCrash ( request ) 
if request . kind ~= "check" then
return false
end
local failure = os . getenv ( "NUPP_TEST_PARALLEL_CHECK_FAILURE" )

return failure == "crash" or failure == "crash-once" and request . initializer == 1
end

function service . main ( ) 
local failure = os . getenv ( "NUPP_TEST_PARALLEL_CHECK_FAILURE" )
note ( os . getenv ( "NUPP_TEST_PARALLEL_CHECK_PID_FILE" ) )
if failure == "exit" then
return 86
elseif failure == "hang" then
require ( "nupp.time" ) . sleep ( 1000 )
end

local function handle ( text ) 
local request , problem = protocol . decode ( text )
if request == nil
or request . schema ~= 1
or type ( request . requestId ) ~= "number"
or request . requestId < 1
or request . requestId ~= math . floor ( request . requestId )
then
return encoded ( {
schema = 1 ,
requestId = 0 ,
ok = false ,
problem = "invalid parallel check request: " .. tostring ( problem )
} )
end
if injectedCrash ( request ) then
os . exit ( 87 )
end
local pause = tonumber ( os . getenv ( "NUPP_TEST_PARALLEL_CHECK_PAUSE_MS" ) or "" )
if pause ~= nil and pause > 0 then
note ( os . getenv ( "NUPP_TEST_PARALLEL_CHECK_ACTIVE_FILE" ) )
require ( "nupp.time" ) . sleep ( pause )
end
local ok , result = pcall ( serve , request )
local answer = ok and result or { ok = false , problem = tostring ( result ) }
answer . schema = 1
answer . requestId = request . requestId

return encoded ( answer )
end

workerchannel . serve ( handle , protocol . MAX_FRAME , function ( ) 
return encoded ( { schema = 1 , requestId = 0 , ok = false , problem = "parallel check request is too large" } )
end )

return 0
end

local __nuppExportValue= service ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.parallelcheckservice"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.parallelcheckservice"]=__nuppExports;return __nuppExports