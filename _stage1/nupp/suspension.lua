_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();const __nuppT4={}; const __nuppT5,__nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12=pcall,xpcall,error,unpack,select,setmetatable,tostring,ipairs; const function __nuppT1(...) return {n=__nuppT9("#",...),...} end; const function __nuppT2(value) return value end; const function __nuppT3(primary,errors,start) const secondary={} for i=start,#errors do secondary[#secondary+1]=errors[i] end return __nuppT10({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT11(v.primary) for _,reason in __nuppT12(v.suppressed) do text=text.."\ncleanup: "..__nuppT11(reason) end return text end}) end; local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.suspension#suspension.destroyInstalled"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.suspension#suspension.destroyInstalled") end;__nuppCleanup1=cleanup;return cleanup(value) end;





































local suspension = { }




local MAX_DRAIN_PASSES = 64




local BLOCKING_WAIT_SLICE_MS = 1





suspension.Source = {} suspension.Source.__index = suspension.Source



















suspension.Context = {} suspension.Context.__index = suspension.Context






















suspension.Waiting = {} suspension.Waiting.__index = suspension.Waiting












suspension.Handler = {} suspension.Handler.__index = suspension.Handler


























local installed = setmetatable ( { } , { __mode = "k" } )
local mainInstalled = nil

local running = coroutine . running




local function effectiveInstallation ( )
local co = running ( )
local current = co == nil and mainInstalled or installed [ co ]









while current ~= nil and current . restored do
current = current . previous
end

return current
end

local function effective ( )
local current = effectiveInstallation ( )

return current and current . handler or nil
end



local sources = { }

local function sortSources ( )
table . sort ( sources , function ( a , b )
if a . priority == b . priority then
return a . name < b . name
end

return a . priority < b . priority
end )
end

local SourceMT = { }
SourceMT . __index = SourceMT

function SourceMT . release ( self )
if self . released then
return
end
self . released = true
for index = 1 , # sources do
if sources [ index ] == self then
table . remove ( sources , index )
break
end
end
end

