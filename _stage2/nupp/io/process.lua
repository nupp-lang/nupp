_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;

































local suspension = require ( "nupp.suspension" )
local processtypes = require ( "nupp.io.processtypes" )

local process = { }
















local READ_LIMIT = 65536

local progressed , releasePump , await , awaitTick , pumpOnce , readForCompletion




local defaultBackend = nil



























process.Reader = {} process.Reader.__index = process.Reader









function process.Reader:isEOF()
return self . eof
end


function process.Reader:isClosed()
return self . closed
end











function process.Reader:release()
if self . closed then
return
end





local ok , released , why = pcall ( function ( )
return self . owner . backend : closeStream ( self . handle )
end )
if not ok then
self . closed = true
error (
(
"nupp: closing a process stream raised: %s"
) : format ( released == nil and "without saying why" or tostring ( released ) ) ,
0
)
end


self . closed = released == true
if why == nil and released ~= true then



why = "the platform did not release the descriptor and did not say why"
end
if why ~= nil then



error ( ( "nupp: could not close a process stream: %s" ) : format ( why ) , 0 )
end
end


















function process.Reader:poll(limit)
if self . closed or self . eof then
return nil
end
local wanted = limit or READ_LIMIT
if wanted < 1 then
wanted = 1
end
local got = self . owner . backend : read ( self . handle , wanted )
if got == nil then
self . eof = true

return nil
end

return got
end



function process.Reader:next()
if self . closed or self . eof then
return nil
end
local chunk = nil
await (
self . owner ,
"process stream read" ,
function ( )
if self . closed or self . eof then
return true
end
local got = self : poll ( )
if got == nil then
return true
end
if # got > 0 then
chunk = got

return true
end

return false
end ,
function ( )



return setmetatable({ child =  self . owner . handle ,  read =  { self . handle } ,  write =  { } }, processtypes.Interest)
end
)

return chunk
end



function process.Reader:setTimeout(timeoutMs)
if timeoutMs < 0 or timeoutMs > 2147483647 or math . floor ( timeoutMs ) ~= timeoutMs then
error ( "nupp: process reader timeout must be 0 through 2147483647 milliseconds" , 2 )
end
self . timeoutMs = timeoutMs
end

function process.Reader:read(count)
if self . closed then
return nil , "the process reader is closed"
end
local chunk , reason = readForCompletion ( self , count < 1 and 1 or count )
if reason ~= nil then
return nil , reason
end

return chunk or ""
end

function process.Reader:readInto(destination, offset, count)
local at = offset or 0
local wanted = count or READ_LIMIT
if at < 0 or wanted < 0 then
error ( "nupp: process reader destination offset and count must not be negative" , 2 )
end
if wanted == 0 then
return 0
end
local chunk , reason = self : read ( wanted )
if chunk == nil then
return nil , reason
end
if # chunk == 0 then
return 0
end
destination : setString ( chunk , at )

return # chunk
end

function process.Reader:transferTo(destination)
local total = 0
while true do
local chunk , reason = self : read ( READ_LIMIT )
if chunk == nil then
return nil , reason
end
if # chunk == 0 then
return total
end
local wrote , failure = destination : write ( chunk )
if not wrote then
return nil , failure
end
total = total + # chunk
end
end

function process.Reader:close()
local ok , problem = pcall ( function ( )
self : release ( )
end )
if not ok then
return false , problem == nil and "the process reader could not close" or tostring ( problem )
end

return true
end








process.Writer = {} process.Writer.__index = process.Writer















function process.Writer:isGone()
return self . gone
end


function process.Writer:isClosed()
return self . closed
end







function process.Writer:release()
if self . closed then
return
end





local ok , released , why = pcall ( function ( )
return self . owner . backend : closeStream ( self . handle )
end )
if not ok then
self . closed = true
error (
(
"nupp: closing a process stream raised: %s"
) : format ( released == nil and "without saying why" or tostring ( released ) ) ,
0
)
end


self . closed = released == true
if why == nil and released ~= true then



why = "the platform did not release the descriptor and did not say why"
end
if why ~= nil then



error ( ( "nupp: could not close a process stream: %s" ) : format ( why ) , 0 )
end
end



