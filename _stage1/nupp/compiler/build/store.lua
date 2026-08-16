_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);



















local buffer = require ( "string.buffer" )
local fs = require ( "nupp.compiler.fs" )

local store = { }



local FORMAT = 1







local KEEP_COLD = 2048


store.Store = {} store.Store.__index = store.Store
































function store . open ( path , stamp )
local entries = { }
local order = { }
local live = { }
local dirty = false
local stats = { gets = 0 , hits = 0 , puts = 0 }
local self = setmetatable({ path =  path ,  stamp =  stamp ,  stats =  stats }, store.Store)

if path then
local text = fs . readFile ( path )
if text then



local ok , decoded = pcall ( buffer . decode , text )
if ok and type (
decoded
) == "table" and decoded . format == FORMAT and decoded . stamp == stamp and type (
decoded . order
) == "table" and type ( decoded . entries ) == "table" then
entries = decoded . entries
for _ , key in ipairs ( decoded . order ) do
if entries [ key ] ~= nil then
order [ # order + 1 ] = key
end
end
end
end
end

function self . get ( key )
stats . gets = ( stats . gets or 0 ) + 1
local value = entries [ key ]
if value == nil then
return nil
end
stats . hits = ( stats . hits or 0 ) + 1
live [ key ] = true

return value
end

function self . put ( key , value )
stats . puts = ( stats . puts or 0 ) + 1
if entries [ key ] == nil then
order [ # order + 1 ] = key
end
entries [ key ] = value
live [ key ] = true
dirty = true
end

function self . save ( )
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
for index = # order , 1 , - 1 do
local key = order [ index ]
if not live [ key ] and cold < KEEP_COLD then
cold = cold + 1
keptOrder [ # keptOrder + 1 ] = key
keptEntries [ key ] = entries [ key ]
end
end
local ok , text = pcall ( buffer . encode , {
format = FORMAT ,
stamp = stamp ,
order = keptOrder ,
entries = keptEntries ,
} )


if ok then
pcall ( fs . writeFile , path , text )
end
dirty = false
end

return self
end






store.Value = {} store.Value.__index = store.Value











function store . openValue ( path , stamp )
local self = setmetatable({ }, store.Value)
local dirty = false
if path then
local text = fs . readFile ( path )
if text then
local ok , decoded = pcall ( buffer . decode , text )
if ok and type ( decoded ) == "table" and decoded . format == FORMAT and decoded . stamp == stamp then
self . value = decoded . value
end
end
end
function self . set ( value )
self . value = value
dirty = true
end

function self . save ( )
if not path or not dirty then
return
end
local ok , text = pcall ( buffer . encode , { format = FORMAT , stamp = stamp , value = self . value } )
if ok then
pcall ( fs . writeFile , path , text )
end
dirty = false
end

return self
end

return store