local function addSource (
name ,
priority ,
poll ,
wait
)
local source = setmetatable (
{ name = name , priority = priority , poll = poll , wait = wait , released = false } ,
SourceMT
)
sources [ # sources + 1 ] = source
sortSources ( )

return source
end










function suspension . source (
name ,
priority ,
poll ,
wait
)
return addSource ( name , priority , poll , wait )
end





function suspension . poll ( )
local settled = 0

local pass = { }
for index = 1 , # sources do
pass [ index ] = sources [ index ]
end
for index = 1 , # pass do
local source = pass [ index ]
if not source . released then
settled = settled + ( source . poll ( ) or 0 )
end
end

return settled
end







local function waitCandidates ( waiting )
local associated = waiting . context and waiting . context . associated
local preferred = { }
if associated ~= nil then
for index = 1 , # sources do
local source = sources [ index ]
if associated [ source ] and not source . released and source . wait ~= nil then
preferred [ # preferred + 1 ] = source . wait
end
end
end
if # preferred > 0 then
return preferred
end

local fallback = { }
for index = 1 , # sources do
local source = sources [ index ]
if not source . released and source . wait ~= nil then
fallback [ # fallback + 1 ] = source . wait
end
end

return fallback
end

local function blockingPark ( waiting )
while not waiting : ready ( ) do
if # sources == 0 then
error ( ( "nupp: %s cannot complete: no readiness source is registered" ) : format ( waiting . operation ) , 0 )
end
if suspension . poll ( ) == 0 and not waiting : ready ( ) then
local candidates = waitCandidates ( waiting )
if # candidates > 0 then
local cursor = waiting . waitCursor or 1
if cursor > # candidates then
cursor = 1
end
local wait = candidates [ cursor ]
waiting . waitCursor = cursor % # candidates + 1
wait ( BLOCKING_WAIT_SLICE_MS )



if not waiting : ready ( ) then
suspension . poll ( )
end
end
end
end
end

local WaitingMT = { }
WaitingMT . __index = WaitingMT

function WaitingMT . ready ( self )
return self . isReady ( )
end

function WaitingMT . onResume ( self , waker )
self . setWaker ( waker )
end

local ContextMT = { }
ContextMT . __index = ContextMT

function ContextMT . source (
self ,
name ,
priority ,
poll ,
wait
)
local source = addSource ( name , priority , poll , wait )


local owned = self . owned
if owned == nil then
owned = { }
self . owned = owned
end
owned [ # owned + 1 ] = source
self . associated = self . associated or { }
self . associated [ source ] = true

return source
end

function ContextMT . uses ( self , source )
if source == nil or source . released then
error ( "nupp: cannot use a released readiness source" , 2 )
end
self . associated = self . associated or { }
self . associated [ source ] = true
end

function ContextMT . canPark ( self )
local handler = self . handler
if handler == nil then
return true
end
if handler . canPark == nil then
return true
end

return handler . canPark ( handler ) ~= false
end



local function releaseOwned ( context )
local owned = context and context . owned
if owned == nil then
return
end
context . owned = nil
for index = 1 , # owned do
pcall ( owned [ index ] . release , owned [ index ] )
end
end















function suspension . suspend (
operation ,
subscribe
)
local current = effectiveInstallation ( )
local handler = current and current . handler or nil



local state = { resumed = false , value = nil , cancelled = false , reason = nil , waker = nil }

local function resume ( answer )
if state . resumed or state . cancelled then
error ( ( "nupp: %s was resumed twice" ) : format ( operation ) , 0 )
end
state . resumed , state . value = true , answer
local wake = state . waker
if wake then
state . waker = nil
wake ( )
end
end

local context = setmetatable ( { handler = handler , owned = nil , associated = nil } , ContextMT )


local subscribed , cancel = pcall ( subscribe , resume , context )
if not subscribed then
releaseOwned ( context )
error ( cancel , 0 )
end
if state . resumed then


releaseOwned ( context )

return state . value
end

if not cancel then
releaseOwned ( context )
error (
( "nupp: %s did not resume and answered no cancellation, so it could never be abandoned" ) : format ( operation ) ,
0
)
end
if not ContextMT . canPark ( context ) then
pcall ( cancel )
releaseOwned ( context )
error ( ( "nupp: %s cannot suspend here" ) : format ( operation ) , 0 )
end




local ticket = nil
if current ~= nil then
ticket = { operation = operation , unsubscribeAttempted = false }
function ticket . abandon ( reason )




local unsubscribeError = nil
if not ticket . unsubscribeAttempted then
ticket . unsubscribeAttempted = true




local ok , err = pcall ( cancel )
if not ok then
unsubscribeError = err
end
end
state . cancelled , state . reason = true , reason
local wakeError = nil
local wake = state . waker
if wake then



local ok , err = pcall ( wake )
if ok then
state . waker = nil
else
wakeError = err
end
end

if unsubscribeError ~= nil then
error ( unsubscribeError , 0 )
end
if wakeError ~= nil then
error ( wakeError , 0 )
end
end

current . parks [ ticket ] = true
end

local waiting = setmetatable (
{
operation = operation ,
context = context ,
waitCursor = 1 ,
isReady = function ( )
return state . resumed or state . cancelled
end ,
setWaker = function ( wake )
state . waker = wake
end ,
} ,
WaitingMT
)





local ok , err
if handler then
ok , err = pcall ( handler . park , handler , waiting , cancel )
else
ok , err = pcall ( blockingPark , waiting )
end



if ticket and current then
current . parks [ ticket ] = nil
end
releaseOwned ( context )
if state . cancelled then
error ( ( "nupp: %s was cancelled: %s" ) : format ( operation , state . reason or "the extent ended" ) , 0 )
end
if not ok then


pcall ( cancel )
local text = tostring ( err )
if text : find ( "C%-call boundary" ) or text : find ( "attempt to yield across" ) then
error ( ( "nupp: %s cannot suspend: non-yieldable C code is on the stack" ) : format ( operation ) , 0 )
end
error ( err , 0 )
end
if not state . resumed then
pcall ( cancel )
error ( ( "nupp: %s: the handler returned without resuming it" ) : format ( operation ) , 0 )
end

return state . value
end


suspension.Installed = {} suspension.Installed.__index = suspension.Installed




















function suspension.Installed:release()
if self . released then
return
end





if not self . restored then
self . restored = true
if self . co == nil then
mainInstalled = self . previous
else
installed [ self . co ] = self . previous
end
end





local firstError = nil
local function attempt ( fn , argument )
local ok , err = pcall ( fn , argument )
if not ok and firstError == nil then
firstError = err
end
end








for ticket in pairs ( self . parks or { } ) do
attempt ( ticket . abandon , "the handled extent ended" )
end



if self . handler . shutdown then
attempt ( self . handler . shutdown , self . handler )
end

local remaining = next ( self . parks or { } )
local passes = 0
while remaining ~= nil and passes < MAX_DRAIN_PASSES do
passes = passes + 1
attempt ( suspension . poll , nil )
remaining = next ( self . parks or { } )
end




if firstError ~= nil then


error ( firstError , 0 )
end





if remaining ~= nil then
local names = { }
for ticket in pairs ( self . parks or { } ) do
names [ # names + 1 ] = ticket . operation
end
table . sort ( names )
error (
(
"nupp: the handled extent ended with %d park(s) unfinished: %s"
) : format ( # names , table . concat ( names , ", " ) ) ,
0
)
end
self . released = true
end


function suspension . Installed . drop ( self )
self : release ( )
end

function suspension . destroyInstalled ( self )
self : drop ( )
end ;__nuppCleanups["nupp.suspension#suspension.destroyInstalled"]=suspension.destroyInstalled



















function suspension . install ( handler ) __nuppCleanups["nupp.suspension#suspension.destroyInstalled"]=suspension.destroyInstalled;
local co = running ( )
local previous
if co == nil then
previous = mainInstalled
else
previous = installed [ co ]
end


local installation = setmetatable({ co =
co ,  previous =
previous ,  handler =
handler ,  restored =
false ,  released =
false ,  parks =
{ } }, suspension.Installed)

if co == nil then
mainInstalled = installation
else
installed [ co ] = installation
end

return installation
end















function suspension . create ( body )
local co = coroutine . create ( body )



local inherited = effectiveInstallation ( )
if inherited ~= nil then
installed [ co ] = inherited
end

return co
end
















function suspension . handled ( )
return effective ( ) ~= nil
end





function suspension . canSuspend ( )
local handler = effective ( )
if handler == nil or handler . canPark == nil then
return true
end

return handler . canPark ( handler ) ~= false
end

































local ABANDONED = { }











local function drive (
bodies ,
limit ,
stopEarly
)
local count = # bodies
local values = { }
local errors = { }
local threads = { }
local indexOf = setmetatable ( { } , { __mode = "k" } )
local runnable = { }
local abandoned = { }
local entered = { }
local started = 0
local finished = 0
local first = nil
local wakeDriver = nil
local inFlight = limit and ( limit > 1 and limit or 1 ) or count



local function nudge ( )
local wake = wakeDriver
if wake then
wakeDriver = nil
wake ( )
end
end

local branchHandler = setmetatable({ park =
function ( _ , waiting , cancel )
local index = indexOf [ running ( ) ]
local function markRunnable ( )
runnable [ index ] = true
nudge ( )
end

while not waiting : ready ( ) do
waiting : onResume ( markRunnable )


if waiting : ready ( ) then
break
end
coroutine . yield ( )
if abandoned [ index ] then
cancel ( )
error ( ABANDONED , 0 )
end
end
end ,  canPark =
function ( _ )
return true
end ,  shutdown =
function ( _ )
end }, suspension.Handler)





local function startNext ( )
started = started + 1
local index = started
local body = bodies [ index ]
local co = suspension . create ( function ( )
local produced
do
do local __nuppT13=0; local  __nuppT19 ; const __nuppT14,__nuppT15,__nuppT16=__nuppT6(function() do const __nuppT20= suspension . install ( branchHandler ) ; __nuppT19= __nuppT20 ; __nuppT13=1;  local handling=__nuppT19;
entered [ index ] = true
produced = body ( ) end; return "normal" end,__nuppT2); const __nuppT17={}; local __nuppT18=0; if __nuppT13>=1 then  const __nuppT21,__nuppT22=__nuppT5(__nuppCleanup1,__nuppT19);  if not __nuppT21 then __nuppT18=__nuppT18+1; __nuppT17[__nuppT18]=__nuppT22 end; end; if not __nuppT14 then if __nuppT18>0 then __nuppT7(__nuppT3(__nuppT15,__nuppT17,1),0) else __nuppT7(__nuppT15,0) end end; if __nuppT18>0 then if __nuppT18>1 then __nuppT7(__nuppT3(__nuppT17[1],__nuppT17,2),0) else __nuppT7(__nuppT17[1],0) end end; if __nuppT15=="return" then  return __nuppT8(__nuppT16,1,__nuppT16.n)  end; end
end

return produced
end )
threads [ index ] = co
indexOf [ co ] = index
runnable [ index ] = true
end

local ceiling = inFlight < count and inFlight or count
for _ = 1 , ceiling do
startNext ( )
end



local function parkDriver ( resume , _ )
wakeDriver = function ( )
resume ( true )
end

return function ( )
wakeDriver = nil
end
end

while finished < count do
local ran = false
for index = 1 , count do
local co = threads [ index ]
if co ~= nil and runnable [ index ] then
runnable [ index ] = nil
ran = true
local ok , answer = coroutine . resume ( co )
if coroutine . status ( co ) == "dead" then
threads [ index ] = nil
finished = finished + 1
if ok then
values [ index ] = answer
elseif answer ~= ABANDONED then
errors [ index ] = answer
end
if first == nil and answer ~= ABANDONED then
first = index
end
if stopEarly ~= nil and stopEarly ( ) then


for other = 1 , count do
local victim = threads [ other ]
if victim ~= nil then
abandoned [ other ] = true
if entered [ other ] then
coroutine . resume ( victim )
else
local victimBody = bodies [ other ]
if type ( victimBody ) == "table" and victimBody . __nuppRelease then
victimBody . __nuppRelease ( )
end
end
threads [ other ] = nil
finished = finished + 1
end
end
for other = started + 1 , count do
local victimBody = bodies [ other ]
if type ( victimBody ) == "table" and victimBody . __nuppRelease then
victimBody . __nuppRelease ( )
end
end
finished = finished + ( count - started )
started = count
elseif started < count then
startNext ( )
end
end
end
end
if finished >= count then
break
end
if not ran then



suspension . suspend ( "suspension.all" , parkDriver )
end
end

return values , errors , first
end










function suspension . all ( bodies )
local values , errors = drive ( bodies , nil , nil )
for index = 1 , # bodies do
if errors [ index ] ~= nil then
error ( errors [ index ] , 0 )
end
end

return values
end








function suspension . gather ( bodies )
local values , errors = drive ( bodies , nil , nil )

return values , errors
end









local function raceImpl ( bodies )
local rawBodies
rawBodies = bodies
if # rawBodies == 0 then
return nil , nil
end
local values , errors , first = drive ( rawBodies , nil , function ( )
return true
end )
if first ~= nil and errors [ first ] ~= nil then
error ( errors [ first ] , 0 )
end

return first ~= nil and values [ first ] or nil , first
end

local race

do


race = raceImpl
end
suspension . race = race













function suspension . batch ( bodies , limit )
local values , errors = drive ( bodies , limit , nil )
for index = 1 , # bodies do
if errors [ index ] ~= nil then
error ( errors [ index ] , 0 )
end
end

return values
end

return suspension