function process.Writer:offer(data)
if self . closed or self . gone or # data == 0 then
return 0
end
local sent , gone = self . owner . backend : write ( self . handle , data )
if gone then



self . gone = true
end

return sent
end



function process.Writer:send(data, stopAt, stallFor)
if self . closed or self . gone then
return 0
end
local sent = 0
local before = 0
local function interest ( )


return setmetatable({ child =  self . owner . handle ,  read =  { } ,  write =  { self . handle } }, processtypes.Interest)
end





local function offered ( )
if self . closed or self . gone then
return true
end
sent = sent + self : offer ( data : sub ( sent + 1 ) )





return sent > before
end

while sent < # data and not self . closed and not self . gone do
before = sent
local completed = await ( self . owner , "process stream write" , offered , interest , stopAt )
if not completed then
break
end
if sent > before and stallFor ~= nil then
stopAt = self . owner . backend : now ( ) + stallFor
end
end

return sent
end



function process.Writer:setTimeout(timeoutMs)
if timeoutMs < 0 or timeoutMs > 2147483647 or math . floor ( timeoutMs ) ~= timeoutMs then
error ( "nupp: process writer timeout must be 0 through 2147483647 milliseconds" , 2 )
end
self . timeoutMs = timeoutMs
end

function process.Writer:write(bytes)
if self . closed then
return false , "the process writer is closed"
end
if self . gone then
return false , "the child is no longer reading this stream"
end
local stopAt = self . owner . backend : now ( ) + self . timeoutMs
local ok , sent = pcall ( function ( )
return self : send ( bytes , stopAt , self . timeoutMs )
end )
if not ok then
return false , tostring ( sent )
end
if sent ~= # bytes then
if self . gone then
return false , "the child stopped reading before every byte was written"
end
return false , "the process write timed out"
end

return true
end

function process.Writer:writeFrom(source, offset, count)
local at = offset or 0
local length = source : length ( )
local wanted = count == nil and length - at or count
if at < 0 or wanted < 0 or at + wanted > length then
error ( "nupp: process writer buffer range is outside the source" , 2 )
end
local wrote , reason = self : write ( source : getString ( at , wanted ) )
if not wrote then
return nil , reason
end

return wanted
end

function process.Writer:writeView(source, offset, count)
local at = offset or 0
local length = source : length ( )
local wanted = count == nil and length - at or count
if at < 0 or wanted < 0 or at + wanted > length then
error ( "nupp: process writer byte-view range is outside the source" , 2 )
end
local bytes = source : getString ( ) : sub ( at + 1 , at + wanted )
local wrote , reason = self : write ( bytes )
if not wrote then
return nil , reason
end

return wanted
end

function process.Writer:flush()
if self . closed then
return false , "the process writer is closed"
end
if self . gone then
return false , "the child is no longer reading this stream"
end

return true
end

function process.Writer:close()
local ok , problem = pcall ( function ( )
self : release ( )
end )
if not ok then
return false , problem == nil and "the process writer could not close" or tostring ( problem )
end

return true
end



function process . asReader ( source )
return source
end


function process . asWriter ( source )
return source
end


process.Process = {} process.Process.__index = process.Process













































function process.Process:isRunning()
if self . exit ~= nil then
return false
end
progressed ( self )

return self . exit == nil
end


function process.Process:wait()
await (
self ,
"process wait" ,
function ( )
return self . exit ~= nil
end ,
function ( )




return setmetatable({ child =  self . handle ,  read =  { } ,  write =  { } }, processtypes.Interest)
end
)
if self . timedOut and self . exit ~= nil then
self . exit . timedOut = true
end

return self . exit
end


function process.Process:kill(force)
if self . exit ~= nil then
return true
end
local ok , problem = pcall ( function ( )
self . backend : kill ( self . handle , force == true )
end )
if not ok then
return false , problem == nil and "the process could not be terminated" or tostring ( problem )
end

return true
end






