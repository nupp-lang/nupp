_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



















local aotcheck = require ( "nupp.tools.build.aotcheck" )
local envMod = require ( "nupp.compiler.project.env" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local fs = require ( "nupp.compiler.fs" )
local moduleTargets = require ( "nupp.compiler.standardsurface" )
local protocol = require ( "nupp.tools.build.parallelcheckprotocol" )
local workerchannel = require ( "nupp.compiler.workerchannel" )
local clock = require ( "nupp.time" )

local join = fs . join

local parallelcheck = { }

const MIN_MODULES = 64
const MIN_BYTES = 262144
const MAX_AUTOMATIC_WORKERS = 6
const MAX_REQUESTED_WORKERS = 8
const WORKER_TIMEOUT_MS = 120000





function parallelcheck . plan ( moduleCount , sourceBytes , available , requested ) 
if requested ~= nil then
local workers = math . max ( 1 , math . min ( math . floor ( requested ) , 8 , moduleCount ) )

return { workers = workers , reason = workers == 1 and "requested serial checking" or nil , requested = true , }
end
if moduleCount < 64 or sourceBytes < 262144 then
return { workers = 1 , reason = "the project is below the parallel workload floor" , requested = false , }
end
local workers = math . max ( 1 , math . min ( available , 6 , moduleCount ) )

return { workers = workers , reason = workers == 1 and "the host has one available worker" or nil , requested = false , }
end

local function tracing ( ) 
return os . getenv ( "NUPP_PARALLEL_CHECK_TRACE" ) ~= nil
end

local function serialFacts ( reason ) 
return { mode = "serial" , workers = 1 , retries = 0 , batches = 0 , reason = reason }
end











function parallelcheck . run ( input ) 
local report = input . reporter
local inc = input . inc
local target = input . target
local root , outDir = input . root , input . outDir

local function declined ( reason ) 
report : parallelCounted ( ( { mode = "serial" , workers = 1 , retries = 0 , batches = 0 , reason = reason } ) )

return nil , reason
end

if aotcheck . applies ( target . aot ) then
return declined ( "the target applies an ahead-of-time policy" )
end
if not protocol . available then
return declined ( "this host has no plain-data encoding for worker payloads" )
end




local contentDigest = fingerprint . contentDigest ( true )
local sources = { }
local declaredModules = { }
local supportedModules = { }
local ordered = { }
local totalBytes = 0
for _ , item in ipairs ( input . queue ) do

if sources [ item . path ] == nil and not declaredModules [ item . name ] then
local text = inc . fileText ( item . path )
if text == nil then
return declined ( "a project source could not be read: " .. tostring ( item . path ) )
end
local source = {
name = item . name ,
path = item . path ,
hash = contentDigest ( text ) ,
bytes = # ( text ) ,
}
sources [ item . path ] = source
declaredModules [ item . name ] = true
supportedModules [ item . name ] = moduleTargets . supports ( item . name , target . host )
ordered [ # ordered + 1 ] = source
totalBytes = totalBytes + # ( text )
end
end
local system = require ( "nupp.system" )
local plan = parallelcheck . plan (
# ordered ,
totalBytes ,
system . availableParallelism ( ) ,
tonumber ( os . getenv ( "NUPP_CHECK_JOBS" ) or "" )
)
local jobCount = plan . workers
if jobCount == 1 then
return declined ( plan . reason )
end

report : at ( input . build and "parallel build" or "parallel check" )
local tasks = require ( "nupp.tasks" )
local suspension = require ( "nupp.suspension" )
local process = require ( "nupp.compiler.process" )
local moduleobject = require ( "nupp.tools.build.moduleobject" )
local compilerRoot = envMod . compilerRoot ( )
local hosted = rawget ( _G , "__NUPP_EXECUTABLE" )
local executable = compilerRoot and join ( compilerRoot , "bin/nupp" )
or type ( hosted ) == "string" and hosted
or tostring ( arg and arg [ 0 ] or "nupp" )
local timeoutMs = os . getenv ( "NUPP_TEST_PARALLEL_CHECK_FAILURE" ) == "hang" and 100 or 120000


local state = {
channels = { } ,

resident = { } ,
initialized = { } ,
requestIds = { } ,
lanes = { } ,
spawned = 0 ,
retries = 0 ,
batches = 0 ,
stats = { } ,
}

local function closeChildren ( force ) 
for _ , channel in pairs ( state . channels ) do
workerchannel . close ( channel , force )
end
state . channels = { }
end

local function abandon ( reason ) 
closeChildren ( true )



if tasks . isCancelled ( reason ) or tostring ( reason ) : match ( "interrupted!$" ) ~= nil then
error ( reason , 0 )
end
report : parallelCounted ( {
mode = "serial-fallback" ,
workers = jobCount ,
retries = state . retries ,
batches = state . batches ,
reason = tostring ( reason ) ,
} )
report : at ( "resolve" )
if ( os . getenv ( "NUPP_PARALLEL_CHECK_TRACE" ) ~= nil ) then
io . stderr : write ( "parallel cold check fell back: " .. tostring ( reason ) .. "\n" )
end

return nil , tostring ( reason )
end

local function startChild ( index ) 
local previous = state . channels [ index ]
if previous ~= nil then
workerchannel . close ( previous , true )
end
do local __nuppT21=0; local  __nuppT27 ; local __nuppT28=false ; local __nuppT22,__nuppT23,__nuppT24=__nuppT14(function() do local __nuppT29=__nuppT9( process . startIsolated ( { executable , "__parallel-check-service" } ) ); __nuppT27= __nuppT29[1] ; __nuppT21=1;  __nuppT28=true;  local  child , problem = __nuppT29[1] , __nuppT29[2] ;
if child == nil or child . stdin == nil or child . stdout == nil then
if child ~= nil then
do (function(__nuppT30,...)  __nuppT28=false; return __nuppT30:close(...)  end)( child ) end
end
error ( problem or "parallel check worker has no protocol streams" , 0 )
end
state . channels [ index ] = workerchannel . open ( (function() __nuppT28=false; return  child  end)() , { maxFrame = protocol . MAX_FRAME } )
state . resident [ index ] = { }
state . initialized [ index ] = nil

state . spawned = state . spawned + 1
state . lanes [ index ] = state . lanes [ index ] or { batches = 0 , totalMs = 0 , semanticMs = 0 , decodeMs = 0 }
state . lanes [ index ] . initializer = state . spawned end; return "normal" end,__nuppT10); local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT28 and __nuppT27~=nil then  local __nuppT31,__nuppT32=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT31 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT32 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end

local function requestWorker ( index , request ) 
local channel = state . channels [ index ]
state . requestIds [ index ] = ( state . requestIds [ index ] or 0 ) + 1
request . schema = 1
request . requestId = state . requestIds [ index ]
request . initializer = state . lanes [ index ] . initializer
local text , stopped = workerchannel . request ( channel , protocol . encode ( request ) , clock . now ( ) + timeoutMs )
if text == nil then
local kind = stopped and stopped . kind or "ended"
local said = stopped and stopped . said or ""
local reason = kind == "timeout" and "parallel check worker timed out"
or kind == "stopped" and "parallel check worker stopped accepting requests"
or kind == "ended" and "parallel check worker stopped before answering"
or "parallel check worker returned an invalid frame (" .. kind .. ")"
error ( reason .. ( said ~= "" and ( ": " .. said ) or "" ) , 0 )
end
local answer , problem = protocol . decode ( text )
if answer == nil then
error (
"parallel check worker returned an invalid response: " .. tostring (
problem
) .. " (" .. tostring ( # ( text ) ) .. " bytes; worker said " .. channel . said .. ")" ,
0
)
end
if answer . schema ~= 1 or answer . requestId ~= request . requestId then
error ( "parallel check worker returned a mismatched response" , 0 )
end

return answer
end

local started , startProblem = pcall ( function ( ) 
for index = 1 , jobCount do
startChild ( index )
end
end )
if not started then
return abandon ( startProblem )
end



local scanStarted = clock . now ( )
local objects = { }
table . sort ( ordered , function ( left , right ) 
if left . bytes ~= right . bytes then
return left . bytes > right . bytes
end

return left . path < right . path
end )
local scanAssigned = { }
local scanWeights = { }
for worker = 1 , jobCount do
scanAssigned [ worker ] , scanWeights [ worker ] = { } , 0
end
for _ , source in ipairs ( ordered ) do
local selected = 1
for worker = 2 , jobCount do
if scanWeights [ worker ] < scanWeights [ selected ] then
selected = worker
end
end
local list = scanAssigned [ selected ]
list [ # list + 1 ] = { path = source . path , name = source . name }
scanWeights [ selected ] = scanWeights [ selected ] + math . max ( 1 , source . bytes )
end

local function scanWorker ( index ) 
if # scanAssigned [ index ] == 0 then
return
end
local answer = requestWorker ( index , {
kind = "scan" ,
sources = scanAssigned [ index ] ,
declaredModules = declaredModules ,
supportedModules = supportedModules ,
} )
if not answer . ok then
error ( answer . problem or "parallel graph scan failed" , 0 )
end
for _ , object in ipairs ( answer . objects or { } ) do
objects [ # objects + 1 ] = object
end
end

local scanned , scanProblem = pcall ( function ( ) local __nuppT37;
do const  __nuppT44= tasks . open ( jobCount ) ; __nuppT37=__nuppT37 or {} ; local __nuppT45=__nuppT37[1]; if not __nuppT45 then __nuppT45=function(scope) do
for worker = 1 , jobCount do
do (function(__nuppT46,__nuppT47,__nuppT48) return __nuppT46:spawn( __nuppT48 ,__nuppT47 ) end)( scope , worker , scanWorker ) end
end end; return "normal" end; __nuppT37[1]=__nuppT45 end; const __nuppT39,__nuppT40,__nuppT41=__nuppT14(__nuppT45,__nuppT10,__nuppT44); const __nuppT38=1;
local __nuppT42={}; local __nuppT43=0; if __nuppT38>=1 then  local __nuppT49,__nuppT50=__nuppT13(__nuppCleanup1,__nuppT44);  if not __nuppT49 then __nuppT43=__nuppT43+1; __nuppT42[__nuppT43]=__nuppT50 end; end; if not __nuppT39 then if __nuppT43>0 then __nuppT15(__nuppT11(__nuppT40,__nuppT42,1),0) else __nuppT15(__nuppT40,0) end end; if __nuppT43>0 then if __nuppT43>1 then __nuppT15(__nuppT11(__nuppT42[1],__nuppT42,2),0) else __nuppT15(__nuppT42[1],0) end end; if __nuppT40=="return" then  return __nuppT16(__nuppT41,1,__nuppT41.n)  end; end
end )
if not scanned then
return abandon ( scanProblem )
end
local sourceCount = # ordered
if # objects ~= sourceCount then
return abandon ( "parallel graph scan did not return every module" )
end



local linkedOk , linked = pcall ( moduleobject . link , objects )
if not linkedOk then
return abandon ( linked )
end
if input . build and input . constSelection ~= nil then
for _ , object in ipairs ( objects ) do
if object . constGenerics then
closeChildren ( true )

return declined (
object . path .. " declares a const-generic function, which a build specializes across modules"
)
end
end
end
local components = linked . components
local componentDependencies = linked . dependencies
local componentDependents = linked . dependents


local projectPaths = { }
for path in pairs ( sources ) do
if not path : match ( "%.lua$" ) then
projectPaths [ # projectPaths + 1 ] = path
end
end
table . sort ( projectPaths )
local weights = { }
for index , component in ipairs ( components ) do
local weight = 0
for _ , path in ipairs ( component ) do
weight = weight + math . max ( 1 , sources [ path ] . bytes )
end
weights [ index ] = weight
end
local scanMs = clock . now ( ) - scanStarted

local remaining = # components
local waiting = { }
local ready = { }
local queueWaiters = { }
local randomState = tonumber ( os . getenv ( "NUPP_TEST_PARALLEL_CHECK_RANDOM_SEED" ) or "" )
for index = 1 , # components do
waiting [ index ] = # componentDependencies [ index ]
if waiting [ index ] == 0 then
ready [ # ready + 1 ] = index
end
end

local function wakeQueue ( ) 
local waking = queueWaiters
queueWaiters = { }
for _ , wake in ipairs ( waking ) do
wake ( true )
end
end

local function waitForQueue ( ) 
suspension . suspend ( "parallel check ready queue" , function ( resume ) 
if # ready > 0 or remaining == 0 then
resume ( true )

return function ( ) 
end
end
queueWaiters [ # queueWaiters + 1 ] = resume

return function ( ) 
for index = # queueWaiters , 1 , -1 do
if queueWaiters [ index ] == resume then
table . remove ( queueWaiters , index )
do break end
end
end
end
end )
end


local function takeComponent ( ) 
while # ready == 0 and remaining > 0 do
waitForQueue ( )
end
if remaining == 0 then
return nil
end
local selected = 1
if randomState ~= nil then
randomState = ( ( randomState ) * 48271 ) % 2147483647
selected = math . floor ( ( randomState ) % # ready ) + 1
else
for position = 2 , # ready do
local candidate , best = ready [ position ] , ready [ selected ]
if weights [ candidate ] > weights [ best ] or weights [ candidate ] == weights [ best ] and candidate < best then
selected = position
end
end
end

return table . remove ( ready , selected )
end



local bundleOf = { }
local bundleByFingerprint = { }

local function requestFor ( worker , component ) 
local resident = state . resident [ worker ]
local imports = { }
local included = { }


local function includeBundle ( first ) 
local stack = { { bundle = first , expanded = false } }
while # stack > 0 do
local top = stack [ # stack ]
local bundle = top . bundle
local key = bundle . fingerprint
if resident [ key ] or included [ key ] then
stack [ # stack ] = nil
elseif not top . expanded then
top . expanded = true
for _ , arena in ipairs ( bundle . prerequisites ) do
local prerequisite = bundleByFingerprint [ arena ]
if prerequisite == nil then
if not resident [ arena ] then
error ( "parallel interface prerequisite is unavailable: " .. tostring ( arena ) , 0 )
end
elseif not resident [ arena ] and not included [ arena ] then
stack [ # stack + 1 ] = { bundle = prerequisite , expanded = false }
end
end
else
stack [ # stack ] = nil
included [ key ] = true
imports [ # imports + 1 ] = { fingerprint = key , bytes = bundle . bytes }
end
end
end



local reached = { [ component ] = true }
local walk = { component }
local needed = { }
while # walk > 0 do
local current = table . remove ( walk )
for _ , dependency in ipairs ( componentDependencies [ current ] ) do
if not reached [ dependency ] then
reached [ dependency ] = true
if bundleOf [ dependency ] ~= nil then
needed [ # needed + 1 ] = dependency
end
walk [ # walk + 1 ] = dependency
end
end
end
table . sort ( needed , function ( left , right ) 
return bundleOf [ left ] . order < bundleOf [ right ] . order
end )
for _ , dependency in ipairs ( needed ) do
includeBundle ( bundleOf [ dependency ] )
end

local paths = components [ component ]
local checkSources = { }
for _ , path in ipairs ( paths ) do
checkSources [ # checkSources + 1 ] = { path = path , name = sources [ path ] . name , hash = sources [ path ] . hash }
end
local request = { kind = "check" , sources = checkSources , imports = imports , }
if not state . initialized [ worker ] then
request . init = {
root = root ,
outDir = outDir ,
config = input . config ,
target = target ,
state = {
dependencies = input . state . dependencies ,
moduleCompilerHash = input . state . moduleCompilerHash ,
configHash = input . state . configHash ,
modules = { } ,
} ,
projectPaths = projectPaths ,
staged = input . staged ,
strict = input . strict ,
build = input . build == true ,
constSelection = input . constSelection ,
linked = input . linked ,
}
end

return request
end

local checked = { }
local codes = { }
local completedBundles = 0

local function accept ( worker , component , request , answer ) 
if not answer . ok or # ( answer . unchecked or { } ) > 0 then
local reason = tostring ( answer . problem or "incomplete batch" )
local diagnostic = answer . diagnostics and answer . diagnostics [ 1 ]
if diagnostic ~= nil then
reason = reason .. ": " .. tostring (
diagnostic . filename or ""
) .. ":" .. tostring (
diagnostic . line or 0
) .. " " .. tostring ( diagnostic . code or "" ) .. " " .. tostring ( diagnostic . msg or "" )
end
error (
reason .. " [paths " .. table . concat (
components [ component ] ,
", "
) .. "; worker said " .. state . channels [ worker ] . said .. "]" ,
0
)
end
state . initialized [ worker ] = true
local resident = state . resident [ worker ]
for _ , import in ipairs ( request . imports ) do
resident [ import . fingerprint ] = true
end
local batchStats = answer . stats or { }
local lane = state . lanes [ worker ]
lane . batches = lane . batches + 1
for _ , name in ipairs ( { "totalMs" , "semanticMs" , "decodeMs" } ) do
lane [ name ] = lane [ name ] + ( batchStats [ name ] or 0 )
end
state . batches = state . batches + 1
for name , value in pairs ( batchStats ) do
if type ( value ) == "number" then
state . stats [ name ] = ( state . stats [ name ] or 0 ) + value
end
end
for name , record in pairs ( answer . modules or { } ) do
checked [ name ] = record
end
for name , code in pairs ( answer . codes or { } ) do
codes [ name ] = code
end
local produced = answer . interface
if produced ~= nil then
completedBundles = completedBundles + 1
produced . order = completedBundles
bundleOf [ component ] = produced
bundleByFingerprint [ produced . fingerprint ] = produced
resident [ produced . fingerprint ] = true
end
remaining = remaining - 1
for _ , dependent in ipairs ( componentDependents [ component ] ) do
waiting [ dependent ] = waiting [ dependent ] - 1
if waiting [ dependent ] == 0 then
ready [ # ready + 1 ] = dependent
end
end
wakeQueue ( )
end

local function runWorker ( worker ) 
while true do
local component = takeComponent ( )
if component == nil then
return
end
local request = requestFor ( worker , component )
local answered , answer = pcall ( requestWorker , worker , request )
if not answered and ( tasks . isCancelled ( answer ) or tostring ( answer ) : match ( "interrupted!$" ) ~= nil ) then
error ( answer , 0 )
end
if not answered then


state . retries = state . retries + 1
startChild ( worker )
request = requestFor ( worker , component )
answered , answer = pcall ( requestWorker , worker , request )
end
if not answered then
error ( answer , 0 )
end
accept ( worker , component , request , answer )
end
end

local ran , problem = pcall ( function ( ) local __nuppT62;
do const  __nuppT69= tasks . open ( jobCount ) ; __nuppT62=__nuppT62 or {} ; local __nuppT70=__nuppT62[2]; if not __nuppT70 then __nuppT70=function(scope) do
for worker = 1 , jobCount do
do (function(__nuppT71,__nuppT72,__nuppT73) return __nuppT71:spawn( __nuppT73 ,__nuppT72 ) end)( scope , worker , runWorker ) end
end end; return "normal" end; __nuppT62[2]=__nuppT70 end; const __nuppT64,__nuppT65,__nuppT66=__nuppT14(__nuppT70,__nuppT10,__nuppT69); const __nuppT63=1;
local __nuppT67={}; local __nuppT68=0; if __nuppT63>=1 then  local __nuppT74,__nuppT75=__nuppT13(__nuppCleanup1,__nuppT69);  if not __nuppT74 then __nuppT68=__nuppT68+1; __nuppT67[__nuppT68]=__nuppT75 end; end; if not __nuppT64 then if __nuppT68>0 then __nuppT15(__nuppT11(__nuppT65,__nuppT67,1),0) else __nuppT15(__nuppT65,0) end end; if __nuppT68>0 then if __nuppT68>1 then __nuppT15(__nuppT11(__nuppT67[1],__nuppT67,2),0) else __nuppT15(__nuppT67[1],0) end end; if __nuppT65=="return" then  return __nuppT16(__nuppT66,1,__nuppT66.n)  end; end
end )
if not ran then
return abandon ( problem )
end
for path , source in pairs ( sources ) do
if checked [ source . name ] == nil then
return abandon ( "parallel check did not return " .. path )
end
end
if ( os . getenv ( "NUPP_PARALLEL_CHECK_TRACE" ) ~= nil ) then
local stats = state . stats
local lanes = { }
for worker = 1 , jobCount do
local lane = state . lanes [ worker ]
lanes [
# lanes + 1
] = ("%d:%d/%.0f/%.0f/%.0f") : format ( worker , lane . batches , lane . totalMs , lane . semanticMs , lane . decodeMs )
end
local sent , received = 0 , 0
for _ , channel in pairs ( state . channels ) do
sent = sent + channel . sent
received = received + channel . received
end
io . stderr : write (
("parallel cold check: batches=%d modules=%d interfaces=%d imports=%d scan=%.0fms setup=%.0fms decode=%.0fms semantic=%.0fms record=%.0fms interface=%.0fms encode=%.0fms worker=%.0fms sent=%d received=%d retries=%d lanes=%s\n")




: format (
state . batches ,
sourceCount ,
stats . interfaceNodes or 0 ,
stats . importedModules or 0 ,
scanMs ,
stats . setupMs or 0 ,
stats . decodeMs or 0 ,
stats . semanticMs or 0 ,
stats . recordMs or 0 ,
stats . interfaceMs or 0 ,
stats . encodeMs or 0 ,
stats . totalMs or 0 ,
sent ,
received ,
state . retries ,
table . concat ( lanes , "," )
)
)
end
closeChildren ( )
report : parallelCounted ( { mode = "parallel" , workers = jobCount , retries = state . retries , batches = state . batches , } )
report : at ( "resolve" )

return { records = checked , codes = codes } , nil
end

local __nuppExportValue= parallelcheck ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.parallelcheck"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.parallelcheck"]=__nuppExports;return __nuppExports