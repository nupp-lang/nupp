_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT66={}; local function __nuppT63(...) return {n=select("#",...),...} end; local __nuppT67,__nuppT68,__nuppT69,__nuppT70,__nuppT71,__nuppT72,__nuppT73,__nuppT74=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT64(value) return value end; local function __nuppT65(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT72({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT73(v.primary) for _,reason in __nuppT74(v.suppressed) do text=text.."\ncleanup: "..__nuppT73(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tasks\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.tasks\0runtime\0002") };








































































local suspension = require ( "nupp.suspension" )

local suspensionHost = require ( "nupp.suspension.host" )

local workerModule = require ( "nupp.runtime.workersprovider" ) . provider
local taskownership = require ( "nupp.runtime.taskownership" )



local runtimeCancellation = require ( "nupp.suspension.cancellation" )
local loadedTime = require ( "nupp.runtime.timeprovider" ) . provider

local function missingTime ( ) 
error ( "nupp: a task scope timeout requires a clock provider" , 2 )
end

local timeModule = loadedTime or { now = missingTime , wakeAt = missingTime }

local tasks = { }






local function pack ( ... ) 
return { values = { ... } , count = select ( "#" , ... ) }
end










tasks.Cancellation = {} tasks.Cancellation.__index = tasks.Cancellation ;_G.nupp.__reflect.link(tasks.Cancellation,__nuppT1[1],{ })







local function cancellation ( operation , reason ) 
return runtimeCancellation . create ( operation , reason )
end
















function tasks . isCancelled ( value ) 
return runtimeCancellation . is ( value ) == true
end




















































































































tasks.Scope = {} tasks.Scope.__index = tasks.Scope ;_G.nupp.__reflect.link(tasks.Scope,__nuppT1[2],{ })












































local ScopeMT = { __index = tasks . Scope }


local activeScope = nil


local activeChild = nil

local function state ( scope ) 
return ( scope ) . _state
end






local rootOpen = setmetatable ( { } , { __mode = "k" } )

local mainRoot = { }

local function rootKey ( ) 
return coroutine . running ( ) or mainRoot
end

local function currentRootStack ( ) 
return rootOpen [ ( coroutine . running ( ) or mainRoot ) ]
end







local function drivesScope ( owner ) 
const child = activeChild

return child == nil or child . scope ~= owner
end



local function currentScope ( ) 
const child = activeChild
if child ~= nil then
const opened = child . openScopes
if opened ~= nil and # opened > 0 then
return opened [ # opened ]
end

return activeScope
end
const opened = ( rootOpen [ ( coroutine . running ( ) or mainRoot ) ] )
if opened ~= nil and # opened > 0 then
return opened [ # opened ]
end

return activeScope
end




local function fireWakers ( owner ) 
const waking = owner . wakers
if # waking == 0 then
return
end
owner . wakers = { }
for index = 1 , # waking do
waking [ index ] ( true )
end
end

local function removeWaker ( owner , wake ) 
const wakers = owner . wakers
for index = # wakers , 1 , -1 do
if wakers [ index ] == wake then
table . remove ( wakers , index )

do break end
end
end
end

local function markRunnable ( owner , child ) 
if child . runnable or child . status == "done" or child . status == "failed" or child . status == "cancelled" then
return
end
child . runnable = true
const tail = owner . tail + 1
owner . tail = tail
owner . queue [ tail ] = child
owner . ready = owner . ready + 1
fireWakers ( owner )
end







local function compactQueue ( owner ) 
if owner . stale <= 32 or owner . stale <= owner . ready then
return
end
const queue = owner . queue
const kept = { }
for index = owner . head , owner . tail do
const child = queue [ index ]
if child ~= nil and child . runnable then
kept [ # kept + 1 ] = child
end
end
owner . queue = kept
owner . head = 1
owner . tail = # kept
owner . stale = 0
end

local function link ( owner , child ) 
const last = owner . last
child . before = last
child . after = nil
if last ~= nil then
last . after = child
else
owner . first = child
end
owner . last = child
end

local function unlink ( owner , child ) 
const before = child . before
const after = child . after
if before ~= nil then
before . after = after
else
owner . first = after
end
if after ~= nil then
after . before = before
else
owner . last = before
end
child . before = nil
child . after = nil
end


local function wakeSlots ( owner ) 
const waiting = owner . slotWaiters
if # waiting == 0 then
return
end
owner . slotWaiters = { }
for index = 1 , # waiting do
waiting [ index ] ( true )
end
end







local function settleChild ( owner , child , status ) 
child . status = status
child . thread = nil
if child . runnable then


child . runnable = false
owner . ready = owner . ready - 1
owner . stale = owner . stale + 1
compactQueue ( owner )
end
owner . live = owner . live - 1
unlink ( owner , child )


if child . lending then
child . lending = false
owner . lent = owner . lent - 1
end
const onSettle = owner . onSettle
if onSettle ~= nil then
onSettle ( child )
end
local waiting = child . waiters
child . waiters = { }
for index = 1 , # waiting do
waiting [ index ] ( true )
end
wakeSlots ( owner )
end

local function releaseUncalled ( child ) 
local release = child . release
if release ~= nil then
child . release = nil
release ( )
end
end





local function withSuppressed ( primary , suppressed ) 
return setmetatable ( { primary = primary , suppressed = suppressed . values , suppressedCount = suppressed . count , } , {
__tostring = function ( value ) 
local text = tostring ( value . primary )
for index = 1 , value . suppressedCount do
text = text .. "\ncleanup: " .. tostring ( value . suppressed [ index ] )
end

return text
end ,
} )
end






local function ownFailure ( owner , problem ) 
if not owner . failed then
owner . failed = true
owner . failure = problem
else
const suppressed = owner . suppressed
if suppressed == nil then
owner . suppressed = pack ( problem )
else
suppressed . count = suppressed . count + 1
suppressed . values [ suppressed . count ] = problem
end
end
end

local requestCancellation





local function cancelOpened ( child ) 
const opened = child . openScopes
if opened == nil then
return
end
for index = 1 , # opened do
const nested = opened [ index ]
if nested . cancellation == nil then
nested . cancellation = child . cancelled
end
requestCancellation ( nested , child . name , child . reason )
end
end

requestCancellation = function ( owner , operation , reason ) 
if owner . cancellation == nil then
owner . cancellation = cancellation ( operation , reason )
end



local child = owner . first
while child ~= nil do
const after = child . after
if child . status == "queued" or child . status == "running" then
child . requested = true
child . cancelled = child . cancelled or owner . cancellation
markRunnable ( owner , child )
cancelOpened ( child )
end
child = after
end
local workerScope = owner . workerScope
if workerScope ~= nil then
workerScope : _cancelAll ( reason )
end
end


local function deadlinePassed ( owner ) 
const deadline = owner . deadline
if deadline == nil then
return false
end
if timeModule . now ( ) < deadline then
return false
end
requestCancellation ( owner , "the task scope" , "its deadline passed" )

return true
end





local function resumeChild ( owner , child ) 
const co = child . thread
if co == nil then
return
end
child . runnable = false
if child . status == "queued" then
child . status = "running"
end
suspensionHost . consumeTurn ( )
const previousScope = activeScope
const previousChild = activeChild
activeScope = owner
activeChild = child
const ok , answer = coroutine . resume ( co )
activeScope = previousScope
activeChild = previousChild
if coroutine . status ( co ) ~= "dead" then
return
end
if ok then
child . values = answer
settleChild ( owner , child , "done" )
elseif tasks . isCancelled ( answer ) then
child . cancelled = answer
settleChild ( owner , child , "cancelled" )
elseif owner . soft then



child . problem = answer
settleChild ( owner , child , "failed" )
else
child . problem = answer




ownFailure ( owner , answer )
settleChild ( owner , child , "failed" )
requestCancellation ( owner , child . name , "a sibling failed" )
end
end

local function takeRunnable ( owner ) 
const queue = owner . queue
while owner . head <= owner . tail do
const head = owner . head
const child = queue [ head ]
queue [ head ] = nil
owner . head = head + 1
if child ~= nil and child . runnable then
child . runnable = false
owner . ready = owner . ready - 1

return child
end
owner . stale = owner . stale - 1
end
owner . head = 1
owner . tail = 0
owner . stale = 0

return nil
end






local function parkScope ( owner ) 
return function ( resume , _ ) 
const function wake ( _ ) 
resume ( true )
end

owner . wakers [ # owner . wakers + 1 ] = wake
const deadline = owner . deadline
if deadline == nil then
return function ( ) 
removeWaker ( owner , wake )
end
end
const cancelTimer = timeModule . wakeAt ( deadline , function ( _ ) 
fireWakers ( owner )
end )

return function ( ) 
removeWaker ( owner , wake )
cancelTimer ( )
end
end
end







local function parkedOperation ( owner , fallback ) 
local child = owner . first
while child ~= nil do
if not child . runnable then
return child . name
end
child = child . after
end

return fallback
end

local function pump ( owner , operation , settled ) 
while not settled ( ) do
deadlinePassed ( owner )
if suspensionHost . turnAvailable ( ) then
const child = takeRunnable ( owner )
if child ~= nil then
resumeChild ( owner , child )
elseif owner . live == 0 then
return
else
suspension . suspend ( parkedOperation ( owner , operation ) , parkScope ( owner ) )
end
elseif owner . ready > 0 then
suspensionHost . deferTurn ( )
elseif owner . live == 0 then
return
else
suspension . suspend ( parkedOperation ( owner , operation ) , parkScope ( owner ) )
end
end
end











local function frameHandler ( owner ) 
const outerCanPark = suspensionHost . delegatedCanPark ( )
const parkOutward = suspensionHost . delegatedPark ( )

return ( _G.setmetatable({ park =
function ( _ , waiting , cancel ) 




local cancelTimer = nil
local registered = nil






const function scopeReady ( ) 
if owner . settling then


return owner . ready > 0 and suspensionHost . turnAvailable ( )
end
const deadline = owner . deadline
const expired = deadline ~= nil and timeModule . now ( ) >= deadline

return ( owner . ready > 0 and suspensionHost . turnAvailable ( ) )
or owner . failed
or expired
or ( owner . cancellation ~= nil and not owner . deliberate )
end





const function armScope ( wake ) 
if registered ~= nil then
removeWaker ( owner , registered )
end
const waker = function ( _ ) 
wake ( )
end
registered = waker
owner . wakers [ # owner . wakers + 1 ] = waker
const deadline = owner . deadline
if deadline ~= nil and cancelTimer == nil then
cancelTimer = timeModule . wakeAt ( deadline , function ( _ ) 
fireWakers ( owner )
end )
end
end

const combined = suspensionHost . derive ( waiting , scopeReady , armScope )
while not waiting : ready ( ) do
deadlinePassed ( owner )




if not owner . settling then
if owner . failed then
cancel ( )
error ( owner . failure , 0 )
end
const cancelled = owner . cancellation
if cancelled ~= nil and not owner . deliberate then
cancel ( )
error ( cancelled , 0 )
end
end
const child = suspensionHost . turnAvailable ( ) and takeRunnable ( owner ) or nil
if child ~= nil then
resumeChild ( owner , child )
else
const ok , problem = pcall ( parkOutward , combined , cancel )
if registered ~= nil then
removeWaker ( owner , registered )
registered = nil
end
if cancelTimer ~= nil then
cancelTimer ( )
cancelTimer = nil
end
if not ok then
error ( problem , 0 )
end
end
end



deadlinePassed ( owner )
if owner . settling then
return
end
if owner . failed then
error ( owner . failure , 0 )
end
const cancelled = owner . cancellation
if cancelled ~= nil and not owner . deliberate then
error ( cancelled , 0 )
end
end ,  canPark =
function ( _ ) 
return outerCanPark ( )
end ,  shutdown =
function ( _ ) 
end }, suspensionHost.Handler) )

end










local function settleAgainstScope ( owner ) 
if owner . settling then
return
end
if owner . failed then
error ( owner . failure , 0 )
end
const cancelled = owner . cancellation
if cancelled ~= nil and not owner . deliberate then
error ( cancelled , 0 )
end
end





local TaskMT = { }
TaskMT . __index = TaskMT

local function newTask ( owner , child ) 
return setmetatable ( { _owner = owner , _child = child , } , TaskMT )
end

function TaskMT . isDone ( self ) 
const status = ( self . _child ) . status

return status == "done" or status == "failed" or status == "cancelled"
end

function TaskMT . status ( self ) 
return ( self . _child ) . status
end

function TaskMT . cancel ( self , reason ) 
const child = self . _child
const owner = self . _owner
if child . requested or TaskMT . isDone ( self ) then
return false
end
child . requested = true
child . cancelled = cancellation ( child . name , reason )
cancelOpened ( child )
if child . status == "queued" and not child . entered then


releaseUncalled ( child )
child . thread = nil
settleChild ( owner , child , "cancelled" )

return true
end
markRunnable ( owner , child )

return true
end

function TaskMT . await ( self ) 
const owner = self . _owner
const child = self . _child
settleAgainstScope ( owner )
if not TaskMT . isDone ( self ) then
if drivesScope ( owner ) then

pump ( owner , child . name , function ( ) 
return TaskMT . isDone ( self ) or owner . failed
end )
else


const waitingChild = activeChild

const function subscribe ( resume , _ ) 
child . waiters [ # child . waiters + 1 ] = resume

return function ( ) 
for index = # child . waiters , 1 , -1 do
if child . waiters [ index ] == resume then
table . remove ( child . waiters , index )

do break end
end
end
end
end

while not TaskMT . isDone ( self ) and not owner . failed do
suspension . suspend ( child . name , subscribe )
if waitingChild . requested then
error ( waitingChild . cancelled , 0 )
end
end
end
end
settleAgainstScope ( owner )
if child . status == "failed" then
error ( child . problem , 0 )
end
if child . status == "cancelled" then
error ( child . cancelled , 0 )
end
const answer = child . values

return unpack ( answer . values , 1 , answer . count )
end







local function occupied ( owner ) 
return owner . live + owner . forks - owner . lent
end

















local function awaitSlot ( owner , operation ) 
const limit = owner . limit
if limit == nil then
return false
end

const function roomOrNothingToDrive ( ) 
return ( owner . live + owner . forks - owner . lent ) < limit or owner . failed or owner . live == 0
end

while ( owner . live + owner . forks - owner . lent ) >= limit and not owner . failed do
if owner . live > 0 then
if drivesScope ( owner ) then
pump ( owner , operation , roomOrNothingToDrive )
else
settleAgainstScope ( owner )

return true
end
else
const workerScope = owner . workerScope
if workerScope == nil then
return false
end
if not workerScope : _settleOldest ( ) then
return false
end
end
end
settleAgainstScope ( owner )

return false
end









local function lendSlot ( owner , operation ) 
const child = activeChild
const limit = owner . limit

const function subscribe ( resume , _ ) 
owner . slotWaiters [ # owner . slotWaiters + 1 ] = resume

return function ( ) 
for index = # owner . slotWaiters , 1 , -1 do
if owner . slotWaiters [ index ] == resume then
table . remove ( owner . slotWaiters , index )

do break end
end
end
end
end

child . lending = true
owner . lent = owner . lent + 1
while ( owner . live + owner . forks - owner . lent ) >= limit and not owner . failed do
suspension . suspend ( operation , subscribe )
if child . requested then
do break end
end
end
child . lending = false
owner . lent = owner . lent - 1
if child . requested then
error ( child . cancelled , 0 )
end
end






local function admit ( owner , name ) 
settleAgainstScope ( owner )

return awaitSlot ( owner , name )
end

local function spawnRaw ( owner , name , body , arguments ) 




const child = {
thread = nil ,
name = name ,
scope = owner ,
openScopes = nil ,
status = "queued" ,
values = nil ,
problem = nil ,
cancelled = nil ,
requested = false ,
reason = nil ,
entered = false ,
runnable = false ,
release = nil ,
lending = false ,
waiters = { } ,
}
child . release = function ( ) 
taskownership . release ( body )
end
if owner . closed then
releaseUncalled ( child )
error ( "nupp: the task scope is closed" , 2 )
end
const admitted , lends = pcall ( admit , owner , name )
if not admitted then
releaseUncalled ( child )
error ( lends , 0 )
end
const co = suspensionHost . create ( function ( ) local __nuppT62;


if child . requested then
releaseUncalled ( child )
error ( child . cancelled , 0 )
end
child . release = nil
local produced
do
do const  __nuppT81= suspensionHost . install ( owner . handler ) ; __nuppT62=__nuppT62 or {} ; local __nuppT82=__nuppT62[1]; if not __nuppT82 then __nuppT82=function(handling) do
child . entered = true
if arguments ~= nil then
produced = pack ( body ( unpack ( arguments . values , 1 , arguments . count ) ) )
else
produced = pack ( body ( ) )
end end; return "normal" end; __nuppT62[1]=__nuppT82 end; const __nuppT76,__nuppT77,__nuppT78=__nuppT68(__nuppT82,__nuppT64,__nuppT81); const __nuppT75=1; local __nuppT79={}; local __nuppT80=0; if __nuppT75>=1 then  local __nuppT83,__nuppT84=__nuppT67(__nuppCleanup1,__nuppT81);  if not __nuppT83 then __nuppT80=__nuppT80+1; __nuppT79[__nuppT80]=__nuppT84 end; end; if not __nuppT76 then if __nuppT80>0 then __nuppT69(__nuppT65(__nuppT77,__nuppT79,1),0) else __nuppT69(__nuppT77,0) end end; if __nuppT80>0 then if __nuppT80>1 then __nuppT69(__nuppT65(__nuppT79[1],__nuppT79,2),0) else __nuppT69(__nuppT79[1],0) end end; if __nuppT77=="return" then  return __nuppT70(__nuppT78,1,__nuppT78.n)  end; end
end

return produced
end )
child . thread = co
link ( owner , child )
owner . live = owner . live + 1



const cancelled = owner . cancellation
if cancelled ~= nil then
child . requested = true
child . cancelled = cancelled
end
markRunnable ( owner , child )
if lends == true then
lendSlot ( owner , name )
end

return child
end

local function spawnChild ( owner , name , body , arguments ) 
return newTask ( owner , spawnRaw ( owner , name , body , arguments ) )
end

local function workersImpl ( owner ) 
if owner . workerScope == nil then
if workerModule == nil then
error ( "nupp: a task scope cannot fork: no worker provider is available" , 2 )
end
local observer = {
created = function ( _ , _ ) 
owner . forks = owner . forks + 1
end ,
settled = function ( _ , _ , status , problem ) 
owner . forks = owner . forks - 1
if status == "failed" then
local failure = "nupp: worker task failed: " .. tostring ( problem )
ownFailure ( owner , failure )
requestCancellation ( owner , "worker task" , "a sibling failed" )
end
wakeSlots ( owner )
end ,
}
owner . settleHook = workerModule . settle
owner . workerScope = workerModule . openScope ( owner . deadline , observer )
end

return owner . workerScope
end









local ForkMT = { }
ForkMT . __index = ForkMT

function ForkMT . isDone ( self ) 
return ( self . _task ) : isDone ( )
end

function ForkMT . status ( self ) 
return ( self . _task ) : status ( )
end

function ForkMT . cancel ( self , reason ) 
return ( self . _task ) : cancel ( reason )
end

function ForkMT . await ( self ) 
const owner = self . _owner
settleAgainstScope ( owner )
const status , values , count , problem = (
owner . settleHook
) ( self . _task )




deadlinePassed ( owner )
settleAgainstScope ( owner )
if status == "failed" or status == "cancelled" then
error ( problem , 0 )
end

return unpack ( values , 1 , count )
end

local function forkImpl ( scope , fn , ... ) 
const owner = ( ( scope ) . _state )
if owner . closed then
error ( "nupp: the task scope is closed" , 2 )
end
settleAgainstScope ( owner )
const workerScope = workersImpl ( owner )
const lends = awaitSlot ( owner , "a worker task" )


const task = workerScope : spawn ( fn , ... )
if lends then
lendSlot ( owner , "a worker task" )
end

return setmetatable ( { _owner = owner , _task = task , } , ForkMT )
end

local function cancelImpl ( owner , reason ) 
if owner . closed then
error ( "nupp: the task scope is closed" , 2 )
end
owner . deliberate = true
requestCancellation ( owner , "the task scope" , reason )
end

local spawnSurface




local spawnNamedSurface




local forkSurface




local cancelSurface
do




spawnSurface = function ( scope , body , ... ) 
return spawnChild ( ( ( scope ) . _state ) , "a task" , body , select ( "#" , ... ) > 0 and pack ( ... ) or nil )
end
spawnNamedSurface = function ( scope , body , name ) 
return spawnChild ( ( ( scope ) . _state ) , name , body , nil )
end
forkSurface = forkImpl
cancelSurface = function ( scope , reason ) 
cancelImpl ( ( ( scope ) . _state ) , reason )
end
end



































do
tasks . Scope . spawn = spawnSurface
end

do
tasks . Scope . _spawnNamed = spawnNamedSurface
end





















do
tasks . Scope . fork = forkSurface
end



















do
tasks . Scope . cancel = cancelSurface
end



















function tasks . checkpoint ( ) 
local namespace = _G . nupp
local workerCheckpoint = type ( namespace ) == "table" and rawget ( namespace , "__workerCheckpoint" ) or nil
if type ( workerCheckpoint ) == "function" then
local requested , deadline = workerCheckpoint ( )
if requested then
error ( cancellation ( "worker task" , deadline and "its deadline passed" or nil ) , 0 )
end
end
const owner = currentScope ( )
if owner == nil then
return
end
deadlinePassed ( owner )
const child = activeChild
if child ~= nil and child . requested then
error ( child . cancelled , 0 )
end
const cancelled = owner . cancellation
if cancelled ~= nil then
error ( cancelled , 0 )
end
end







function tasks . deadline ( ) 
const owner = currentScope ( )
if owner == nil then
return nil
end

return owner . deadline
end






local function draining ( child ) 
const opened = child . openScopes
if opened ~= nil then
for index = 1 , # opened do
if ( opened [ index ] ) . settling then
return true
end
end
end

return false
end

local function newState ( deadline , limit ) 
const owner = {
first = nil ,
last = nil ,
queue = { } ,
head = 1 ,
tail = 0 ,
ready = 0 ,
stale = 0 ,
onSettle = nil ,
live = 0 ,
failure = nil ,
suppressed = nil ,
failed = false ,
cancellation = nil ,
deadline = deadline ,
handler = nil ,
wakers = { } ,
settling = false ,
workerScope = nil ,
settleHook = nil ,
limit = limit ,
forks = 0 ,
lent = 0 ,
slotWaiters = { } ,
closed = false ,
deliberate = false ,
soft = false ,
openedIn = nil ,
openedRoot = nil ,
frame = nil ,
}



const outerCanPark = suspensionHost . delegatedCanPark ( )
owner . handler = _G.setmetatable({ park =
function ( _ , waiting , cancel ) 
const child = activeChild
const scopeOwner = activeScope

const function ready ( ) 
markRunnable ( scopeOwner , child )
end

while not waiting : ready ( ) do
waiting : onResume ( ready )
if waiting : ready ( ) then
do break end
end
coroutine . yield ( )



if child . requested and not draining ( child ) then
cancel ( )
error ( child . cancelled , 0 )
end
end
end ,  canPark =
function ( _ ) 
return outerCanPark ( )
end ,  shutdown =
function ( _ ) 
end }, suspensionHost.Handler)


return owner
end


local function settle ( owner ) 
if owner . failed then
requestCancellation ( owner , "the task scope" , "the scope is unwinding" )
end
owner . settling = true



pump ( owner , "the task scope" , function ( ) 
return owner . live == 0
end )
local workerScope = owner . workerScope
if workerScope ~= nil then
local ok , problem = pcall ( workerScope . close , workerScope )
owner . workerScope = nil
if not ok and not owner . failed then
ownFailure ( owner , problem )
end
end
owner . settling = false
end



local function registerOpen ( owner ) 
const child = activeChild
if child ~= nil then
local opened = child . openScopes
if opened == nil then
opened = { }
child . openScopes = opened
end
opened [ # opened + 1 ] = owner
owner . openedIn = child
else
const key = ( coroutine . running ( ) or mainRoot )
local opened = rootOpen [ key ]
if opened == nil then
opened = { }
rootOpen [ key ] = opened
end
opened [ # opened + 1 ] = owner
owner . openedRoot = key
end
end

local function unregisterOpen ( owner ) 
const child = owner . openedIn
const key = owner . openedRoot
const stack = ( child ~= nil and child . openScopes or rootOpen [ key ] )
if stack == nil then
return
end
for index = # stack , 1 , -1 do
if stack [ index ] == owner then
table . remove ( stack , index )

do break end
end
end
if child == nil and # stack == 0 then
rootOpen [ key ] = nil
end
end










local function closeScope ( owner ) 
if owner . closed then
return
end
const drained , problem = pcall ( settle , owner )



owner . settling = false
unregisterOpen ( owner )
const frame = owner . frame
if frame ~= nil then
owner . frame = nil
frame : close ( )
end
if not drained then
error ( problem , 0 )
end
owner . closed = true
if owner . failed then
const suppressed = owner . suppressed
if suppressed ~= nil then
error ( withSuppressed ( owner . failure , suppressed ) , 0 )
end
error ( owner . failure , 0 )
end
const cancelled = owner . cancellation
if cancelled ~= nil and not owner . deliberate then
error ( cancelled , 0 )
end
end





















do


tasks . Scope . close = function ( scope ) 
closeScope ( ( ( scope ) . _state ) )
end
end









































local function openState ( limit , timeoutMs ) 
if limit ~= nil and ( limit < 1 or limit ~= math . floor ( limit ) ) then
error ( "nupp: a task scope limit must be a positive integer" , 3 )
end
local absolute = nil
if timeoutMs ~= nil then
if timeoutMs ~= timeoutMs or timeoutMs < 0 or timeoutMs == math . huge then
error ( "nupp: a task scope timeout must be a finite non-negative number" , 3 )
end
absolute = timeModule . now ( ) + timeoutMs
end
const inherited = tasks . deadline ( )
if inherited ~= nil and ( absolute == nil or inherited < absolute ) then
absolute = inherited
end
const owner = newState ( absolute , limit )
registerOpen ( owner )



do local __nuppT113=0; local  __nuppT119 ; local __nuppT120=false ; local __nuppT114,__nuppT115,__nuppT116=__nuppT68(function() do local __nuppT121= suspensionHost . installDriver ( frameHandler ( owner ) ) ; __nuppT119= __nuppT121 ; __nuppT113=1;  __nuppT120=true;  local handling=__nuppT119;
owner . frame = (function() __nuppT120=false; return  handling  end)()

return "return",__nuppT63( owner ) end; return "normal" end,__nuppT64); local __nuppT117={}; local __nuppT118=0; if __nuppT113>=1 and __nuppT120 then  local __nuppT122,__nuppT123=__nuppT67(__nuppCleanup1,__nuppT119);  if not __nuppT122 then __nuppT118=__nuppT118+1; __nuppT117[__nuppT118]=__nuppT123 end; end; if not __nuppT114 then if __nuppT118>0 then __nuppT69(__nuppT65(__nuppT115,__nuppT117,1),0) else __nuppT69(__nuppT115,0) end end; if __nuppT118>0 then if __nuppT118>1 then __nuppT69(__nuppT65(__nuppT117[1],__nuppT117,2),0) else __nuppT69(__nuppT117[1],0) end end; if __nuppT115=="return" then  return __nuppT70(__nuppT116,1,__nuppT116.n)  end; end
end

function tasks . open ( limit , timeoutMs ) 
return setmetatable ( { _state = openState ( limit , timeoutMs ) , } , ScopeMT )
end





local function runImpl ( ... ) 
local limit = nil
local timeoutMs = nil
local body
if select ( "#" , ... ) == 1 then
body = ...
else
limit , timeoutMs , body = ...
end
const owner = openState ( limit , timeoutMs )
const scope = setmetatable ( { _state = owner , } , ScopeMT )
const answer = pack ( pcall ( body , scope ) )
if answer . values [ 1 ] == true then


closeScope ( owner )

return unpack ( answer . values , 2 , answer . count )
end
const problem = answer . values [ 2 ]



const scopeOwned = ( owner . failed and problem == owner . failure )
or ( owner . cancellation ~= nil and not owner . deliberate and problem == owner . cancellation )
if not scopeOwned and not owner . closed then


cancelImpl ( owner , "the body failed" )
end
const settled , settleProblem = pcall ( closeScope , owner )
if settled or settleProblem == problem then
error ( problem , 0 )
end
if scopeOwned and owner . failed and problem == owner . failure then
error ( settleProblem , 0 )
end


error ( withSuppressed ( problem , pack ( settleProblem ) ) , 0 )
end


































local run



do


run = runImpl
end
tasks . run = run












local function familyScope ( ) 
const owner = newState ( tasks . deadline ( ) , nil )
owner . soft = true
registerOpen ( owner )

do local __nuppT127=0; local  __nuppT133 ; local __nuppT134=false ; local __nuppT128,__nuppT129,__nuppT130=__nuppT68(function() do local __nuppT135= suspensionHost . installDriver ( frameHandler ( owner ) ) ; __nuppT133= __nuppT135 ; __nuppT127=1;  __nuppT134=true;  local handling=__nuppT133;
owner . frame = (function() __nuppT134=false; return  handling  end)()

return "return",__nuppT63( owner ) end; return "normal" end,__nuppT64); local __nuppT131={}; local __nuppT132=0; if __nuppT127>=1 and __nuppT134 then  local __nuppT136,__nuppT137=__nuppT67(__nuppCleanup1,__nuppT133);  if not __nuppT136 then __nuppT132=__nuppT132+1; __nuppT131[__nuppT132]=__nuppT137 end; end; if not __nuppT128 then if __nuppT132>0 then __nuppT69(__nuppT65(__nuppT129,__nuppT131,1),0) else __nuppT69(__nuppT129,0) end end; if __nuppT132>0 then if __nuppT132>1 then __nuppT69(__nuppT65(__nuppT131[1],__nuppT131,2),0) else __nuppT69(__nuppT131[1],0) end end; if __nuppT129=="return" then  return __nuppT70(__nuppT130,1,__nuppT130.n)  end; end
end






local function enterBranches ( owner , bodies , count , branches ) 
for index = 1 , count do
branches [ index ] = spawnRaw ( owner , "branch " .. tostring ( index ) , bodies [ index ] , nil )
end
end













local function settleFamily ( owner , branches ) 
closeScope ( owner )
const values = { }
const errors = { }
for index , child in ipairs ( branches ) do
if child . status == "failed" then
errors [ index ] = child . problem
elseif child . status == "done" then
const produced = child . values
if produced . count > 1 then



errors [ index ] = ("nupp: branch %d returned %d values, and a family branch answers one") : format ( index , produced . count )
else
values [ index ] = produced . values [ 1 ]
end
end
end

return values , errors
end

































local function gatherImpl ( bodies ) 
local rawBodies
rawBodies = bodies
const count = # rawBodies
if count == 0 then
return { } , { }
end
const owner = familyScope ( )


const branches = { }
const entered , problem = pcall ( enterBranches , owner , rawBodies , count , branches )
const values , errors = settleFamily ( owner , branches )
if not entered then
error ( problem , 0 )
end

return values , errors
end

local gather

do


gather = gatherImpl
end
tasks . gather = gather




















local function raceImpl ( bodies ) 
local rawBodies
rawBodies = bodies
const count = # rawBodies
if count == 0 then
return nil , nil
end
const owner = familyScope ( )
const branches = { }
const positions = { }
local first = nil



owner . onSettle = function ( child ) 
if first == nil and ( child . status == "done" or child . status == "failed" ) then
first = positions [ child ]
end
end

const raced , problem = pcall ( function ( ) 
enterBranches ( owner , rawBodies , count , branches )
for index , child in ipairs ( branches ) do
positions [ child ] = index
end
pump ( owner , "a racing family" , function ( ) 
return first ~= nil or owner . live == 0
end )
end )
if raced and first ~= nil then


cancelImpl ( owner , "another branch settled first" )
end
const values , errors = settleFamily ( owner , branches )
if not raced then
error ( problem , 0 )
end
if first == nil then
return nil , nil
end
if errors [ first ] ~= nil then
error ( errors [ first ] , 0 )
end

return values [ first ] , first
end

local race

do


race = raceImpl
end
tasks . race = race








local function lifecycle ( scope ) 
const owner = ( ( scope ) . _state )
local listed = 0
local child = owner . first
while child ~= nil do
listed = listed + 1
child = child . after
end
const workerScope = owner . workerScope
const registered = workerModule ~= nil and rawget ( workerModule , "__registered" ) or nil
const pending = workerScope ~= nil and registered ~= nil and ( registered ) ( workerScope )
or 0

return {
live = owner . live ,
listed = listed ,
queued = owner . tail - owner . head + 1 ,
ready = owner . ready ,
forks = owner . forks ,
workers = pending ,
}
end

rawset ( tasks , "__lifecycle" , lifecycle )

local __nuppExportValue= tasks ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tasks"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tasks"]=__nuppExports;return __nuppExports