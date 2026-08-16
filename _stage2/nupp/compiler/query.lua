_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
















local query = { }

















































query.Q = {} query.Q.__index = query.Q





























function query . new ( )
return setmetatable({ revision =
1 ,  inputs =
{ } ,  defs =
{ } ,  memo =
{ } ,  stack =
{ } ,  active =
{ } ,  stats =
{ } ,  hits =
{ } ,  cutoffs =
{ } }, query.Q)

end






function query . Q : define ( name , fn , eq )
self . defs [ name ] = { fn = fn , eq = eq }
end


function query . Q : setInput ( name , key , value )
self . revision = self . revision + 1
local byName = self . inputs [ name ] or { }
self . inputs [ name ] = byName
byName [ key ] = { value = value , changedAt = self . revision }
end


function query . Q : clearInput ( name , key )
self . revision = self . revision + 1
local byName = self . inputs [ name ]
if byName then
byName [ key ] = nil
end

local m = self . memo [ name ]
if m then
m [ key ] = nil
end
end



local depChangedAt


local function record ( self , name , key )
local top = self . stack [ # self . stack ]
if top then
top . deps [ # top . deps + 1 ] = { name = name , key = key }
end
end












function query . Q : get ( name , key )
local byInput = self . inputs [ name ]
local inp = byInput and byInput [ key ]
if inp then
record ( self , name , key )
return inp . value
end

local def = assert ( self . defs [ name ] , "unknown query: " .. tostring ( name ) )
local m = self . memo [ name ] or { }
self . memo [ name ] = m
local entry = m [ key ]

if entry and entry . verifiedAt == self . revision then
self . hits [ name ] = ( self . hits [ name ] or 0 ) + 1
record ( self , name , key )
return entry . value
end

local activeKey = name .. "\0" .. tostring ( key )
if self . active [ activeKey ] then

record ( self , name , key )
return entry and entry . value or nil
end

if entry then




self . stack [ # self . stack + 1 ] = { deps = { } }
local validated , clean = pcall ( function ( )
for _ , d in ipairs ( entry . deps ) do
if depChangedAt ( self , d . name , d . key ) > entry . verifiedAt then
return false
end
end

return true
end )
self . stack [ # self . stack ] = nil
if not validated then
error ( clean , 0 )
end
if clean then
entry . verifiedAt = self . revision
self . hits [ name ] = ( self . hits [ name ] or 0 ) + 1
record ( self , name , key )
return entry . value
end
end

self . stats [ name ] = ( self . stats [ name ] or 0 ) + 1
self . active [ activeKey ] = true
self . stack [ # self . stack + 1 ] = { deps = { } }
local ok , value = pcall ( def . fn , self , key )
local frame = self . stack [ # self . stack ]
self . stack [ # self . stack ] = nil
self . active [ activeKey ] = nil
if not ok then
error ( value , 0 )
end

local changedAt = self . revision
if entry then
local same
if def . eq then
same = def . eq ( entry . value , value )
else
same = entry . value == value
end
if same then
self . cutoffs [ name ] = ( self . cutoffs [ name ] or 0 ) + 1
changedAt = entry . changedAt
value = entry . value
end
end
m [ key ] = { value = value , changedAt = changedAt , verifiedAt = self . revision , deps = frame . deps }
record ( self , name , key )

return value
end



depChangedAt = function ( self , name , key )
local byName = self . inputs [ name ]
local inp = byName and byName [ key ]
if inp then
return inp . changedAt
end
self : get ( name , key )
local m = self . memo [ name ]
local entry = m and m [ key ]

return entry and entry . changedAt or self . revision
end

return query
