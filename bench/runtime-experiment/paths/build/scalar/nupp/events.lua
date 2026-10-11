_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppClear = require("table.clear"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.events\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.events\0runtime\0003") };






































local derive = require ( "nupp.derive" )
local pool = require ( "nupp.util.internal.pool" )
local arena = require ( "nupp.mem.arena" )

local events = { }




















































































local Info = {} Info.__index = Info
















local infos = setmetatable ( { } , { __mode = "k" } )
local nextId = 1




local INFO_KEY = "__nuppEventInfo"



local function infoOf ( witness ) 
local known = infos [ witness ]
if known ~= nil then
return known
end
local entry = derive . entry ( witness )
local data = entry and entry . schema and entry . schema . data or nil
local recorded = data and data . events or nil
local initializer = derive . initializer ( witness )
if recorded == nil or initializer == nil then
error ( "nupp: the type did not derive events.Event" , 3 )
end
local info = _G.setmetatable({ id =
nextId ,  name =
recorded . name ,  representation =
recorded . representation ,  witness =
witness ,  initializer =
initializer }, Info)

nextId = nextId + 1
infos [ witness ] = info
if type ( witness ) == "table" then
rawset ( witness , "__nuppEventInfo" , info )
end

return info
end



local function infoFor ( witness ) 
local info = nil
if type ( witness ) == "table" then
info = rawget ( witness , "__nuppEventInfo" )
else
info = infos [ witness ]
end
if info == nil then
return infoOf ( witness )
end

return info
end









function events . id ( event ) 
return infoOf ( event ) . id
end





function events . name ( event ) 
return infoOf ( event ) . name
end











local STRIDE = 3



local function tombstone ( ) 
end







events.Observers = {} events.Observers.__index = events.Observers ;_G.nupp.__reflect.link(events.Observers,__nuppT1[1],{ })

















function events . newObservers ( ) 
return ( _G.setmetatable({ byAddress =
{ } ,  count =
0 ,  depth =
0 ,  pending =
false ,  dirty =
{ } ,  detached =
{ } ,  freeLists =
{ } ,  freeMaps =
{ } ,  allocators =
{ } ,  ownedArenas =
{ } }, events.Observers) )

end











local function takeList ( observers ) 
local free = observers . freeLists
local count = # free
if count > 0 then
local list = free [ count ]
free [ count ] = nil
return list
end

return { n = 0 , once = 0 , holes = 0 }
end

local function takeMap ( observers ) 
local free = observers . freeMaps
local count = # free
if count > 0 then
local map = free [ count ]
free [ count ] = nil
return map
end

return { }
end




local function giveList ( observers , list ) 
local n = list . n
for slot = 1 , n * 3 do
list [ slot ] = nil
end
list . n = 0
list . once = 0
list . holes = 0
local free = observers . freeLists
free [ # free + 1 ] = list
end

local function giveMap ( observers , map ) 
__nuppClear ( map )
local free = observers . freeMaps
free [ # free + 1 ] = map
end



local function compact ( list ) 
local n = list . n
local index = 1
while index <= n do
local base = ( index - 1 ) * 3
if list [ base + 2 ] == tombstone then
local last = ( n - 1 ) * 3
if index < n then
list [ base + 1 ] = list [ last + 1 ]
list [ base + 2 ] = list [ last + 2 ]
list [ base + 3 ] = list [ last + 3 ]
end
list [ last + 1 ] = nil
list [ last + 2 ] = nil
list [ last + 3 ] = nil
n = n - 1
else
index = index + 1
end
end
list . n = n
list . holes = 0

return n
end



local function prune ( observers , address , eventId , list ) 
if list . n ~= 0 then
return
end
local map = observers . byAddress [ address ]
if map == nil or map [ eventId ] ~= list then
return
end
map [ eventId ] = nil
giveList ( observers , list )
if next ( map ) == nil then
observers . byAddress [ address ] = nil
giveMap ( observers , map )
end
end





local function settle ( observers ) 
local arenas = observers . ownedArenas
for index = 1 , # arenas do
arenas [ index ] : reset ( )
end
if not observers . pending then
return
end
observers . pending = false





local dirty = observers . dirty
local byAddress = observers . byAddress
for address in pairs ( dirty ) do
dirty [ address ] = nil
local map = byAddress [ address ]
if map ~= nil then
local eventId , list = next ( map )
while eventId ~= nil do
local following , followingList = next ( map , eventId )
compact ( list )
prune ( observers , address , eventId , list )
if byAddress [ address ] ~= map then
do break end
end
eventId , list = following , followingList
end
end
end
local detached = observers . detached
for index = # detached , 1 , -1 do
local item = detached [ index ]
detached [ index ] = nil
if item . n ~= nil then
giveList ( observers , item )
else
giveMap ( observers , item )
end
end
end



local function touched ( observers , address , eventId , list ) 
if observers . depth > 0 then
observers . dirty [ address ] = true
observers . pending = true
return
end
compact ( list )
prune ( observers , address , eventId , list )
end


local function liveIn ( list ) 
local live = 0
local n = list . n
for index = 1 , n do
if list [ ( index - 1 ) * 3 + 2 ] ~= tombstone then
live = live + 1
end
end

return live
end





local function register (
source ,
address ,
event ,
callback ,
id ,
once
) 
local observers = source . observers
local info = infoFor ( event )
local map = observers . byAddress [ address ]
if map == nil then
map = takeMap ( observers )
observers . byAddress [ address ] = map
end
local list = map [ info . id ]
if list == nil then
list = takeList ( observers )
map [ info . id ] = list
end
local n = list . n
if id ~= nil then
for index = 1 , n do
local base = ( index - 1 ) * 3
if list [ base + 1 ] == id and list [ base + 2 ] ~= tombstone then
error ( ("nupp: events observer %q is already registered for %s here") : format ( id , info . name ) , 3 )
end
end
end
local base = n * 3
list [ base + 1 ] = id or false
list [ base + 2 ] = callback
list [ base + 3 ] = once
list . n = n + 1
if once then
list . once = ( list . once ) + 1
end
observers . count = observers . count + 1
end














function events . observe (
source ,
address ,
event ,
callback ,
id
) 
register ( source , address , event , callback , id , false )
end













function events . observeOnce (
source ,
address ,
event ,
callback ,
id
) 
register ( source , address , event , callback , id , true )
end














function events . stopObserving (
source ,
address ,
event ,
callbackOrId
) 
local observers = source . observers
if observers . count == 0 then
return false
end
local info = infoFor ( event )
local map = observers . byAddress [ address ]
local list = map and map [ info . id ] or nil
if list == nil then
return false
end
local byName = type ( callbackOrId ) == "string"
local removed = 0
local n = list . n
for index = 1 , n do
local base = ( index - 1 ) * 3
local callback = list [ base + 2 ]
if callback ~= tombstone then
local matches = byName and list [ base + 1 ] == callbackOrId or not byName and callback == callbackOrId
if matches then
list [ base + 2 ] = tombstone
if list [ base + 3 ] then
list . once = ( list . once ) - 1
end
list [ base + 3 ] = false
list . holes = ( list . holes ) + 1
removed = removed + 1
if byName then
do break end
end
end
end
end
if removed == 0 then
return false
end
observers . count = observers . count - removed
touched ( observers , address , info . id , list )

return true
end






function events . hasObservers (
source ,
address ,
event
) 
local observers = source . observers
if observers . count == 0 then
return false
end
local map = observers . byAddress [ address ]
local list = map and map [ infoFor ( event ) . id ] or nil

return list ~= nil and liveIn ( list ) > 0
end



local function detach ( observers , item ) 
if observers . depth > 0 then
local detached = observers . detached
detached [ # detached + 1 ] = item
observers . pending = true
elseif item . n ~= nil then
giveList ( observers , item )
else
giveMap ( observers , item )
end
end









function events . clearAddress ( source , address ) 
local observers = source . observers
local map = observers . byAddress [ address ]
if map == nil then
return
end
observers . byAddress [ address ] = nil
for _ , list in pairs ( map ) do
observers . count = observers . count - liveIn ( list )
detach ( observers , list )
end
detach ( observers , map )
end






function events . reset ( source ) 
local observers = source . observers
local addresses = { }
for address in pairs ( observers . byAddress ) do
addresses [ # addresses + 1 ] = address
end
for index = 1 , # addresses do
events . clearAddress ( source , addresses [ index ] )
end
end














function events . setAllocator (
source ,
event ,
allocator
) 
local observers = source . observers
if observers . depth > 0 then
error ( "nupp: events allocator cannot change while a delivery is active" , 2 )
end
observers . allocators [ infoOf ( event ) . id ] = allocator
end



local function allocatorFor ( observers , info ) 
local existing = observers . allocators [ info . id ]
if existing ~= nil then
return existing
end
local made
if info . representation == "struct" then
made = arena . newArena ( info . witness , 256 )
local owned = observers . ownedArenas
owned [ # owned + 1 ] = made
else
made = pool . new ( info . witness , 32 )
end
observers . allocators [ info . id ] = made

return made
end











local function deliverTo ( observers , list , event , address , eventId ) 
local n = list . n
if list . once == 0 and list . holes == 0 then

for index = 1 , n do
( list [ ( index - 1 ) * 3 + 2 ] ) ( event )
end
return
end
for index = 1 , n do
local base = ( index - 1 ) * 3
local callback = list [ base + 2 ]
if callback ~= tombstone then
if list [ base + 3 ] then
list [ base + 2 ] = tombstone
list [ base + 3 ] = false
list . once = ( list . once ) - 1
list . holes = ( list . holes ) + 1
observers . count = observers . count - 1
touched ( observers , address , eventId , list )
end
callback ( event )
end
end
end







local function finish ( observers , allocator , storage , ok , failure ) 
local released = true
local releaseFailure = nil
if allocator ~= nil then
released , releaseFailure = pcall ( allocator . release , allocator , storage )
end
observers . depth = observers . depth - 1
if observers . depth == 0 then
settle ( observers )
end
if not released then
error ( releaseFailure , 0 )
end
if not ok then
error ( failure , 0 )
end
end

















function events . emit (
source ,
address ,
event ,
...
) 
local observers = source . observers
if observers . count == 0 then
return
end
local info = infoFor ( event )
local map = observers . byAddress [ address ]
local list = map and map [ info . id ] or nil
if list == nil or list . n == 0 then
return
end
local allocator = allocatorFor ( observers , info )
local storage = allocator : acquire ( )
observers . depth = observers . depth + 1





local fill = info . initializer
local ok , failure = pcall ( fill , storage , ... )
if ok then
ok , failure = pcall ( deliverTo , observers , list , storage , address , info . id )
end
finish ( observers , allocator , storage , ok , failure )
end











function events . deliver (
source ,
address ,
event ,
instance
) 
local observers = source . observers
if observers . count == 0 then
return
end
local info = infoFor ( event )
local map = observers . byAddress [ address ]
local list = map and map [ info . id ] or nil
if list == nil or list . n == 0 then
return
end
observers . depth = observers . depth + 1
local ok , failure = pcall ( deliverTo , observers , list , instance , address , info . id )
finish ( observers , nil , nil , ok , failure )
end










events.MessageBus = {} events.MessageBus.__index = events.MessageBus ;_G.nupp.__reflect.link(events.MessageBus,__nuppT1[2],{ __nuppT1[1] })
































































function events . MessageBus . observe (
self ,
address ,
event ,
callback ,
id
) 
events . observe ( self , address , event , callback , id )
end

function events . MessageBus . observeOnce (
self ,
address ,
event ,
callback ,
id
) 
events . observeOnce ( self , address , event , callback , id )
end

function events . MessageBus . stopObserving (
self ,
address ,
event ,
callbackOrId
) 
return events . stopObserving ( self , address , event , callbackOrId )
end

function events . MessageBus . hasObservers (
self ,
address ,
event
) 
return events . hasObservers ( self , address , event )
end

function events . MessageBus . emit (
self ,
address ,
event ,
...
) 
events . emit ( self , address , event , ... )
end

function events . MessageBus . deliver (
self ,
address ,
event ,
instance
) 
events . deliver ( self , address , event , instance )
end

function events . MessageBus . clearAddress ( self , address ) 
events . clearAddress ( self , address )
end

function events . MessageBus . reset ( self ) 
events . reset ( self )
end

function events . MessageBus . setAllocator (
self ,
event ,
allocator
) 
events . setAllocator ( self , event , allocator )
end






function events . newMessageBus ( ) 
local observers = events . newObservers ( )
return ( _G.setmetatable({ observers =  observers }, events.MessageBus) )
end

local __nuppExportValue= events ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.events"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.events"]=__nuppExports;return __nuppExports