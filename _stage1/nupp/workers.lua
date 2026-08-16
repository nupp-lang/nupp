_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;

































local buffer = require ( "string.buffer" )














local native = require ( "nupp.workers.native" )
local suspension = require ( "nupp.suspension" )

local workers = { }









const Channel = {} Channel.__index = Channel






workers.Exit = {} workers.Exit.__index = workers.Exit











workers.Self = {} workers.Self.__index = workers.Self














workers.Worker = {} workers.Worker.__index = workers.Worker






































local ChannelMT = { __index = Channel }
local WorkerMT = { __index = workers . Worker }
local SelfMT = { __index = workers . Self }

local function channel ( handle , owned )
return setmetatable ( { handle = handle , owned = owned , destroyed = false } , ChannelMT )
end

local function newChannel ( )
local handle = native . channelCreate ( )
if handle == nil then
error ( "nupp: cannot create a worker channel" , 3 )
end

return channel ( handle , true )
end

local SENDABLE = { boolean = true , number = true , string = true , }



local function unsendable ( value , path , depth , seen )
local kind = type ( value )
if SENDABLE [ kind ] then
return nil
end



if kind ~= "table" then
return ( "%s is a %s" ) : format ( path , kind )
end
if getmetatable ( value ) ~= nil then
return ( "%s has a metatable" ) : format ( path )
end
if depth >= 32 then
return ( "%s nests deeper than 32 tables" ) : format ( path )
end
if seen [ value ] then
return ( "%s repeats a table already present in the message" ) : format ( path )
end
seen [ value ] = true
for key , item in pairs ( value ) do
if not SENDABLE [ type ( key ) ] then
return ( "%s has a %s key" ) : format ( path , type ( key ) )
end
local rejected = unsendable ( item , ( "%s[%s]" ) : format ( path , tostring ( key ) ) , depth + 1 , seen )
if rejected ~= nil then
return rejected
end
end

return nil
end

local function encode ( frame )
local rejected = unsendable ( frame , "message" , 0 , { } )
if rejected ~= nil then
error ( "nupp: cannot send to a worker: " .. rejected , 3 )
end

return buffer . encode ( frame )
end

local function decode ( bytes )
local ok , value = pcall ( buffer . decode , bytes )
if not ok or type ( value ) ~= "table" or type ( ( value ) [ "kind" ] ) ~= "string" then
error ( "nupp: a worker returned an invalid message frame" , 3 )
end

return value
end

local function push ( self , frame )
if self . destroyed or not native . channelPush ( self . handle , encode ( frame ) ) then
error ( "nupp: a worker channel is closed or its bounded queue is full" , 3 )
end
end

local function pop ( self , timeoutMs )
if self . destroyed then
return nil
end
local bytes = native . channelPop ( self . handle , timeoutMs )

return bytes ~= nil and decode ( bytes ) or nil
end

local function destroy ( self )
if self . destroyed or not self . owned then
return
end
self . destroyed = true
native . channelDestroy ( self . handle )
self . handle = nil
end

local function takeMessage ( self )
if self . _firstMessage > self . _lastMessage then
return nil
end
local value = self . _messages [ self . _firstMessage ]
self . _messages [ self . _firstMessage ] = nil
if self . _firstMessage == self . _lastMessage then
self . _firstMessage = 1
self . _lastMessage = 0
else
self . _firstMessage = self . _firstMessage + 1
end

return value
end

local function takeReply ( self , id )
local reply = self . _replies [ id ]
if reply ~= nil then
self . _replies [ id ] = nil
end

return reply
end



local function route ( self , timeoutMs )
local frame = pop ( self . _outbox , timeoutMs )
if frame == nil then
return false
end
if frame . kind == "reply" and frame . id ~= nil then
if self . _pendingIds [ frame . id ] then
self . _pendingIds [ frame . id ] = nil
self . _replies [ frame . id ] = frame
end
elseif frame . kind == "message" then
self . _lastMessage = self . _lastMessage + 1
self . _messages [ self . _lastMessage ] = frame . payload
else
error ( "nupp: a worker returned an unknown message frame" , 3 )
end

return true
end

local function ended ( self )
return native . channelClosed ( self . _outbox . handle ) and native . channelCount ( self . _outbox . handle ) == 0
end




local function waitFor (
self ,
operation ,
ready ,
timeoutMs
)
if ready ( ) then
return true
end
if timeoutMs ~= nil and timeoutMs == 0 then
return false
end
local deadline = timeoutMs ~= nil and native . now ( ) + timeoutMs or nil
if not suspension . handled ( ) then
while not ready ( ) do
local budget = - 1
if deadline ~= nil then
local remaining = math . ceil ( deadline - native . now ( ) )
if remaining <= 0 then
return false
end
budget = remaining
end
if not route ( self , budget ) and ended ( self ) then
return ready ( )
end
end

return true
end

local function subscribe ( resume , context )
local source = context : source ( "nupp.workers" , 50 , function ( )
local moved = route ( self , 0 )
if ready ( ) or ended ( self ) or deadline ~= nil and native . now ( ) >= deadline then
resume ( true )

return 1
end

return moved and 1 or 0
end )

return function ( )
source : release ( )
end
end

while not ready ( ) do
if ended ( self ) then
return false
end
if deadline ~= nil and native . now ( ) >= deadline then
return false
end
suspension . suspend ( operation , subscribe )
end

return true
end

function workers . Worker : send ( value )
if self . _closed or self . _exit ~= nil then
error ( "nupp: cannot send to a closed worker" , 2 )
end
local rejected = unsendable ( value , "value" , 0 , { } )
if rejected ~= nil then
error ( "nupp: cannot send to a worker: " .. rejected , 2 )
end
push ( self . _inbox , { kind = "message" , payload = value } )
end

