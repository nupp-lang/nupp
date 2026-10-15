_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.maps"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local mapping;__nuppExports["mapping"]=function(...) return mapping(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.maps\0runtime\0001") , _G.nupp.__reflect.declaration("example.maps\0runtime\0002") , _G.nupp.__reflect.declaration("example.maps\0runtime\0003") , _G.nupp.__reflect.declaration("example.maps\0runtime\0004") , _G.nupp.__reflect.declaration("example.maps\0runtime\0005") };

local core = require ( "nupp.serde" )

local Key = {} Key.__index = Key

function Key:apply(source, writer) 
writer : writeInteger ( self . member , _G.setmetatable({ decimal =  tostring ( source ) ,  width =  32 ,  signed =  true }, core.Integer) )
end ;_G.nupp.__reflect.link(Key,__nuppT1[1],{ })


local Value = {} Value.__index = Value

function Value:apply(source, writer) 
writer : writeString ( self . member , source : sub ( 1 ) )
end ;_G.nupp.__reflect.link(Value,__nuppT1[2],{ })


local Entries = {} Entries.__index = Entries


function Entries:apply(source, writer) 
local keys = { }
for key in pairs ( source ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
for _ , key in ipairs ( keys ) do
writer : writeEntry ( key , self . key , assert ( source [ key ] ) , self . value )
end
end ;_G.nupp.__reflect.link(Entries,__nuppT1[3],{ __nuppT1[1] , __nuppT1[2] })


local Read = {} Read.__index = Read


function Read:apply(state, key, value) 





local number = key : readInteger ( self . key , 32 , true )
local index = tonumber ( number . decimal )
if state [ index ] ~= nil then
error ( "duplicate logical map key" , 2 )
end
state [ index ] = value : readString ( self . value )
end ;_G.nupp.__reflect.link(Read,__nuppT1[4],{ })


local Map = {} Map.__index = Map



function Map:write(value, writer) 
writer : writeMap ( self . member , nil , value , self . emit )
end

function Map:read(reader) 
local result = { }
reader : readMap ( self . member , result , self . consume )
return result
end ;_G.nupp.__reflect.link(Map,__nuppT1[5],{ __nuppT1[3] , __nuppT1[4] }) ;__nuppExports["Map"]=Map


mapping=function ( member , key , value ) 
return ( _G.setmetatable({ member =
member ,  emit =
_G.setmetatable({ key =  _G.setmetatable({ member =  key }, Key) ,  value =  _G.setmetatable({ member =  value }, Value) }, Entries) ,  consume =
_G.setmetatable({ key =  key ,  value =  value }, Read) }, Map) )

end ;__nuppExports["mapping"]=mapping
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Map]="example.maps\0Map"; end);if not __nuppOk then package.loaded["example.maps"]=nil;error(__nuppWhy,0) end;package.loaded["example.maps"]=__nuppExports;return __nuppExports