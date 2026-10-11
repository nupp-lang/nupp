_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.native.writer"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local value;__nuppExports["value"]=function(...) return value(...) end;

local core = require ( "nupp.serde.internal.value" )
local documents = require ( "nupp.serde.internal.document" )
local numbers = require ( "nupp.serde.internal.numbers" )
local json = require ( "nupp.codec.json" )


local Budget = {} Budget.__index = Budget


local Frame = {} Frame.__index = Frame








local fromContents





local Output = {} Output.__index = Output





function Output:live() 
assert ( not self . closed , "native writer has expired" )
end

function Output:close() 
self . closed = true
end

function Output:include(member) 
self : live ( )
return true
end

function Output:put(member, value) 
self : live ( )
self . budget . nodes += 1
assert ( self . budget . nodes <= 1000000 , "native persistence tree limit exceeded" )
local frame = self . frames [ # self . frames ]
if frame == nil then
assert ( self . result == nil , "native root was written twice" )
self . result = value
elseif frame . kind == "structure" or frame . kind == "union" then
assert ( not frame . names [ member . name ] , "duplicate native member" )
frame . names [ member . name ] = true
frame . value [ # frame . value + 1 ] = member . name
frame . value [ # frame . value + 1 ] = value
frame . count += 1
elseif frame . kind == "map" then
assert ( frame . inEntry , "native value outside a map entry" )
if frame . readingKey then
assert ( frame . key == nil , "map key was written twice" )
frame . key = value
else
frame . value [ # frame . value + 1 ] = assert ( frame . key , "map entry has no key" )
frame . value [ # frame . value + 1 ] = value
frame . key = nil
frame . count += 1
end
else
frame . value [ # frame . value + 1 ] = value
frame . count += 1
end
end

function Output:writeNull(member) 
self : put ( member , { "null" } )
end

function Output:writeBoolean(member, value) 
self : put ( member , { "boolean" , value } )
end

function Output:writeString(member, value) 
self : put ( member , { "string" , value } )
end

function Output:writeBytes(member, value) 
self : put ( member , { "bytes" , value } )
end

function Output:writeNumberToken(member, value) 
json . numberToken ( value )
self : put ( member , { "numberToken" , value } )
end

function Output:writeBigInteger(member, value) 
documents . bigInteger ( value )
self : put ( member , { "bigInteger" , value } )
end

function Output:writeInteger(member, value) 
numbers . integer ( value . decimal , value . width , value . signed )
self : put ( member , { "integer" , value . decimal , value . width , value . signed } )
end

function Output:writeFloat(member, value, width) 
self : put ( member , { "float" , numbers . floating ( value , width , true ) , width } )
end

function Output:writeDecimal(member, value) 
documents . bigInteger ( value . coefficient )
assert ( value . exponent % 1 == 0 and math . abs ( value . exponent ) <= 9007199254740991 , "invalid decimal exponent" )
self : put ( member , { "decimal" , value . coefficient , value . exponent } )
end

function Output:writeTimestamp(member, value) 
numbers . integer ( value . seconds , 64 , true )
assert ( value . nanos % 1 == 0 and value . nanos >= 0 and value . nanos < 1000000000 , "invalid timestamp nanos" )
self : put ( member , { "timestamp" , value . seconds , value . nanos } )
end

function Output:writeAtom(member, value) 
error ( "native persistence refuses atoms without an explicit adapter" , 2 )
end

function Output:writeDocument(member, value, adapter) 
self : put ( member , { "document" , fromContents ( adapter , value , self . depth + # self . frames + 1 , self . budget ) } )
end

function Output:aggregate(member, kind, size, source, emit) 







self : live ( )
assert ( self . depth + # self . frames < 128 , "native persistence nesting limit exceeded" )
local frame = _G.setmetatable({ kind =  kind ,  value =  { kind } ,  names =  {} ,  count =  0 ,  inEntry =  false ,  readingKey =  false }, Frame)
self . frames [ # self . frames + 1 ] = frame
emit : apply ( source , self )
assert ( size == nil or size == frame . count , "wrong native aggregate size" )
self . frames [ # self . frames ] = nil
self : put ( member , frame . value )
end

function Output:writeStruct(member, source, emit) 
self : aggregate ( member , "structure" , nil , source , emit )
end

function Output:writeUnion(member, source, emit) 
self : aggregate ( member , "union" , 1 , source , emit )
end

function Output:writeList(member, size, source, emit) 
self : aggregate ( member , "list" , size , source , emit )
end

function Output:writeTuple(member, size, source, emit) 
self : aggregate ( member , "tuple" , size , source , emit )
end

function Output:writeMap(member, size, source, emit) 
self : aggregate ( member , "map" , size , source , emit )
end

function Output:writeEntry(key, keyEmit, value, valueEmit) 






self : live ( )
local frame = assert ( self . frames [ # self . frames ] , "entry outside map" )
assert ( frame . kind == "map" and not frame . inEntry , "entry outside map" )
frame . inEntry , frame . readingKey = true , true
keyEmit : apply ( key , self )
assert ( frame . key ~= nil , "map key was not written" )
frame . readingKey = false
local before = frame . count
valueEmit : apply ( value , self )
assert ( frame . count == before + 1 , "map value was not written" )
frame . inEntry = false
end

function Output:writeUnknown(field, value, adapter) 





self : live ( )
assert ( getmetatable ( field ) == documents . Name , "wire field needs an explicit logical identity mapping" )
local frame = assert ( self . frames [ # self . frames ] , "unknown field outside structure" )
assert ( frame . kind == "structure" or frame . kind == "union" , "unknown field outside structure" )
local name = ( field ) . name
assert ( not frame . names [ name ] , "unknown field collides with a logical member" )
frame . names [ name ] = true
frame . value [ # frame . value + 1 ] = name
frame . value [ # frame . value + 1 ] = fromContents ( adapter , value , self . depth + # self . frames , self . budget )
frame . count += 1
end

local Capture = {} Capture.__index = Capture


function Capture:apply(adapter, value) 
local writer = _G.setmetatable({ depth =  self . depth ,  budget =  self . budget ,  frames =  {} ,  closed =  false }, Output)
adapter : write ( value , writer )
assert ( # writer . frames == 0 , "unfinished native aggregate" )
local result = assert ( writer . result , "binding did not emit a value" )

return result
end

fromContents = function ( adapter , value , depth , budget ) 
assert ( depth <= 128 , "native persistence nesting limit exceeded" )
return adapter : contents ( ) : accept ( _G.setmetatable({ depth =  depth ,  budget =  budget }, Capture) , value )
end
value=function ( binding , value ) 
return binding : accept ( _G.setmetatable({ depth =  0 ,  budget =  _G.setmetatable({ nodes =  0 }, Budget) }, Capture) , value )
end ;__nuppExports["value"]=value
 end);if not __nuppOk then package.loaded["nupp.serde.internal.native.writer"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.native.writer"]=__nuppExports;return __nuppExports