_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
































local zone = require ( "nupp.zone" )
local jitProfile = require ( "jit.profile" )
local jitUtil = require ( "jit.util" )
local vmdef = require ( "jit.vmdef" )

local profile = { }
































































profile.Sample = {} profile.Sample.__index = profile.Sample




























profile.SampleReport = {} profile.SampleReport.__index = profile.SampleReport





















profile.SampleSession = {} profile.SampleSession.__index = profile.SampleSession






























profile.AbortSite = {} profile.AbortSite.__index = profile.AbortSite





















profile.TraceReport = {} profile.TraceReport.__index = profile.TraceReport






















profile.TraceSession = {} profile.TraceSession.__index = profile.TraceSession







































local function writeFile ( path , text )
local file , openReason = io . open ( path , "wb" )
if not file then
error ( "profile: cannot write '" .. path .. "': " .. ( openReason or "unknown" ) , 3 )
end
local written , writeReason = file : write ( text )
if not written then
file : close ( )
error ( "profile: cannot write '" .. path .. "': " .. ( writeReason or "unknown" ) , 3 )
end
local closed , closeReason = file : close ( )
if not closed then
error ( "profile: cannot close '" .. path .. "': " .. ( closeReason or "unknown" ) , 3 )
end
end









local function sanitize ( frame )
return ( frame : gsub ( "[;/\n\r]" , "_" ) )
end




local function dominantState ( sample )
local state , best = "N" , sample . compiled
if sample . interpreted > best then
state , best = "I" , sample . interpreted
end
if sample . cCode > best then
state , best = "C" , sample . cCode
end
if sample . collecting > best then
state , best = "G" , sample . collecting
end
if sample . compiling > best then
state , best = "J" , sample . compiling
end

return state
end




local function appendFrames ( frames , text , separator )
if text == "" then
return
end