function process.Process:communicate(options)
local ok , answer = pcall ( function ( )
local given = options or { }
local input = given . input
local pending = input == nil and "" or type ( input ) == "string" and input or input : getString ( )
local maximum = given . maxOutputBytes or 268435456
if maximum < 0 then
error ( "nupp: process maximum output must not be negative" , 2 )
end
local stdin , stdout , stderr = self . stdin , self . stdout , self . stderr
local sent = 0
local out , err = { } , { }
local outputBytes = 0
local function inputDone ( )

return stdin == nil or stdin . closed or stdin . gone
end

local function outputDone ( )
return ( stdout == nil or stdout . eof or stdout . closed ) and ( stderr == nil or stderr . eof or stderr . closed )
end

local function idle ( )
return ( inputDone ( ) and outputDone ( ) ) or self . exit ~= nil and outputDone ( )
end





local function abandonInput ( )
if stdin ~= nil and not stdin . closed then
stdin : release ( )
end
end










local function interest ( )
local read = { }
if stdout ~= nil and not stdout . eof and not stdout . closed then
read [ # read + 1 ] = stdout . handle
end
if stderr ~= nil and not stderr . eof and not stderr . closed then
read [ # read + 1 ] = stderr . handle
end
local write = { }
if stdin ~= nil and not stdin . closed and sent < # pending then
write [ # write + 1 ] = stdin . handle
end

return setmetatable({ child =  self . handle ,  read =  read ,  write =  write }, processtypes.Interest)
end

while not ( inputDone ( ) and outputDone ( ) ) do
local moved = false
if stdin ~= nil and not stdin . closed then
if sent < # pending then
local wrote = stdin : offer ( pending : sub ( sent + 1 ) )
if wrote > 0 then
sent = sent + wrote
moved = true
end
end
if sent >= # pending then



stdin : release ( )
moved = true
end
end
if stdout ~= nil and not stdout . eof and not stdout . closed then
local chunk = stdout : poll ( )
if chunk == nil or # chunk > 0 then
if chunk ~= nil then
outputBytes = outputBytes + # chunk
if outputBytes > maximum then
self : kill ( true )
error ( "process output exceeds the configured maximum" , 0 )
end
out [ # out + 1 ] = chunk
end
moved = true
end
end
if stderr ~= nil and not stderr . eof and not stderr . closed then
local chunk = stderr : poll ( )
if chunk == nil or # chunk > 0 then
if chunk ~= nil then
outputBytes = outputBytes + # chunk
if outputBytes > maximum then
self : kill ( true )
error ( "process output exceeds the configured maximum" , 0 )
end
err [ # err + 1 ] = chunk
end
moved = true
end
end
if not moved then





if idle ( ) then
break
end
awaitTick ( self , "process communicate" , interest )
end
end

abandonInput ( )

return setmetatable({ output =
table . concat ( out ) ,  errorOutput =
table . concat ( err ) ,  exit =
self : wait ( ) }, processtypes.Result)

end )
if not ok then
return nil , answer == nil and "process communication failed without saying why" or tostring ( answer )
end

return answer
end





function process.Process:close()
if self . reaped then
return true
end
if self . closing then
local runner = coroutine . running ( )
if runner == self . closingBy then




return true
end

if not suspension . handled ( ) then





error (
"nupp: process close arrived from another coroutine while a teardown was "
.. "running, with no handler to schedule it" ,
0
)
end







await (
self ,
"process close" ,
function ( )
return not self . closing
end ,
function ( )
return setmetatable({ child =  self . handle ,  read =  { } ,  write =  { } }, processtypes.Interest)
end
)
if self . reaped then
return true
end


end
self . closing = true
self . closingBy = coroutine . running ( )








local firstError = nil
local function attempt ( step )
local ok , raised = pcall ( step )
if not ok and firstError == nil then



firstError = raised == nil and "a teardown step failed without saying why" or raised
end
end



if self . stdin ~= nil then
attempt ( function ( )
self . stdin : release ( )
end )
end
if self . stdout ~= nil then
attempt ( function ( )
self . stdout : release ( )
end )
end
if self . stderr ~= nil then
attempt ( function ( )
self . stderr : release ( )
end )
end
if self . exit == nil then
attempt ( function ( )


self . backend : kill ( self . handle , true )





await (
self ,
"process close" ,
function ( )
return self . exit ~= nil
end ,
function ( )
return setmetatable({ child =  self . handle ,  read =  { } ,  write =  { } }, processtypes.Interest)
end
)
end )
end
attempt ( function ( )
releasePump ( self )
end )







if not self . childReleased and self . exit ~= nil then





local ok , released , reason = pcall ( function ( )
return self . backend : reap ( self . handle )
end )
if not ok then


self . childReleased = true
if firstError == nil then
firstError = released == nil and "reaping the child failed without saying why" or released
end
else
self . childReleased = released == true
if reason ~= nil then
if firstError == nil then
firstError = reason
end
elseif released ~= true and firstError == nil then
firstError = "the platform did not release the child and did not say why"
end
end
end




self . closing = false
self . closingBy = nil



self . reaped = (
self . stdin == nil or self . stdin . closed
) and (
self . stdout == nil or self . stdout . closed
) and ( self . stderr == nil or self . stderr . closed ) and self . pump == nil and self . childReleased
if firstError ~= nil then
error ( firstError , 0 )
end

return true
end


function process . Process . drop ( self )
self : close ( )
end

function process . destroyProcess ( self )
self : drop ( )
end ;__nuppCleanups["nupp.io.process#process.destroyProcess"]=process.destroyProcess


progressed = function ( self )
local moved = 0
if self . exit == nil then
local ended = self . backend : poll ( self . handle )
if ended ~= nil then
self . exit = ended
moved = moved + 1
end
end

return moved
end


local function enforceDeadline ( self )




if self . deadline == nil or self . exit ~= nil or self . timedOut then
return false
end
if self . backend : now ( ) < self . deadline then
return false
end
self . timedOut = true
self . backend : kill ( self . handle , true )

return true
end





pumpOnce = function ( self )
local moved = progressed ( self )
if enforceDeadline ( self ) then
moved = moved + progressed ( self ) + 1
end

return moved
end


local function ensurePump ( self )
if self . pump ~= nil then
return
end
self . pump = suspension . source ( "nupp.io.process" , 50 , function ( )
return pumpOnce ( self )
end )
end

releasePump = function ( self )
if self . pump == nil then
return
end
self . pump : release ( )
self . pump = nil
end




local BLOCKING_WAIT_MS = 20
















local function blockOnce ( self , interest , stopAt )
local budget = BLOCKING_WAIT_MS
if self . deadline ~= nil then
local remaining = self . deadline - self . backend : now ( )
if remaining < budget then
budget = remaining > 0 and remaining or 0
end
end
if stopAt ~= nil then
local remaining = stopAt - self . backend : now ( )
if remaining < budget then
budget = remaining > 0 and remaining or 0
end
end
self . backend : waitReady ( interest , budget )
pumpOnce ( self )
end

awaitTick = function ( self , operation , interest )
if not suspension . handled ( ) then
blockOnce ( self , interest ( ) )

return
end
ensurePump ( self )
suspension . suspend ( operation , function ( resume , context )
local source = context : source ( "nupp.io.process.tick" , 50 , function ( )
pumpOnce ( self )


resume ( true )

return 1
end )

return function ( )
source : release ( )
end
end )
end


await = function (
self ,
operation ,
ready ,
interest ,
stopAt
)
if ready ( ) then
return true
end
if stopAt ~= nil and self . backend : now ( ) >= stopAt then
return false
end
if not suspension . handled ( ) then




while not ready ( ) do
if stopAt ~= nil and self . backend : now ( ) >= stopAt then
return false
end
blockOnce ( self , interest ( ) , stopAt )
end

return true
end
ensurePump ( self )

local function subscribe ( resume , context )
local source = context : source ( "nupp.io.process.wait" , 50 , function ( )
local moved = pumpOnce ( self )
if ready ( ) or stopAt ~= nil and self . backend : now ( ) >= stopAt or moved > 0 then
resume ( true )

return 1
end

return 0
end )

return function ( )
source : release ( )
end
end

while not ready ( ) do
if stopAt ~= nil and self . backend : now ( ) >= stopAt then
return false
end
pumpOnce ( self )
if ready ( ) then
return true
end
suspension . suspend ( operation , subscribe )
end

return true
end




readForCompletion = function ( source , limit )
if source . closed or source . eof then
return nil
end
local chunk = nil
local stopAt = source . owner . backend : now ( ) + source . timeoutMs
local completed = await (
source . owner ,
"process stream read" ,
function ( )
if source . closed or source . eof then
return true
end
local got = source : poll ( limit )
if got == nil then
return true
end
if # got > 0 then
chunk = got

return true
end

return false
end ,
function ( )
return setmetatable({ child =  source . owner . handle ,  read =  { source . handle } ,  write =  { } }, processtypes.Interest)
end ,
stopAt
)
if not completed then
return nil , "the process read timed out"
end

return chunk
end

local function newReader ( owner , handle )
if handle == nil then
return nil
end

return setmetatable({ owner =  owner ,  handle =  handle ,  closed =  false ,  eof =  false ,  timeoutMs =  30000 }, process.Reader)
end

local function newWriter ( owner , handle )
if handle == nil then
return nil
end

return setmetatable({ owner =  owner ,  handle =  handle ,  closed =  false ,  gone =  false ,  timeoutMs =  30000 }, process.Writer)
end





function process . useBackend ( backend )
defaultBackend = backend
end




local function validateOptions ( options )
local given = options
if type ( given . args ) ~= "table" or # given . args == 0 then
error ( "nupp: process args must contain a program" , 3 )
end
for index = 1 , # given . args do
if type ( given . args [ index ] ) ~= "string" then
error ( ( "nupp: process argument %d must be a string" ) : format ( index ) , 3 )
end
end
local streams = { pipe = true , inherit = true , null = true }
if given . stdin ~= nil and streams [ given . stdin ] ~= true then
error ( "nupp: process stdin must be pipe, inherit, or null" , 3 )
end
if given . stdout ~= nil and streams [ given . stdout ] ~= true then
error ( "nupp: process stdout must be pipe, inherit, or null" , 3 )
end
if given . stderr ~= nil and streams [ given . stderr ] ~= true and given . stderr ~= "stdout" then
error ( "nupp: process stderr must be pipe, inherit, null, or stdout" , 3 )
end
if given . timeoutMs ~= nil and (
type (
given . timeoutMs
) ~= "number" or given . timeoutMs < 0 or given . timeoutMs > 2147483647 or math . floor (
given . timeoutMs
) ~= given . timeoutMs
) then
error ( "nupp: process timeout must be 0 through 2147483647 milliseconds" , 3 )
end
end


local function fromSpawn (
backend ,
options ,
handle ,
inHandle ,
outHandle ,
errHandle ,
pid
) __nuppCleanups["nupp.io.process#process.destroyProcess"]=process.destroyProcess;
local self = setmetatable({ stdin =
nil ,  stdout =
nil ,  stderr =
nil ,  backend =
backend ,  handle =
handle ,  exit =
nil ,  reaped =
false ,  childReleased =
false ,  closing =
false ,  closingBy =
nil ,  pump =
nil ,  timedOut =
false ,  pid =
pid ,  deadline =


options . timeoutMs ~= nil and ( backend : now ( ) + options . timeoutMs ) or nil }, process.Process)

self . stdin = newWriter ( self , inHandle )
self . stdout = newReader ( self , outHandle )
self . stderr = newReader ( self , errHandle )

return self
end











function process . spawnOn (
backend ,
options
) __nuppCleanups["nupp.io.process#process.destroyProcess"]=process.destroyProcess;
validateOptions ( options )
local handle , inHandle , outHandle , errHandle , pid , problem = backend : spawn ( options )
if handle == nil then
error ( problem or "the process could not be started" , 2 )
end

return fromSpawn ( backend , options , handle , inHandle , outHandle , errHandle , pid )
end





function process . new ( options ) __nuppCleanups["nupp.io.process#process.destroyProcess"]=process.destroyProcess;
validateOptions ( options )
local backend = defaultBackend
if backend == nil then
local native = require ( "nupp.io.processnative" )
backend = native . new ( process . exited )
defaultBackend = backend
end

local handle , inHandle , outHandle , errHandle , pid , problem = ( backend ) : spawn ( options )
if handle == nil then
return nil , problem or "the process could not be started"
end

return fromSpawn ( backend , options , handle , inHandle , outHandle , errHandle , pid )
end





function process . exited ( exitCode , killed , timedOut )
return {
exitCode = exitCode ,
killed = killed ,
timedOut = timedOut ,
succeeded = function ( self )

return not self . killed and not self . timedOut and self . exitCode == 0
end ,
}
end

return process
