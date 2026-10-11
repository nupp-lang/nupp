_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.project.store\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.project.store\0runtime\0002") };




























local loaded , nativeBuffer = pcall ( require , "string.buffer" )

local function unavailable ( ) 
error ( "binary cache serialization is unavailable on this host" )
end

local buffer = loaded and nativeBuffer or { encode = unavailable , decode = unavailable }
local fs = require ( "nupp.compiler.fs" )

local store = { }



local FORMAT = 3









local KEEP_STAMPS = 2









local sealMemo = nil

local function sealDigest ( ) 
if sealMemo == nil then
local ok , services = pcall ( require , "nupp.compiler.hostservices" )
local digest = ok and services and services . hash and services . hash . digest or nil

sealMemo = digest and pcall ( digest , "" ) and digest or false
end

return sealMemo or nil
end



local function slotsIn ( path ) 
local text = fs . readFile ( path )
if not text then
return { }
end



local ok , envelope = pcall ( buffer . decode , text )
if not ok or type ( envelope ) ~= "table" or envelope . format ~= 3 or type ( envelope . slots ) ~= "table" then
return { }
end
local slots = { }
for _ , slot in ipairs ( envelope . slots ) do
if type ( slot ) == "table" and type ( slot . stamp ) == "string" and type ( slot . body ) == "string" then
slots [ # slots + 1 ] = slot
end
end

return slots
end






local function writeSealed ( path , stamp , body ) 
local ok , inner = pcall ( buffer . encode , body )
if not ok then
return
end
local digest = sealDigest ( )
local slots = { { stamp = stamp , seal = digest and digest ( inner ) or nil , body = inner } }
for _ , slot in ipairs ( slotsIn ( path ) ) do
if # slots >= 2 then
do break end
end
if slot . stamp ~= stamp then
slots [ # slots + 1 ] = slot
end
end
local encoded , text = pcall ( buffer . encode , { format = 3 , slots = slots } )


if encoded then
pcall ( fs . writeFile , path , text )
end
end





local function unseal ( path , stamp ) 
for _ , slot in ipairs ( slotsIn ( path ) ) do
if slot . stamp == stamp then
local digest = sealDigest ( )
if digest and slot . seal ~= digest ( slot . body ) then
return nil
end
local decodedOk , body = pcall ( buffer . decode , slot . body )

return decodedOk and body or nil
end
end

return nil
end







local KEEP_COLD = 2048


store.Store = {} store.Store.__index = store.Store ;_G.nupp.__reflect.link(store.Store,__nuppT1[1],{ })
































function store . open ( path , stamp ) 
local entries = { }
local order = { }
local live = { }
local dirty = false
local stats = { gets = 0 , hits = 0 , puts = 0 }

if path then
local decoded = unseal ( path , stamp )
if type ( decoded ) == "table" and type ( decoded . order ) == "table" and type ( decoded . entries ) == "table" then
entries = decoded . entries
for _ , key in ipairs ( decoded . order ) do
if entries [ key ] ~= nil then
order [ # order + 1 ] = key
end
end
end
end

local function get ( key ) 
stats . gets = ( stats . gets or 0 ) + 1
local value = entries [ key ]
if value == nil then
return nil
end
stats . hits = ( stats . hits or 0 ) + 1
live [ key ] = true

return value
end

local function put ( key , value ) 
stats . puts = ( stats . puts or 0 ) + 1
if entries [ key ] == nil then
order [ # order + 1 ] = key
end
entries [ key ] = value
live [ key ] = true
dirty = true
end

local function save ( ) 
if not path or not dirty then
return
end




local keptOrder = { }
local keptEntries = { }
for _ , key in ipairs ( order ) do
if live [ key ] then
keptOrder [ # keptOrder + 1 ] = key
keptEntries [ key ] = entries [ key ]
end
end
local cold = 0
for index = # order , 1 , -1 do
local key = order [ index ]
if not live [ key ] and cold < 2048 then
cold = cold + 1
keptOrder [ # keptOrder + 1 ] = key
keptEntries [ key ] = entries [ key ]
end
end
writeSealed ( path , stamp , { order = keptOrder , entries = keptEntries } )
dirty = false
end

return ( _G.setmetatable({ path =  path ,  stamp =  stamp ,  stats =  stats ,  get =  get ,  put =  put ,  save =  save }, store.Store) )
end






store.Value = {} store.Value.__index = store.Value ;_G.nupp.__reflect.link(store.Value,__nuppT1[2],{ })











function store . openValue ( path , stamp ) 
local self
local initial
local dirty = false
if path then
local decoded = unseal ( path , stamp )
if type ( decoded ) == "table" then
initial = decoded . value
end
end

local function set ( value ) 
assert ( self ) . value = value
dirty = true
end

local function save ( ) 
if not path or not dirty then
return
end
writeSealed ( path , stamp , { value = assert ( self ) . value } )
dirty = false
end

self = _G.setmetatable({ value =  initial ,  set =  set ,  save =  save }, store.Value)

return self
end

local __nuppExportValue= store ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.store"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.store"]=__nuppExports;return __nuppExports