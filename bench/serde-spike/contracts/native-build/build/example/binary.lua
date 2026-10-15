_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.binary"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local encode;__nuppExports["encode"]=function(...) return encode(...) end;local identity;__nuppExports["identity"]=function(...) return identity(...) end;local reader;__nuppExports["reader"]=function(...) return reader(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.binary\0runtime\0001") , _G.nupp.__reflect.declaration("example.binary\0runtime\0002") , _G.nupp.__reflect.declaration("example.binary\0runtime\0003") };

local core = require ( "nupp.serde" )



local Field = {} Field.__index = Field


function Field:diagnosticLabel() 
return "binary field"
end ;_G.nupp.__reflect.link(Field,__nuppT1[1],{ }) ;__nuppExports["Field"]=Field


local Entry = {} Entry.__index = Entry ;_G.nupp.__reflect.link(Entry,__nuppT1[2],{ __nuppT1[1] }) ;__nuppExports["Entry"]=Entry




local function word ( value , size ) 
local bytes = { }
for index = size , 1 , -1 do
bytes [ index ] = string . char ( value % 256 )
value = math . floor ( value / 256 )
end

return table . concat ( bytes )
end

encode=function ( entries ) 
assert ( # entries <= 100000 , "binary field count exceeded" )
local parts = { "NB1\0" }
for _ , entry in ipairs ( entries ) do
local field = entry . field
if field . number < 1
or field . number > 65535
or field . number % 1 ~= 0
or field . wire < 0
or field . wire > 255
or field . wire % 1 ~= 0
then
error ( "binary field identity is out of range" , 2 )
end
if # entry . bytes > 16777216 then
error ( "binary field exceeds byte limit" , 2 )
end
parts [ # parts + 1 ] = word ( field . number , 2 ) .. string . char ( field . wire ) .. word ( # entry . bytes , 4 ) .. entry . bytes
end

return table . concat ( parts )
end ;__nuppExports["encode"]=encode

local Reader = {} Reader.__index = Reader



function Reader:next() 
local bytes , position = self . bytes , self . position
if position > # bytes then
return nil
end
if # bytes - position + 1 < 7 then
error ( "truncated binary field header" , 2 )
end
self . count += 1
if self . count > 100000 then
error ( "binary field count exceeded" , 2 )
end
local number = bytes : byte ( position ) * 256 + bytes : byte ( position + 1 )
local wire = bytes : byte ( position + 2 )
local size = 0
for index = position + 3 , position + 6 do
size = size * 256 + bytes : byte ( index )
end
if number == 0 then
error ( "binary field zero is reserved" , 2 )
end
if size > 16777216 then
error ( "binary field exceeds byte limit" , 2 )
end
position += 7
if position + size - 1 > # bytes then
error ( "truncated binary field value" , 2 )
end
self . position = position + size

return ( _G.setmetatable({ field =
_G.setmetatable({ number =  number ,  wire =  wire }, Field) ,  bytes =
bytes : sub ( position , position + size - 1 ) }, Entry) )

end ;_G.nupp.__reflect.link(Reader,__nuppT1[3],{ }) ;__nuppExports["Reader"]=Reader


reader=function ( bytes ) 
if bytes : sub ( 1 , 4 ) ~= "NB1\0" then
error ( "unsupported binary fixture version" , 2 )
end
return ( _G.setmetatable({ bytes =  bytes ,  position =  5 ,  count =  0 }, Reader) )
end ;__nuppExports["reader"]=reader

identity=function ( field ) 
if getmetatable ( field ) ~= Field then
error ( "not a binary field identity" , 2 )
end
return field
end ;__nuppExports["identity"]=identity
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Entry]="example.binary\0Entry";__nuppWorkerRecords[Field]="example.binary\0Field";__nuppWorkerRecords[Reader]="example.binary\0Reader"; end);if not __nuppOk then package.loaded["example.binary"]=nil;error(__nuppWhy,0) end;package.loaded["example.binary"]=__nuppExports;return __nuppExports