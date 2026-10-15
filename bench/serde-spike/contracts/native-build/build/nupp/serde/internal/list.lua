_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.list"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local adapter;__nuppExports["adapter"]=function(...) return adapter(...) end;

local core = require ( "nupp.serde.internal.value" )
local Child = {} Child.__index = Child




function Child:describe(direction) 
return self . adapter : describe ( direction )
end

local Description = {} Description.__index = Description








local Elements = {} Elements.__index = Elements

function Elements:apply(source, writer) 
for _ , value in ipairs ( source ) do
self . adapter : write ( value , writer )
end
end

local Read = {} Read.__index = Read

function Read:apply(state, index, reader) 
assert ( index == # state + 1 , "nonsequential list element" )
local value = self . adapter : read ( reader )
assert ( value ~= nil , "dense list elements cannot be nil" )
state [ index ] = value
end

local Adapter = {} Adapter.__index = Adapter




function Adapter:describe(direction) 
local selected = self . child : describe ( direction )
return ( _G.setmetatable({ member =  self . member ,  children =  { self . child } ,  canRead =  selected . canRead ,  kind =  "list" ,  nullable =  false }, Description) )
end

function Adapter:write(value, writer) 
writer : writeList ( self . member , # value , value , self . emit )
end

function Adapter:read(reader) 
local values = { }
reader : readList ( self . member , values , self . consume )
return values
end

adapter=function (
member ,
element ,
adapter
) 
return ( _G.setmetatable({ member =
member ,  child =
_G.setmetatable({ member =  element ,  adapter =  adapter ,  required =  true ,  hasDefault =  false }, Child) ,  emit =
_G.setmetatable({ adapter =  adapter }, Elements) ,  consume =
_G.setmetatable({ adapter =  adapter }, Read) }, Adapter) )

end ;__nuppExports["adapter"]=adapter
 end);if not __nuppOk then package.loaded["nupp.serde.internal.list"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.list"]=__nuppExports;return __nuppExports