local pattern = "[^" .. separator .. "]+"
for piece in text : gmatch ( pattern ) do
frames [ # frames + 1 ] = sanitize ( piece )
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
frames [ # frames ] = frames [ # frames ] .. "_[" .. dominantState ( sample ) .. "]"
lines [ index ] = table . concat ( frames , ";" ) .. " " .. string . format ( "%d" , sample . count )
end

return table . concat ( lines , "\n" )
end








local function trimToRoot ( stack , root )
local prefix = root .. ":"
local from = 1
while from <= # stack do
if stack : sub ( from , from + # prefix - 1 ) == prefix then
return stack : sub ( from )
end
local nextFrame = stack : find ( ";" , from , true )
if not nextFrame then
return stack
end
from = nextFrame + 1
end

return stack
end




local sampling = false






function profile . sample ( options )
if sampling then
error ( "profile.sample: a sample session is already running; stop it first" , 2 )
end

local opts = options or { }
local intervalMs = opts . intervalMs or 10
if intervalMs < 1 then
error ( "profile.sample: intervalMs must be at least 1" , 2 )
end
local stackDepth = opts . stackDepth or 16
if stackDepth < 1 then
error ( "profile.sample: stackDepth must be at least 1" , 2 )
end

local session = setmetatable({ intervalMs =
intervalMs ,  zoneFilter =
opts . zone ,  root =
opts . root ,  paused =
false ,  stopped =
false ,  aggregate =
{ } }, profile.SampleSession)





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
sample = setmetatable({ zonePath =
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





jitProfile . start ( "li" .. string . format ( "%d" , intervalMs ) , record )
sampling = true

return session
end








function profile . SampleSession : pause ( )
if self . stopped then
error ( "SampleSession:pause: the session has already stopped" , 2 )
end
self . paused = true
end




function profile . SampleSession : resume ( )
if self . stopped then
error ( "SampleSession:resume: the session has already stopped" , 2 )
end
self . paused = false
end







function profile . SampleSession : stop ( filename )
if self . stopped then
error ( "SampleSession:stop: the session has already stopped" , 2 )
end
self . stopped = true
jitProfile . stop ( )
sampling = false
zone . release ( )

local prefix = self . zoneFilter
local root = self . root
local kept = { }
local samples = 0



local merged = { }
for path , stacks in pairs ( self . aggregate ) do
if not prefix or path : sub ( 1 , # prefix ) == prefix then
for _ , sample in pairs ( stacks ) do
samples = samples + sample . count
local stack = root and trimToRoot ( sample . stack , root ) or sample . stack
local row = merged [ path .. "\0" .. stack ]
if not row then
row = setmetatable({ zonePath =
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

local report = setmetatable({ intervalMs =
self . intervalMs ,  samples =
samples ,  stacks =
# kept ,  text =
collapse ( kept ) }, profile.SampleReport)

if filename then
writeFile ( filename , report . text )
end

return report
end





local traceerr = vmdef . traceerr
local bcnames = vmdef . bcnames



local function opcodeName ( opcode )
local start = opcode * 6 + 1
return ( bcnames : sub ( start , start + 5 ) : gsub ( "%s+$" , "" ) )
end




local function abortReason ( errorCode , errorArg )
if not errorCode then
return "abort"
end

local format = traceerr [ errorCode ]
if not format then
return "error " .. tostring ( errorCode )
end
if format : find ( "NYI: bytecode" , 1 , true ) and type ( errorArg ) == "number" then
return "NYI: bytecode " .. opcodeName ( errorArg )
end
if errorArg == nil then
return format
end

local ok , filled = pcall ( string . format , format , errorArg )

return ok and filled or format
end




local function classify ( reason )
if reason : find ( "blacklist" , 1 , true ) then
return "blacklist"
end
if reason : find ( "leaving loop" , 1 , true ) then
return "info"
end
if reason : find ( "inner loop" , 1 , true ) then
return "info"
end
if reason : find ( "down-recursion" , 1 , true ) then
return "info"
end
if reason : find ( "up-recursion" , 1 , true ) then
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
if text : find ( "[,\"\n\r]" ) then
return "\"" .. text : gsub ( "\"" , "\"\"" ) .. "\""
end
return text
end

local function serializeTraceReport ( report )
local lines = { "severity,count,reason,location,zone" }
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






function profile . trace ( options )
if tracing then
error ( "profile.trace: a trace session is already running; stop it first" , 2 )
end

local opts = options or { }
local session = setmetatable({ includeBenign =
opts . includeBenign or false ,  startedAt =
os . time ( ) ,  paused =
false ,  stopped =
false ,  sites =
{ } ,  totalAborts =
0 ,  blacklisted =
0 ,  callback =
function ( )
end }, profile.TraceSession)





local function onTraceEvent ( ... )
local what , _ , func , pc , errorCode , errorArg = ...
if what ~= "abort" or session . paused then
return
end

local reason = abortReason ( errorCode , errorArg )
local severity = classify ( reason )
if severity == "info" and not session . includeBenign then
return
end

session . totalAborts = session . totalAborts + 1
if severity == "blacklist" then
session . blacklisted = session . blacklisted + 1
end

local location = describeLocation ( func , pc )
local path = zone . path ( )
local key = severity .. "|" .. reason .. "|" .. location .. "|" .. path
local site = session . sites [ key ]
if site then
site . count = site . count + 1
else
session . sites [
key
] = setmetatable({ severity =
severity ,  count =
1 ,  reason =
reason ,  location =
location ,  zonePath =
path }, profile.AbortSite)

end
end

session . callback = onTraceEvent
zone . acquire ( )
jit . attach ( onTraceEvent , "trace" )
tracing = true

return session
end







function profile . TraceSession : pause ( )
if self . stopped then
error ( "TraceSession:pause: the session has already stopped" , 2 )
end
self . paused = true
end




function profile . TraceSession : resume ( )
if self . stopped then
error ( "TraceSession:resume: the session has already stopped" , 2 )
end
self . paused = false
end






function profile . TraceSession : stop ( filename )
if self . stopped then
error ( "TraceSession:stop: the session has already stopped" , 2 )
end
self . stopped = true

jit . attach ( self . callback )
tracing = false
zone . release ( )

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

local report = setmetatable({ durationSec =
( os . time ( ) ) - self . startedAt ,  totalAborts =
self . totalAborts ,  blacklisted =
self . blacklisted ,  sites =
sites }, profile.TraceReport)

if filename then
writeFile ( filename , tostring ( report ) )
end

return report
end

return profile
