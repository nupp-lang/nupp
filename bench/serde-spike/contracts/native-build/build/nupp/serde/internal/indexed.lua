_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT19={}; local function __nuppT16(...) return {n=select("#",...),...} end; local __nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25,__nuppT26,__nuppT27=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT17(value) return value end; local function __nuppT18(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT25({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT26(v.primary) for _,reason in __nuppT27(v.suppressed) do text=text.."\ncleanup: "..__nuppT26(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.indexed"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local layout;__nuppExports["layout"]=function(...) return layout(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.indexed\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.indexed\0runtime\0002") };

local core = require ( "nupp.serde.internal.value" )
local structures = require ( "nupp.serde.internal.structure" )




local Slot = {} Slot.__index = Slot ;_G.nupp.__reflect.link(Slot,__nuppT1[1],{ }) ;__nuppExports["Slot"]=Slot





local Value = {} Value.__index = Value













function Value:has(slot) 
assert ( slot . owner == self . owner , "slot belongs to another layout" )
return self . present [ slot . position ] == true
end










function Value:get(slot) 
assert ( slot . owner == self . owner , "slot belongs to another layout" )
return self . values [ slot . position ]
end






function Value:set(slot, value) 
assert ( slot . owner == self . owner , "slot belongs to another layout" )
self . values [ slot . position ] = value
self . present [ slot . position ] = true
end





function Value:remove(slot) 
assert ( slot . owner == self . owner , "slot belongs to another layout" )
self . values [ slot . position ] = nil
self . present [ slot . position ] = nil
end ;_G.nupp.__reflect.link(Value,__nuppT1[2],{ }) ;__nuppExports["Value"]=Value


local Builder = {} Builder.__index = Builder

function Builder:close() 
self . value = nil
end


local Field = {} Field.__index = Field






function Field:describe(direction) 
return self . adapter : describe ( direction )
end

function Field:write(source, writer) 
assert ( source . owner == self . slot . owner , "value belongs to another layout" )
if source : has ( self . slot ) then
self . adapter : write ( source . values [ self . slot . position ] , writer )
elseif self . hasDefault then
self . adapter : write ( assert ( self . default ) ( ) , writer )
else
assert ( not self . required , "missing required indexed member: " .. self . member . name )
end
end

function Field:read(state, reader) 
local value = assert ( state . value , "closed indexed builder" )
assert ( not value : has ( self . slot ) , "duplicate indexed member" )
value : set ( self . slot , self . adapter : read ( reader ) )
end

function Field:accept(consumer) 
local slot = self . slot
return consumer : apply (
self . member ,
function ( source ) 
return source : has ( slot )
end ,
structures . borrowedGet ( function ( source ) 
assert ( source : has ( slot ) , "absent indexed member" )
return source . values [ slot . position ]
end ) ,
function ( state , value ) 
assert ( state . value , "closed indexed builder" ) : set ( slot , value )
end ,
self . adapter ,
self . default
)
end


local Construction = {} Construction.__index = Construction



function Construction:begin() 
return ( _G.setmetatable({ value =  _G.setmetatable({ owner =  self . owner ,  values =  {} ,  present =  {} }, Value) }, Builder) )
end

function Construction:finish(state) 
do local __nuppT28=0; local  __nuppT34 ; local __nuppT35=false ; local __nuppT29,__nuppT30,__nuppT31=__nuppT21(function() do local __nuppT36= state ; __nuppT34= __nuppT36 ; __nuppT28=1;  __nuppT35=true;  local owned=__nuppT34;
local value = assert ( owned . value )
for index , field in ipairs ( self . fields ) do
if not value . present [ index ] then
assert ( not field . required or field . hasDefault , "missing required indexed member: " .. field . member . name )
if field . hasDefault then
value . values [ index ] = assert ( self . defaults [ index ] ) ( )
value . present [ index ] = true
end
end
end
do (function(__nuppT37,...)  __nuppT35=false; return __nuppT37:close(...)  end)( owned ) end

return "return",__nuppT16( value ) end; return "normal" end,__nuppT17); local __nuppT32={}; local __nuppT33=0; if __nuppT28>=1 and __nuppT35 then  local __nuppT38,__nuppT39=__nuppT20(__nuppCleanup1,__nuppT34);  if not __nuppT38 then __nuppT33=__nuppT33+1; __nuppT32[__nuppT33]=__nuppT39 end; end; if not __nuppT29 then if __nuppT33>0 then __nuppT22(__nuppT18(__nuppT30,__nuppT32,1),0) else __nuppT22(__nuppT30,0) end end; if __nuppT33>0 then if __nuppT33>1 then __nuppT22(__nuppT18(__nuppT32[1],__nuppT32,2),0) else __nuppT22(__nuppT32[1],0) end end; if __nuppT30=="return" then  return __nuppT23(__nuppT31,1,__nuppT31.n)  end; end
end





















































local Mapping = {} Mapping.__index = Mapping






function Mapping:define(member, adapter, required, default, hasDefault) 







assert ( self . selected == nil , "indexed layout is sealed" )
assert ( adapter : describe ( "write" ) . member == member , "adapter describes another member" )
for _ , field in ipairs ( self . fields ) do
assert ( field . member ~= member , "duplicate indexed member" )
end
local position = # self . fields + 1
local slot = _G.setmetatable({ owner =  self . owner ,  position =  position }, Slot)
self . fields [
position
] = _G.setmetatable({ member =
member ,  required =
required ,  hasDefault =
hasDefault ,  slot =
slot ,  adapter =
adapter ,  default =
default }, Field)

if default ~= nil then
self . defaults [ position ] = default
end

return slot
end

function Mapping:add(member, adapter, required) 
return self : define ( member , adapter , required , nil , false )
end

function Mapping:addDefault(member, adapter, default) 





return self : define ( member , adapter , false , default , true )
end

function Mapping:value() 
return ( _G.setmetatable({ owner =  self . owner ,  values =  {} ,  present =  {} }, Value) )
end

function Mapping:binding() 
local selected = self . selected
if selected == nil then
selected = _G.setmetatable({ adapter =
structures . adapter (
self . member ,
self . fields ,
_G.setmetatable({ owner =  self . owner ,  fields =  self . fields ,  defaults =  self . defaults }, Construction) ,
nil ,
nil ,
true
) }, core.Bound)

self . selected = selected
end

return selected
end


layout=function ( member ) 
return ( _G.setmetatable({ member =  member ,  owner =  {} ,  fields =  {} ,  defaults =  {} }, Mapping) )
end ;__nuppExports["layout"]=layout
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Slot]="nupp.serde.internal.indexed\0Slot";__nuppWorkerRecords[Value]="nupp.serde.internal.indexed\0Value"; end);if not __nuppOk then package.loaded["nupp.serde.internal.indexed"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.indexed"]=__nuppExports;return __nuppExports