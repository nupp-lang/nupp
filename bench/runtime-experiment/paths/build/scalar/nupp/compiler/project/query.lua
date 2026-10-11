_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.project.query\0runtime\0001") };


















local query = { }

















































query.Q = {} query.Q.__index = query.Q ;_G.nupp.__reflect.link(query.Q,__nuppT1[1],{ })






























function query . new ( ) 
return ( _G.setmetatable({ revision =
1 ,  inputs =
{ } ,  defs =
{ } ,  memo =
{ } ,  stack =
{ } ,  active =
{ } ,  stats =
{ } ,  hits =
{ } ,  cutoffs =
{ } }, query.Q) )

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

local active = self . active [ name ]
if active and active [ key ] then

record ( self , name , key )
return entry and entry . value or nil
end

if entry then











self . stack [ # self . stack + 1 ] = { deps = { } }
active = active or { }
self . active [ name ] = active
active [ key ] = true
local validated , clean = pcall ( function ( ) 
for _ , d in ipairs ( entry . deps ) do
if depChangedAt ( self , d . name , d . key ) > entry . verifiedAt then
return false
end
end

return true
end )
active [ key ] = nil
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
active = active or { }
self . active [ name ] = active
active [ key ] = true
self . stack [ # self . stack + 1 ] = { deps = { } }
local ok , value = pcall ( def . fn , self , key )
local frame = self . stack [ # self . stack ]
self . stack [ # self . stack ] = nil
active [ key ] = nil
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

local __nuppExportValue= query ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.query"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.query"]=__nuppExports;return __nuppExports