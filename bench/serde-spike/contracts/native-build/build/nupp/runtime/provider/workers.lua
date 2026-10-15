_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















const _DYNAMIC_REQUIRES = "@requires-dynamically nothing"

















local buffer = require ( "string.buffer" )
local suspension = require ( "nupp.suspension" )
local cancellation = require ( "nupp.suspension.cancellation" )

































local native = require ( "nupp.workers.native" )

assert ( type ( native . workerParallelism ) == "function" , "nupp: native worker scheduler is unavailable" )

rawset ( _G . nupp , "__workerCheckpoint" , native . workerTaskCheckpoint )

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





















local Channel = {} Channel.__index = Channel







local Lane = {} Lane.__index = Lane










local Scheduler = {} Scheduler.__index = Scheduler






local TaskImpl = {} TaskImpl.__index = TaskImpl




























workers . Scope = contracts . Scope

local ChannelMT = { __index = Channel }
local TaskMT = { __index = TaskImpl }
local ScopeMT = { __index = workers . Scope }





local function channel ( handle , owned ) 
return setmetatable ( { handle = handle , owned = owned , destroyed = false } , ChannelMT )
end

local function newChannel ( ) 
local handle = native . channelCreate ( )
if handle == nil then
error ( "nupp: cannot create a worker channel" , 3 )
end

return ( setmetatable ( { handle = handle , owned = true , destroyed = false } , ChannelMT ) )
end

local SENDABLE = { [ "nil" ] = true , boolean = true , number = true , string = true , }



local function recordAddress ( metatable ) 
local namespace = _G . nupp and rawget ( _G . nupp , "__workerRecords" )
local address = type ( namespace ) == "table" and namespace [ metatable ] or nil

return type ( address ) == "string" and address or nil
end

local heapModule = require ( "nupp.mem.heap" )
local heapArrayMovable = rawget ( heapModule , "__heapArrayMovable" )
local heapArrayParts = rawget ( heapModule , "__heapArrayParts" )
local heapArrayFromParts = rawget ( heapModule , "__heapArrayFromParts" )
local heapArrayFree = rawget ( heapModule , "__heapArrayFree" )

local sharedbytesModule = require ( "nupp.mem.sharedbytes" )
local regionParts = rawget ( sharedbytesModule , "__regionParts" )
local regionFromParts = rawget ( sharedbytesModule , "__regionFromParts" )
local sharedbytesNative = require ( "nupp.mem.sharedbytes.native" )




local function regionIntact ( region ) 
local handle , first , length = ( regionParts ) ( region )
local size = sharedbytesNative . length ( handle )

return type ( size ) == "number"
and type ( first ) == "number"
and type ( length ) == "number"
and first >= 1
and length >= 0
and first == math . floor ( first )
and length == math . floor ( length )
and first + length - 1 <= size
end





local function unsendable ( value , path , depth , state ) 
local kind = type ( value )
if SENDABLE [ kind ] then
return nil
end

if kind ~= "table" then
return ("%s is a %s") : format ( path , kind )
end
local metatable = getmetatable ( value )
if metatable ~= nil then
if metatable == ( _G . nupp and rawget ( _G . nupp , "__regionMetatable" ) ) then


if not regionIntact ( value ) then
return ("%s is a region whose extent lies outside its storage") : format ( path )
end
state . hasRegions = true

return nil
end
if metatable == ( _G . nupp and rawget ( _G . nupp , "__heapArrayMetatable" ) ) then





if ( heapArrayMovable ) ( value ) == nil then
return ("%s is a heap array that cannot move") : format ( path )
end
if state . seen [ value ] then
return ("%s repeats a table already present in the message") : format ( path )
end
state . seen [ value ] = true
state . hasMoved = true

