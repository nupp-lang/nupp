_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT10={}; local function __nuppT7(...) return {n=select("#",...),...} end; local __nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT8(value) return value end; local function __nuppT9(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT16({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT17(v.primary) for _,reason in __nuppT18(v.suppressed) do text=text.."\ncleanup: "..__nuppT17(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

























local effects = require ( "nupp.runtime.browser.effects" )
local suspension = require ( "nupp.suspension" )
local suspensionHost = require ( "nupp.suspension.host" )
local suspensionContract = require ( "nupp.suspension.spi" )
local values = require ( "nupp.host.internal.values" )
local wire = require ( "nupp.runtime.browser.hostwire" )
local json = require ( "nupp.runtime.provider.lunajson" )
local ffi = require ( "ffi" )

local unpackValues = rawget ( _G , "unpack" ) or ( table ) . unpack

local provider = { }



const RESULT_BUDGET_BYTES = 8388608


const MAX_PENDING_POSTS = 1024


const INBOX_BYTES = 4096

const MAX_INBOX_BYTES = 1048576

local memoryModule = nil

local function memory ( ) 
if memoryModule == nil then
memoryModule = require ( "nupp.runtime.browser.memory" )
end

return memoryModule
end

local function report ( kind , problem ) 
io . stderr : write ( "nupp: host " .. kind .. ": " .. tostring ( problem ) .. "\n" )
end

local refusingHandler = _G.setmetatable({ park =
function ( _ , _ , _ ) 
error ( "nupp: a host late handler cannot suspend; release with host.post" , 0 )
end ,  canPark =
function ( _ ) 
return false
end ,  shutdown =
function ( _ ) 
end }, suspensionContract.Handler)



local function runLate ( kind , late , ... ) 
do local __nuppT19=0; local  __nuppT25 ; local __nuppT26=false ; local __nuppT20,__nuppT21,__nuppT22=__nuppT12(function(...) do local __nuppT27= suspensionHost . install ( refusingHandler ) ; __nuppT25= __nuppT27 ; __nuppT19=1;  __nuppT26=true;  local installed=__nuppT25;
local ok , problem = pcall ( late , ... )
do (function(__nuppT28,...)  __nuppT26=false; return __nuppT28:close(...)  end)( installed ) end
if not ok then
report ( kind , "late handler failed: " .. tostring ( problem ) )
end end; return "normal" end,__nuppT8,...); local __nuppT23={}; local __nuppT24=0; if __nuppT19>=1 and __nuppT26 then  local __nuppT29,__nuppT30=__nuppT11(__nuppCleanup1,__nuppT25);  if not __nuppT29 then __nuppT24=__nuppT24+1; __nuppT23[__nuppT24]=__nuppT30 end; end; if not __nuppT20 then if __nuppT24>0 then __nuppT13(__nuppT9(__nuppT21,__nuppT23,1),0) else __nuppT13(__nuppT21,0) end end; if __nuppT24>0 then if __nuppT24>1 then __nuppT13(__nuppT9(__nuppT23[1],__nuppT23,2),0) else __nuppT13(__nuppT23[1],0) end end; if __nuppT21=="return" then  return __nuppT14(__nuppT22,1,__nuppT22.n)  end; end
end





local nextRecord = 1
local nextTransfer = 1

local pending = { }
local pendingPosts = 0

local calls = { }
local callCount = 0
local routes = { }
local routeCount = 0
local inboxBytes = 4096


local frame = nil

local blockedSenders = { }


local spareWriter = nil
local unanswered = 0

local function newRecord ( op , kind ) 
local id = nextRecord
nextRecord = nextRecord + 1
return { op = op , id = id , kind = kind }
end

local function needsFrame ( ) 
return # pending > 0 or callCount > 0 or routeCount > 0
end

local ensureFrame



local function writeValues ( writer , list ) 
local count = list . n
wire . u16 ( writer , count )
for position = 1 , count do
local value = list [ position ]
local tag = list . tags [ position ]
if tag == "nil" then
wire . u8 ( writer , wire . NIL )
elseif tag == "boolean" then
wire . u8 ( writer , value and wire . TRUE or wire . FALSE )
elseif tag == "number" then
wire . u8 ( writer , wire . NUMBER )
wire . f64 ( writer , value )
elseif tag == "string" then
wire . u8 ( writer , wire . STRING )
wire . sized ( writer , value , # value )
elseif tag == "bytes" then
wire . u8 ( writer , wire . BYTES )
wire . sized ( writer , value . pointer , value . size )
else
wire . u8 ( writer , wire . UPLOAD )
wire . u32 ( writer , value . transfer )
end
end
end

local function writeRecord ( writer , record ) 
wire . u8 ( writer , record . op )
wire . u32 ( writer , record . id )
local op = record . op
if op == wire . CALL or op == wire . POST or op == wire . SEND then
wire . u16 ( writer , # record . kind )
wire . raw ( writer , record . kind , # record . kind )
writeValues ( writer , record . values )
elseif op == wire . ABANDON then
wire . u32 ( writer , record . result )
elseif op == wire . ABORT then
wire . u32 ( writer , record . transfer )
elseif op == wire . ROUTES then
wire . sized ( writer , record . text , # record . text )
end
end




local function prepareFrame ( ) 
local current = frame
if current == nil then
return false
end
local writer = nil
if unanswered == 0 and spareWriter ~= nil then
writer = spareWriter
wire . reset ( writer )
else
writer = wire . writer ( 1024 )
end
local kept = { }
local shipped = { }
for _ , record in ipairs ( pending ) do
local size = ( record . size or 64 )

if ( record . uploads or 0 ) > 0 or ( writer . length > 0 and writer . length + size > values . CHUNK_BYTES ) then
kept [ # kept + 1 ] = record
else
writeRecord ( writer , record )
shipped [ # shipped + 1 ] = record
end
end
pending = kept
for _ , record in ipairs ( shipped ) do
record . shipped = true
if record . op == wire . POST then
pendingPosts = pendingPosts - 1
end
end



local records = writer . length
local size = math . max ( records , inboxBytes )
if writer . capacity < size then
local grown = wire . writer ( size )
wire . raw ( grown , writer . buffer , records )
writer = grown
end
current . writer = writer
current . inbox = writer . buffer
current . inboxBytes = size
unanswered = unanswered + 1
current . inboxLease = memory ( ) . lease ( writer . buffer , size , true )
current . payload . spans = { { lease = current . inboxLease , bytes = size } }
current . payload . records = records
frame = nil


local blocked = blockedSenders
blockedSenders = { }
for _ , resume in ipairs ( blocked ) do
resume ( true )
end

return # blocked > 0
end

effects . beforePark ( prepareFrame )

local function readValues ( reader , count ) 
local decoded = { }
local fetches = nil
for position = 1 , count do
local tag = wire . readU8 ( reader )
if tag == wire . FALSE then
decoded [ position ] = false
elseif tag == wire . TRUE then
decoded [ position ] = true
elseif tag == wire . NUMBER then
decoded [ position ] = wire . readF64 ( reader )
elseif tag == wire . STRING then
decoded [ position ] = wire . readString ( reader , wire . readU32 ( reader ) )
elseif tag == wire . BYTES then
local text = wire . readString ( reader , wire . readU32 ( reader ) )
decoded [ position ] = values . byteSpan ( text , ffi . cast ( "const uint8_t *" , text ) , # text )
elseif tag == wire . FETCH then
fetches = fetches or { }
fetches [ # fetches + 1 ] = { index = position , size = wire . readU32 ( reader ) }
elseif tag ~= wire . NIL then
error ( "nupp: a host answer carried an unknown value tag " .. tostring ( tag ) , 0 )
end
end

return decoded , fetches
end

local function control ( record ) 
pending [ # pending + 1 ] = record
ensureFrame ( )
end



local function deliverLate ( entry , answer ) 
if not answer . ok then
return
end
if answer . result ~= 0 then
local record = newRecord ( wire . ABANDON )
record . result = answer . result
control ( record )
return
end
if entry . late ~= nil then
runLate ( entry . kind , entry . late , unpackValues ( answer . values , 1 , answer . count ) )
end
end

local function deliverAnswer ( id , answer ) 
local entry = calls [ id ]
if entry == nil then
return
end
calls [ id ] = nil
callCount = callCount - 1
if entry . cancelled then
deliverLate ( entry , answer )
elseif entry . resume ~= nil then


entry . answer = answer
entry . resume ( answer )
end
end


local function deliverMessage ( deliverTo , list , count ) 
if count == 2 then
deliverTo ( list [ 1 ] , list [ 2 ] )
elseif count == 1 then
deliverTo ( list [ 1 ] )
elseif count == 3 then
deliverTo ( list [ 1 ] , list [ 2 ] , list [ 3 ] )
elseif count == 4 then
deliverTo ( list [ 1 ] , list [ 2 ] , list [ 3 ] , list [ 4 ] )
elseif count == 0 then
deliverTo ( )
else
deliverTo ( unpackValues ( list , 1 , count ) )
end
end



local deliveryCursor = 1




local function deliverMessages ( messages ) 
while deliveryCursor <= # messages do
local message = messages [ deliveryCursor ]
deliveryCursor = deliveryCursor + 1
local route = routes [ message . kind ]
if route ~= nil then
deliverMessage ( route . deliver , message . values , message . count )
end
end
end


local installRefusing = suspensionHost . install



local function readInbox ( current , written ) 
local reader = wire . reader ( current . inbox , written )
local messages = nil
while wire . remaining ( reader ) > 0 do
local op = wire . readU8 ( reader )
if op == wire . ANSWER then
local id = wire . readU32 ( reader )
local ok = wire . readU8 ( reader ) == 1
if ok then
local result = wire . readU32 ( reader )
local count = wire . readU16 ( reader )
local decoded , fetches = readValues ( reader , count )
deliverAnswer ( id , { ok = true , result = result , count = count , values = decoded , fetches = fetches } )
else
deliverAnswer ( id , { ok = false , error = wire . readString ( reader , wire . readU32 ( reader ) ) } )
end
elseif op == wire . MESSAGE then
local kind = wire . readString ( reader , wire . readU16 ( reader ) )
local count = wire . readU16 ( reader )
local decoded = readValues ( reader , count )
messages = messages or { }
messages [ # messages + 1 ] = { kind = kind , values = decoded , count = count }
elseif op == wire . DROPPED then
local kind = wire . readString ( reader , wire . readU16 ( reader ) )
local count = wire . readU32 ( reader )
local route = routes [ kind ]
if route ~= nil then
route . dropped = route . dropped + count
end
else
error ( "nupp: a host frame's inbox held an unknown record " .. tostring ( op ) , 0 )
end
end
if messages ~= nil then

local installed = installRefusing ( refusingHandler )
deliveryCursor = 1
while true do
local finished , problem = pcall ( deliverMessages , messages )
if finished then
do break end
end
report ( messages [ deliveryCursor - 1 ] . kind , "delivery failed: " .. tostring ( problem ) )
end
installed : close ( )
end
end

local function frameAnswered ( current , response ) 
unanswered = unanswered - 1
spareWriter = current . writer
if current . inboxLease ~= nil then
memory ( ) . releaseLease ( current . inboxLease )
end
if type ( response ) == "table" and response . ok == true and type ( response . value ) == "table" then
local value = response . value
local written = value . written
if type ( written ) == "number" and written > 0 and written <= current . inboxBytes then
readInbox ( current , written )
end
local more = value . more
if type ( more ) == "number" and more > 0 then
inboxBytes = math . floor (
math . min ( 1048576 , math . max ( inboxBytes * 2 , ( written or 0 ) + more ) )
)
elseif inboxBytes > 4096 and ( written or 0 ) < inboxBytes / 4 then
inboxBytes = math . max ( 4096 , math . floor ( inboxBytes / 2 ) )
end
elseif type ( response ) == "table" and response . ok == false then
report ( "frame" , response . error )
end
ensureFrame ( )
end

ensureFrame = function ( ) 
if frame ~= nil or not ( # pending > 0 or callCount > 0 or routeCount > 0 ) then
return
end
local current = { payload = { op = "x" } }
frame = current
effects . request ( "host" , current . payload , function ( response ) 
frameAnswered ( current , response )
end )
end








local function argumentList ( kind , copyBytes , ... ) 
local count = select ( "#" , ... )
local list = { n = count , tags = { } }
local size = 64 + # kind
local carried = 0
local uploads = nil
for position = 1 , count do
local tag , value , length = values . classify ( kind , position , ( select ( position , ... ) ) )
if tag == "bytes" then
local bytes = length
if carried + bytes > values . CHUNK_BYTES then
if copyBytes then
error (
string . format ( "nupp: host %s carries more than the one MiB of bytes a post or send may" , kind ) ,
0
)
end
uploads = uploads or { }
local transfer = nextTransfer
nextTransfer = nextTransfer + 1
uploads [ # uploads + 1 ] = { transfer = transfer , pointer = value , size = bytes }
list . tags [ position ] = "upload"
list [ position ] = { transfer = transfer }
size = size + 8
else
local pointer = value
local anchor = nil
if copyBytes then
anchor = ffi . string ( value , bytes )
pointer = anchor
end
list . tags [ position ] = "bytes"
list [ position ] = { pointer = pointer , size = bytes , anchor = anchor }
size = size + bytes + 8
carried = carried + bytes
end
else
list . tags [ position ] = tag
list [ position ] = value
size = size + ( tag == "string" and # value or 0 ) + 12
end
end

return list , size , uploads
end







local function queueUploads ( record , uploads ) 
local cancels = { }
local leases = { }
local guestMemory = memory ( )
for _ , upload in ipairs ( uploads ) do
local base = ffi . cast ( "const uint8_t *" , upload . pointer )
local offset = 0
while offset < upload . size do
local length = math . min ( values . CHUNK_BYTES , upload . size - offset )
local lease = guestMemory . lease ( base + offset , length , false )
leases [ # leases + 1 ] = lease
record . uploads = ( record . uploads or 0 ) + 1
cancels [ # cancels + 1 ] = effects . request (
"host" ,
{
op = "upload" ,
transfer = upload . transfer ,
offset = offset ,
total = upload . size ,
spans = { { lease = lease , bytes = length } } ,
} ,
function ( response ) 
guestMemory . releaseLease ( lease )
record . uploads = record . uploads - 1
if type ( response ) == "table" and response . ok == false then
record . uploadFailure = record . uploadFailure or response . error
end
end ,
nil ,
true
)
offset = offset + length
end
end

return cancels , leases
end

local admittedBytes = 0
local admissionWaiters = { }

local function release ( amount ) 
admittedBytes = admittedBytes - amount
while # admissionWaiters > 0 do
local waiter = admissionWaiters [ 1 ]
if admittedBytes + waiter . size > 8388608 then
return
end
table . remove ( admissionWaiters , 1 )
admittedBytes = admittedBytes + ( waiter . size )
waiter . resume ( true )
end
end



local function admit ( kind , size ) 
if # admissionWaiters == 0 and admittedBytes + size <= 8388608 then
admittedBytes = admittedBytes + size
return
end
suspension . suspend ( "host " .. kind .. " result admission" , function ( resume ) 
local waiter = { size = size , resume = resume }
admissionWaiters [ # admissionWaiters + 1 ] = waiter
return function ( ) 
for index = # admissionWaiters , 1 , -1 do
if admissionWaiters [ index ] == waiter then
table . remove ( admissionWaiters , index )
end
end
end
end )
end

local function abandon ( result ) 
local record = newRecord ( wire . ABANDON )
record . result = result
control ( record )
end




local function fetchBytes ( kind , result , announced , decoded ) 
local total = 0
for _ , entry in ipairs ( announced ) do
local size = entry . size
if size > values . MAX_INBOUND_BYTES then
abandon ( result )
error ( "nupp: host " .. kind .. " answered a byte value larger than 8 MiB" , 0 )
end
total = total + size
end
if total > 8388608 then
abandon ( result )
error ( string . format ( "nupp: host %s answered %d bytes, more than the 8 MiB a result may hold" , kind , total ) , 0 )
end
local admitted , admissionProblem = pcall ( admit , kind , total )
if not admitted then
abandon ( result )
error ( admissionProblem , 0 )
end
local storage = { }
local guestMemory = memory ( )
local fetched , problem = pcall ( suspension . suspend , "host " .. kind .. " result" , function (
resume
) 
local outstanding = 0
local failure = nil
local cancels = { }
local leases = { }

local function settled ( response ) 
outstanding = outstanding - 1
if failure == nil and ( type ( response ) ~= "table" or response . ok ~= true ) then
failure = type ( response ) == "table" and response . error or "invalid fetch response"
end
if outstanding == 0 then
resume ( failure )
end
end

for index , entry in ipairs ( announced ) do
local size = entry . size
local buffer = ffi . new ( "uint8_t[?]" , math . max ( size , 1 ) )
storage [ index ] = buffer
local offset = 0
while offset < size do
local length = math . min ( values . CHUNK_BYTES , size - offset )
local lease = guestMemory . lease ( buffer + offset , length , true )
leases [ # leases + 1 ] = lease
outstanding = outstanding + 1
cancels [ # cancels + 1 ] = effects . request (
"host" ,
{
op = "fetch" ,
result = result ,
index = entry . index ,
offset = offset ,
spans = { { lease = lease , bytes = length } } ,
} ,
function ( response ) 
guestMemory . releaseLease ( lease )
settled ( response )
end ,
nil ,
true
)
offset = offset + length
end
end
if outstanding == 0 then
resume ( nil )
end

return function ( ) 
for _ , cancel in ipairs ( cancels ) do
cancel ( )
end
for _ , lease in ipairs ( leases ) do
guestMemory . releaseLease ( lease )
end
abandon ( result )
end
end )
release ( total )
if not fetched then
error ( problem , 0 )
end
if problem ~= nil then
abandon ( result )
error ( "nupp: host " .. kind .. " result could not be fetched: " .. tostring ( problem ) , 0 )
end
for index , entry in ipairs ( announced ) do
decoded [ entry . index ] = values . byteSpan ( storage [ index ] , storage [ index ] , entry . size )
end
end





function provider . attached ( ) 
return true
end

function provider . call ( kind , late , ... ) 
local list , size , uploads = argumentList ( kind , false , ... )
local record = newRecord ( wire . CALL , kind )
record . values = list
record . size = size
local uploadCancels = nil
local uploadLeases = nil
if uploads ~= nil then
uploadCancels , uploadLeases = queueUploads ( record , uploads )
end
local entry = { kind = kind , late = late , cancelled = false , resume = nil , answer = nil }
local ok , suspended = pcall ( suspension . suspend , "host " .. kind , function ( resume ) 
entry . resume = resume
calls [ record . id ] = entry
callCount = callCount + 1
pending [ # pending + 1 ] = record
ensureFrame ( )

return function ( ) 
entry . resume = nil
if entry . answer ~= nil then
local answer = entry . answer
entry . answer = nil
deliverLate ( entry , answer )
return
end
if not record . shipped then

for index = # pending , 1 , -1 do
if pending [ index ] == record then
table . remove ( pending , index )
end
end
if calls [ record . id ] == entry then
calls [ record . id ] = nil
callCount = callCount - 1
end
else
entry . cancelled = true
local cancel = newRecord ( wire . CANCEL )
cancel . id = record . id
control ( cancel )
end
if uploadCancels ~= nil then
local anyShipped = false
for _ , cancel in ipairs ( uploadCancels ) do
if not cancel ( ) then
anyShipped = true
end
end
if anyShipped then
for _ , upload in ipairs ( uploads ) do
local abort = newRecord ( wire . ABORT )
abort . transfer = upload . transfer
control ( abort )
end
end
end
end
end )
if uploadLeases ~= nil then
local guestMemory = memory ( )
for _ , lease in ipairs ( uploadLeases ) do
guestMemory . releaseLease ( lease )
end
end
if not ok then
error ( suspended , 0 )
end
local answer = suspended
entry . answer = nil
if not answer . ok then
error ( "nupp: host " .. kind .. " failed: " .. tostring ( answer . error ) , 0 )
end
local decoded = answer . values
if answer . fetches ~= nil then
fetchBytes ( kind , answer . result , answer . fetches , decoded )
end

return unpackValues ( decoded , 1 , answer . count )
end

function provider . post ( kind , ... ) 
if pendingPosts >= 1024 then
error ( "nupp: host " .. kind .. " cannot be posted: 1024 posts are already waiting to ship" , 0 )
end
local list , size = argumentList ( kind , true , ... )
local record = newRecord ( wire . POST , kind )
record . values = list
record . size = size
pendingPosts = pendingPosts + 1
pending [ # pending + 1 ] = record
ensureFrame ( )
end





function provider . send ( kind , policy , limit , ... ) 
local held = 0
local oldest = nil
for index , record in ipairs ( pending ) do
if record . op == wire . SEND and record . kind == kind then
held = held + 1
oldest = oldest or index
end
end

if held >= ( policy == "latest" and 1 or limit ) then
if policy == "latest" or policy == "dropOldest" then
table . remove ( pending , oldest )
else

suspension . suspend ( "host stream " .. kind , function ( resume ) 
blockedSenders [ # blockedSenders + 1 ] = resume
return function ( ) 
for index = # blockedSenders , 1 , -1 do
if blockedSenders [ index ] == resume then
table . remove ( blockedSenders , index )
end
end
end
end )
provider . send ( kind , policy , limit , ... )
return
end
end
local list , size = argumentList ( kind , true , ... )
local record = newRecord ( wire . SEND , kind )
record . values = list
record . size = size
pending [ # pending + 1 ] = record
ensureFrame ( )
end


local function routesRecord ( ) 
local policies = { }
for kind , route in pairs ( routes ) do
policies [ kind ] = { p = route . policy , l = route . limit }
end
local record = newRecord ( wire . ROUTES )
record . text = json . encode ( json . asObject ( policies ) )
record . size = 64 + # record . text

return record
end

function provider . route ( kind , policy , limit , deliver ) 
if routes [ kind ] ~= nil then
error ( "nupp: host stream " .. kind .. " is already routed; close that route first" , 0 )
end
local route = { deliver = deliver , policy = policy , limit = limit , dropped = 0 }
routes [ kind ] = route
routeCount = routeCount + 1


control ( routesRecord ( ) )

local function stop ( ) 
if routes [ kind ] == route then
routes [ kind ] = nil
routeCount = routeCount - 1
control ( routesRecord ( ) )
end
end

local function dropped ( ) 
return route . dropped
end

return stop , dropped
end

local __nuppExportValue= provider ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.host"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.host"]=__nuppExports;return __nuppExports