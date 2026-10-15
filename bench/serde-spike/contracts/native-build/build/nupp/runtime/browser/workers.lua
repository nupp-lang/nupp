_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















const _DYNAMIC_REQUIRES = "@requires-dynamically nothing"

local base64 = require ( "nupp.codec.base64" )
local browserEffects = require ( "nupp.runtime.browser.effects" )
local codec = require ( "nupp.runtime.browser.workercodec" )
local suspension = require ( "nupp.suspension" )
local cancellation = require ( "nupp.suspension.cancellation" )
local workers = { }

local contracts = require ( "nupp.workers.spi" )








local function pack ( ... ) 
return { values = { ... } , count = select ( "#" , ... ) }
end







local registeredSendables = rawget ( _G . nupp , "__workerSendables" )
if type ( registeredSendables ) ~= "table" then
registeredSendables = setmetatable ( { } , { __mode = "k" } )
rawset ( _G . nupp , "__workerSendables" , registeredSendables )
end
local sendableDescriptors = registeredSendables
local outlinedSendables = { }

local function sendableKey ( moduleName , member ) 
return moduleName .. "\0" .. member
end


local function defineSendable ( moduleName , member , fn ) 
outlinedSendables [ ( moduleName .. "\0" .. member ) ] = fn
end


local function describeSendable ( fn , moduleName , member , ... ) 
sendableDescriptors [ fn ] = { module = moduleName , member = member , captures = pack ( ... ) }
return fn
end

workers . defineSendable = defineSendable
workers . describeSendable = describeSendable




local scannedAddresses = setmetatable ( { } , { __mode = "k" } )