return nil
end
local address = recordAddress ( metatable )
if address == nil then
return ("%s has a metatable") : format ( path )
end
local records = state . records
local prior = records ~= nil and records [ address ] or nil
if prior ~= nil and prior ~= metatable then
return ("%s has an ambiguous record metatable") : format ( path )
end
if prior == nil then
if records == nil then
records = { }
state . records = records
end
records [ address ] = metatable
local addresses = state . addresses
if addresses == nil then
addresses = { }
state . addresses = addresses
end
addresses [ # addresses + 1 ] = address
end
end
if depth >= 32 then
return ("%s nests deeper than 32 tables") : format ( path )
end
if state . seen [ value ] then
return ("%s repeats a table already present in the message") : format ( path )
end
state . seen [ value ] = true


for key , item in next , value do
local keyKind = type ( key )
if not SENDABLE [ keyKind ] then
return ("%s has a %s key") : format ( path , keyKind )
end
if not SENDABLE [ type ( item ) ] then
local rejected = unsendable ( item , ("%s[%s]") : format ( path , tostring ( key ) ) , depth + 1 , state )
if rejected ~= nil then
return rejected
end
end
end

return nil
end

local function validatedTaskTransfer ( captures , arguments ) 
local transfer = { seen = { } , records = nil , addresses = nil }
local rejectedCaptures = unsendable ( captures . values , "captures" , 0 , transfer )
if rejectedCaptures ~= nil then
error ( "nupp: cannot copy task captures: " .. rejectedCaptures , 3 )
end
local rejected = unsendable ( arguments . values , "arguments" , 0 , transfer )
if rejected ~= nil then
error ( "nupp: cannot copy task arguments: " .. rejected , 3 )
end

return transfer
end

local function resolveRecord ( address ) 
local moduleName , memberPath = address : match ( "^(.-)%z(.+)$" )
if moduleName == nil or moduleName == "" or memberPath == nil then
error ( "nupp: a worker value names an invalid record" , 3 )
end
for _ , path in ipairs ( { moduleName , memberPath } ) do
if path : sub ( 1 , 1 ) == "." or path : sub ( -1 ) == "." or path : find ( ".." , 1 , true ) then
error ( "nupp: a worker value names an invalid record" , 3 )
end
for member in path : gmatch ( "[^.]+" ) do
if not member : match ( "^[%a_][%w_]*$" ) then
error ( "nupp: a worker value names an invalid record" , 3 )
end
end
end
local value = require ( moduleName )
for member in memberPath : gmatch ( "[^.]+" ) do
if type ( value ) ~= "table" then
error ( "nupp: a worker value names an invalid record" , 3 )
end
value = ( value ) [ member ]
end
local namespace = _G . nupp and rawget ( _G . nupp , "__workerRecords" )
if type ( value ) ~= "table" or type ( namespace ) ~= "table" or namespace [ value ] ~= address then
error ( "nupp: a worker value names an unknown record" , 3 )
end

return value
end




local resolvedRecords = setmetatable ( { } , { __mode = "v" } )

local function resolveRecordCached ( address ) 
local metatable = resolvedRecords [ address ]
if metatable == nil then
metatable = resolveRecord ( address )
resolvedRecords [ address ] = metatable
end

return metatable
end

local noRecords = { }










local function channelCodec ( target ) 
local codec = target . codec
if codec ~= nil then
return codec
end
local count = native . channelDictCount ( target . handle )
local metatables = { }
local unresolved = nil
for index = 1 , count do
local address = native . channelDictAddress ( target . handle , index )
local resolved , metatable = pcall ( resolveRecordCached , address )
if resolved then
metatables [ index ] = metatable
else



local standIn = { }
metatables [ index ] = standIn
if unresolved == nil then
unresolved = { }
end
( unresolved ) [ standIn ] = tostring ( metatable )
end
end
codec = {
count = count ,
unresolved = unresolved ,
encoder = buffer . new ( {
metatable = metatables
} ) ,
decoder = buffer . new ( { metatable = metatables } ) ,
}
target . codec = codec

return codec
end

local function registerDictAddress ( target , address ) 
local registered = target . registered
if registered == nil then
registered = { }
target . registered = registered
end
if not registered [ address ] then
if native . channelDictRegister ( target . handle , address ) == nil then
error ( "nupp: a worker channel dictionary is full: one lane carries at most 256 record types" , 3 )
end
registered [ address ] = true
target . codec = nil
end
end

local function registerTransferRecords ( target , transfer ) 
local addresses = transfer . addresses
if addresses == nil then
return
end
for _ , address in ipairs ( addresses ) do
registerDictAddress ( target , address )
end
end

local function encodePacked ( target , packed ) 
if packed . count == 0 then
return 0 , ""
end
local encoder = channelCodec ( target ) . encoder
encoder : reset ( )
if packed . count == 1 then
encoder : encode ( packed . values [ 1 ] )
else
encoder : encode ( packed . values )
end

return packed . count , encoder : get ( )
end





local function readyCodec ( target ) 
local codec = channelCodec ( target )
if native . channelDictCount ( target . handle ) ~= codec . count then
target . codec = nil
codec = channelCodec ( target )
end

return codec
end




local function decodePacked ( target , count , bytes ) 
if count == 0 then
return { values = { } , count = 0 }
end
local decoder = readyCodec ( target ) . decoder
decoder : set ( bytes )
local value = decoder : decode ( )
if count == 1 then
return { values = { value } , count = 1 }
end

return { values = value , count = count }
end












local ATTACHMENT_TABLE = "__nuppAttachmentTable"









local function rewriteAttachments ( value , regionMT , arrayMT , state ) 
if type ( value ) ~= "table" then
return value
end
local metatable = getmetatable ( value )
if metatable ~= nil and metatable == regionMT then
local index = state . map [ value ]
if index == nil then
local handle , first , length = ( regionParts ) ( value )
local flat = state . flat
flat [ # flat + 1 ] = handle
flat [ # flat + 1 ] = first
flat [ # flat + 1 ] = length
state . count = state . count + 1
index = state . count
state . map [ value ] = index
end

return { __nuppRegion = index }
end
if metatable ~= nil and metatable == arrayMT then
local bytes , count , tag = ( heapArrayParts ) ( value )
if bytes == nil then
error ( "nupp: a heap array cannot move" , 0 )
end
local flat = state . flat
flat [ # flat + 1 ] = bytes
flat [ # flat + 1 ] = count
flat [ # flat + 1 ] = tag
state . count = state . count + 1
local moved = state . moved
if moved == nil then
moved = { }
state . moved = moved
end
moved [ # moved + 1 ] = bytes

return { __nuppMoved = state . count }
end
local copy = { }
for key , item in next , value do
copy [ key ] = rewriteAttachments ( item , regionMT , arrayMT , state )
end
setmetatable ( copy , metatable )




if rawget ( copy , "__nuppRegion" ) ~= nil
or rawget ( copy , "__nuppMoved" ) ~= nil
or rawget ( copy , "__nuppAttachmentTable" ) ~= nil
then
return { [ "__nuppAttachmentTable" ] = copy }
end

return copy
end

local function packAttachments ( packed , transfer ) 
if transfer . hasRegions then

end
if transfer . hasMoved then

end
local regionMT = _G . nupp and rawget ( _G . nupp , "__regionMetatable" )
local arrayMT = _G . nupp and rawget ( _G . nupp , "__heapArrayMetatable" )
local state = { flat = { } , count = 0 , map = { } , moved = nil }
local values = rewriteAttachments ( packed . values , regionMT , arrayMT , state )

return { values = values , count = packed . count } , state . flat , state . moved
end



local function releaseMoved ( moved ) 
if moved == nil then
return
end

for _ , bytes in ipairs ( moved ) do
( heapArrayFree ) ( bytes )
end
end





local function plantAttachments ( value , flat , cache ) 
if type ( value ) ~= "table" then
return value
end
local escaped = rawget ( value , "__nuppAttachmentTable" )
if type ( escaped ) == "table" then


for key , item in next , escaped do
if type ( item ) == "table" then
rawset ( escaped , key , plantAttachments ( item , flat , cache ) )
end
end

return escaped
end
local regionIndex = rawget ( value , "__nuppRegion" )
if type ( regionIndex ) == "number" then
local index = regionIndex
local built = cache [ index ]
if built == nil then

local base = ( index - 1 ) * 3
built = (
regionFromParts
) ( flat [ base + 1 ] , flat [ base + 2 ] , flat [ base + 3 ] )
cache [ index ] = built
end

return built
end
local movedIndex = rawget ( value , "__nuppMoved" )
if type ( movedIndex ) == "number" then

local base = ( movedIndex - 1 ) * 3
local pointer = flat [ base + 1 ]
local built = (
heapArrayFromParts
) ( pointer , flat [ base + 2 ] , flat [ base + 3 ] )
if built == nil then
( heapArrayFree ) ( pointer )
error ( "nupp: a moved buffer's element layout is not supported by this lane" , 0 )
end

return built
end
for key , item in next , value do
if type ( item ) == "table" then
rawset ( value , key , plantAttachments ( item , flat , cache ) )
end
end

return value
end




local function releaseArrivedMoved ( attachments ) 
if attachments == nil then
return
end
local flat = attachments
for index = 1 , # flat , 3 do
local handle = flat [ index ]
if type ( handle ) == "userdata" and getmetatable ( handle ) == nil then
( heapArrayFree ) ( handle )
end
end
end







local function unresolvedRecord ( value , unresolved , depth ) 
if type ( value ) ~= "table" or depth > 33 then
return nil
end
local metatable = getmetatable ( value )
if metatable ~= nil and unresolved [ metatable ] ~= nil then
return unresolved [ metatable ]
end
for _ , item in next , value do
local problem = unresolvedRecord ( item , unresolved , depth + 1 )
if problem ~= nil then
return problem
end
end

return nil
end

local function decodePackedFrame ( source , count , bytes , attachments ) 
local unresolved = nil
if count ~= 0 then
local ready , codec = pcall ( readyCodec , source )
if not ready then
releaseArrivedMoved ( attachments )

return nil , tostring ( codec )
end
unresolved = ( codec ) . unresolved
end
local packed = decodePacked ( source , count , bytes )
if unresolved ~= nil then
local problem = unresolvedRecord ( packed . values , unresolved , 0 )
if problem ~= nil then
releaseArrivedMoved ( attachments )

return nil , problem
end
end
if attachments ~= nil then
local planted , values = pcall ( plantAttachments , packed . values , attachments , { } )
if not planted then
return nil , tostring ( values )
end
packed . values = values
end

return packed , nil
end





local function releasePlantedMoved ( value , depth ) 
if type ( value ) ~= "table" or depth > 33 then
return
end
local metatable = getmetatable ( value )
if metatable ~= nil and metatable == ( _G . nupp and rawget ( _G . nupp , "__heapArrayMetatable" ) ) then

local bytes = ( heapArrayParts ) ( value )
if bytes ~= nil then
( heapArrayFree ) ( bytes )
end

return
end
for _ , item in next , value do
releasePlantedMoved ( item , depth + 1 )
end
end




local function packedValue ( encoding , bytes , value ) 
if encoding == "packed" then
return value
elseif encoding == "string" then
return { values = { bytes } , count = 1 }
elseif encoding == "value" or encoding == "record" then
return { values = { value } , count = 1 }
end
error ( "nupp: a worker returned an invalid value payload" , 3 )

return { values = { } , count = 0 }
end





local function encodeFrame ( frame ) 
local header
if frame . kind == "task" then
if frame . encoding == "buffer" then
header = { "t" , frame . id , frame . module , frame . member , frame . records }
elseif frame . encoding == "string" then
header = { "ts" , frame . id , frame . module , frame . member }
elseif frame . encoding == "value" then
header = { "tv" , frame . id , frame . module , frame . member , frame . value }
else
header = { "te" , frame . id , frame . module , frame . member }
end
elseif frame . cancelled == true then
header = { "c" , frame . id , frame . deadline == true }
elseif frame . ok == true then
if frame . encoding == "buffer" then
header = { "r" , frame . id , frame . records }
elseif frame . encoding == "string" then
header = { "rs" , frame . id }
elseif frame . encoding == "value" then
header = { "rv" , frame . id , frame . value }
else
header = { "re" , frame . id }
end
else
header = { "e" , frame . id , frame . error }
end

return buffer . encode ( header )
end

local function decode ( bytes ) 
local value = buffer . decode ( bytes )
if type ( value ) ~= "table" then
error ( "nupp: a worker returned an invalid task frame" , 3 )
end
local header = value
local tag = header [ 1 ]
if type ( header [ 2 ] ) == "number" then
if tag == "t"
and type ( header [ 3 ] ) == "string"
and type ( header [ 4 ] ) == "string"
and type ( header [ 5 ] ) == "table"
then
return {
kind = "task" ,
id = header [ 2 ] ,
module = header [ 3 ] ,
member = header [ 4 ] ,
encoding = "buffer" ,
records = header [ 5 ] ,
}
elseif ( tag == "ts" or tag == "te" ) and type ( header [ 3 ] ) == "string" and type ( header [ 4 ] ) == "string" then
return {
kind = "task" ,
id = header [ 2 ] ,
module = header [ 3 ] ,
member = header [ 4 ] ,
encoding = tag == "ts" and "string" or "empty" ,
records = noRecords ,
}
elseif tag == "tv" and type ( header [ 3 ] ) == "string" and type ( header [ 4 ] ) == "string" then
return {
kind = "task" ,
id = header [ 2 ] ,
module = header [ 3 ] ,
member = header [ 4 ] ,
encoding = "value" ,
records = noRecords ,
value = header [ 5 ] ,
}
elseif tag == "r" and type ( header [ 3 ] ) == "table" then
return {
kind = "reply" ,
id = header [ 2 ] ,
ok = true ,
encoding = "buffer" ,
records = header [ 3 ] ,
}
elseif tag == "rs" or tag == "re" then
return {
kind = "reply" ,
id = header [ 2 ] ,
ok = true ,
encoding = tag == "rs" and "string" or "empty" ,
records = noRecords ,
}
elseif tag == "rv" then
return {
kind = "reply" ,
id = header [ 2 ] ,
ok = true ,
encoding = "value" ,
records = noRecords ,
value = header [ 3 ] ,
}
elseif tag == "e" and type ( header [ 3 ] ) == "string" then
return { kind = "reply" , id = header [ 2 ] , ok = false , error = header [ 3 ] , }
elseif tag == "c" and type ( header [ 3 ] ) == "boolean" then
return { kind = "reply" , id = header [ 2 ] , cancelled = true , deadline = header [ 3 ] , }
end
end
error ( "nupp: a worker returned an invalid task frame" , 3 )

return { kind = "invalid" }
end




local function refusal ( target ) 
if target . destroyed or native . channelClosed ( target . handle ) then
return "nupp: a worker lane is closed"
end

return "nupp: a worker queue is full"
end



local function push ( target , frame ) 
local accepted = not target . destroyed and native . channelPush ( target . handle , encodeFrame ( frame ) , frame . bytes or "" )
if not accepted then
error ( refusal ( target ) , 3 )
end
end

local function pop ( source , timeoutMs ) 
if source . destroyed then
return nil
end
local header , body , nativeKind , nativeId , nativeModule , nativeMember , nativeValue , nativeCount , nativeAttachments = native . channelPop (
source . handle ,
timeoutMs
)
if nativeKind == 7
and nativeId ~= nil
and nativeModule ~= nil
and nativeMember ~= nil
and type ( nativeValue ) == "string"
and nativeCount ~= nil
then


local value , problem = decodePackedFrame ( source , nativeCount , nativeValue , nativeAttachments )
return {
kind = "task" ,
id = nativeId ,
module = nativeModule ,
member = nativeMember ,
bytes = "" ,
records = noRecords ,
encoding = "packed" ,
value = value ,
error = problem ,
}
elseif nativeKind == 8 and nativeId ~= nil and type ( nativeValue ) == "string" and nativeCount ~= nil then
local value , problem = decodePackedFrame ( source , nativeCount , nativeValue , nativeAttachments )
if problem ~= nil then
return { kind = "reply" , id = nativeId , ok = false , error = "results cannot be received: " .. problem }
end
return {
kind = "reply" ,
id = nativeId ,
ok = true ,
bytes = "" ,
records = noRecords ,
encoding = "packed" ,
value = value ,
attached = nativeAttachments ~= nil ,
}
end
if nativeKind == 1 and nativeId ~= nil and nativeModule ~= nil and nativeMember ~= nil and nativeValue ~= nil then
return {
kind = "task" ,
id = nativeId ,
module = nativeModule ,
member = nativeMember ,
bytes = "" ,
records = noRecords ,
encoding = "value" ,
value = nativeValue ,
}
elseif nativeKind == 2 and nativeId ~= nil and nativeValue ~= nil then
return {
kind = "reply" ,
id = nativeId ,
ok = true ,
bytes = "" ,
records = noRecords ,
encoding = "value" ,
value = nativeValue ,
}
elseif nativeKind == 3
and nativeId ~= nil
and nativeModule ~= nil
and nativeMember ~= nil
and type ( nativeValue ) == "string"
then
return {
kind = "task" ,
id = nativeId ,
module = nativeModule ,
member = nativeMember ,
bytes = nativeValue ,
records = noRecords ,
encoding = "string" ,
value = nil ,
}
elseif nativeKind == 4 and nativeId ~= nil and type ( nativeValue ) == "string" then
return {
kind = "reply" ,
id = nativeId ,
ok = true ,
bytes = nativeValue ,
records = noRecords ,
encoding = "string" ,
value = nil ,
}
elseif ( nativeKind == 5 or nativeKind == 6 ) and nativeId ~= nil and type ( nativeValue ) == "table" then
local address = rawget ( nativeValue , 0 )
if type ( address ) ~= "string" then
error ( "nupp: a worker returned an invalid native record frame" , 3 )
end
rawset ( nativeValue , 0 , nil )
setmetatable ( nativeValue , resolveRecordCached ( address ) )
if nativeKind == 5 and nativeModule ~= nil and nativeMember ~= nil then
return {
kind = "task" ,
id = nativeId ,
module = nativeModule ,
member = nativeMember ,
bytes = "" ,
records = noRecords ,
encoding = "record" ,
value = nativeValue ,
}
elseif nativeKind == 6 then
return {
kind = "reply" ,
id = nativeId ,
ok = true ,
bytes = "" ,
records = noRecords ,
encoding = "record" ,
value = nativeValue ,
}
end
error ( "nupp: a worker returned an invalid native record frame" , 3 )
elseif nativeKind ~= nil then
error ( "nupp: a worker returned an invalid native task frame" , 3 )
end
if header == nil then
return nil
end
if body == nil then
error ( "nupp: a worker returned an invalid task frame" , 3 )
end
local frame = decode ( header )
if frame . kind == "task" or frame . ok == true then
frame . bytes = body
elseif body ~= "" then
error ( "nupp: a worker returned an invalid task frame" , 3 )
end

return frame
end





local function destroy ( value ) 
if value . destroyed or not value . owned then
return
end
value . destroyed = true
native . channelDestroy ( value . handle )
value . handle = nil
end

local function startLane ( ) 
local inbox = newChannel ( )
local outbox = newChannel ( )
local handle , problem = native . workerSpawn ( inbox . handle , outbox . handle )
if handle == nil then
destroy ( inbox )
destroy ( outbox )
error ( "nupp: cannot start the worker scheduler: " .. ( problem or "unknown failure" ) , 3 )
end

local ready = native . channelPop ( outbox . handle , -1 )
if ready ~= "ready" then
native . channelClose ( inbox . handle )
local _ , failure = native . workerJoin ( handle )
destroy ( inbox )
destroy ( outbox )
error ( "nupp: worker initialization failed: " .. ( failure or "missing startup acknowledgement" ) , 3 )
end

return ( _G.setmetatable({ handle =
handle ,  inbox =
inbox ,  outbox =
outbox ,  nextId =
1 ,  inflight =
0 ,  pending =
{ } ,  waiters =
{ } ,  tasks =
{ } }, Lane) )

end

local sharedScheduler = nil
local settleReply = nil
local BLOCKING_REPLY_SLICE_MS = 10

local function scheduler ( ) 
if sharedScheduler ~= nil then
return sharedScheduler
end
local workerInbox = native . current ( )
if workerInbox ~= nil then
error ( "nupp: a worker task cannot open another worker scope" , 3 )
end
local count = math . max ( 1 , math . min ( native . workerParallelism ( ) , 64 ) )
local lanes = { }
for index = 1 , count do
local ok , lane = pcall ( startLane )
if not ok then
for _ , started in ipairs ( lanes ) do
native . channelClose ( started . inbox . handle )
native . workerJoin ( started . handle )
destroy ( started . inbox )
destroy ( started . outbox )
end
error ( lane , 3 )
end
lanes [ index ] = lane
end
sharedScheduler = _G.setmetatable({ lanes =  lanes ,  source =  nil ,  waitCursor =  1 }, Scheduler)

return sharedScheduler
end

local function route ( lane , timeoutMs ) 
local frame = pop ( lane . outbox , timeoutMs )
if frame == nil then
return false
end
local id = frame . id
if frame . kind ~= "reply" or id == nil or not lane . pending [ id ] then
error ( "nupp: a worker returned an unknown task reply" , 3 )
end
lane . pending [ id ] = nil
lane . inflight = lane . inflight - 1
native . workerTaskRelease ( lane . handle , id )
local task = lane . tasks [ id ]
lane . tasks [ id ] = nil
if task == nil then
error ( "nupp: a worker returned a task with no parent handle" , 3 )
end
if task . _state ~= "cancelled" then
settleReply ( task , frame )
end
local waiting = lane . waiters [ id ]
if waiting ~= nil then
lane . waiters [ id ] = nil
for index = 1 , # waiting do
waiting [ index ] ( true )
end
end

return true
end

local function ended ( lane ) 
return native . channelClosed ( lane . outbox . handle ) and native . channelCount ( lane . outbox . handle ) == 0
end



local function ready ( lane , id ) 
return lane . pending [ id ] == nil
end

local function wakeEndedLane ( lane ) 
if lane . inflight == 0 or not ( native . channelClosed ( lane . outbox . handle ) and native . channelCount ( lane . outbox . handle ) == 0 ) then
return 0
end
local waiters = lane . waiters
lane . waiters = { }
local woke = 0
for _ , waiting in pairs ( waiters ) do
for index = 1 , # waiting do
waiting [ index ] ( true )
woke = woke + 1
end
end

return woke
end

local function pollScheduler ( value ) 
local moved = 0
for _ , lane in ipairs ( value . lanes ) do
while route ( lane , 0 ) do
moved = moved + 1
end
moved = moved + wakeEndedLane ( lane )
end

return moved
end

local function waitScheduler ( value , timeoutMs ) 
if pollScheduler ( value ) > 0 then
return 1
end
local count = # value . lanes
for offset = 0 , count - 1 do
local index = ( value . waitCursor + offset - 1 ) % count + 1
local lane = value . lanes [ index ]
if lane . inflight > 0 and not ( native . channelClosed ( lane . outbox . handle ) and native . channelCount ( lane . outbox . handle ) == 0 ) then
value . waitCursor = index % count + 1
local bounded = timeoutMs < 0 and 10
or math . min ( timeoutMs , 10 )

return route ( lane , bounded ) and 1 or 0
end
end

return 0
end

local function schedulerSource ( value ) 
local existing = value . source
if existing ~= nil and not ( existing ) . released then
return existing
end
local created = suspension . source (
"nupp.workers" ,
50 ,
function ( ) 
return pollScheduler ( value )
end ,
function ( timeoutMs ) 
return waitScheduler ( value , timeoutMs )
end
)
rawset ( created , "active" , function ( ) 
for _ , lane in ipairs ( value . lanes ) do
if lane . inflight > 0 and not ( native . channelClosed ( lane . outbox . handle ) and native . channelCount ( lane . outbox . handle ) == 0 ) then
return true
end
end

return false
end )
value . source = created

return created
end

local function waitForBlocking ( lane , id ) 
while not ( lane . pending [ id ] == nil ) do
if not route ( lane , -1 ) and ( native . channelClosed ( lane . outbox . handle ) and native . channelCount ( lane . outbox . handle ) == 0 ) then
error ( "nupp: a worker thread ended before answering a task" , 3 )
end
end
end

local function waitFor ( value , lane , id ) 
if ( lane . pending [ id ] == nil ) then
return
end


if not suspension . handled ( ) then
waitForBlocking ( lane , id )

return
end

local function subscribe ( resume , context ) 
context : uses ( schedulerSource ( value ) )
local waiting = lane . waiters [ id ]
if waiting == nil then
waiting = { }
lane . waiters [ id ] = waiting
end
waiting [ # waiting + 1 ] = resume

return function ( ) 
local current = lane . waiters [ id ]
if current == nil then
return
end
for index = # current , 1 , -1 do
if current [ index ] == resume then
table . remove ( current , index )

do break end
end
end
if # current == 0 then
lane . waiters [ id ] = nil
end
end
end

while not ( lane . pending [ id ] == nil ) and not ( native . channelClosed ( lane . outbox . handle ) and native . channelCount ( lane . outbox . handle ) == 0 ) do
suspension . suspend ( "worker task" , subscribe )
end
if not ( lane . pending [ id ] == nil ) then
error ( "nupp: a worker thread ended before answering a task" , 3 )
end
end





local scannedAddresses = setmetatable ( { } , { __mode = "k" } )












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


local function owed ( task ) 
if task . _observed then
return false
end
if task . _moved then
return true
end
local observer = task . _observer

return task . _state == "failed" and ( observer == nil or observer . settled == nil )
end


local function release ( task ) 
if task . _state ~= "queued" and not owed ( task ) then
delist ( task )
end
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



local function leastBusy ( value ) 
local selected = nil
for _ , candidate in ipairs ( value . lanes ) do
if not native . channelClosed ( candidate . inbox . handle )
and ( selected == nil or candidate . inflight < ( selected ) . inflight )
then
selected = candidate
end
end
if selected == nil then
error ( "nupp: every worker lane has ended" , 3 )
end

return selected
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
local preparedInput = descriptor and descriptor . input or nil
local prepared = captures . count == 0
and arguments . count == 1
and (
preparedInput == "number" and type ( arguments . values [ 1 ] ) == "number"
or preparedInput == "string" and type ( arguments . values [ 1 ] ) == "string"
)
local transfer = nil
if not prepared then
transfer = validatedTaskTransfer ( captures , arguments )
end
local submittedArguments = arguments
if captures . count > 0 then
submittedArguments = { values = { } , count = captures . count + arguments . count }
for index = 1 , captures . count do
submittedArguments . values [ index ] = captures . values [ index ]
end
for index = 1 , arguments . count do
submittedArguments . values [ captures . count + index ] = arguments . values [ index ]
end
end
local lane = leastBusy ( self . _scheduler )
local id = lane . nextId
lane . nextId = id + 1
if not native . workerTaskCreate ( lane . handle , id , self . _deadline ) then
error ( "nupp: cannot register worker task state" , 2 )
end
schedulerSource ( self . _scheduler )
local task = setmetatable (
{
_lane = lane ,
_scheduler = self . _scheduler ,
_id = id ,
_state = "queued" ,
_values = { } ,
_count = 0 ,
_error = nil ,
_cancelled = nil ,
_observed = false ,
_observer = self . _observer ,
_moved = false ,
_scope = nil ,
_listed = false ,
_before = nil ,
_after = nil ,
} ,
TaskMT
)
lane . inflight = lane . inflight + 1
lane . pending [ id ] = true
lane . tasks [ id ] = task
local movedPointers = nil
local submitted , problem = pcall ( function ( ) 
if preparedInput == "number" and prepared then
if not native . channelPushNumberTask (
lane . inbox . handle ,
id ,
moduleName ,
member ,
arguments . values [ 1 ]
) then
error ( refusal ( lane . inbox ) , 3 )
end
elseif preparedInput == "string" and prepared then
if not native . channelPushStringTask (
lane . inbox . handle ,
id ,
moduleName ,
member ,
arguments . values [ 1 ]
) then
error ( refusal ( lane . inbox ) , 3 )
end
else
registerTransferRecords ( lane . inbox , transfer )
local outgoing = submittedArguments
local attachments = nil
if ( transfer ) . hasRegions or ( transfer ) . hasMoved then
outgoing , attachments , movedPointers = packAttachments ( submittedArguments , transfer )
end
local count , bytes = encodePacked ( lane . inbox , outgoing )
movedPointers = nil
if not native . channelPushBufferTask (
lane . inbox . handle ,
id ,
moduleName ,
member ,
count ,
bytes ,
attachments
) then
error ( refusal ( lane . inbox ) , 3 )
end
end
end )
if not submitted then
releaseMoved ( movedPointers )
lane . pending [ id ] = nil
lane . tasks [ id ] = nil
lane . inflight = lane . inflight - 1
native . workerTaskRelease ( lane . handle , id )
error ( problem , 2 )
end
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





function TaskImpl : isDone ( ) 
if self . _state ~= "queued" then
return true
end
while route ( self . _lane , 0 ) do
end

return self . _state == "done" or self . _state == "failed" or self . _state == "cancelled"
end

function TaskImpl : status ( ) 
if not self : isDone ( ) then
local status = native . workerTaskStatus ( self . _lane . handle , self . _id )
if status == 2 or status == 3 then
return "running"
end
end

return self . _state
end

local function notifySettled ( task ) 
local observer = task . _observer
if observer ~= nil and observer . settled ~= nil then
observer . settled ( observer , task , task . _state , task . _error or task . _cancelled )
end
end

settleReply = function ( task , reply ) 
if task . _state == "cancelled" then


releasePlantedMoved ( reply . value , 0 )
return
end
if reply . cancelled == true then
task . _cancelled = task . _cancelled
or cancellation . create ( "worker task" , reply . deadline == true and "its deadline passed" or nil )
task . _state = "cancelled"
elseif reply . ok == true then
local packed = packedValue ( reply . encoding , reply . bytes , reply . value )
task . _values = packed . values
task . _count = packed . count
task . _moved = reply . attached == true
task . _state = "done"
else
task . _error = reply . error or "worker task failed without an error"
task . _state = "failed"
end


notifySettled ( task )
release ( task )
end

function TaskImpl : cancel ( reason ) 
if self : isDone ( ) then
return false
end
local requested = native . workerTaskCancel ( self . _lane . handle , self . _id )
if requested == 0 then
return false
end
self . _cancelled = cancellation . create ( "worker task" , reason )
if requested == 1 then
self . _state = "cancelled"
notifySettled ( self )
release ( self )
end

return true
end

function TaskImpl : await ( ) 
self . _observed = true
if not self : isDone ( ) then
waitFor ( self . _scheduler , self . _lane , self . _id )
end
release ( self )
if self . _state == "failed" then
error ( "nupp: worker task failed: " .. ( self . _error or "unknown failure" ) , 2 )
end
if self . _state == "cancelled" then
error ( self . _cancelled , 2 )
end

return unpack ( self . _values , 1 , self . _count )
end



local function settleParking ( task ) 
task . _observed = true
if not TaskImpl . isDone ( task ) then
waitFor ( task . _scheduler , task . _lane , task . _id )
end
release ( task )

return task . _state == "failed" and "nupp: worker task failed: " .. ( task . _error or "unknown failure" ) or nil
end









local function settleForScope ( task ) 
task . _observed = true
if not TaskImpl . isDone ( task ) then
waitFor ( task . _scheduler , task . _lane , task . _id )
end
release ( task )
if task . _state == "failed" then
return "failed" , nil , 0 , "nupp: worker task failed: " .. ( task . _error or "unknown failure" )
end
if task . _state == "cancelled" then
return "cancelled" , nil , 0 , task . _cancelled
end

return "done" , task . _values , task . _count , nil
end

workers . settle = settleForScope





local function closeScope ( self ) 
if self . _closed then
return
end
self . _closed = true
local firstFailure = nil
for _ , task in ipairs ( listed ( self ) ) do
local observed = task . _observed == true
local problem = settleParking ( task )
if not observed then
releasePlantedMoved ( task . _values , 0 )
end
if problem ~= nil and not observed and firstFailure == nil then
firstFailure = problem
end
end
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
while task ~= nil and task . _state ~= "queued" do
task = task . _after
end
if task == nil then
return false
end
if not TaskImpl . isDone ( task ) then
waitFor ( task . _scheduler , task . _lane , task . _id )
end
release ( task )

return true
end

local function openScope ( deadline , observer ) 
return setmetatable (
{
spawn = spawnSurface ,
close = closeScope ,
_cancelAll = cancelAllScope ,
_settleOldest = settleOldestScope ,
_scheduler = scheduler ( ) ,
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





local function workerFailure ( problem ) 
if cancellation . is ( problem ) then
return problem
end

return debug . traceback ( tostring ( problem ) , 2 )
end

local function workerReply ( outbox , id , ok , answer , preparedOutput ) 
if not ok then
if cancellation . is ( answer ) then
local cancelled = answer
push ( outbox , {
kind = "reply" ,
id = id ,
cancelled = true ,
deadline = cancelled . reason == "its deadline passed" ,
} )

return
end
push ( outbox , { kind = "reply" , id = id , ok = false , error = tostring ( answer ) } )
return
end
local packed = answer
local prepared = packed . count == 1
and (
preparedOutput == "number" and type ( packed . values [ 1 ] ) == "number"
or preparedOutput == "string" and type ( packed . values [ 1 ] ) == "string"
)
local transfer = nil
local rejected = nil
if not prepared then
transfer = { seen = { } , records = nil , addresses = nil }
rejected = unsendable ( answer , "results" , 0 , transfer )
end
if rejected ~= nil then
releasePlantedMoved ( packed . values , 0 )
push ( outbox , { kind = "reply" , id = id , ok = false , error = "results cannot be copied: " .. rejected } )
elseif preparedOutput == "number" and prepared then
if not native . channelPushNumberReply ( outbox . handle , id , packed . values [ 1 ] ) then
error ( refusal ( outbox ) , 3 )
end
elseif preparedOutput == "string" and prepared then
if not native . channelPushStringReply ( outbox . handle , id , packed . values [ 1 ] ) then
error ( refusal ( outbox ) , 3 )
end
else
registerTransferRecords ( outbox , transfer )
local outgoing = packed
local attachments = nil
local movedPointers = nil
if ( transfer ) . hasRegions or ( transfer ) . hasMoved then
outgoing , attachments , movedPointers = packAttachments ( packed , transfer )
end
local encoded , count , bytes = pcall ( encodePacked , outbox , outgoing )
if not encoded then
releaseMoved ( movedPointers )
error ( count , 0 )
end
if not native . channelPushBufferReply ( outbox . handle , id , count , bytes , attachments ) then
error ( refusal ( outbox ) , 3 )
end
end
end



local function answerTask ( outbox , frame ) 
pcall ( push , outbox , frame )
end



function workers . runScheduler ( ) 
local inHandle , outHandle = native . current ( )
if inHandle == nil or outHandle == nil then
error ( "nupp: worker scheduler started outside a worker state" , 2 )
end
local inbox = ( setmetatable ( { handle = inHandle , owned = false , destroyed = false } , ChannelMT ) )
local outbox = ( setmetatable ( { handle = outHandle , owned = false , destroyed = false } , ChannelMT ) )
assert ( native . channelPush ( outHandle , "ready" , "" ) , "nupp: cannot acknowledge worker initialization" )
while true do
local frame = pop ( inbox , -1 )
if frame == nil then
return
end
local id = frame . id
if frame . kind ~= "task"
or id == nil
or frame . module == nil
or frame . member == nil
or frame . bytes == nil
or frame . records == nil
or frame . encoding == nil
then
error ( "nupp: worker scheduler received an invalid task" , 2 )
end
local shouldRun , deadline = native . workerTaskStart ( id )
if not shouldRun then
releasePlantedMoved ( frame . value , 0 )
native . workerTaskFinish ( id )
answerTask ( outbox , { kind = "reply" , id = id , cancelled = true , deadline = deadline , } )
else
local preparedOutput = nil
local ok , answer = xpcall (
function ( ) 
if frame . error ~= nil then
error ( frame . error , 0 )
end
local moduleName = frame . module
local member = frame . member
local moduleValue = require ( moduleName )
local callable = outlinedSendables [ ( moduleName .. "\0" .. member ) ]
or ( type ( moduleValue ) == "table" and ( moduleValue ) [ member ] or nil )
if type ( callable ) ~= "function" then
error ( ("%s.%s is not a registered sendable function") : format ( moduleName , member ) , 0 )
end
local descriptor = sendableDescriptors [ callable ]
preparedOutput = descriptor and descriptor . output or nil
local arguments = packedValue ( frame . encoding , frame . bytes , frame . value )

return pack ( callable ( unpack ( arguments . values , 1 , arguments . count ) ) )
end ,
workerFailure
)
local cancelled , finishedDeadline = native . workerTaskFinish ( id )
if ok and cancelled then
releasePlantedMoved ( ( answer ) . values , 0 )
answerTask ( outbox , { kind = "reply" , id = id , cancelled = true , deadline = finishedDeadline , } )
else
if not ok then
releasePlantedMoved ( frame . value , 0 )
end



local replied , problem = pcall ( workerReply , outbox , id , ok , answer , preparedOutput )
if not replied then
if ok then
releasePlantedMoved ( ( answer ) . values , 0 )
end
answerTask ( outbox , {
kind = "reply" ,
id = id ,
ok = false ,
error = "results cannot be sent: " .. tostring ( problem ) ,
} )
end
end
end
end
end


local checked = workers

local __nuppExportValue= workers ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.workers"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.workers"]=__nuppExports;return __nuppExports