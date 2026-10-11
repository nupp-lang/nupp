_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppT8={}; local function __nuppT5(...) return {n=select("#",...),...} end; local __nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT6(value) return value end; local function __nuppT7(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT14({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT15(v.primary) for _,reason in __nuppT16(v.suppressed) do text=text.."\ncleanup: "..__nuppT15(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT56 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.bench\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.bench\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.bench\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.bench\0runtime\0004") };































local json = require ( "nupp.codec.json" )
local profile = require ( "nupp.profile" )
local statistics = require ( "nupp.bench.internal.statistics" )
local time = require ( "nupp.time" )

local bench = __nuppNew(0,3)













bench . SCHEMA = 4


bench . OLDEST_BASELINE_SCHEMA = 2



local ROUNDS = 7



local TARGET_ROUND_MS = 50


local MAX_N = 1073741824







bench . __nuppSink = nil













function bench . keep ( value ) 
bench . __nuppSink = value
end






bench.Case = {} bench.Case.__index = bench.Case ;_G.nupp.__reflect.link(bench.Case,__nuppT1[1],{ })









bench.Invocation = {} bench.Invocation.__index = bench.Invocation ;_G.nupp.__reflect.link(bench.Invocation,__nuppT1[2],{ })






































































bench.Measurement = {} bench.Measurement.__index = bench.Measurement ;_G.nupp.__reflect.link(bench.Measurement,__nuppT1[3],{ })











































































































































































local measurements = { }
local traceProfileSeen = nil






local jobs = { }
local selectedDeclarations = 0
local declaredNames = { }



local reported = false





local options = {
out = "build/bench-record.json" ,
baseline = nil ,
json = false ,
accept = false ,
quiet = false ,




only = nil ,


list = false ,



casesOut = nil ,


iterations = nil ,



sampleOut = nil ,
sampleIntervalMs = 1 ,
sampleZone = nil ,
sampleRoot = nil ,
}

local function readOptions ( ) 
local argv = _G . arg
if not argv then
return
end
local index = 1
while argv [ index ] do
local entry = argv [ index ]
local name , value = entry : match ( "^%-%-([%w%-]+)=(.*)$" )
if not name then
name = entry : match ( "^%-%-([%w%-]+)$" )
end
if name == "list-cases" then
options . list = true
elseif name == "cases-out" then
options . casesOut = value or argv [ index + 1 ]
if not value then
index = ( index + 1 )
end
elseif name == "case" then
options . only = value or argv [ index + 1 ]
if not value then
index = ( index + 1 )
end
elseif name == "json" then
options . json = true
elseif name == "quiet" then
options . quiet = true
elseif name == "accept" then
options . accept = true
elseif name == "out" then
options . out = value or argv [ index + 1 ] or options . out
if not value then
index = ( index + 1 )
end
elseif name == "baseline" then
options . baseline = value or argv [ index + 1 ]
if not value then
index = ( index + 1 )
end
elseif name == "n" then
local given = tonumber ( value or argv [ index + 1 ] )
if not value then
index = ( index + 1 )
end
if not given or given < 1 or given ~= math . floor ( given ) then
error ( "nupp: --n needs a positive whole number" , 0 )
end
options . iterations = math . floor ( given )
elseif name == "sample-out" then
options . sampleOut = value or argv [ index + 1 ]
if not value then
index = ( index + 1 )
end
elseif name == "sample-interval-ms" then
local given = tonumber ( value or argv [ index + 1 ] )
if not value then
index = ( index + 1 )
end
if not given or given < 1 or given ~= math . floor ( given ) then
error ( "nupp: --sample-interval-ms needs a positive whole number" , 0 )
end
options . sampleIntervalMs = math . floor ( given )
elseif name == "sample-zone" then
options . sampleZone = value or argv [ index + 1 ]
if not value then
index = ( index + 1 )
end
elseif name == "sample-root" then
options . sampleRoot = value or argv [ index + 1 ]
if not value then
index = ( index + 1 )
end
end
index = ( index + 1 )
end
end

readOptions ( )





local function readFile ( path ) 
do const  __nuppT23= io . open ( path , "r" ) ; local __nuppT24=__nuppT8[1]; if not __nuppT24 then __nuppT24=function(handle) do
if not handle then
return "return",__nuppT5( nil )
end
local content = handle : read ( "*a" )
handle : close ( )

return "return",__nuppT5( content ) end; return "normal" end; __nuppT8[1]=__nuppT24 end; const __nuppT18,__nuppT19,__nuppT20=__nuppT10(__nuppT24,__nuppT6,__nuppT23); const __nuppT17=1; local __nuppT21={}; local __nuppT22=0; if __nuppT17>=1 and __nuppT23~=nil then  local __nuppT25,__nuppT26=__nuppT9(__nuppCleanup1,__nuppT23);  if not __nuppT25 then __nuppT22=__nuppT22+1; __nuppT21[__nuppT22]=__nuppT26 end; end; if not __nuppT18 then if __nuppT22>0 then __nuppT11(__nuppT7(__nuppT19,__nuppT21,1),0) else __nuppT11(__nuppT19,0) end end; if __nuppT22>0 then if __nuppT22>1 then __nuppT11(__nuppT7(__nuppT21[1],__nuppT21,2),0) else __nuppT11(__nuppT21[1],0) end end; if __nuppT19=="return" then  return __nuppT12(__nuppT20,1,__nuppT20.n)  end; end
end














function bench . decodeBaseline ( text , path , oldest ) 
local low = oldest or bench . OLDEST_BASELINE_SCHEMA
local decoded , document = pcall ( json . decode , text )
if not decoded or type ( document ) ~= "table" or json . isArray ( document ) then
return nil , ("nupp: baseline %s is not a bench record") : format ( path )
end
local schema = document . schema
if type ( schema ) ~= "number" or schema ~= math . floor ( schema ) or schema < low or schema > bench . SCHEMA then
return nil , ("nupp: baseline %s has schema %s; this bench reads schema %d, and %d through %d without durations")

: format ( path , schema == nil and "none" or tostring ( schema ) , bench . SCHEMA , low , bench . SCHEMA - 1 )
end

return document , nil
end


local baselineDocument = nil

local baselineRead = false

local function baseline ( ) 
if baselineRead then
return baselineDocument
end
baselineRead = true
if not options . baseline then
return nil
end
local text = readFile ( options . baseline )
if not text then
return nil
end
local document , refused = bench . decodeBaseline ( text , options . baseline )

if refused and not options . accept then
error ( refused , 0 )
end
baselineDocument = document

return baselineDocument
end






local function baselineIterations ( name ) 
local previous = baseline ( )
for _ , entry in ipairs ( previous and previous . cases or { } ) do
if entry . name == name and entry . kind == "case" then
return entry . n
end
end

return nil
end

local function median ( values ) 
local sorted = { }
for index = 1 , # values do
sorted [ index ] = values [ index ]
end
table . sort ( sorted )

return sorted [ math . ceil ( # sorted / 2 ) ]
end

local function smallest ( values ) 
local best = values [ 1 ]
for index = 2 , # values do
if values [ index ] < best then
best = values [ index ]
end
end

return best
end

local function quantile ( sorted , fraction ) 
if # sorted == 0 then
return 0
end
local rank = math . ceil ( fraction * # sorted )
if rank < 1 then
rank = 1
end
if rank > # sorted then
rank = # sorted
end

return sorted [ rank ]
end









local function calibrate ( name , body , fixed ) 
if fixed and fixed > 0 then
return fixed
end
local n = 1
local held = false
while n < MAX_N do




local started = time . now ( )
body ( _G.setmetatable({ name =  name ,  n =  n }, bench.Case) )
if time . now ( ) - started >= 50 then
if held then
return n
end
held = true
else
held = false
n = ( n * 2 )
end
end

return n
end

local function abortIdentities ( report ) 
local sites = { }
for _ , site in ipairs ( report . sites ) do
sites [
# sites + 1
] = ("%s|%s|%s|%s")

: format (
tostring ( site . severity ) ,
tostring ( site . reason ) ,
tostring ( site . location or "" ) ,
tostring ( site . zone or "" )
)
end
table . sort ( sites )

return sites , report . totalAborts , report . blacklisted
end









local function announce ( listing ) local __nuppT35;
if options . casesOut then
do const  __nuppT42= io . open ( options . casesOut , "a" ) ; __nuppT35=__nuppT35 or {} ; local __nuppT43=__nuppT35[2]; if not __nuppT43 then __nuppT43=function(handle) do
if not handle then
error ( "nupp: cannot write " .. options . casesOut , 0 )
end
handle : write ( json . encode ( listing ) , "\n" )
handle : close ( )

return "return",__nuppT5( ) end; return "normal" end; __nuppT35[2]=__nuppT43 end; const __nuppT37,__nuppT38,__nuppT39=__nuppT10(__nuppT43,__nuppT6,__nuppT42); const __nuppT36=1; local __nuppT40={}; local __nuppT41=0; if __nuppT36>=1 and __nuppT42~=nil then  local __nuppT44,__nuppT45=__nuppT9(__nuppCleanup1,__nuppT42);  if not __nuppT44 then __nuppT41=__nuppT41+1; __nuppT40[__nuppT41]=__nuppT45 end; end; if not __nuppT37 then if __nuppT41>0 then __nuppT11(__nuppT7(__nuppT38,__nuppT40,1),0) else __nuppT11(__nuppT38,0) end end; if __nuppT41>0 then if __nuppT41>1 then __nuppT11(__nuppT7(__nuppT40[1],__nuppT40,2),0) else __nuppT11(__nuppT40[1],0) end end; if __nuppT38=="return" then  return __nuppT12(__nuppT39,1,__nuppT39.n)  end; end
end
io . stdout : write ( listing . name , "\n" )
end








local function openTrace ( ) 
do local __nuppT47=0; local  __nuppT53 ; local __nuppT54=false ; local __nuppT48,__nuppT49,__nuppT50=__nuppT10(function() do local __nuppT55=__nuppT5( pcall ( profile . trace ) );  local  ok , session = __nuppT55[1] , __nuppT55[2] ; __nuppT53= __nuppT55[2] ; __nuppT47=1;  __nuppT54=true;  __nuppT54=(ok==true);
if not ok then
return "return",__nuppT5( nil )
end



return "return",__nuppT5( (function() __nuppT54=false; return  session  end)() ) end; return "normal" end,__nuppT6); local __nuppT51={}; local __nuppT52=0; if __nuppT47>=1 and __nuppT54 then  local __nuppT57,__nuppT58=__nuppT9(__nuppT56,__nuppT53);  if not __nuppT57 then __nuppT52=__nuppT52+1; __nuppT51[__nuppT52]=__nuppT58 end; end; if not __nuppT48 then if __nuppT52>0 then __nuppT11(__nuppT7(__nuppT49,__nuppT51,1),0) else __nuppT11(__nuppT49,0) end end; if __nuppT52>0 then if __nuppT52>1 then __nuppT11(__nuppT7(__nuppT51[1],__nuppT51,2),0) else __nuppT11(__nuppT51[1],0) end end; if __nuppT49=="return" then  return __nuppT12(__nuppT50,1,__nuppT50.n)  end; end
end



local function openSample ( ) 
if not options . sampleOut then
return nil
end
local argv = _G . arg
local root = options . sampleRoot or ( argv and argv [ 0 ] and argv [ 0 ] : match ( "([^/\\]+)$" ) or nil )
do local __nuppT60=0; local  __nuppT66 ; local __nuppT67=false ; local __nuppT61,__nuppT62,__nuppT63=__nuppT10(function() do local __nuppT68= profile . sample ( { intervalMs = options . sampleIntervalMs , zone = options . sampleZone , root = root , } ) ; __nuppT66= __nuppT68 ; __nuppT60=1;  __nuppT67=true;  local session=__nuppT66;
session : pause ( )

return "return",__nuppT5( (function() __nuppT67=false; return  session  end)() ) end; return "normal" end,__nuppT6); local __nuppT64={}; local __nuppT65=0; if __nuppT60>=1 and __nuppT67 then  local __nuppT69,__nuppT70=__nuppT9(__nuppT56,__nuppT66);  if not __nuppT69 then __nuppT65=__nuppT65+1; __nuppT64[__nuppT65]=__nuppT70 end; end; if not __nuppT61 then if __nuppT65>0 then __nuppT11(__nuppT7(__nuppT62,__nuppT64,1),0) else __nuppT11(__nuppT62,0) end end; if __nuppT65>0 then if __nuppT65>1 then __nuppT11(__nuppT7(__nuppT64[1],__nuppT64,2),0) else __nuppT11(__nuppT64[1],0) end end; if __nuppT62=="return" then  return __nuppT12(__nuppT63,1,__nuppT63.n)  end; end
end




local function announceRun ( name ) 
if options . json or options . quiet then
return
end
io . stdout : write ( "# Benchmark: " , name , "\n" )
io . stdout : flush ( )
end

local function register ( name , run , listing ) 
if name == "" then
error ( "nupp: a benchmark name cannot be empty" , 3 )
end
if declaredNames [ name ] then
error ( "nupp: duplicate benchmark " .. name , 3 )
end
declaredNames [ name ] = true
local declared = listing or { name = name }
if options . list then
announce ( declared )

return
end
if options . only and options . only ~= name then
return
end
selectedDeclarations = ( selectedDeclarations + 1 )
jobs [ # jobs + 1 ] = { name = name , run = run , }
end

local function measureCase ( name , body , fixedN ) 
announceRun ( name )





local session = openTrace ( )
local n = calibrate ( name , body , fixedN or options . iterations or baselineIterations ( name ) )
local subject = _G.setmetatable({ name =  name ,  n =  n }, bench.Case)
body ( subject )

collectgarbage ( "collect" )
local before = collectgarbage ( "count" )
collectgarbage ( "stop" )
local times = { }
for round = 1 , 7 do
local started = time . now ( )
body ( subject )
times [ round ] = time . now ( ) - started
end


local allocated = collectgarbage ( "count" ) - before
collectgarbage ( "restart" )
collectgarbage ( "collect" )
local retained = math . max ( 0 , collectgarbage ( "count" ) - before )

local sites = nil
local total = nil
local blacklisted = nil
if session then
local aborts = session : stop ( )
traceProfileSeen = aborts . traceProfile
sites , total , blacklisted = abortIdentities ( aborts )
end
local sampling = openSample ( )
if sampling then
collectgarbage ( "collect" )
for _ = 1 , 7 do
sampling : resume ( )
body ( subject )
sampling : pause ( )
end
sampling : stop ( options . sampleOut )
end




local rounds = statistics . trend ( times )
local far = statistics . outliers ( times )
local roundOrder = statistics . sorted ( times )
measurements [
# measurements + 1
] = _G.setmetatable({ name =
name ,  kind =
"case" ,  n =
n ,  rounds =
ROUNDS ,  medianMs =
median ( times ) ,  minMs =
smallest ( times ) ,  samplesMs =
times ,  p25Ms =
statistics . quantile ( roundOrder , 0.25 ) ,  p75Ms =
statistics . quantile ( roundOrder , 0.75 ) ,  p99Ms =
statistics . quantile ( roundOrder , 0.99 ) ,  iqrMs =
statistics . iqr ( times ) ,  trend =
rounds . verdict ,  trendTau =
rounds . tau ,  trendPValue =
rounds . pValue ,  trendDrift =
rounds . drift ,  concentration =
statistics . concentration ( times , statistics . CONCENTRATION_TOLERANCE ) ,  outlierCount =
far . severe ,  outlierMaxRatio =
far . maxRatio ,  allocatedKb =
allocated / ROUNDS ,  retainedKb =
retained ,  abortSites =
sites ,  totalAborts =
total ,  blacklisted =
blacklisted ,  profilePath =
options . sampleOut }, bench.Measurement)

end











function bench . case ( name , body , fixedN ) 
register ( name , function ( ) 
measureCase ( name , body , fixedN )
end )
end





local function positiveInteger ( value , fallback , name ) 
local answer = value or fallback
if answer < 1 or answer ~= math . floor ( answer ) then
error ( "nupp: " .. name .. " needs a positive whole number" , 3 )
end

return answer
end

local function positiveNumber ( value , fallback , name ) 
local answer = value or fallback
if answer <= 0 then
error ( "nupp: " .. name .. " needs a positive number" , 3 )
end

return answer
end

local function expandedParameters ( source ) 
if not source then
return { { } }
end
local keys = { }
for key in pairs ( source ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
local expanded = { }
local current = { }
local visit
visit = function ( index ) 
if index > # keys then
local copy = { }
for key , value in pairs ( current ) do
copy [ key ] = value
end
expanded [ # expanded + 1 ] = copy

return
end
local key = keys [ index ]
local values = source [ key ]
if not values then
error ( "nupp: parameter " .. key .. " disappeared" , 3 )
end
if # values == 0 then
error ( "nupp: parameter " .. key .. " has no values" , 3 )
end
for _ , value in ipairs ( values ) do
current [ key ] = value
visit ( ( index + 1 ) )
end
current [ key ] = nil
end
visit ( 1 )

return expanded
end

local function suiteName ( suite , caseName , variant , parameters ) 
local keys = { }
for key in pairs ( parameters ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
local suffix = { }
for _ , key in ipairs ( keys ) do
suffix [ # suffix + 1 ] = key .. "=" .. tostring ( parameters [ key ] )
end
local name = suite .. "." .. caseName .. "." .. variant
if # suffix > 0 then
name = name .. ":" .. table . concat ( suffix , "," )
end

return name
end

local function callVariant (
variant ,
invocation ,
iterations ,
session
) 
local state = nil
if variant . setup then
state = variant . setup ( invocation )
end
if session then
session : resume ( )
end
local started = time . now ( )
local result = nil
for _ = 1 , iterations do
result = variant . run ( state , invocation )
end
local elapsed = time . now ( ) - started
if session then
session : pause ( )
end
bench . keep ( result )
if variant . teardown then
variant . teardown ( state , invocation )
end

return elapsed
end

local function sampleStatistics ( samples ) 
local sorted = { }
local total = 0
for index = 1 , # samples do
local value = samples [ index ]
sorted [ index ] = value
total = total + value
end
table . sort ( sorted )
local mean = total / # sorted
local squared = 0
for _ , value in ipairs ( sorted ) do
local delta = value - mean
squared = squared + delta * delta
end
local stdev = # sorted > 1 and math . sqrt ( squared / ( # sorted - 1 ) ) or 0

return smallest ( sorted ) , mean , stdev , quantile ( sorted , 0.5 ) , quantile ( sorted , 0.9 ) , quantile ( sorted , 0.99 )
end

local function measureSuite (
suite ,
case ,
variant ,
parameters ,
name
) 
local warmups = positiveInteger ( suite . warmupIterations , 10 , "warmupIterations" )
local iterations = positiveInteger ( suite . sampleIterations , 1 , "sampleIterations" )
local minSamples = positiveInteger ( suite . minSamples , 15 , "minSamples" )
local maxSamples = positiveInteger ( suite . maxSamples , 100000 , "maxSamples" )
local minDuration = positiveNumber ( suite . minDurationMs , 500 , "minDurationMs" )
local maxDuration = positiveNumber ( suite . maxDurationMs , 10000 , "maxDurationMs" )
local operations = positiveInteger ( case . operations , 1 , "case operations" )
if maxSamples < minSamples then
error ( "nupp: maxSamples must be at least minSamples" , 0 )
end
if maxDuration < minDuration then
error ( "nupp: maxDurationMs must be at least minDurationMs" , 0 )
end

announceRun ( name )
collectgarbage ( "collect" )
local session = openTrace ( )
if session then
session : pause ( )
end
for _ = 1 , warmups do
callVariant (
variant ,
_G.setmetatable({ name =  case . name ,  data =  case . data ,  parameters =  parameters }, bench.Invocation) ,
iterations ,
session
)
end

local invocation = _G.setmetatable({ name =  case . name ,  data =  case . data ,  parameters =  parameters }, bench.Invocation)
local samples = { }
local measured = 0
local wallStarted = time . now ( )
while # samples < minSamples or measured < minDuration do
if # samples >= maxSamples or time . now ( ) - wallStarted >= maxDuration then
do break end
end
local elapsed = callVariant ( variant , invocation , iterations , session )
measured = measured + elapsed
samples [ # samples + 1 ] = elapsed / ( iterations * operations )
end
if # samples < minSamples or measured < minDuration then
error (
("nupp: %s reached its sampling limit after %d samples and %.3f ms measured; increase sampleIterations or the maximums")

: format ( name , # samples , measured ) ,
0
)
end




local function primeProtectedCall ( ) 
end

pcall ( primeProtectedCall )
local state = nil
if variant . setup then
state = variant . setup ( invocation )
end

local function allocationPass ( ) 
local last = nil
for _ = 1 , iterations do
last = variant . run ( state , invocation )
end

return last
end

collectgarbage ( "collect" )
local before = collectgarbage ( "count" )
collectgarbage ( "stop" )
local ok , result = pcall ( allocationPass )
local allocated = collectgarbage ( "count" ) - before
collectgarbage ( "restart" )
if not ok then
error ( result , 0 )
end
bench . keep ( result )
if variant . teardown then
variant . teardown ( state , invocation )
end
collectgarbage ( "collect" )
local retained = math . max ( 0 , collectgarbage ( "count" ) - before )

local sites = nil
local totalAborts = nil
local blacklisted = nil
if session then
local aborts = session : stop ( )
traceProfileSeen = aborts . traceProfile
sites , totalAborts , blacklisted = abortIdentities ( aborts )
end
local sampling = openSample ( )
if sampling then
collectgarbage ( "collect" )
for _ = 1 , # samples do
callVariant ( variant , invocation , iterations , sampling )
end
sampling : stop ( options . sampleOut )
end
local minimum , mean , stdev , p50 , p90 , p99 = sampleStatistics ( samples )



local drift = statistics . trend ( samples )
local far = statistics . outliers ( samples )
local sampleOrder = statistics . sorted ( samples )
measurements [
# measurements + 1
] = _G.setmetatable({ name =
name ,  kind =
"suite" ,  rounds =
# samples ,  medianMs =
p50 ,  minMs =
minimum ,  samplesMs =
samples ,  meanMs =
mean ,  stdevMs =
stdev ,  p90Ms =
p90 ,  p99Ms =
p99 ,  p25Ms =
statistics . quantile ( sampleOrder , 0.25 ) ,  p75Ms =
statistics . quantile ( sampleOrder , 0.75 ) ,  iqrMs =
statistics . iqr ( samples ) ,  trend =
drift . verdict ,  trendTau =
drift . tau ,  trendPValue =
drift . pValue ,  trendDrift =
drift . drift ,  concentration =
statistics . concentration ( samples , statistics . CONCENTRATION_TOLERANCE ) ,  outlierCount =
far . severe ,  outlierMaxRatio =
far . maxRatio ,  sampleIterations =
iterations ,  operationsPerInvocation =
operations ,  warmupIterations =
warmups ,  minSamples =
minSamples ,  minDurationMs =
minDuration ,  maxSamples =
maxSamples ,  maxDurationMs =
maxDuration ,  suite =
suite . name ,  variant =
variant . name ,  caseName =
case . name ,  parameters =
parameters ,  baselineVariant =
suite . baselineVariant or suite . variants [ 1 ] . name ,  allocatedKb =
allocated / ( iterations * operations ) ,  retainedKb =
retained ,  abortSites =
sites ,  totalAborts =
totalAborts ,  blacklisted =
blacklisted ,  profilePath =
options . sampleOut }, bench.Measurement)

end

local function registerSuite (
options ,
case ,
variant ,
parameters
) 
local name = suiteName ( options . name , case . name , variant . name , parameters )
register (
name ,
function ( ) 
measureSuite ( options , case , variant , parameters , name )
end ,
{ name = name , suite = options . name , caseName = case . name , variant = variant . name , parameters = parameters , }
)
end





function bench . suite ( options ) 
if # options . variants == 0 then
error ( "nupp: a suite needs at least one variant" , 2 )
end
if # options . cases == 0 then
error ( "nupp: a suite needs at least one case" , 2 )
end
local variants = { }
for _ , variant in ipairs ( options . variants ) do
if variants [ variant . name ] then
error ( "nupp: duplicate variant " .. variant . name , 2 )
end
variants [ variant . name ] = true
end
local baselineVariant = options . baselineVariant or options . variants [ 1 ] . name
if not variants [ baselineVariant ] then
error ( "nupp: baselineVariant does not name a variant" , 2 )
end
local cases = { }
for _ , case in ipairs ( options . cases ) do
if cases [ case . name ] then
error ( "nupp: duplicate suite case " .. case . name , 2 )
end
cases [ case . name ] = true
for _ , parameters in ipairs ( expandedParameters ( case . parameters ) ) do
for _ , variant in ipairs ( options . variants ) do
registerSuite ( options , case , variant , parameters )
end
end
end
end












bench.FrameSession = {} bench.FrameSession.__index = bench.FrameSession ;_G.nupp.__reflect.link(bench.FrameSession,__nuppT1[4],{ })






















function bench . frames ( name , budgetMs , count ) 




if name == "" then
error ( "nupp: a benchmark name cannot be empty" , 2 )
end
if declaredNames [ name ] then
error ( "nupp: duplicate benchmark " .. name , 2 )
end
declaredNames [ name ] = true
if options . list then
announce ( { name = name } )
end
local inert = options . list or ( options . only ~= nil and options . only ~= name )
if inert then
return ( _G.setmetatable({ name =
name ,  budgetMs =
budgetMs or 0.0 ,  wanted =
count or 0 ,  samples =
{ } ,  started =
0.0 ,  session =
nil ,  sampling =
nil ,  done =
true }, bench.FrameSession) )

end

selectedDeclarations = ( selectedDeclarations + 1 )
announceRun ( name )

return ( _G.setmetatable({ name =
name ,  budgetMs =
budgetMs or 0.0 ,  wanted =
count or 0 ,  samples =
{ } ,  started =
0.0 ,  session =
openTrace ( ) ,  sampling =
openSample ( ) ,  done =
false }, bench.FrameSession) )

end



function bench . FrameSession : more ( ) 
if self . done then
return false
end
if self . wanted <= 0 then
return true
end

return # self . samples < self . wanted
end


function bench . FrameSession : begin ( ) 
if self . sampling then
self . sampling : resume ( )
end
self . started = time . now ( )
end






function bench . FrameSession : finish ( ) 
local finished = time . now ( )
if self . sampling then
self . sampling : pause ( )
end
self . samples [ # self . samples + 1 ] = finished - self . started
end











function bench . FrameSession : report ( ) 
if self . done then
return
end
self . done = true
local sites = nil
local total = nil
local blacklisted = nil
if self . session then
local aborts = self . session : stop ( )
traceProfileSeen = aborts . traceProfile
sites , total , blacklisted = abortIdentities ( aborts )
end
if self . sampling then
self . sampling : stop ( options . sampleOut )
end
local sorted = { }
for index = 1 , # self . samples do
sorted [ index ] = self . samples [ index ]
end
table . sort ( sorted )
local over = 0
if self . budgetMs > 0 then
for index = 1 , # sorted do
if sorted [ index ] > self . budgetMs then
over = ( over + 1 )
end
end
end

measurements [
# measurements + 1
] = _G.setmetatable({ name =
self . name ,  kind =
"frames" ,  p50Ms =
quantile ( sorted , 0.5 ) ,  p99Ms =
quantile ( sorted , 0.99 ) ,  p999Ms =
quantile ( sorted , 0.999 ) ,  frames =
# sorted ,  overBudget =
over ,  abortSites =
sites ,  totalAborts =
total ,  blacklisted =
blacklisted ,  profilePath =
options . sampleOut }, bench.Measurement)

bench . report ( )
end












local function readRemarks ( ) 
local path = _G . __nuppRemarksOut
if type ( path ) ~= "string" then
return nil
end
local content = readFile ( path )
if not content then
return nil
end
local decoded = json . decode ( content )

return decoded
end

local function writeFile ( path , content ) local __nuppT95;
do const  __nuppT102= io . open ( path , "w" ) ; __nuppT95=__nuppT95 or {} ; local __nuppT103=__nuppT95[3]; if not __nuppT103 then __nuppT103=function(handle) do
if not handle then
error ( "nupp: cannot write " .. path , 0 )
end
handle : write ( content )
handle : close ( ) end; return "normal" end; __nuppT95[3]=__nuppT103 end; const __nuppT97,__nuppT98,__nuppT99=__nuppT10(__nuppT103,__nuppT6,__nuppT102); const __nuppT96=1; local __nuppT100={}; local __nuppT101=0; if __nuppT96>=1 and __nuppT102~=nil then  local __nuppT104,__nuppT105=__nuppT9(__nuppCleanup1,__nuppT102);  if not __nuppT104 then __nuppT101=__nuppT101+1; __nuppT100[__nuppT101]=__nuppT105 end; end; if not __nuppT97 then if __nuppT101>0 then __nuppT11(__nuppT7(__nuppT98,__nuppT100,1),0) else __nuppT11(__nuppT98,0) end end; if __nuppT101>0 then if __nuppT101>1 then __nuppT11(__nuppT7(__nuppT100[1],__nuppT100,2),0) else __nuppT11(__nuppT100[1],0) end end; if __nuppT98=="return" then  return __nuppT12(__nuppT99,1,__nuppT99.n)  end; end
end

local function buildRecord ( ) 
local remarks = readRemarks ( )
local cases = { }
for index = 1 , # measurements do
cases [ index ] = measurements [ index ]
end

return {
schema = bench . SCHEMA ,
cases = cases ,
executionProfile = remarks and remarks . executionProfile or nil ,
remarks = remarks and remarks . remarks or nil ,
allocationSites = remarks and remarks . allocationSites or nil ,
traceProfile = traceProfileSeen ,
compiler = remarks and remarks . compiler or nil ,
}
end






local function sameExecution ( left , right ) 
if left == nil or right == nil then
return false
end
if left . optLevel ~= right . optLevel then
return false
end

return ( left . disabled or "" ) == ( right . disabled or "" )
end








local function sameRecorder ( left , right ) 
if left == nil or right == nil then
return false
end

return left . id == right . id
end









local function allocationCounts ( record ) 
local counts = { }
for _ , site in ipairs ( record . allocationSites or { } ) do
local key = tostring ( site . file ) .. "|" .. tostring ( site . kind )
counts [ key ] = ( ( counts [ key ] or 0 ) + 1 )
end

return counts
end


local function remarkIdentities ( record ) 
local entries = { }
for _ , entry in ipairs ( record . remarks or { } ) do
local at = entry . range and entry . range . start or nil
entries [
# entries + 1
] = ("%s|%s|%s|%s")

: format ( tostring ( entry . code ) , tostring ( entry . file ) , tostring ( at and at . line or 0 ) , tostring ( entry . message ) )
end
table . sort ( entries )

return entries
end

local function listDifference ( current , previous ) 
local seen = { }
for _ , entry in ipairs ( previous ) do
seen [ entry ] = true
end
local added = { }
for _ , entry in ipairs ( current ) do
if not seen [ entry ] then
added [ # added + 1 ] = entry
end
end

return added
end
















function bench . compare ( record , baseline ) 
local failures = { }
local uncompared = { }
if not sameExecution ( record . executionProfile , baseline . executionProfile ) then
uncompared [ # uncompared + 1 ] = "execution profile differs; nothing is comparable"

return failures , uncompared
end
local previous = { }
for _ , entry in ipairs ( baseline . cases or { } ) do
previous [ entry . name ] = entry
end


local currentAllocations = allocationCounts ( record )
local previousAllocations = allocationCounts ( baseline )
local allocationKeys = { }
for key in pairs ( currentAllocations ) do
allocationKeys [ # allocationKeys + 1 ] = key
end
table . sort ( allocationKeys )
for _ , key in ipairs ( allocationKeys ) do
local now = currentAllocations [ key ] or 0
local was = previousAllocations [ key ] or 0
if now > was then
failures [ # failures + 1 ] = ("allocations rose from %d to %d in %s") : format ( was , now , key )
end
end



local currentRemarks = remarkIdentities ( record )
local previousRemarks = remarkIdentities ( baseline )
for _ , entry in ipairs ( listDifference ( currentRemarks , previousRemarks ) ) do
uncompared [ # uncompared + 1 ] = "remark appeared: " .. entry
end
for _ , entry in ipairs ( listDifference ( previousRemarks , currentRemarks ) ) do
uncompared [ # uncompared + 1 ] = "remark went away: " .. entry
end
local recorderMatches = sameRecorder ( record . traceProfile , baseline . traceProfile )
for _ , entry in ipairs ( record . cases or { } ) do
local was = previous [ entry . name ]
if not was then
uncompared [ # uncompared + 1 ] = entry . name .. ": no baseline"
elseif not recorderMatches then
uncompared [ # uncompared + 1 ] = entry . name .. ": trace profile differs, abort sites not compared"
elseif entry . abortSites == nil or was . abortSites == nil then
uncompared [ # uncompared + 1 ] = entry . name .. ": trace aborts were not collected"
else
local added = listDifference ( entry . abortSites or { } , was . abortSites or { } )
for _ , site in ipairs ( added ) do
failures [ # failures + 1 ] = entry . name .. ": new trace abort site: " .. site
end
end
end

return failures , uncompared
end








function bench . format ( record , options ) 
local includeGeometricMean = options and options . geometricMean == true
local rows = { }
local width = 9
local baselines = { }
local hasRatios = false
local workloads = { }
local workloadsByKey = { }
local suites = { }
local suitesByName = { }

local function parameterText ( entry ) 
local keys = { }
for key in pairs ( entry . parameters or { } ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
local values = { }
for _ , key in ipairs ( keys ) do
values [ # values + 1 ] = key .. "=" .. tostring ( entry . parameters [ key ] )
end

return table . concat ( values , "," )
end

local function comparisonKey ( entry ) 
return tostring ( entry . suite ) .. "|" .. tostring ( entry . caseName ) .. "|" .. parameterText ( entry )
end

for _ , entry in ipairs ( record . cases or { } ) do
if entry . kind == "suite" then
hasRatios = true
local key = comparisonKey ( entry )
local workload = workloadsByKey [ key ]
if not workload then
local parameters = parameterText ( entry )
local label = tostring ( entry . suite ) .. "." .. tostring ( entry . caseName )
if parameters ~= "" then
label = label .. ":" .. parameters
end
workload = {
label = label ,
suite = entry . suite ,
caseName = entry . caseName ,
baselineVariant = entry . baselineVariant ,
values = { } ,
variants = { } ,
variantSeen = { } ,
}
workloadsByKey [ key ] = workload
workloads [ # workloads + 1 ] = workload
local suite = suitesByName [ entry . suite ]
if not suite then
suite = {
name = entry . suite ,
baselineVariant = entry . baselineVariant ,
workloads = { } ,
variants = { } ,
variantSeen = { } ,
}
suitesByName [ entry . suite ] = suite
suites [ # suites + 1 ] = suite
end
suite . workloads [ # suite . workloads + 1 ] = workload
end
if not workload . variantSeen [ entry . variant ] then
workload . variantSeen [ entry . variant ] = true
workload . variants [ # workload . variants + 1 ] = entry . variant
end
workload . values [ entry . variant ] = entry . medianMs or 0
local suite = suitesByName [ entry . suite ]
if suite and not suite . variantSeen [ entry . variant ] then
suite . variantSeen [ entry . variant ] = true
suite . variants [ # suite . variants + 1 ] = entry . variant
end
if entry . variant == entry . baselineVariant then
baselines [ key ] = entry . medianMs or 0
end
end
end







local function spreadCell ( entry , scale ) 
local lowerQuartile = entry . p25Ms
local tail = entry . p99Ms
if not lowerQuartile or not tail then
return "-"
end

return ("[%.3f, %.3f]") : format ( lowerQuartile * scale , tail * scale )
end


local function intervalCell ( entry , scale ) 
if entry . intervalWithheld == "trend-warning" then
return "unstable"
end
if not entry . intervalLowMs or not entry . intervalHighMs then
return "-"
end

return ("[%.3f, %.3f]") : format ( entry . intervalLowMs * scale , entry . intervalHighMs * scale )
end

local function coverageCell ( entry ) 
if not entry . intervalCoverage then
return "-"
end

return ("%.2f%%") : format ( entry . intervalCoverage * 100 )
end





local function allocationCell ( entry ) 
local allocated = entry . allocatedKb
if allocated == nil then
return "-"
end
if entry . kind == "case" then
local n = entry . n or 0
if n <= 0 then
return "-"
end
allocated = allocated / n
elseif entry . kind ~= "suite" then
return "-"
end

return ("%.3f") : format ( allocated * 1024 )
end

for _ , entry in ipairs ( record . cases or { } ) do
if entry . kind == "case" then
local n = entry . n or 0
local scale = n > 0 and ( 1000000 / n ) or 0
local score = ( entry . medianMs or 0 ) * scale
rows [
# rows + 1
] = {
name = entry . name ,
mode = "p50" ,
count = tostring ( entry . rounds or 0 ) ,
forkCount = tostring ( entry . forkCount or 1 ) ,
score = ("%.3f") : format ( score ) ,
units = "ns/op" ,
allocation = allocationCell ( entry ) ,
ratio = "-" ,
spread = spreadCell ( entry , scale ) ,
interval = intervalCell ( entry , scale ) ,
coverage = coverageCell ( entry ) ,
}
elseif entry . kind == "suite" then

local score = ( entry . medianMs or 0 ) * 1000000
local baselineScore = baselines [ comparisonKey ( entry ) ]
local ratio = "-"
if baselineScore and score > 0 then
ratio = ("%.3fx") : format ( baselineScore / ( entry . medianMs or 0 ) )
end
rows [
# rows + 1
] = {
name = entry . name ,
mode = "p50" ,
count = tostring ( entry . rounds or 0 ) ,
forkCount = tostring ( entry . forkCount or 1 ) ,
score = ("%.3f") : format ( score ) ,
units = "ns/op" ,
allocation = allocationCell ( entry ) ,
ratio = ratio ,
spread = spreadCell ( entry , 1000000 ) ,
interval = intervalCell ( entry , 1000000 ) ,
coverage = coverageCell ( entry ) ,
}
else
local count = tostring ( entry . frames or 0 )
rows [
# rows + 1
] = {
name = entry . name ,
mode = "p50" ,
count = count ,
forkCount = tostring ( entry . forkCount or 1 ) ,
score = ("%.3f") : format ( entry . p50Ms or 0 ) ,
units = "ms/frame" ,
allocation = "-" ,
ratio = "-" ,
spread = "-" ,
interval = "-" ,
coverage = "-" ,
}
rows [
# rows + 1
] = {
name = entry . name ,
mode = "p99" ,
count = count ,
forkCount = tostring ( entry . forkCount or 1 ) ,
score = ("%.3f") : format ( entry . p99Ms or 0 ) ,
units = "ms/frame" ,
allocation = "-" ,
ratio = "-" ,
spread = "-" ,
interval = "-" ,
coverage = "-" ,
}
rows [
# rows + 1
] = {
name = entry . name ,
mode = "p99.9" ,
count = count ,
forkCount = tostring ( entry . forkCount or 1 ) ,
score = ("%.3f") : format ( entry . p999Ms or 0 ) ,
units = "ms/frame" ,
allocation = "-" ,
ratio = "-" ,
spread = "-" ,
interval = "-" ,
coverage = "-" ,
}
if ( entry . overBudget or 0 ) > 0 then
rows [
# rows + 1
] = {
name = entry . name .. ":over-budget" ,
mode = "count" ,
count = count ,
forkCount = tostring ( entry . forkCount or 1 ) ,
score = tostring ( entry . overBudget ) ,
units = "frames" ,
allocation = "-" ,
ratio = "-" ,
spread = "-" ,
interval = "-" ,
coverage = "-" ,
}
end
end
end
if # rows == 0 then
return ""
end
for _ , row in ipairs ( rows ) do
if # row . name > width then
width = # row . name
end
end




local forks = options and options . forks or 1
local replicated = forks > 1
local spreadWidth = replicated and 20 or 18
local spreadHeading = replicated and "Interval" or "p25-p99"
for _ , row in ipairs ( rows ) do
local cell = ( replicated and row . interval or row . spread ) or "-"
if # cell > spreadWidth then
spreadWidth = # cell
end
end
local pattern = "%-" .. tostring ( width ) .. "s  %5s  %5s  %10s  %-8s  %12s  %" .. tostring ( spreadWidth ) .. "s"
local headings = {
"Benchmark" ,
"Mode" ,
replicated and "Forks" or "Cnt" ,
"Score" ,
"Units" ,
"Alloc B/op" ,
spreadHeading ,
}
if replicated then
pattern = pattern .. "  %9s"
headings [ # headings + 1 ] = "Coverage"
end
if hasRatios then
pattern = pattern .. "  %8s"
headings [ # headings + 1 ] = "Ratio"
end

local function emit ( cells ) 
if # cells == 7 then
return pattern : format ( cells [ 1 ] , cells [ 2 ] , cells [ 3 ] , cells [ 4 ] , cells [ 5 ] , cells [ 6 ] , cells [ 7 ] )
end
if # cells == 8 then
return pattern : format ( cells [ 1 ] , cells [ 2 ] , cells [ 3 ] , cells [ 4 ] , cells [ 5 ] , cells [ 6 ] , cells [ 7 ] , cells [ 8 ] )
end

return pattern : format ( cells [ 1 ] , cells [ 2 ] , cells [ 3 ] , cells [ 4 ] , cells [ 5 ] , cells [ 6 ] , cells [ 7 ] , cells [ 8 ] , cells [ 9 ] )
end

local lines = { emit ( headings ) , }
for _ , row in ipairs ( rows ) do
local cells = {
row . name ,
row . mode ,
( replicated and row . forkCount or row . count ) or "0" ,
row . score ,
row . units ,
row . allocation ,
( replicated and row . interval or row . spread ) or "-" ,
}
if replicated then
cells [ # cells + 1 ] = row . coverage or "-"
end
if hasRatios then
cells [ # cells + 1 ] = row . ratio
end
lines [ # lines + 1 ] = emit ( cells )
end

local winners = { }
local winnerWidth = 8
local variantWidth = 6
for _ , workload in ipairs ( workloads ) do
local winner = nil
local fastest = math . huge
local nextFastest = math . huge
local compared = 0
for _ , variant in ipairs ( workload . variants ) do
local score = workload . values [ variant ]
if score and score > 0 then
compared = ( compared + 1 )
if score < fastest then
nextFastest = fastest
fastest = score
winner = variant
elseif score < nextFastest then
nextFastest = score
end
end
end
if winner and compared > 1 then
winners [
# winners + 1
] = {
workload = workload . label ,
winner = winner ,
speedup = nextFastest < math . huge and nextFastest / fastest or 1 ,
}
winnerWidth = math . max ( winnerWidth , # workload . label )
variantWidth = math . max ( variantWidth , # winner )
end
end
if # winners > 0 then
lines [ # lines + 1 ] = ""
lines [ # lines + 1 ] = "Winners"
local winnerPattern = "%-" .. tostring ( winnerWidth ) .. "s  %-" .. tostring ( variantWidth ) .. "s  %8s"
lines [ # lines + 1 ] = winnerPattern : format ( "Workload" , "Winner" , "Speedup" )
for _ , winner in ipairs ( winners ) do
lines [ # lines + 1 ] = winnerPattern : format ( winner . workload , winner . winner , ("%.3fx") : format ( winner . speedup ) )
end
end

for _ , suite in ipairs ( includeGeometricMean and suites or { } ) do
local expected = 0
for _ , workload in ipairs ( suite . workloads ) do
local baselineScore = workload . values [ suite . baselineVariant ]
if baselineScore and baselineScore > 0 then
expected = ( expected + 1 )
end
end
local summary = { }
local summaryWidth = 7
for _ , variant in ipairs ( suite . variants ) do
local cases = { }
local caseOrder = { }
local compared = 0
for _ , workload in ipairs ( suite . workloads ) do
local baselineScore = workload . values [ suite . baselineVariant ]
local score = workload . values [ variant ]
if baselineScore and baselineScore > 0 and score and score > 0 then
local name = workload . caseName
local case = cases [ name ]
if not case then
case = { total = 0 , count = 0 }
cases [ name ] = case
caseOrder [ # caseOrder + 1 ] = name
end
case . total = case . total + math . log ( baselineScore / score )
case . count = ( case . count + 1 )
compared = ( compared + 1 )
end
end
if expected > 0 and compared == expected then
local total = 0
for _ , name in ipairs ( caseOrder ) do
local case = cases [ name ]
total = total + case . total / case . count
end
summary [ # summary + 1 ] = { variant = variant , ratio = math . exp ( total / # caseOrder ) , }
summaryWidth = math . max ( summaryWidth , # variant )
end
end
if # summary > 1 then
lines [ # lines + 1 ] = ""
lines [
# lines + 1
] = "Geometric mean: " .. tostring ( suite . name ) .. " (vs " .. tostring ( suite . baselineVariant ) .. ")"
local summaryPattern = "%-" .. tostring ( summaryWidth ) .. "s  %8s"
lines [ # lines + 1 ] = summaryPattern : format ( "Variant" , "Ratio" )
for _ , entry in ipairs ( summary ) do
lines [ # lines + 1 ] = summaryPattern : format ( entry . variant , ("%.3fx") : format ( entry . ratio ) )
end
end
end





if not replicated then
lines [ # lines + 1 ] = ""
lines [ # lines + 1 ] = "note: 1 fork per benchmark. p25-p99 is within-process spread, NOT a confidence"
lines [ # lines + 1 ] = "      interval: samples inside one process share its heap, traces and thermal"
lines [ # lines + 1 ] = "      state, so no population interval follows from them. A score far from the"
lines [ # lines + 1 ] = "      middle of that range means the samples are not centered on it. No interval or"
lines [
# lines + 1
] = ("      verdict is available below %d forks; run --pilot to size a replicated run.")

: format ( statistics . MIN_INTERVAL_SAMPLES )
end
for _ , note in ipairs ( options and options . notes or { } ) do
lines [ # lines + 1 ] = note
end

return "\n" .. table . concat ( lines , "\n" ) .. "\n"
end













function bench . report ( ) 
if options . list then
return
end
if reported then
return
end
if options . only and selectedDeclarations == 0 then
error ( "nupp: no benchmark named " .. options . only , 0 )
end
if not options . only and # jobs > 1 then
error ( "nupp: this program defines more than one benchmark; use --case NAME or nupp bench" , 0 )
end
reported = true
local pending = jobs
jobs = { }
for _ , job in ipairs ( pending ) do
job . run ( )
end
local record = buildRecord ( )
local encoded = json . encode ( record )
writeFile ( options . out , encoded )
if options . json then
io . stdout : write ( encoded , "\n" )
elseif not options . quiet then
io . stdout : write ( bench . format ( record ) )
end
if not options . baseline then
return
end
local baselineText = readFile ( options . baseline )
if not baselineText then
if options . accept then
writeFile ( options . baseline , encoded )

return
end
io . stderr : write ( "nupp: no baseline at " .. options . baseline .. "\n" )

return
end
local previous , refused = bench . decodeBaseline ( baselineText , options . baseline )
if refused then
if options . accept then
io . stderr : write ( refused , "; replacing it\n" )
writeFile ( options . baseline , encoded )

return
end
error ( refused , 0 )
end
local failures , uncompared = bench . compare ( record , previous )
for _ , note in ipairs ( uncompared ) do
io . stderr : write ( "nupp: uncompared: " .. note .. "\n" )
end
if options . accept then
writeFile ( options . baseline , encoded )

return
end
if # failures > 0 then
error ( "nupp: " .. table . concat ( failures , "\nnupp: " ) , 0 )
end
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench"]=__nuppExports;return __nuppExports