function workers . Worker : tryReceive ( )
local value = takeMessage ( self )
if value ~= nil then
return value
end
while route ( self , 0 ) do
value = takeMessage ( self )
if value ~= nil then
return value
end
end

return nil
end

function workers . Worker : receive ( timeoutMs )
if timeoutMs ~= nil and ( timeoutMs < 0 or math . floor ( timeoutMs ) ~= timeoutMs ) then
error ( "nupp: worker receive timeout must be a nonnegative integer" , 2 )
end
local value = self : tryReceive ( )
if value ~= nil then
return value
end
waitFor (
self ,
"worker receive" ,
function ( )
return self . _firstMessage <= self . _lastMessage
end ,
timeoutMs
)

return takeMessage ( self )
end

function workers . Worker : call ( value )
if self . _closed or self . _exit ~= nil then
error ( "nupp: cannot call a closed worker" , 2 )
end
local rejected = unsendable ( value , "value" , 0 , { } )
if rejected ~= nil then
error ( "nupp: cannot call a worker: " .. rejected , 2 )
end
local id = self . _nextId
if id > 9007199254740991 then
error ( "nupp: worker request identifiers are exhausted" , 2 )
end
self . _nextId = id + 1
self . _pendingIds [ id ] = true
push ( self . _inbox , { kind = "request" , id = id , payload = value } )
waitFor ( self , "worker call" , function ( )
return self . _replies [ id ] ~= nil
end )
local reply = takeReply ( self , id )
if reply == nil then
self . _pendingIds [ id ] = nil
local exit = self : join ( )
error ( exit . error or "nupp: worker ended before replying" , 2 )
end
if reply . ok ~= true then
error ( "nupp: worker call failed: " .. ( reply . error or "without saying why" ) , 2 )
end

return reply . payload
end

function workers . Worker : close ( )
if self . _closed then
return
end
self . _closed = true
native . channelClose ( self . _inbox . handle )
end

function workers . Worker : join ( )
if self . _exit ~= nil then
return self . _exit
end
if suspension . handled ( ) and not native . workerFinished ( self . _handle ) then
suspension . suspend ( "worker join" , function ( resume , context )
local source = context : source ( "nupp.workers.join" , 50 , function ( )
if native . workerFinished ( self . _handle ) then
resume ( true )

return 1
end

return 0
end )

return function ( )
source : release ( )
end
end )
end
local status , failure = native . workerJoin ( self . _handle )
self . _handle = nil
self . _exit = setmetatable({ succeeded =  status == 0 ,  status =  status ,  error =  failure }, workers.Exit)

return self . _exit
end

function workers . Worker : stop ( )
if self . _destroyed then
return self . _exit
end
self : close ( )
local exit = self : join ( )
destroy ( self . _inbox )
destroy ( self . _outbox )
self . _destroyed = true

return exit
end

function workers . Worker . drop ( self )
self : stop ( )
end

function workers . destroyWorker ( self )
self : drop ( )
end ;__nuppCleanups["nupp.workers#workers.destroyWorker"]=workers.destroyWorker

local function receiveSelf ( self )
return pop ( self . inbox , - 1 )
end

function workers . Self : receive ( )
local frame = receiveSelf ( self )

return frame and frame . payload or nil
end

function workers . Self : send ( value )
local rejected = unsendable ( value , "value" , 0 , { } )
if rejected ~= nil then
error ( "nupp: cannot send from a worker: " .. rejected , 2 )
end
push ( self . outbox , { kind = "message" , payload = value } )
end

function workers . Self : serve ( handler )
while true do
local frame = receiveSelf ( self )
if frame == nil then
return
end
local ok , answer = pcall ( handler , frame . payload )
if frame . kind == "request" and frame . id ~= nil then
if ok then
local rejected = unsendable ( answer , "result" , 0 , { } )
if rejected == nil then
push ( self . outbox , { kind = "reply" , id = frame . id , ok = true , payload = answer } )
else
push ( self . outbox , {
kind = "reply" ,
id = frame . id ,
ok = false ,
error = "a call result cannot cross: " .. rejected ,
} )
end
else
push ( self . outbox , { kind = "reply" , id = frame . id , ok = false , error = tostring ( answer ) , } )
end
end
end
end





function workers . spawn ( entry ) __nuppCleanups["nupp.workers#workers.destroyWorker"]=workers.destroyWorker;
if type ( entry ) ~= "string" or entry == "" then
error ( "nupp: a worker entry must be a nonempty module name" , 2 )
end
local inbox = newChannel ( )
local outbox = newChannel ( )
local handle , problem = native . workerSpawn ( entry , inbox . handle , outbox . handle )
if handle == nil then
destroy ( inbox )
destroy ( outbox )
error ( "nupp: cannot spawn worker: " .. ( problem or "unknown failure" ) , 2 )
end

return setmetatable (
{
_handle = handle ,
_inbox = inbox ,
_outbox = outbox ,
_closed = false ,
_destroyed = false ,
_exit = nil ,
_nextId = 1 ,
_pendingIds = { } ,
_replies = { } ,
_messages = { } ,
_firstMessage = 1 ,
_lastMessage = 0 ,
} ,
WorkerMT
)
end



function workers . current ( )
local inbox , outbox = native . current ( )
if inbox == nil or outbox == nil then
error ( "nupp: workers.current is only valid inside a worker" , 2 )
end

return setmetatable ( { inbox = channel ( inbox , false ) , outbox = channel ( outbox , false ) , } , SelfMT )
end

workers . Worker = workers . Worker
workers . Self = workers . Self
workers . Exit = workers . Exit

return workers
