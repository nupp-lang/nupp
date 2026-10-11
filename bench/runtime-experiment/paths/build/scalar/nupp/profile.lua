_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT6={}; local function __nuppT3(...) return {n=select("#",...),...} end; local __nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT4(value) return value end; local function __nuppT5(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT12({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT13(v.primary) for _,reason in __nuppT14(v.suppressed) do text=text.."\ncleanup: "..__nuppT13(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT45 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.profile\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.profile\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.profile\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.profile\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.profile\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.profile\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.profile\0runtime\0007") };










































local zone = require ( "nupp.profile.zone" )
local jitProfile = require ( "jit.profile" )
local jitUtil = require ( "jit.util" )
local traceRegistry = require ( "nupp.profile.trace" )

local profile = { }













































































profile.Sample = {} profile.Sample.__index = profile.Sample ;_G.nupp.__reflect.link(profile.Sample,__nuppT1[1],{ })




































profile.SampleReport = {} profile.SampleReport.__index = profile.SampleReport ;_G.nupp.__reflect.link(profile.SampleReport,__nuppT1[2],{ })

























profile.SampleSession = {} profile.SampleSession.__index = profile.SampleSession ;_G.nupp.__reflect.link(profile.SampleSession,__nuppT1[3],{ __nuppT1[1] })


































profile.AbortSite = {} profile.AbortSite.__index = profile.AbortSite ;_G.nupp.__reflect.link(profile.AbortSite,__nuppT1[4],{ })




































profile.TraceProfile = {} profile.TraceProfile.__index = profile.TraceProfile ;_G.nupp.__reflect.link(profile.TraceProfile,__nuppT1[5],{ })






























profile.TraceReport = {} profile.TraceReport.__index = profile.TraceReport ;_G.nupp.__reflect.link(profile.TraceReport,__nuppT1[6],{ __nuppT1[4] , __nuppT1[5] })































profile.TraceSession = {} profile.TraceSession.__index = profile.TraceSession ;_G.nupp.__reflect.link(profile.TraceSession,__nuppT1[7],{ __nuppT1[4] , __nuppT1[5] })










































local function writeFile ( path , text ) 
do local __nuppT15=0; local  __nuppT21 ; local __nuppT16,__nuppT17,__nuppT18=__nuppT8(function() do local __nuppT22=__nuppT3( io . open ( path , "wb" ) ); __nuppT21= __nuppT22[1] ; __nuppT15=1;  local  file , openReason = __nuppT22[1] , __nuppT22[2] ;
if not file then
error ( "nupp: cannot write the profile report '" .. path .. "': " .. ( openReason or "unknown" ) , 3 )
end
local written , writeReason = file : write ( text )
if not written then
file : close ( )
error ( "nupp: cannot write the profile report '" .. path .. "': " .. ( writeReason or "unknown" ) , 3 )
end
local closed , closeReason = file : close ( )
if not closed then
error ( "nupp: cannot close the profile report '" .. path .. "': " .. ( closeReason or "unknown" ) , 3 )
end end; return "normal" end,__nuppT4); local __nuppT19={}; local __nuppT20=0; if __nuppT15>=1 and __nuppT21~=nil then  local __nuppT23,__nuppT24=__nuppT7(__nuppCleanup1,__nuppT21);  if not __nuppT23 then __nuppT20=__nuppT20+1; __nuppT19[__nuppT20]=__nuppT24 end; end; if not __nuppT16 then if __nuppT20>0 then __nuppT9(__nuppT5(__nuppT17,__nuppT19,1),0) else __nuppT9(__nuppT17,0) end end; if __nuppT20>0 then if __nuppT20>1 then __nuppT9(__nuppT5(__nuppT19[1],__nuppT19,2),0) else __nuppT9(__nuppT19[1],0) end end; if __nuppT17=="return" then  return __nuppT10(__nuppT18,1,__nuppT18.n)  end; end
end









local function sanitize ( frame ) 
return ( frame : gsub ( "[;/\n\13]" , "_" ) )
end




local function appendFrames ( frames , text , separator ) 
if text == "" then
return
end

local pattern = "[^" .. separator .. "]+"
for piece in text : gmatch ( pattern ) do
frames [ # frames + 1 ] = ( ( piece : gsub ( "[;/\n\13]" , "_" ) ) )
end
end








local function collapse ( samples ) 
if # samples == 0 then
return ""
end

table . sort ( samples , function ( a , b ) 
if a . count ~= b . count then
return a . count > b . count
end
if a . zonePath ~= b . zonePath then
return a . zonePath < b . zonePath
end

return a . stack < b . stack
end )

local lines = { }
for index = 1 , # samples do
local sample = samples [ index ]
local frames = { }
appendFrames ( frames , sample . zonePath , "/" )
appendFrames ( frames , sample . stack , ";" )
if # frames == 0 then
frames [ 1 ] = "<root>"
end


local states = {
N = sample . compiled ,
I = sample . interpreted ,
C = sample . cCode ,
G = sample . collecting ,
J = sample . compiling
}
for _ , state in ipairs ( { "N" , "I" , "C" , "G" , "J" } ) do
local count = states [ state ]
if count > 0 then
local prefix = table . concat ( frames , ";" )
if state == "C" or state == "G" or state == "J" then



local zones = { }
appendFrames ( zones , sample . zonePath , "/" )
zones [ # zones + 1 ] = "<" .. ( state == "G" and "GC" or state == "J" and "JIT" or "C" ) .. ">"
prefix = table . concat ( zones , ";" )
end
lines [ # lines + 1 ] = prefix .. "_[" .. state .. "] " .. string . format ( "%d" , count )
end
end
end

return table . concat ( lines , "\n" )
end















local OUTSIDE_ROOT = "<outside>"

local function trimToRoot ( stack , root ) 
local prefix = root .. ":"
local from = 1
while from <= # stack do
if stack : sub ( from , from + # prefix - 1 ) == prefix then
return stack : sub ( from )
end
local nextFrame = stack : find ( ";" , from , true )
if not nextFrame then
do break end
end
from = nextFrame + 1
end

return "<outside>"
end




local sampling = false














local ignoredSignal , restoreSignal = nil , nil
do
local loaded , ffi = pcall ( require , "ffi" )
if loaded and package . config : sub ( 1 , 1 ) ~= "\\" then


pcall ( ( ffi ) . cdef , "void (*signal(int, void (*)(int)))(int);" )
local reachable , signal = pcall ( function ( ) 
return ( ffi ) . C . signal
end )
if reachable and signal ~= nil then

local SIGPROF , SIG_IGN = 27 , ( ffi ) . cast ( "void (*)(int)" , 1 )





local previous = nil
local captured = false
ignoredSignal = function ( ) 
local ok , was = pcall ( signal , 27 , SIG_IGN )
previous , captured = was , ok
end
restoreSignal = function ( ) 
if captured then
pcall ( signal , 27 , previous )
previous , captured = nil , false
end
end
end
end
end



local function haltSampling ( session ) 
session . stopped = true
jitProfile . stop ( )
if restoreSignal ~= nil then
restoreSignal ( )
end
sampling = false
zone . release ( )
end














function profile . sample ( options ) 
if sampling then
error ( "nupp: a sample session is already running; stop it first" , 2 )
end

local opts = options or { }
local intervalMs = opts . intervalMs or 10
if intervalMs < 1 or intervalMs > 2147483647 then
error ( "nupp: a sample session's intervalMs must be between 1 and 2147483647" , 2 )
end
local stackDepth = opts . stackDepth or 16
if stackDepth < 1 or stackDepth > 2147483647 then
error ( "nupp: a sample session's stackDepth must be between 1 and 2147483647" , 2 )
end

do local __nuppT35=0; local  __nuppT41 ; local __nuppT42=false ; local __nuppT36,__nuppT37,__nuppT38=__nuppT8(function() do local __nuppT43= _G.setmetatable({ intervalMs =
intervalMs ,  zoneFilter =
opts . zone ,  root =
opts . root ,  paused =
false ,  stopped =
false ,  aggregate =
{ } ,  sourceSamples =
{ } }, profile.SampleSession) ; __nuppT41= __nuppT43 ; __nuppT35=1;  __nuppT42=true;  local owned=__nuppT41;



local session = (function() __nuppT42=false; return  owned  end)()




local walk = - stackDepth
local aggregate = session . aggregate



local cachedPath = ""
local cachedStacks = { }
aggregate [ cachedPath ] = cachedStacks

local function record ( thread , samples , vmstate ) 
if session . paused then
return
end

local path = zone . path ( )
if path ~= cachedPath then
local stacks = aggregate [ path ]
if not stacks then
stacks = { }
aggregate [ path ] = stacks
end
cachedPath , cachedStacks = path , stacks
end



local stack = thread and jitProfile . dumpstack ( thread , "FZ;" , walk ) or ""
local sample = cachedStacks [ stack ]
if not sample then
sample = _G.setmetatable({ zonePath =
path ,  stack =
stack ,  count =
0 ,  compiled =
0 ,  interpreted =
0 ,  cCode =
0 ,  collecting =
0 ,  compiling =
0 }, profile.Sample)

cachedStacks [ stack ] = sample
end

if thread and ( vmstate == "N" or vmstate == "I" ) then

local location = jitProfile . dumpstack ( thread , "pl" , 1 )
local locations = session . sourceSamples [ path ]
if not locations then
locations = { }
session . sourceSamples [ path ] = locations
end
locations [ location ] = ( locations [ location ] or 0 ) + samples
end
sample . count = sample . count + samples
if vmstate == "N" then
sample . compiled = sample . compiled + samples
elseif vmstate == "I" then
sample . interpreted = sample . interpreted + samples
elseif vmstate == "C" then
sample . cCode = sample . cCode + samples
elseif vmstate == "G" then
sample . collecting = sample . collecting + samples
elseif vmstate == "J" then
sample . compiling = sample . compiling + samples
end
end

zone . acquire ( )
if ignoredSignal ~= nil then
ignoredSignal ( )
end





jitProfile . start ( "li" .. string . format ( "%d" , intervalMs ) , record )
sampling = true

return "return",__nuppT3( session ) end; return "normal" end,__nuppT4); local __nuppT39={}; local __nuppT40=0; if __nuppT35>=1 and __nuppT42 then  local __nuppT46,__nuppT47=__nuppT7(__nuppT45,__nuppT41);  if not __nuppT46 then __nuppT40=__nuppT40+1; __nuppT39[__nuppT40]=__nuppT47 end; end; if not __nuppT36 then if __nuppT40>0 then __nuppT9(__nuppT5(__nuppT37,__nuppT39,1),0) else __nuppT9(__nuppT37,0) end end; if __nuppT40>0 then if __nuppT40>1 then __nuppT9(__nuppT5(__nuppT39[1],__nuppT39,2),0) else __nuppT9(__nuppT39[1],0) end end; if __nuppT37=="return" then  return __nuppT10(__nuppT38,1,__nuppT38.n)  end; end
end








function profile . SampleSession : pause ( ) 
if self . stopped then
error ( "nupp: the sample session has already stopped" , 2 )
end
self . paused = true
end




function profile . SampleSession : resume ( ) 
if self . stopped then
error ( "nupp: the sample session has already stopped" , 2 )
end
self . paused = false
end







function profile . SampleSession : stop ( filename ) 
if self . stopped then
error ( "nupp: the sample session has already stopped" , 2 )
end
haltSampling ( self )

local prefix = self . zoneFilter



local subtree = ( prefix or "" ) .. "/"
local root = self . root
local kept = { }
local samples = 0



local merged = { }
for path , stacks in pairs ( self . aggregate ) do
if not prefix or path == prefix or path : sub ( 1 , # subtree ) == subtree then
for _ , sample in pairs ( stacks ) do
samples = samples + sample . count
local stack = root and trimToRoot ( sample . stack , root ) or sample . stack
local row = merged [ path .. "\0" .. stack ]
if not row then
row = _G.setmetatable({ zonePath =
path ,  stack =
stack ,  count =
0 ,  compiled =
0 ,  interpreted =
0 ,  cCode =
0 ,  collecting =
0 ,  compiling =
0 }, profile.Sample)

merged [ path .. "\0" .. stack ] = row
kept [ # kept + 1 ] = row
end
row . count = row . count + sample . count
row . compiled = row . compiled + sample . compiled
row . interpreted = row . interpreted + sample . interpreted
row . cCode = row . cCode + sample . cCode
row . collecting = row . collecting + sample . collecting
row . compiling = row . compiling + sample . compiling
end
end
end

local counts = { }
for path , locations in pairs ( self . sourceSamples ) do
if not prefix or path == prefix or path : sub ( 1 , # subtree ) == subtree then
for location , count in pairs ( locations ) do
counts [ location ] = ( counts [ location ] or 0 ) + count
end
end
end
local sourceSamples = { }
for location , count in pairs ( counts ) do
local file , at = location : match ( "^(.*):(%d+)$" )
local line = tonumber ( at )
if file and line and line > 0 then
sourceSamples [ # sourceSamples + 1 ] = { file = file , line = line , samples = count }
end
end
table . sort ( sourceSamples , function ( a , b ) 
if a . file ~= b . file then
return a . file < b . file
end
return a . line < b . line
end )
local report = _G.setmetatable({ intervalMs =
self . intervalMs ,  sourceSamples =
sourceSamples ,  samples =
samples ,  stacks =
# kept ,  text =
collapse ( kept ) }, profile.SampleReport)

if filename then
writeFile ( filename , report . text )
end

return report
end





local function classify ( reason , reasonClass ) 
if reason : find ( "blacklist" , 1 , true ) then
return "blacklist"
end
if reasonClass == "stop" then
return "info"
end

return "warn"
end

local function severityRank ( severity ) 
if severity == "blacklist" then
return 0
elseif severity == "warn" then
return 1
else
return 2
end
end




local function trimSource ( source ) 
if source : sub ( 1 , 1 ) == "@" then
return source : sub ( 2 )
end
return source
end




local function describeLocation ( func , pc ) 
if func then
local ok , info = pcall ( jitUtil . funcinfo , func , pc )
if ok and info then
local described = info
local source = described . short_src or described . source or "?"
local line = described . currentline or described . linedefined or 0
return string . format ( "%s:%d" , trimSource ( source ) , line )
end
end
if type ( func ) == "function" then
local info = debug . getinfo ( func , "S" )
return string . format (
"%s:%d" ,
trimSource ( info and info . short_src or "?" ) ,
( info and info . linedefined or 0 )
)
end

return "?:0"
end



local function csvField ( text ) 
if text : find ( "[,\"\n\13]" ) then
return "\"" .. text : gsub ( "\"" , "\"\"" ) .. "\""
end
return text
end

local function serializeTraceReport ( report ) 
local lines = { "severity,count,reason,location,zone,rootLocation" }
for index = 1 , # report . sites do
local site = report . sites [ index ]
lines [
# lines + 1
] = table . concat (
{
site . severity ,
string . format ( "%d" , site . count ) ,
csvField ( site . reason ) ,
csvField ( site . location ) ,
csvField ( site . zonePath ) ,
csvField ( site . rootLocation or site . location ) ,
} ,
","
)
end

return table . concat ( lines , "\n" )
end





( profile . TraceReport ) . __tostring = serializeTraceReport ;

( profile . SampleReport ) . __tostring = function ( report ) 
return report . text
end

local tracing = false





function profile . SampleSession . close ( self ) 
if not self . stopped then
haltSampling ( self )
end
end



local function haltTracing ( session ) 
session . stopped = true

jit . attach ( session . callback )
tracing = false
zone . release ( )
end














function profile . trace ( options ) 
if tracing then
error ( "nupp: a trace session is already running; stop it first" , 2 )
end

local opts = options or { }
local selected = traceRegistry . profile ( )
do local __nuppT62=0; local  __nuppT68 ; local __nuppT69=false ; local __nuppT63,__nuppT64,__nuppT65=__nuppT8(function() do local __nuppT70= _G.setmetatable({ includeBenign =
opts . includeBenign or false ,  startedAt =
os . time ( ) ,  paused =
false ,  stopped =
false ,  sites =
{ } ,  totalAborts =
0 ,  blacklisted =
0 ,  traceProfile =
_G.setmetatable({ id =
selected . id ,  luajitRevision =
selected . luajitRevision ,  luajitVersion =
selected . luajitVersion ,  architecture =
selected . architecture ,  operatingSystem =
selected . operatingSystem ,  enabledRecorderFeatures =
selected . enabledRecorderFeatures ,  bytecodeSchema =
selected . bytecodeSchema ,  supported =
selected . supported }, profile.TraceProfile) ,  callback =

function ( ) 
end }, profile.TraceSession) ; __nuppT68= __nuppT70 ; __nuppT62=1;  __nuppT69=true;  local owned=__nuppT68;



local session = (function() __nuppT69=false; return  owned  end)()




local roots = { }

local function onTraceEvent ( ... ) 
local what , traceNumber , func , pc , errorCode , errorArg = ...
if what == "start" then
if session . paused or roots [ errorCode ] == false then
roots [ traceNumber ] = false
else
roots [ traceNumber ] = roots [ errorCode ] or describeLocation ( func , pc )
end
return
elseif what == "flush" then
roots = { }
return
end
if what ~= "abort" or session . paused or roots [ traceNumber ] == false then
return
end

local normalizedCode = type ( errorCode ) == "number" and errorCode or nil
local normalizedArg = ( type ( errorArg ) == "number" or type ( errorArg ) == "string" ) and errorArg or nil
local normalized , reason = traceRegistry . runtime ( normalizedCode , normalizedArg )
local severity = classify ( reason , normalized . class )
if severity == "info" and not session . includeBenign then
return
end

session . totalAborts = session . totalAborts + 1
if severity == "blacklist" then
session . blacklisted = session . blacklisted + 1
end

local location = describeLocation ( func , pc )
local path = zone . path ( )
local rootLocation = roots [ traceNumber ] or location
local key = severity .. "|" .. reason .. "|" .. rootLocation .. "|" .. location .. "|" .. path
local site = session . sites [ key ]
if site then
site . count = site . count + 1
else
session . sites [
key
] = _G.setmetatable({ severity =
severity ,  count =
1 ,  reason =
reason ,  reasonId =
normalized . id ,  reasonClass =
normalized . class ,  rawReason =
reason ,  location =
location ,  rootLocation =
rootLocation ,  zonePath =
path }, profile.AbortSite)

end
end

session . callback = onTraceEvent
zone . acquire ( )
jit . attach ( onTraceEvent , "trace" )
tracing = true

return "return",__nuppT3( session ) end; return "normal" end,__nuppT4); local __nuppT66={}; local __nuppT67=0; if __nuppT62>=1 and __nuppT69 then  local __nuppT73,__nuppT74=__nuppT7(__nuppT45,__nuppT68);  if not __nuppT73 then __nuppT67=__nuppT67+1; __nuppT66[__nuppT67]=__nuppT74 end; end; if not __nuppT63 then if __nuppT67>0 then __nuppT9(__nuppT5(__nuppT64,__nuppT66,1),0) else __nuppT9(__nuppT64,0) end end; if __nuppT67>0 then if __nuppT67>1 then __nuppT9(__nuppT5(__nuppT66[1],__nuppT66,2),0) else __nuppT9(__nuppT66[1],0) end end; if __nuppT64=="return" then  return __nuppT10(__nuppT65,1,__nuppT65.n)  end; end
end







function profile . TraceSession : pause ( ) 
if self . stopped then
error ( "nupp: the trace session has already stopped" , 2 )
end
self . paused = true
end




function profile . TraceSession : resume ( ) 
if self . stopped then
error ( "nupp: the trace session has already stopped" , 2 )
end
self . paused = false
end






function profile . TraceSession : stop ( filename ) 
if self . stopped then
error ( "nupp: the trace session has already stopped" , 2 )
end
haltTracing ( self )

local sites = { }
for _ , site in pairs ( self . sites ) do
sites [ # sites + 1 ] = site
end
table . sort ( sites , function ( a , b ) 
local left , right = severityRank ( a . severity ) , severityRank ( b . severity )
if left ~= right then
return left < right
end
if a . count ~= b . count then
return a . count > b . count
end
if a . reason ~= b . reason then
return a . reason < b . reason
end

return a . location < b . location
end )

local report = _G.setmetatable({ durationSec =
( os . time ( ) ) - self . startedAt ,  totalAborts =
self . totalAborts ,  blacklisted =
self . blacklisted ,  sites =
sites ,  traceProfile =
self . traceProfile ,  reasonCatalogId =
traceRegistry . CATALOG_ID ,  reasonCatalogVersion =
traceRegistry . CATALOG_VERSION }, profile.TraceReport)

if filename then
writeFile ( filename , tostring ( report ) )
end

return report
end





function profile . TraceSession . close ( self ) 
if not self . stopped then
haltTracing ( self )
end
end

local __nuppExportValue= profile ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.profile"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.profile"]=__nuppExports;return __nuppExports