local function callableAddress ( fn ) 
local described = sendableDescriptors [ fn ]
if described ~= nil then
return described . module , described . member
end
local scanned = scannedAddresses [ fn ]
if scanned ~= nil then
return scanned [ 1 ] , scanned [ 2 ]
end
local found = { }
local loaded = package . loaded
for moduleName , moduleValue in pairs ( loaded ) do
if type ( moduleName ) == "string" and type ( moduleValue ) == "table" then
for member , value in pairs ( moduleValue ) do
if type ( member ) == "string" and value == fn then
found [ # found + 1 ] = moduleName .. "\0" .. member
end
end
end
end
table . sort ( found )
local address = found [ 1 ]
if address == nil then
return nil , nil
end
local moduleName , member = address : match ( "^(.-)%z(.*)$" )
scannedAddresses [ fn ] = { moduleName , member }

return moduleName , member
end


local TaskImpl = {} TaskImpl.__index = TaskImpl






























workers . Scope = contracts . Scope

local TaskMT = { __index = TaskImpl }
local ScopeMT = { __index = workers . Scope }




local MAX_UNSETTLED = 1024
local MAX_UNSETTLED_BYTES = 268435456



local DRAIN_WINDOW = 64

local unsettled = { }
local unsettledCount = 0
local unsettledBytes = 0
local nextTaskId = 1




local laneActive = false



local function answered ( item ) 
if item == nil then
error ( "nupp: the worker pool answered nothing" , 0 )
end
if item . ok ~= true then
error ( "nupp: worker scheduling failed: " .. tostring ( item . error ) , 0 )
end

return item . value
end


local function deliverStarts ( value ) 
for _ , id in ipairs ( value ~= nil and value . started or { } ) do
local task = unsettled [ id ]
if task ~= nil and task . _state == "queued" then
task . _state = "running"
end
end
end

local function notifySettled ( task ) 
local observer = task . _observer
if observer ~= nil and observer . settled ~= nil then
observer . settled ( observer , task , task . _state , task . _error or task . _cancelled )
end
end







local function enlist ( scope , task ) 
local last = scope . _last
task . _scope = scope
task . _listed = true
task . _before = last
task . _after = nil
if last ~= nil then
last . _after = task
else
scope . _first = task
end
scope . _last = task
scope . _registered = scope . _registered + 1
end

local function delist ( task ) 
if not task . _listed then
return
end
local scope = task . _scope
local before = task . _before
local after = task . _after
if before ~= nil then
before . _after = after
else
scope . _first = after
end
if after ~= nil then
after . _before = before
else
scope . _last = before
end
task . _listed = false
task . _before = nil
task . _after = nil
scope . _registered = scope . _registered - 1
end


local function leave ( task ) 
local state = task . _state
if state ~= "done" and state ~= "failed" and state ~= "cancelled" then
return
end
local observer = task . _observer
if state == "failed" and not task . _observed and ( observer == nil or observer . settled == nil ) then
return
end
delist ( task )
end


local function listed ( scope ) 
local tasks = { }
local task = scope . _first
while task ~= nil do
tasks [ # tasks + 1 ] = task
task = task . _after
end

return tasks
end

local function release ( task ) 
if unsettled [ task . _id ] == nil then
return
end
unsettled [ task . _id ] = nil
unsettledCount = unsettledCount - 1
unsettledBytes = unsettledBytes - ( task . _bytes )
end

local function settle ( task , value ) 
deliverStarts ( value )
if task . _state == "done" or task . _state == "failed" or task . _state == "cancelled" then
return
end
local status = value ~= nil and value . status or nil
if status == "done" then
local packed = codec . decode ( assert ( base64 . decode ( value . payload ) ) )
task . _values = packed . values
task . _count = packed . count
task . _state = "done"
elseif status == "cancelled" then
task . _cancelled = task . _cancelled
or cancellation . create ( "worker task" , value . deadline == true and "its deadline passed" or nil )
task . _state = "cancelled"
else
task . _error = value ~= nil and value . error or "worker task failed without an error"
task . _state = "failed"
end
release ( task )

notifySettled ( task )
leave ( task )
end



local function poolRequest ( payload , resume ) 
return browserEffects . request ( "workers" , payload , resume )
end
















local pendingSubmission = nil


local function submit ( entry ) 
local batch = pendingSubmission
if batch == nil then
batch = { operation = "submit" , tasks = { } , }
pendingSubmission = batch
local batchTasks = batch . tasks
poolRequest ( batch , function ( item ) 
pendingSubmission = nil
local value = item ~= nil and item . ok == true and item . value or nil
local refused = item ~= nil and item . error or "the worker pool refused a batch"
deliverStarts ( value )
for _ , rejected in ipairs ( value ~= nil and value . rejected or { } ) do
local task = unsettled [ rejected . task ]
if task ~= nil then
settle ( task , { status = "failed" , error = rejected . error , } )
end
end
if value ~= nil then
return
end

for _ , one in ipairs ( batchTasks ) do
local task = unsettled [ one . task ]
if task ~= nil then
settle ( task , { status = "failed" , error = refused , } )
end
end
end )
end
local tasks = batch . tasks
tasks [ # tasks + 1 ] = entry
end

function TaskImpl : isDone ( ) 
return self . _state == "done" or self . _state == "failed" or self . _state == "cancelled"
end

function TaskImpl : status ( ) 
return self . _state
end

function TaskImpl : cancel ( reason ) 
if self : isDone ( ) or self . _requested then
return false
end
self . _requested = true
self . _cancelled = cancellation . create ( "worker task" , reason )
poolRequest ( { operation = "cancel" , task = self . _id , reason = reason , } , function ( item ) 
deliverStarts ( item ~= nil and item . ok == true and item . value or nil )
end )

return true
end







local function ensureAwait ( task ) 
if task . _awaiting or task : isDone ( ) then
return
end
task . _awaiting = true
poolRequest ( { operation = "await" , task = task . _id , } , function ( item ) 
task . _answer = item
local waiters = task . _resume
if waiters ~= nil then
task . _resume = nil
for index = 1 , # waiters do
waiters [ index ] ( true )
end
end
end )
end


local function consume ( task ) 
local answer = task . _answer
task . _answer = nil
task . _awaiting = false
settle ( task , answered ( answer ) )
end



local function awaitSettlement ( task ) 
if task : isDone ( ) then
return
end
ensureAwait ( task )
if task . _answer == nil then


suspension . suspend ( "worker task" , function ( resume ) 
local waiters = task . _resume
if waiters == nil then
waiters = { }
task . _resume = waiters
end
waiters [ # waiters + 1 ] = resume

return function ( ) 
for index = # waiters , 1 , -1 do
if waiters [ index ] == resume then
table . remove ( waiters , index )
do break end
end
end
end
end )
end


if not task : isDone ( ) then
consume ( task )
end
end




local function settleForScope ( task ) 
task . _observed = true
awaitSettlement ( task )
leave ( task )
if task . _state == "failed" then
return "failed" , nil , 0 , "nupp: worker task failed: " .. ( task . _error or "unknown failure" )
end
if task . _state == "cancelled" then
return "cancelled" , nil , 0 , task . _cancelled
end

return "done" , task . _values , task . _count , nil
end

workers . settle = settleForScope

function TaskImpl : await ( ) 
self . _observed = true
awaitSettlement ( self )
leave ( self )
if self . _state == "failed" then
error ( "nupp: worker task failed: " .. ( self . _error or "unknown failure" ) , 2 )
end
if self . _state == "cancelled" then
error ( self . _cancelled , 2 )
end

return unpack ( self . _values , 1 , self . _count )
end

local function spawnImpl ( self , fn , ... ) 
if self . _closed then
error ( "nupp: cannot spawn into a closed worker scope" , 2 )
end
local moduleName , member = callableAddress ( fn )
if moduleName == nil or member == nil then
error ( "nupp: this function has no sendable module outline" , 2 )
end
local descriptor = sendableDescriptors [ fn ]
local captures = descriptor and descriptor . captures or pack ( )
local arguments = pack ( ... )
codec . validate ( captures , arguments )
local submitted = arguments
if captures . count > 0 then
submitted = { values = { } , count = captures . count + arguments . count }
for index = 1 , captures . count do
submitted . values [ index ] = captures . values [ index ]
end
for index = 1 , arguments . count do
submitted . values [ captures . count + index ] = arguments . values [ index ]
end
end
local payload = base64 . encode ( codec . encode ( submitted ) )
if unsettledCount >= 1024 or unsettledBytes + # payload > 268435456 then


error ( "nupp: a worker queue is full" , 2 )
end
local id = nextTaskId
nextTaskId = id + 1
local task = setmetatable (
{
_id = id ,
_state = "queued" ,
_values = { } ,
_count = 0 ,
_error = nil ,
_cancelled = nil ,
_bytes = # payload ,
_observed = false ,
_requested = false ,
_awaiting = false ,
_answer = nil ,
_resume = nil ,
_observer = self . _observer ,
_scope = nil ,
_listed = false ,
_before = nil ,
_after = nil ,
} ,
TaskMT
)
unsettled [ id ] = task
unsettledCount = unsettledCount + 1
unsettledBytes = unsettledBytes + # payload
submit ( { task = id , module = moduleName , member = member , payload = payload , deadline = self . _deadline , } )
enlist ( self , task )
if self . _observer ~= nil and self . _observer . created ~= nil then
self . _observer . created ( self . _observer , task )
end

return task
end

local spawnSurface




do
spawnSurface = spawnImpl
end





local function settleAll ( children , wait ) 




for index = 1 , math . min ( 64 , # children ) do
ensureAwait ( children [ index ] )
end
local firstFailure = nil
for index , task in ipairs ( children ) do
local ahead = children [ index + 64 ]
if ahead ~= nil then
ensureAwait ( ahead )
end
local observed = task . _observed == true
local ok , problem = pcall ( function ( ) 
wait ( task )
end )
if ok and not observed and task . _state == "failed" then
problem = "nupp: worker task failed: " .. ( task . _error or "unknown failure" )
ok = false
end
if not ok and not observed and firstFailure == nil then
firstFailure = problem
end
end

return firstFailure
end

local function closeScope ( self ) 
if self . _closed then
return
end
self . _closed = true
local firstFailure = settleAll ( listed ( self ) , awaitSettlement )
if firstFailure ~= nil then
error ( firstFailure , 2 )
end
end

local function cancelAllScope ( self , reason ) 
for _ , task in ipairs ( listed ( self ) ) do
task : cancel ( reason )
end
end




local function settleOldestScope ( self ) 
local task = self . _first
while task ~= nil and task : isDone ( ) do
task = task . _after
end
if task == nil then
return false
end
awaitSettlement ( task )
leave ( task )

return true
end

local function openScope ( deadline , observer ) 
if laneActive then
error ( "nupp: a worker task cannot open another worker scope" , 3 )
end

return setmetatable (
{
spawn = spawnSurface ,
close = closeScope ,
_cancelAll = cancelAllScope ,
_settleOldest = settleOldestScope ,
_first = nil ,
_last = nil ,
_registered = 0 ,
_closed = false ,
_deadline = deadline ,
_observer = observer ,
} ,
ScopeMT
)
end

workers . openScope = openScope


rawset ( workers , "__registered" , function ( scope ) 
return scope . _registered
end )






local function laneExchange ( payload ) 
local answer = suspension . suspend ( "worker lane" , function ( resume ) 
return browserEffects . request ( "lane" , payload , resume )
end )

return answered ( answer )
end

local checkpointCancelled = false
local checkpointDeadline = false

local function laneCheckpoint ( ) 
if checkpointCancelled then
return true , checkpointDeadline
end
local answer = laneExchange ( { operation = "checkpoint" , } )
checkpointCancelled = answer . cancelled == true
checkpointDeadline = answer . deadline == true

return checkpointCancelled , checkpointDeadline
end

local function workerFailure ( problem ) 
if cancellation . is ( problem ) then
return problem
end

return debug . traceback ( tostring ( problem ) , 2 )
end


local function runFrame ( frame ) 
checkpointCancelled = false
checkpointDeadline = false
local ok , answer = xpcall (
function ( ) 
local moduleName = frame . module
local member = frame . member
local moduleValue = require ( moduleName )
local callable = outlinedSendables [ ( moduleName .. "\0" .. member ) ]
or ( type ( moduleValue ) == "table" and ( moduleValue ) [ member ] or nil )
if type ( callable ) ~= "function" then
error ( ("%s.%s is not a registered sendable function") : format ( moduleName , member ) , 0 )
end
local arguments = codec . decode ( assert ( base64 . decode ( frame . payload ) ) )

return pack ( callable ( unpack ( arguments . values , 1 , arguments . count ) ) )
end ,
workerFailure
)
if not ok then
if cancellation . is ( answer ) then
local cancelled = answer
return {
operation = "reply" ,
task = frame . task ,
status = "cancelled" ,
deadline = cancelled . reason == "its deadline passed" ,
}
end

return { operation = "reply" , task = frame . task , status = "failed" , error = tostring ( answer ) , }
end
local produced = answer
local transfer = { seen = { } , records = nil , addresses = nil }
local rejected = codec . unsendable ( produced . values , "results" , 0 , transfer )
if rejected ~= nil then
return {
operation = "reply" ,
task = frame . task ,
status = "failed" ,
error = "results cannot be copied: " .. rejected ,
}
end

return { operation = "reply" , task = frame . task , status = "done" , payload = base64 . encode ( codec . encode ( produced ) ) , }
end






function workers . runScheduler ( ) 
laneActive = true
rawset ( _G . nupp , "__workerCheckpoint" , laneCheckpoint )
local reply = { operation = "next" }
while true do
local frame = laneExchange ( reply )
if frame == nil or frame . task == nil then
return
end
reply = runFrame ( frame )
end
end


local checked = workers

local __nuppExportValue= workers ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.workers"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.workers"]=__nuppExports;return __nuppExports