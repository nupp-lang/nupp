_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT5={}; local function __nuppT2(...) return {n=select("#",...),...} end; local __nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT3(value) return value end; local function __nuppT4(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT11({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT12(v.primary) for _,reason in __nuppT13(v.suppressed) do text=text.."\ncleanup: "..__nuppT12(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT63 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local json = require ( "nupp.codec.json" )

local buildProcess = require ( "nupp.compiler.process" )
local cli = require ( "nupp.cli" )
local files = require ( "nupp.io.files" )
local process = require ( "nupp.io.process" )
local random = require ( "nupp.random" )
local statistics = require ( "nupp.bench.internal.statistics" )
local system = require ( "nupp.system" )
local time = require ( "nupp.time" )






local bench = require ( "nupp.bench" )
local compare = bench . compare
local format = bench . format




local OLDEST_BASELINE_SCHEMA = 3


local RECORD_OUT = "build/bench-case.json"

local REMARKS_OUT = "build/remarks.json"
local MERGED_OUT = "build/bench-record.json"
local DEFAULT_TIMEOUT_MS = 120000





local PILOT_FORKS = 5


local MACHINE_KEY_FILE = "bench-machine-key"

local runner = { }





















































local function readFile ( path ) 
do const  __nuppT20= io . open ( path , "r" ) ; local __nuppT21=__nuppT5[1]; if not __nuppT21 then __nuppT21=function(handle) do
if not handle then
return "return",__nuppT2( nil )
end
local content = handle : read ( "*a" )
handle : close ( )

return "return",__nuppT2( content ) end; return "normal" end; __nuppT5[1]=__nuppT21 end; const __nuppT15,__nuppT16,__nuppT17=__nuppT7(__nuppT21,__nuppT3,__nuppT20); const __nuppT14=1; local __nuppT18={}; local __nuppT19=0; if __nuppT14>=1 and __nuppT20~=nil then  local __nuppT22,__nuppT23=__nuppT6(__nuppCleanup1,__nuppT20);  if not __nuppT22 then __nuppT19=__nuppT19+1; __nuppT18[__nuppT19]=__nuppT23 end; end; if not __nuppT15 then if __nuppT19>0 then __nuppT8(__nuppT4(__nuppT16,__nuppT18,1),0) else __nuppT8(__nuppT16,0) end end; if __nuppT19>0 then if __nuppT19>1 then __nuppT8(__nuppT4(__nuppT18[1],__nuppT18,2),0) else __nuppT8(__nuppT18[1],0) end end; if __nuppT16=="return" then  return __nuppT9(__nuppT17,1,__nuppT17.n)  end; end
end

local function writeFile ( path , content ) local __nuppT24;
do const  __nuppT31= io . open ( path , "w" ) ; __nuppT24=__nuppT24 or {} ; local __nuppT32=__nuppT24[2]; if not __nuppT32 then __nuppT32=function(handle) do
if not handle then
return "return",__nuppT2( false )
end
handle : write ( content )
handle : close ( )

return "return",__nuppT2( true ) end; return "normal" end; __nuppT24[2]=__nuppT32 end; const __nuppT26,__nuppT27,__nuppT28=__nuppT7(__nuppT32,__nuppT3,__nuppT31); const __nuppT25=1; local __nuppT29={}; local __nuppT30=0; if __nuppT25>=1 and __nuppT31~=nil then  local __nuppT33,__nuppT34=__nuppT6(__nuppCleanup1,__nuppT31);  if not __nuppT33 then __nuppT30=__nuppT30+1; __nuppT29[__nuppT30]=__nuppT34 end; end; if not __nuppT26 then if __nuppT30>0 then __nuppT8(__nuppT4(__nuppT27,__nuppT29,1),0) else __nuppT8(__nuppT27,0) end end; if __nuppT30>0 then if __nuppT30>1 then __nuppT8(__nuppT4(__nuppT29[1],__nuppT29,2),0) else __nuppT8(__nuppT29[1],0) end end; if __nuppT27=="return" then  return __nuppT9(__nuppT28,1,__nuppT28.n)  end; end
end

local function appendFile ( path , content ) local __nuppT35;
do const  __nuppT42= io . open ( path , "a" ) ; __nuppT35=__nuppT35 or {} ; local __nuppT43=__nuppT35[3]; if not __nuppT43 then __nuppT43=function(handle) do
if not handle then
return "return",__nuppT2( false )
end
handle : write ( content )
handle : close ( )

return "return",__nuppT2( true ) end; return "normal" end; __nuppT35[3]=__nuppT43 end; const __nuppT37,__nuppT38,__nuppT39=__nuppT7(__nuppT43,__nuppT3,__nuppT42); const __nuppT36=1; local __nuppT40={}; local __nuppT41=0; if __nuppT36>=1 and __nuppT42~=nil then  local __nuppT44,__nuppT45=__nuppT6(__nuppCleanup1,__nuppT42);  if not __nuppT44 then __nuppT41=__nuppT41+1; __nuppT40[__nuppT41]=__nuppT45 end; end; if not __nuppT37 then if __nuppT41>0 then __nuppT8(__nuppT4(__nuppT38,__nuppT40,1),0) else __nuppT8(__nuppT38,0) end end; if __nuppT41>0 then if __nuppT41>1 then __nuppT8(__nuppT4(__nuppT40[1],__nuppT40,2),0) else __nuppT8(__nuppT40[1],0) end end; if __nuppT38=="return" then  return __nuppT9(__nuppT39,1,__nuppT39.n)  end; end
end







local function discover ( ) 
local found = { }
for _ , path in ipairs ( files . glob ( "bench/*.bench.nupp" ) or { } ) do
found [ # found + 1 ] = path : toString ( )
end
table . sort ( found )

return found
end

local function matchesAny ( value , patterns ) 
if not patterns or # patterns == 0 then
return true
end
for _ , pattern in ipairs ( patterns ) do
if value : match ( pattern ) ~= nil then
return true
end
end

return false
end

local function parameterText ( parameters ) 
local keys = { }
for key in pairs ( parameters or { } ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
local values = { }
for _ , key in ipairs ( keys ) do
values [ # values + 1 ] = key .. "=" .. tostring ( ( parameters or { } ) [ key ] )
end

return table . concat ( values , "," )
end

local function selected (
benchmark ,
casePatterns ,
parameterPatterns ,
variantPatterns
) 
if not matchesAny ( benchmark . caseName or benchmark . name , casePatterns ) then
return false
end
if variantPatterns and not matchesAny ( benchmark . variant or "" , variantPatterns ) then
return false
end

return matchesAny ( parameterText ( benchmark . parameters ) , parameterPatterns )
end

local function slug ( name ) 
local answer = name : gsub ( "[^%w%-_.]+" , "-" ) : gsub ( "^%-+" , "" ) : gsub ( "%-+$" , "" )

return answer ~= "" and answer or "benchmark"
end

local function profilePath ( directory , index , name ) 
return ("%s/%03d-%s.collapsed") : format ( directory : gsub ( "/+$" , "" ) , index , slug ( name ) )
end

local function nuppRun (
executable ,
path ,
extra ,
timeoutMs ,
gpuCostsOut
) 
local args = { executable , "run" , "-O1" , "--remarks-out" }
if gpuCostsOut ~= nil then
args [ # args + 1 ] = "--gpu-costs"
args [ # args + 1 ] = gpuCostsOut
end
args [ # args + 1 ] = path
for _ , entry in ipairs ( extra ) do
args [ # args + 1 ] = entry
end
local childArgs = buildProcess . isolatedArguments ( args )
do local __nuppT53=0; local  __nuppT59 ; local __nuppT60=false ; local __nuppT54,__nuppT55,__nuppT56=__nuppT7(function() do local __nuppT61=__nuppT2( process . spawn ( {
args = childArgs ,
stdin = "inherit" ,
stdout = "pipe" ,
stderr = "pipe" ,
timeoutMs = timeoutMs ,
} ) ); __nuppT59= __nuppT61[1] ; __nuppT53=1;  __nuppT60=true;  local  child , spawnProblem = __nuppT61[1] , __nuppT61[2] ;
if child == nil then
return "return",__nuppT2( false , tostring ( spawnProblem or "could not start the child" ) )
end
local result , communicateProblem = child : communicate ( )
do (function(__nuppT62,...)  __nuppT60=false; return __nuppT62:close(...)  end)( child ) end
if not result then
return "return",__nuppT2( false , tostring ( communicateProblem or "could not collect child output" ) )
end
if result . errorOutput ~= "" then
io . stderr : write ( result . errorOutput )
end
if not result : succeeded ( ) and result . output ~= "" then
io . stderr : write ( result . output )
end
if result . exit . timedOut then
return "return",__nuppT2( false , ("timed out after %.3fs") : format ( timeoutMs / 1000 ) )
end

return "return",__nuppT2( result : succeeded ( ) , nil ) end; return "normal" end,__nuppT3); local __nuppT57={}; local __nuppT58=0; if __nuppT53>=1 and __nuppT60 and __nuppT59~=nil then  local __nuppT64,__nuppT65=__nuppT6(__nuppT63,__nuppT59);  if not __nuppT64 then __nuppT58=__nuppT58+1; __nuppT57[__nuppT58]=__nuppT65 end; end; if not __nuppT54 then if __nuppT58>0 then __nuppT8(__nuppT4(__nuppT55,__nuppT57,1),0) else __nuppT8(__nuppT55,0) end end; if __nuppT58>0 then if __nuppT58>1 then __nuppT8(__nuppT4(__nuppT57[1],__nuppT57,2),0) else __nuppT8(__nuppT57[1],0) end end; if __nuppT55=="return" then  return __nuppT9(__nuppT56,1,__nuppT56.n)  end; end
end


local CASES_CACHE = "build/bench-cases.json"



local CASES_DIR = "build/bench-cases"


local NOWHERE = package . config : sub ( 1 , 1 ) == "\\" and "NUL" or "/dev/null"







local function listingWidth ( count ) 
if package . config : sub ( 1 , 1 ) == "\\" then

return 1
end
local cores = system . availableParallelism ( )
if cores < 1 then
cores = 1
end
if count < cores then
return count
end

return cores
end


local function parseListing ( text ) 
local names = { }
local seen = { }
for line in text : gmatch ( "[^\13\n]+" ) do
local decoded , invalid = json . decode ( line )
if invalid ~= nil then
return { } , "wrote an invalid case listing"
end
local benchmark
if type ( decoded ) == "string" then
benchmark = { name = decoded }
elseif type ( decoded ) == "table" and type ( decoded . name ) == "string" then
benchmark = decoded
else
return { } , "wrote an invalid case listing"
end
local name = benchmark . name
if seen [ name ] then
return { } , "defines the case " .. name .. " more than once"
end
seen [ name ] = true
names [ # names + 1 ] = benchmark
end

return names , nil
end








local function compilerFingerprint ( ) 
local ok , loaded = pcall ( require , "nupp.compiler.project.fingerprint" )
if not ok or not loaded then
return nil
end

return loaded
end



local function sourceDigest ( path ) 
local fingerprint = compilerFingerprint ( )
if fingerprint == nil then
return nil
end

return fingerprint . hashFile ( path , fingerprint . contentDigest ( true ) )
end

local function listingKey ( ) 
local fingerprint = compilerFingerprint ( )
if fingerprint == nil then
return nil
end
local digest = fingerprint . contentDigest ( true )
local parts = { fingerprint . toolFingerprint ( digest ) }
local sources = { }
for _ , pattern in ipairs ( { "bench/**/*.nupp" , "bench/**/*.lua" , "bench/*.nupp" , "bench/*.lua" } ) do
for _ , path in ipairs ( files . glob ( pattern ) or { } ) do
sources [ # sources + 1 ] = path : toString ( )
end
end
table . sort ( sources )
local last = nil
for _ , path in ipairs ( sources ) do
if path ~= last then
parts [ # parts + 1 ] = path .. "\0" .. ( fingerprint . hashFile ( path , digest ) or "missing" )
last = path
end
end

return digest ( table . concat ( parts , "\0" ) )
end











local function rememberedListings ( key ) 
if key == nil then
return { }
end
local text = readFile ( "build/bench-cases.json" )
if not text then
return { }
end
local decoded = json . decode ( text )
if type ( decoded ) ~= "table" or decoded . key ~= key or type ( decoded . files ) ~= "table" then
return { }
end
local answer = { }
for path , entry in pairs ( decoded . files ) do
if type ( entry ) == "table" and type ( entry . source ) == "string" and type ( entry . cases ) == "table" then
answer [ path ] = entry
end
end

return answer
end

local function rememberListings ( key , listings ) 
if key == nil then
return
end
pcall ( function ( ) 
files . createDirectory ( "build" )
writeFile ( "build/bench-cases.json" , json . encode ( { key = key , files = listings } ) )
end )
end













local function casesFor (
executable ,
paths ,
timeoutMs
) 
local answers = { }
local problems = { }
local key = listingKey ( )
local remembered = rememberedListings ( key )
local sources = { }
local wanted = { }
for _ , path in ipairs ( paths ) do
local source = sourceDigest ( path )
sources [ path ] = source or ""
local known = remembered [ path ]
if known ~= nil and source ~= nil and known . source == source then
answers [ path ] = known . cases
else
wanted [ # wanted + 1 ] = path
end
end
if # wanted == 0 then
return answers , problems
end
files . createDirectory ( "build/bench-cases" )

local function accept ( path , listing , output , code , timedOut ) 
if output ~= "" then
io . stderr : write ( output )
end
if timedOut then
problems [ path ] = ("case listing timed out after %.3fs") : format ( timeoutMs / 1000 )

return
end
if code ~= 0 then
problems [ path ] = "case listing failed"

return
end
local text = readFile ( listing )
if not text then
problems [ path ] = "wrote no case listing"

return
end
local listed , problem = parseListing ( text )
if problem then
problems [ path ] = problem

return
end
answers [ path ] = listed



if sources [ path ] ~= "" then
remembered [ path ] = { source = sources [ path ] , cases = listed }
end
end

local function argumentsFor ( path , listing ) 
return buildProcess . isolatedArguments ( {
executable ,
"run" ,
"-O1" ,
"--remarks-out" ,
path ,
"--list-cases" ,
"--cases-out" ,
listing
} )
end

local width = listingWidth ( # wanted )
if width <= 1 then
for _ , path in ipairs ( wanted ) do

os . remove ( "build/bench-cases/1.txt" )
local ok , problem = nuppRun ( executable , path , { "--list-cases" , "--cases-out" , "build/bench-cases/1.txt" } , timeoutMs )
if not ok then
problems [ path ] = problem and "case listing " .. problem or "case listing failed"
else
accept ( path , "build/bench-cases/1.txt" , "" , 0 , false )
end
os . remove ( "build/bench-cases/1.txt" )
end
rememberListings ( key , remembered )

return answers , problems
end

local first = 1
while first <= # wanted do
local last = first + width - 1
if last > # wanted then
last = # wanted
end
local parts = { }
local produced = { }
for index = first , last do
local stem = "build/bench-cases" .. "/" .. tostring ( index )
local job = {
path = wanted [ index ] ,
listing = stem .. ".txt" ,
output = stem .. ".out" ,
status = stem .. ".rc" ,
expired = stem .. ".timeout" ,
}
produced [ index ] = job
os . remove ( job . listing )
os . remove ( job . output )
os . remove ( job . status )
os . remove ( job . expired )










local seconds = math . ceil ( timeoutMs / 1000 )
parts [
# parts + 1
] = "( { " .. buildProcess . command (
argumentsFor ( job . path , job . listing )
) .. " ; } <" .. NOWHERE .. " >" .. buildProcess . quote (
job . output
) .. " 2>&1 & __nupp_job=$!; ( __nupp_n=0; while [ $__nupp_n -lt " .. tostring (
seconds
)
.. " ]; do sleep 1; __nupp_n=$((__nupp_n+1)); kill -0 $__nupp_job 2>/dev/null || exit 0; done; "
.. "kill -9 $__nupp_job 2>/dev/null && printf 1 >"
.. buildProcess . quote (
job . expired
)
.. " ) <"
.. NOWHERE
.. " >"
.. NOWHERE
.. " 2>&1 & __nupp_watch=$!; wait $__nupp_job; printf %d $? >"
.. buildProcess . quote (
job . status
) .. "; kill $__nupp_watch 2>/dev/null ) &"
end
parts [ # parts + 1 ] = "wait"




os . execute ( "{\n" .. table . concat ( parts , "\n" ) .. "\n} 2>" .. NOWHERE )
for index = first , last do
local job = produced [ index ]



local status = tonumber ( ( readFile ( job . status ) or "" ) : match ( "%d+" ) or "" )
accept (
job . path ,
job . listing ,
readFile ( job . output ) or "" ,
( status or 1 ) ,
readFile ( job . expired ) ~= nil
)
os . remove ( job . listing )
os . remove ( job . output )
os . remove ( job . status )
os . remove ( job . expired )
end
first = last + 1
end
rememberListings ( key , remembered )

return answers , problems
end


local function runCase (
executable ,
path ,
name ,
n ,
timeoutMs ,
sampleOut ,
sampleIntervalMs ,
sampleZone ,
gpuCostsOut
) 
os . remove ( "build/bench-case.json" )
os . remove ( "build/remarks.json" )
local extra = { "--case" , name , "--out" , "build/bench-case.json" , "--quiet" }
if n then
extra [ # extra + 1 ] = "--n"
extra [ # extra + 1 ] = tostring ( n )
end
if sampleOut then
extra [ # extra + 1 ] = "--sample-out"
extra [ # extra + 1 ] = sampleOut
extra [ # extra + 1 ] = "--sample-root"
extra [ # extra + 1 ] = path : match ( "([^/\\]+)$" ) or path
extra [ # extra + 1 ] = "--sample-interval-ms"
extra [ # extra + 1 ] = tostring ( sampleIntervalMs )
if sampleZone then
extra [ # extra + 1 ] = "--sample-zone"
extra [ # extra + 1 ] = sampleZone
end
end
local ok , runProblem = nuppRun ( executable , path , extra , timeoutMs , gpuCostsOut )
local text = readFile ( "build/bench-case.json" )
if not text then
return nil , path .. " / " .. name .. ": " .. ( runProblem or "wrote no record" )
end
local decoded , invalid = json . decode ( text )
if invalid ~= nil then
return nil , path .. " / " .. name .. ": wrote a record that does not parse"
end
decoded . gpuCosts = gpuCostsOut



local remarksText = readFile ( "build/remarks.json" )
if remarksText then
local remarks , unreadable = json . decode ( remarksText )
if unreadable == nil then
decoded . executionProfile = remarks . executionProfile
decoded . remarks = remarks . remarks
decoded . allocationSites = remarks . allocationSites
decoded . compiler = remarks . compiler
end
end
if not ok then
return decoded , path .. " / " .. name .. ": " .. ( runProblem or "the case reported a failure" )
end

return decoded , nil
end


local function previousIterations ( record ) 
for _ , measurement in ipairs ( record and record . cases or { } ) do
if measurement . kind == "case" and type ( measurement . n ) == "number" and measurement . n >= 1 then
return math . floor ( measurement . n )
end
end

return nil
end

local function progressLine ( record , name , wallSec ) 
local measurement = record and record . cases and record . cases [ 1 ]
if not measurement then
return ("# Result: %s  no measurement  wall=%.3fs\n") : format ( name , wallSec )
end
local score = 0
local units = "ns/op"
local count = measurement . rounds or 0
local countLabel = "rounds"
if measurement . kind == "case" then
local n = measurement . n or 0
if n > 0 then
score = ( measurement . medianMs or 0 ) * 1000000 / n
end
elseif measurement . kind == "suite" then
score = ( measurement . medianMs or 0 ) * 1000000
countLabel = "samples"
else
score = measurement . p50Ms or 0
units = "ms/frame"
count = measurement . frames or 0
countLabel = "frames"
end

return ("# Result: %s  p50=%.3f %s  %s=%d  wall=%.3fs\n") : format ( name , score , units , countLabel , count , wallSec )
end







local function onlyMeasurement ( record ) 
local cases = record and record . cases
if not cases or # cases == 0 then
return nil
end

return cases [ 1 ]
end






local function usableRecord ( record ) 
local measurement = record and record . cases and record . cases [ 1 ]
if not measurement then
return false
end
if measurement . kind == "case" then
return type ( measurement . n ) == "number" and measurement . n >= 1 and measurement . medianMs ~= nil
end
if measurement . kind == "suite" then
return measurement . medianMs ~= nil
end

return measurement . p50Ms ~= nil
end






local function perOperation ( measurement ) 
if not measurement then
return 0
end
if measurement . kind == "case" then
local n = measurement . n or 0
if n <= 0 then
return 0
end

return ( measurement . medianMs or 0 ) / n
end
if measurement . kind == "suite" then
return measurement . medianMs or 0
end

return measurement . p50Ms or 0
end



local function fromPerOperation ( measurement , value ) 
if measurement and measurement . kind == "case" then
return value * ( measurement . n or 1 )
end

return value
end







local function allocationIdentities ( record ) 
local entries = { }
for _ , site in ipairs ( record and record . allocationSites or { } ) do
entries [
# entries + 1
] = tostring ( site . file ) .. "|" .. tostring ( site . kind ) .. "|" .. tostring ( site . line ) .. "|" .. tostring ( site . col )
end
table . sort ( entries )

return entries
end


local function remarkIdentities ( record ) 
local entries = { }
for _ , entry in ipairs ( record and record . remarks or { } ) do
local at = entry . range and entry . range . start or nil
entries [
# entries + 1
] = ("%s|%s|%s|%s")

: format ( tostring ( entry . code ) , tostring ( entry . file ) , tostring ( at and at . line or 0 ) , tostring ( entry . message ) )
end
table . sort ( entries )

return entries
end


local function sameList ( left , right ) 
if # left ~= # right then
return false
end
for index = 1 , # left do
if left [ index ] ~= right [ index ] then
return false
end
end

return true
end








local function mergeAbortSites ( forks ) 
local seen = { }
local order = { }
local observed = 0
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
local sites = measurement and measurement . abortSites
if sites then
observed = ( observed + 1 )
for _ , site in ipairs ( sites ) do
local count = seen [ site ]
if count == nil then
count = 0
order [ # order + 1 ] = site
end
seen [ site ] = ( count + 1 )
end
end
end
if observed == 0 then

return nil , { }
end
local unanimous = { }
local flaky = { }
for _ , site in ipairs ( order ) do
local count = seen [ site ]
if count == observed then
unanimous [ # unanimous + 1 ] = site
else
flaky [ # flaky + 1 ] = { site = site , forks = count , of = observed , }
end
end
table . sort ( unanimous )

return unanimous , flaky
end







local function mergeForks ( name , path , forks ) 
local notes = { }
local first = forks [ 1 ]
local firstMeasurement = onlyMeasurement ( first )
local summaries = { }
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
if measurement then
summaries [ # summaries + 1 ] = perOperation ( measurement )
end
end





local firstAllocations = allocationIdentities ( first )
local firstRemarks = remarkIdentities ( first )
for index = 2 , # forks do
if not sameList ( allocationIdentities ( forks [ index ] ) , firstAllocations ) then
notes [
# notes + 1
] = name .. ": nondeterministic compiler output: fork " .. tostring (
index
) .. " reported different allocation sites"
end
if not sameList ( remarkIdentities ( forks [ index ] ) , firstRemarks ) then
notes [
# notes + 1
] = name .. ": nondeterministic compiler output: fork " .. tostring ( index ) .. " reported different remarks"
end
end

local unanimousAborts , flaky = mergeAbortSites ( forks )
for _ , entry in ipairs ( flaky ) do
notes [
# notes + 1
] = ("%s: flaky abort site: %s in %d/%d forks; reported, not gated")

: format ( name , entry . site , entry . forks , entry . of )
end

local merged = { }
for key , value in pairs ( firstMeasurement or { } ) do
merged [ key ] = value
end
merged . forkCount = # summaries
merged . forkSummariesMs = summaries
merged . abortSites = unanimousAborts




local trending = 0
local tested = 0
local drifts = { }
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
local verdict = measurement and measurement . trend
if verdict == "trend" or verdict == "no-trend-detected" then
tested = ( tested + 1 )
if verdict == "trend" then
trending = ( trending + 1 )
drifts [ # drifts + 1 ] = measurement . trendDrift or 0
end
end
end
local unsettled = tested > 0 and trending * 2 >= tested
if # summaries > 0 then
merged . medianMs = fromPerOperation ( firstMeasurement , statistics . median ( summaries ) )
if firstMeasurement and firstMeasurement . kind == "frames" then
merged . p50Ms = statistics . median ( summaries )
end
end




local allocated = { }
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
if measurement and measurement . allocatedKb ~= nil then
allocated [ # allocated + 1 ] = measurement . allocatedKb
end
end
if # allocated > 0 then
merged . allocatedKb = statistics . median ( allocated )
end
if unsettled then
merged . intervalWithheld = "trend-warning"
notes [
# notes + 1
] = ("%s: trend-warning: monotone trend in %d/%d forks; interval withheld and verdict forced to inconclusive")

: format ( name , trending , tested )
else
local interval = statistics . medianInterval ( summaries )
if interval then
merged . intervalLowMs = fromPerOperation ( firstMeasurement , interval . low )
merged . intervalHighMs = fromPerOperation ( firstMeasurement , interval . upper )
merged . intervalCoverage = interval . attainedCoverage
else
merged . intervalWithheld = "below-minimum-forks"
end
end





local concentrations = { }
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
if measurement and measurement . concentration then
concentrations [ # concentrations + 1 ] = measurement . concentration
end
end
if # concentrations > 0 then
local typical = statistics . median ( concentrations )
merged . concentration = typical
if typical < statistics . MIN_CONCENTRATION then
notes [
# notes + 1
] = ("%s: scattered: only %.0f%% of samples lie within %.0f%% of the median, so the score describes no rate this benchmark ran at; raise sampleIterations until one sample spans whole collector cycles")



: format ( name , typical * 100 , statistics . CONCENTRATION_TOLERANCE * 100 )
end
end

local outliers = 0
local worst = 1
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
if measurement then
outliers = ( outliers + ( measurement . outlierCount or 0 ) )
if ( measurement . outlierMaxRatio or 1 ) > worst then
worst = measurement . outlierMaxRatio or 1
end
end
end
merged . outlierCount = outliers
merged . outlierMaxRatio = worst
if outliers > 0 then
local total = 0
for _ , fork in ipairs ( forks ) do
local measurement = onlyMeasurement ( fork )
total = ( total + ( ( measurement and measurement . samplesMs ) and # measurement . samplesMs or 0 ) )
end
notes [
# notes + 1
] = ("%s: outliers: %d severe of %d samples across %d forks, max %.1fx median; classified only, all samples retained")

: format ( name , outliers , total , # forks , worst )
end

local forkEntries = { }
for index , fork in ipairs ( forks ) do
forkEntries [ # forkEntries + 1 ] = { index = index , measurement = onlyMeasurement ( fork ) , gpuCosts = fork . gpuCosts , }
end

return {
name = name ,
case = path ,
forks = forkEntries ,
summary = merged ,
executionProfile = first . executionProfile ,
remarks = first . remarks ,
allocationSites = first . allocationSites ,
traceProfile = first . traceProfile ,
compiler = first . compiler ,
} , notes
end


local function comparableRecord ( entry ) 
return {
schema = bench . SCHEMA ,
cases = { entry . summary , } ,
executionProfile = entry . executionProfile ,
remarks = entry . remarks ,
allocationSites = entry . allocationSites ,
traceProfile = entry . traceProfile ,
compiler = entry . compiler ,
}
end











local function durationChange ( current , previous , paired ) 
if # current == 0 or # previous == 0 then
return 0 , nil , 1
end
local currentLogs = { }
local previousLogs = { }
for _ , value in ipairs ( current ) do
currentLogs [ # currentLogs + 1 ] = value > 0 and math . log ( value ) or 0
end
for _ , value in ipairs ( previous ) do
previousLogs [ # previousLogs + 1 ] = value > 0 and math . log ( value ) or 0
end
if paired and # currentLogs == # previousLogs then
local differences = { }
for index = 1 , # currentLogs do
differences [ # differences + 1 ] = currentLogs [ index ] - previousLogs [ index ]
end
local shift = statistics . pairedShift ( differences )
local estimate = statistics . median ( differences )
local interval = nil
if shift then
interval = { low = math . exp ( shift . low ) - 1 , upper = math . exp ( shift . upper ) - 1 , }
end

return math . exp ( estimate ) - 1 , interval , statistics . pairedPValue ( differences )
end
local estimate , shift = statistics . unpairedShift ( currentLogs , previousLogs )
local interval = nil
if shift then
interval = { low = math . exp ( shift . low ) - 1 , upper = math . exp ( shift . upper ) - 1 , }
end

return math . exp ( estimate ) - 1 , interval , statistics . unpairedPValue ( currentLogs , previousLogs )
end

local function percent ( value ) 
return ("%+.1f%%") : format ( value * 100 )
end












local function hostProfile ( merged ) 
local luajitRevision = nil
for _ , entry in ipairs ( merged ) do
local profile = entry . traceProfile
if profile and profile . luajitRevision then
luajitRevision = profile . luajitRevision
do break end
end
end

return {
platform = system . platform ,
architecture = system . architecture ,
pointerBits = system . pointerBits ,
luajitRevision = luajitRevision ,
}
end







local function machineKey ( ) 
local directory = os . getenv ( "NUPP_TOOLCHAIN_CACHE" ) or ( os . getenv ( "HOME" ) or "." ) .. "/.cache/nupp"
local path = directory .. "/bench-machine-key"
local existing = readFile ( path )
if existing then
local trimmed = existing : gsub ( "%s+$" , "" )
if trimmed ~= "" then
return trimmed
end
end
local generator = random . Xoshiro128 .__nuppCtor1 ( math . floor ( os . time ( ) * 1000 + os . clock ( ) * 1000000 ) )

local built = { }
for _ = 1 , 32 do
local pick = generator : integer ( 1 , 16 )
built [ # built + 1 ] = ("0123456789abcdef") : sub ( pick , pick )
end
local key = table . concat ( built )
files . createDirectory ( directory )
if not writeFile ( path , key .. "\n" ) then



return nil
end

return key
end






local function reportPilot ( merged , forks , failures ) 
local recommended = statistics . MIN_INTERVAL_SAMPLES
io . stdout : write ( ("\nnupp: pilot over %d forks, one shuffled permutation per round\n\n") : format ( forks ) )
local style = cli . style ( io . stdout )
local rows = { }
for _ , entry in ipairs ( merged ) do
local summaries = entry . summary . forkSummariesMs or { }
local variation = statistics . coefficientOfVariation ( summaries )
local tight = statistics . forksForPrecision ( variation , 0.02 )
local loose = statistics . forksForPrecision ( variation , 0.05 )
if tight > recommended then
recommended = tight
end
rows [
# rows + 1
] = {
cli . paintedCell ( entry . name , style . strong ) ,
cli . cell ( ("%.1f%%") : format ( variation * 100 ) ) ,
cli . cell ( tostring ( tight ) ) ,
cli . cell ( tostring ( loose ) ) ,
}
end
cli . writeTable (
io . stdout ,
{
columns = {
{ heading = "Benchmark" } ,
{ heading = "Between-fork CV" , align = "right" } ,
{ heading = "Forks for +-2%" , align = "right" } ,
{ heading = "Forks for +-5%" , align = "right" } ,
} ,
rows = rows ,
style = style ,
}
)
io . stdout : write ( ("\nnupp: --forks %d covers every selected benchmark at +-2%%\n") : format ( recommended ) )
for _ , failure in ipairs ( failures ) do
io . stderr : write ( "nupp: " .. failure .. "\n" )
end

return # failures > 0 and 1 or 0
end




local VERDICT_SEVERITY = { regressed = "error" , unchanged = "note" , inconclusive = "note" , }

local function verdictPaint ( style , verdict ) 
if verdict == "improved" then
return style . green
end
local severity = VERDICT_SEVERITY [ verdict ]

return severity ~= nil and cli . severity ( style , severity ) or style . faint
end







local function formatVerdicts ( verdicts , margin , source , paired ) 
local style = cli . style ( io . stdout )
local lines = { }
lines [ # lines + 1 ] = ""
if paired then
lines [ # lines + 1 ] = ("Durations: candidate vs %s  (interleaved, paired)") : format ( source )
else
lines [ # lines + 1 ] = ("Durations vs %s  (observational, unpaired)") : format ( source )
lines [ # lines + 1 ] = "note: the baseline was recorded in another session; nothing controls for what"
lines [ # lines + 1 ] = "      changed on this machine between them. Use --against for a causal claim."
end
local counts = { }
local rows = { }
for _ , item in ipairs ( verdicts ) do
local interval = "-"
if item . withheld == "trend-warning" then
interval = "withheld (trend)"
elseif item . withheld == "below-minimum-forks" then
interval = "withheld (forks)"
elseif item . interval then
interval = ("[%s, %s]") : format ( percent ( item . interval . low ) , percent ( item . interval . upper ) )
end
rows [
# rows + 1
] = {
cli . paintedCell ( item . name , style . strong ) ,
cli . cell ( percent ( item . change ) ) ,
cli . cell ( interval ) ,
cli . paintedCell ( item . verdict , verdictPaint ( style , item . verdict ) ) ,
}
counts [ item . verdict ] = ( ( counts [ item . verdict ] or 0 ) + 1 )
end

const table_ = cli . table (
{
columns = {
{ heading = "Benchmark" } ,
{ heading = "Change" , align = "right" } ,
{ heading = "Interval" , align = "right" } ,
{ heading = "Verdict" } ,
} ,
rows = rows ,
style = style ,
}
)
for line in table_ : gmatch ( "[^\n]+" ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
lines [
# lines + 1
] = ("nupp: %d compared, equivalence margin +-%.1f%%, Benjamini-Hochberg adjusted")

: format ( # verdicts , margin * 100 )
lines [
# lines + 1
] = ("      %d regressed, %d improved, %d unchanged, %d inconclusive")

: format ( counts . regressed or 0 , counts . improved or 0 , counts . unchanged or 0 , counts . inconclusive or 0 )

return table . concat ( lines , "\n" ) .. "\n"
end






local function planned (
executable ,
paths ,
timeoutMs ,
casePatterns ,
parameterPatterns ,
variantPatterns ,
failures
) 
local entries = { }
local listings , listingFailures = casesFor ( executable , paths , timeoutMs )
for _ , path in ipairs ( paths ) do
local names = listings [ path ] or { }
local listingFailure = listingFailures [ path ]
if listingFailure then
failures [ # failures + 1 ] = path .. ": " .. listingFailure
elseif # names == 0 then
failures [ # failures + 1 ] = path .. ": defines no case"
end
for _ , benchmark in ipairs ( names ) do
if selected ( benchmark , casePatterns , parameterPatterns , variantPatterns ) then
entries [
# entries + 1
] = {
path = path ,
name = benchmark . name ,
records = { } ,
againstRecords = { } ,
iterations = nil ,
}
end
end
end

return entries
end




local function problem ( code , message , file ) 
return { filename = file , code = code , msg = message }
end




local function writeRunDocument ( document , code , problems ) 
local report = require ( "nupp.tools.cli.report" )
local shown = { }
for key , value in pairs ( document ) do
shown [ key ] = value
end
shown . ok = code == 0
shown . diagnostics = report . diagnosticValues ( problems )
io . stdout : write ( report . encode ( shown ) , "\n" )

return code
end

function runner . run ( options ) 
local executable = options . executable or "nupp"
local baselinePath = options . baseline
local accept = options . accept == true
local asJson = options . json == true
local listOnly = options . list == true
local casePatterns = options . casePatterns
local parameterPatterns = options . parameterPatterns
local variantPatterns = options . variantPatterns
local onlyFile = options . file
local historyPath = options . history
local label = options . label
local timeoutMs = options . timeoutMs or 120000
local profileDir = options . profileDir
local gpuCostsDirectory = nil
local profileIntervalMs = options . profileIntervalMs or 1
local profileZone = options . profileZone
local pilot = options . pilot == true
local forks = pilot and 5 or ( options . forks or 1 )
local margin = options . margin
local against = options . against
if timeoutMs < 1 or timeoutMs ~= math . floor ( timeoutMs ) then
io . stderr : write ( "nupp: timeout must be a positive whole number of milliseconds\n" )

return 2
end
if forks < 1 or forks ~= math . floor ( forks ) then
io . stderr : write ( "nupp: --forks needs a positive whole number\n" )

return 2
end
if profileIntervalMs < 1 or profileIntervalMs ~= math . floor ( profileIntervalMs ) then
io . stderr : write ( "nupp: profile interval must be a positive whole number of milliseconds\n" )

return 2
end




local function refuse ( code , message , file ) 
if asJson then
return writeRunDocument (
{ schema = ( require ( "nupp.bench" ) ) . SCHEMA , recordedAt = "" , benchmarks = json . asArray ( { } ) } ,
1 ,
{ ( { filename = file , code = code , msg = message } ) }
)
end
io . stderr : write ( "nupp: " .. message .. "\n" )

return 1
end

if profileDir then
local made , madeProblem = files . createDirectory ( profileDir )
if not made then
return refuse (
"NUPP0001" ,
"cannot create profile directory " .. profileDir .. ": " .. tostring ( madeProblem ) ,
profileDir
)
end
end

if listOnly then
local failed = false
local paths = onlyFile and { onlyFile } or discover ( )
local listings , listingProblems = casesFor ( executable , paths , timeoutMs )
local matched = { }
local problems = { }
for _ , path in ipairs ( paths ) do
local listingProblem = listingProblems [ path ]
if listingProblem then
if asJson then
problems [
# problems + 1
] = problem ( files . exists ( path ) and "NUPP0004" or "NUPP0001" , path .. ": " .. listingProblem , path )
else
io . stderr : write ( "nupp: " .. path .. ": " .. listingProblem .. "\n" )
end
failed = true
end
for _ , benchmark in ipairs ( listings [ path ] or { } ) do
if selected ( benchmark , casePatterns , parameterPatterns , variantPatterns ) then
matched [ # matched + 1 ] = { benchmark = benchmark , path = path }
end
end
end
if # matched == 0 and not failed then
if asJson then
problems [ # problems + 1 ] = problem ( "NUPP0003" , "no benchmark matched the selection" )
else
io . stderr : write ( "nupp: no benchmark matched the selection\n" )
end
failed = true
end
if asJson then
local entries = { }
for index , entry in ipairs ( matched ) do
local benchmark = entry . benchmark
entries [
index
] = {
name = benchmark . name ,
file = entry . path ,
suite = benchmark . suite ,
case = benchmark . caseName ,
variant = benchmark . variant ,
parameters = benchmark . parameters ,
}
end
io . stdout : write (
require ( "nupp.tools.cli.report" ) . encode ( {
ok = not failed ,
benchmarks = json . asArray ( entries ) ,
diagnostics = require ( "nupp.tools.cli.report" ) . diagnosticValues ( problems ) ,
} ) ,
"\n"
)

return failed and 1 or 0
end
local style = cli . style ( io . stdout )
local rows = { }
for index , entry in ipairs ( matched ) do
rows [
index
] = { cli . paintedCell ( entry . benchmark . name , style . strong ) , cli . paintedCell ( entry . path , style . faint ) , }
end
cli . writeTable (
io . stdout ,
{ columns = { { heading = "benchmark" } , { heading = "file" } } , rows = rows , style = style }
)

return failed and 1 or 0
end

local previous = nil
if baselinePath then
local text = readFile ( baselinePath )
if text then
local document , refused = bench . decodeBaseline ( text , baselinePath , 3 )


if refused then
io . stderr : write ( refused , accept and "; replacing it\n" or "\n" )
if not accept then
return 1
end
end
previous = document
end


if not previous and not accept then
return refuse ( "NUPP0001" , "no baseline at " .. baselinePath , baselinePath )
end
end

if options . gpuCostsDir ~= nil then
if options . gpuCostsDir == "" then
return refuse ( "NUPP0001" , "--gpu-costs needs an output directory" )
end
gpuCostsDirectory = options . gpuCostsDir .. "/" .. require ( "nupp.util" ) . uuid4 ( )
local made , madeProblem = files . createDirectory ( gpuCostsDirectory )
if not made then
return refuse ( "NUPP0001" , "cannot create GPU cost directory: " .. tostring ( madeProblem ) , gpuCostsDirectory )
end
end

local executionFailures = { }
local regressions = { }
local notes = { }
local paths = onlyFile and { onlyFile } or discover ( )
local entries = planned (
executable ,
paths ,
timeoutMs ,
casePatterns ,
parameterPatterns ,
variantPatterns ,
executionFailures
)
local seed = options . seed or math . floor ( os . time ( ) * 1000 + os . clock ( ) * 1000 ) % 2147483647
local shuffler = random . Xoshiro128 .__nuppCtor1 ( seed )






for round = 1 , forks do
local order = { }
for _ , entry in ipairs ( entries ) do
order [ # order + 1 ] = entry
end
if # order > 1 then
shuffler : shuffle ( order )
end
for _ , entry in ipairs ( order ) do
local sampleOut = nil
if profileDir and round == 1 then
sampleOut = profilePath ( profileDir , # entry . records + 1 , entry . name )
end
if not asJson and not pilot then
if forks > 1 then
io . stdout : write ( ("# Benchmark: %s (%s) fork %d/%d\n") : format ( entry . name , entry . path , round , forks ) )
else
io . stdout : write ( ("# Benchmark: %s (%s)\n") : format ( entry . name , entry . path ) )
end
io . stdout : flush ( )
end
local gpuCostStem = gpuCostsDirectory ~= nil
and (
gpuCostsDirectory
.. "/"
.. tostring ( round )
.. "-"
.. require ( "nupp.compiler.hash" ) . digest ( entry . path .. "\0" .. entry . name ) : sub ( 1 , 16 )
.. "-"
.. slug ( entry . name ) : sub ( 1 , 72 )
)
or nil
local started = time . now ( )
local record , failure = runCase (
executable ,
entry . path ,
entry . name ,
entry . iterations ,
timeoutMs ,
sampleOut ,
profileIntervalMs ,
profileZone ,
gpuCostStem ~= nil and gpuCostStem .. "-candidate.jsonl" or nil
)
local wallSec = ( time . now ( ) - started ) / 1000
if failure then
executionFailures [ # executionFailures + 1 ] = failure
end




if record and not usableRecord ( record ) then
executionFailures [
# executionFailures + 1
] = ("%s / %s: fork %d wrote no usable measurement and was dropped")

: format ( entry . path , entry . name , round )
record = nil
end
if record then
entry . records [ # entry . records + 1 ] = record



if not entry . iterations then
entry . iterations = previousIterations ( record )
end
if not asJson and not pilot then
io . stdout : write ( progressLine ( record , entry . name , wallSec ) )
if sampleOut then
io . stdout : write ( "# Profile: " , sampleOut , "\n" )
end
io . stdout : flush ( )
end
end
if against then



local otherRecord , otherFailure = runCase (
against ,
entry . path ,
entry . name ,
entry . iterations ,
timeoutMs ,
nil ,
profileIntervalMs ,
profileZone ,
gpuCostStem ~= nil and gpuCostStem .. "-against.jsonl" or nil
)
if otherFailure then
executionFailures [ # executionFailures + 1 ] = "against: " .. otherFailure
end
if otherRecord and not usableRecord ( otherRecord ) then
executionFailures [
# executionFailures + 1
] = ("against: %s / %s: fork %d wrote no usable measurement and was dropped")

: format ( entry . path , entry . name , round )
otherRecord = nil
end
if otherRecord then
entry . againstRecords [ # entry . againstRecords + 1 ] = otherRecord
end
end
end
end

local merged = { }
local againstByName = { }
for _ , entry in ipairs ( entries ) do
if # entry . records > 0 then
local summary , forkNotes = mergeForks ( entry . name , entry . path , entry . records )
merged [ # merged + 1 ] = summary
for _ , note in ipairs ( forkNotes ) do
notes [ # notes + 1 ] = note
end
if # entry . againstRecords > 0 then
local other = mergeForks ( entry . name , entry . path , entry . againstRecords )
againstByName [ tostring ( entry . path ) .. "\0" .. tostring ( entry . name ) ] = other
end
end
end
if ( onlyFile or casePatterns or parameterPatterns or variantPatterns )
and # merged == 0
and # executionFailures == 0
then
executionFailures [ # executionFailures + 1 ] = "no benchmark matched the selection"
end

if pilot then
return reportPilot ( merged , forks , executionFailures )
end

local document = {
schema = bench . SCHEMA ,
recordedAt = os . date ( "!%Y-%m-%dT%H:%M:%SZ" ) ,
label = label ,
forks = forks ,
seed = seed ,
margin = margin ,
hostProfile = hostProfile ( merged ) ,
machineKey = machineKey ( ) ,
comparison = against and "interleaved" or ( baselinePath and "observational" or nil ) ,
benchmarks = merged ,
comparisons = json . asArray ( { } ) ,
}

if against and margin then
local baselines = { }
for _ , entry in ipairs ( merged ) do
local other = againstByName [ tostring ( entry . case ) .. "\0" .. tostring ( entry . name ) ]
if other then
baselines [ # baselines + 1 ] = other
end
end
local comparison = {
kind = "interleaved" ,
source = against ,
baseline = { benchmarks = baselines } ,
verdicts = json . asArray ( { } )
}
document . comparisons [ # document . comparisons + 1 ] = comparison
local pending = { }
for _ , entry in ipairs ( merged ) do
local other = againstByName [ tostring ( entry . case ) .. "\0" .. tostring ( entry . name ) ]
if other then
local current = entry . summary . forkSummariesMs or { }
local before = other . summary . forkSummariesMs or { }
local change , interval , pValue = durationChange ( current , before , true )
local withheld = entry . summary . intervalWithheld or other . summary . intervalWithheld





if withheld then
interval = nil
end
pending [
# pending + 1
] = {
case = entry . case ,
name = entry . name ,
change = change ,
interval = interval ,
pValue = pValue ,
withheld = withheld ,
}
end
end
if # pending > 0 then
local pValues = { }
for _ , item in ipairs ( pending ) do
pValues [ # pValues + 1 ] = item . pValue
end
local adjusted = statistics . benjaminiHochberg ( pValues )
for index , item in ipairs ( pending ) do
item . adjusted = adjusted [ index ]
item . verdict = statistics . verdict ( item . interval , margin or 0 , adjusted [ index ] )
comparison . verdicts [ # comparison . verdicts + 1 ] = item
end
end
end
if previous then
local comparison = {
kind = "observational" ,
source = baselinePath ,
baseline = {
recordedAt = previous . recordedAt ,
hostProfile = previous . hostProfile ,
machineKey = previous . machineKey ,
benchmarks = previous . benchmarks ,
} ,
verdicts = json . asArray ( { } ) ,
}
document . comparisons [ # document . comparisons + 1 ] = comparison
local baselineByName = { }
for _ , entry in ipairs ( previous . benchmarks or { } ) do
baselineByName [ tostring ( entry . case ) .. "\0" .. tostring ( entry . name ) ] = entry
end
local sameMachine = previous . machineKey ~= nil and previous . machineKey == document . machineKey
local pending = { }
for _ , entry in ipairs ( merged ) do
local was = baselineByName [ tostring ( entry . case ) .. "\0" .. tostring ( entry . name ) ]
if not was then
notes [ # notes + 1 ] = entry . name .. ": no baseline for this benchmark"
else
local caseFailures , caseNotes = compare ( ( { schema = bench . SCHEMA , cases = { entry . summary , } , executionProfile = entry . executionProfile , remarks = entry . remarks , allocationSites = entry . allocationSites , traceProfile = entry . traceProfile , compiler = entry . compiler , } ) , ( { schema = bench . SCHEMA , cases = { was . summary , } , executionProfile = was . executionProfile , remarks = was . remarks , allocationSites = was . allocationSites , traceProfile = was . traceProfile , compiler = was . compiler , } ) )
for _ , item in ipairs ( caseFailures ) do
regressions [ # regressions + 1 ] = entry . name .. ": " .. item
end
for _ , item in ipairs ( caseNotes ) do
notes [ # notes + 1 ] = entry . name .. ": " .. item
end
if margin and sameMachine then
local current = entry . summary . forkSummariesMs or { }
local before = was . summary and was . summary . forkSummariesMs or { }
local change , interval , pValue = durationChange ( current , before , false )
local withheld = entry . summary . intervalWithheld
if withheld then
interval = nil
end
pending [
# pending + 1
] = {
case = entry . case ,
name = entry . name ,
change = change ,
interval = interval ,
pValue = pValue ,
withheld = withheld ,
}
end
end
end
if margin and not sameMachine then
notes [
# notes + 1
] = "durations not compared: the baseline was recorded on another machine, so nothing controls for the difference"
end
if # pending > 0 then
local pValues = { }
for _ , item in ipairs ( pending ) do
pValues [ # pValues + 1 ] = item . pValue
end
local adjusted = statistics . benjaminiHochberg ( pValues )
for index , item in ipairs ( pending ) do
item . adjusted = adjusted [ index ]
item . verdict = statistics . verdict ( item . interval , margin or 0 , adjusted [ index ] )
comparison . verdicts [ # comparison . verdicts + 1 ] = item
end
end
end



document . gpuCostsDirectory = gpuCostsDirectory
local encoded = json . encode ( document )
if not writeFile ( "build/bench-record.json" , encoded ) then
executionFailures [ # executionFailures + 1 ] = "cannot write build/bench-record.json"
end
if historyPath and # executionFailures == 0 and not appendFile ( historyPath , encoded .. "\n" ) then
executionFailures [ # executionFailures + 1 ] = "cannot append " .. historyPath
end


local function finish ( code ) 
if not asJson then
return code
end
local problems = { }
for _ , failure in ipairs ( executionFailures ) do
problems [ # problems + 1 ] = problem ( "NUPP0004" , failure )
end
if not accept then
for _ , regression in ipairs ( regressions ) do
problems [ # problems + 1 ] = problem ( "NUPP0004" , regression )
end
end
if code ~= 0 and # problems == 0 then
problems [ # problems + 1 ] = problem ( "NUPP0004" , "the run failed" )
end

return writeRunDocument ( document , code , problems )
end

if not asJson then
local cases = { }
for _ , entry in ipairs ( merged ) do
cases [ # cases + 1 ] = entry . summary
end
io . stdout : write ( format ( { cases = cases , } , { geometricMean = options . geo == true , forks = forks , } ) )
for _ , comparison in ipairs ( document . comparisons ) do
if # comparison . verdicts > 0 then
io . stdout : write (
formatVerdicts (
comparison . verdicts ,
margin or 0 ,
comparison . source ,
comparison . kind == "interleaved"
)
)
end
end
end
for _ , note in ipairs ( notes ) do
io . stderr : write ( "nupp: " .. note .. "\n" )
end
for _ , failure in ipairs ( executionFailures ) do
io . stderr : write ( "nupp: " .. failure .. "\n" )
end
for _ , regression in ipairs ( regressions ) do
io . stderr : write ( "nupp: " .. ( accept and "accepted: " or "" ) .. regression .. "\n" )
end
if baselinePath and accept then
if # executionFailures > 0 then
io . stderr : write ( "nupp: baseline not written because a benchmark failed\n" )

return finish ( 1 )
end
if not writeFile ( baselinePath , encoded ) then
io . stderr : write ( "nupp: cannot write " .. baselinePath .. "\n" )
executionFailures [ # executionFailures + 1 ] = "cannot write " .. baselinePath

return finish ( 1 )
end
io . stderr : write ( "nupp: baseline written to " .. baselinePath .. "\n" )

return finish ( 0 )
end
if accept and not baselinePath then
io . stderr : write ( "nupp: --accept needs --baseline PATH to write\n" )
executionFailures [ # executionFailures + 1 ] = "--accept needs --baseline PATH to write"

return finish ( 1 )
end




return finish ( ( # executionFailures > 0 or # regressions > 0 ) and 1 or 0 )
end





runner . mergeForks = mergeForks

local __nuppExportValue= runner ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.benchrunner"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.benchrunner"]=__nuppExports;return __nuppExports