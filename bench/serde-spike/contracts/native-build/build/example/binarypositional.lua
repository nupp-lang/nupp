_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.binarypositional"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local decode;__nuppExports["decode"]=function(...) return decode(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.binarypositional\0runtime\0001") };

local core = require ( "nupp.serde" )
local integers = require ( "example.binarynumbers" )




local Slot = {} Slot.__index = Slot ;_G.nupp.__reflect.link(Slot,__nuppT1[1],{ }) ;__nuppExports["Slot"]=Slot






local function length ( size ) 
assert ( size >= 0 and size <= 16777216 , "positional slot exceeds byte limit" )
return string . char (
math . floor ( size / 16777216 ) % 256 ,
math . floor ( size / 65536 ) % 256 ,
math . floor ( size / 256 ) % 256 ,
size % 256
)
end

encode=function ( layout , values ) 
assert ( # values == # layout , "positional arity does not match its schema" )
local parts = { }
for index , slot in ipairs ( layout ) do
local value = values [ index ]
if slot . kind == "integer" then
assert ( type ( value ) ~= "string" , "integer slot requires an integer carrier" )
local selected = value
local numbers = require ( "nupp.serde.codec" )
parts [ index ] = integers . encode ( numbers . integer ( selected . decimal , slot . width , slot . signed ) )
else
assert ( type ( value ) == "string" , "variable slot requires bytes" )
local bytes = value
parts [ index ] = length ( # bytes ) .. bytes
end
end

return table . concat ( parts )
end ;__nuppExports["encode"]=encode

decode=function ( layout , bytes ) 
local values = { }
local position = 1
for index , slot in ipairs ( layout ) do
local size
if slot . kind == "integer" then
size = slot . width / 8
else
assert ( position + 3 <= # bytes , "truncated positional slot length" )
size = 0
for offset = 0 , 3 do
size = size * 256 + assert ( bytes : byte ( position + offset ) )
end
assert ( size <= 16777216 , "positional slot exceeds byte limit" )
position += 4
end
assert ( position + size - 1 <= # bytes , "truncated positional slot" )
local value = bytes : sub ( position , position + size - 1 )
values [ index ] = slot . kind == "integer" and integers . decode ( value , slot . width , slot . signed ) or value
position += size
end
assert ( position == # bytes + 1 , "positional suffix has no layout schema" )

return values
end ;__nuppExports["decode"]=decode
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Slot]="example.binarypositional\0Slot"; end);if not __nuppOk then package.loaded["example.binarypositional"]=nil;error(__nuppWhy,0) end;package.loaded["example.binarypositional"]=__nuppExports;return __nuppExports