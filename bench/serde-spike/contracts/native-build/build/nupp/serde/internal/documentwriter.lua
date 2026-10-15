_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.documentwriter"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local fromBinding;__nuppExports["fromBinding"]=function(...) return fromBinding(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.documentwriter\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.documentwriter\0runtime\0002") };

local core = require ( "nupp.serde.internal.value" )
local documents = require ( "nupp.serde.internal.document" )
local errors = require ( "nupp.serde.internal.errors" )
local numbers = require ( "nupp.serde.internal.numbers" )

local Frame = {} Frame.__index = Frame ;_G.nupp.__reflect.link(Frame,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0002","nupp.serde.internal.document") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0004","nupp.serde.internal.document") })










local fromContents

local Output = {} Output.__index = Output






function Output:live() 
assert ( not self . closed , "document writer scope has expired" )
end

function Output:finish() 
self : live ( )
assert ( # self . frames == 0 , "unfinished document aggregate" )
return assert ( self . result , "binding did not emit a value" )
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
if self . source ~= nil and value : context ( ) == nil then
value = documents . withContext ( value , self . source )
end
local frame = self . frames [ # self . frames ]
if frame == nil then
assert ( self . result == nil , "binding emitted more than one value" )
self . result = value
elseif frame . kind == "structure" or frame . kind == "union" then
assert ( not frame . names [ member . name ] , "duplicate logical document member" )
frame . names [ member . name ] = true
frame . fields [ # frame . fields + 1 ] = _G.setmetatable({ name =  member . name ,  value =  value }, documents.Entry)
elseif frame . kind == "map" then
assert ( frame . inEntry , "map value outside an entry" )
if frame . readingKey then
assert ( frame . key == nil , "map key emitted more than one value" )
frame . key = value
else
local key = assert ( frame . key , "map entry has no key or emitted more than one value" )
frame . entries [ # frame . entries + 1 ] = _G.setmetatable({ key =  key ,  value =  value }, documents.MapEntry)
frame . key = nil
end
else
frame . elements [ # frame . elements + 1 ] = value
end
end

function Output:writeNull(member) 
self : put ( member , documents . null ( ) )
end

function Output:writeBoolean(member, value) 
self : put ( member , documents . boolean ( value ) )
end

function Output:writeInteger(member, value) 
self : put ( member , documents . integer ( numbers . integer ( value . decimal , value . width , value . signed ) ) )
end

function Output:writeFloat(member, value, width) 
self : put ( member , documents . float ( _G.setmetatable({ value =  numbers . floating ( value , width , true ) ,  width =  width }, core.Float) ) )
end

function Output:writeBigInteger(member, value) 
self : put ( member , documents . bigInteger ( value ) )
end

function Output:writeDecimal(member, value) 
self : put (
member ,
documents . decimal ( _G.setmetatable({ coefficient =  value . coefficient ,  exponent =  value . exponent }, core.Decimal) )
)
end

function Output:writeNumberToken(member, value) 
self : put ( member , documents . numberToken ( value ) )
end

function Output:writeString(member, value) 
self : put ( member , documents . string ( value ) )
end

function Output:writeBytes(member, value) 
self : put ( member , documents . bytes ( value ) )
end

function Output:writeTimestamp(member, value) 
self : put ( member , documents . timestamp ( _G.setmetatable({ seconds =  value . seconds ,  nanos =  value . nanos }, core.Timestamp) ) )
end

function Output:writeAtom(member, value) 
self : put ( member , documents . atom ( value ) )
end

function Output:writeDocument(member, value, adapter) 
self : put ( member , documents . document ( fromContents ( adapter , value , self . depth + # self . frames + 1 ) ) )
end

function Output:aggregate(member, kind, size, source, emit) 







self : live ( )
if self . depth + # self . frames >= 128 then
error (
_G.setmetatable({ code =  "limit" ,  message =  "document nesting limit exceeded" ,  path =  "$" ,  cause =  nil ,  suppressed =  {} }, errors.Error) ,
0
)
end
local frame = _G.setmetatable({ kind =  kind ,  fields =  {} ,  elements =  {} ,  entries =  {} ,  names =  {} ,  inEntry =  false ,  readingKey =  false }, Frame)
self . frames [ # self . frames + 1 ] = frame
emit : apply ( source , self )
local value
if kind == "structure" then
value = documents . object ( frame . fields )
elseif kind == "union" then
assert ( # frame . fields == 1 , "union requires exactly one alternative" )
value = documents . union ( frame . fields [ 1 ] . name , frame . fields [ 1 ] . value )
elseif kind == "map" then
value = documents . map ( frame . entries )
elseif kind == "tuple" then
value = documents . tuple ( frame . elements )
else
value = documents . list ( frame . elements )
end
assert ( size == nil or value : size ( ) == size , "wrong aggregate size" )
table . remove ( self . frames )
self : put ( member , value )
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
assert ( frame . key ~= nil , "map key did not emit a value" )
frame . readingKey = false
local before = # frame . entries
valueEmit : apply ( value , self )
assert ( # frame . entries == before + 1 , "map entry did not emit a value" )
frame . inEntry = false
end

function Output:writeUnknown(field, value, adapter) 





self : live ( )
if getmetatable ( field ) ~= documents . Name then
error ( "wire field needs an explicit logical identity mapping" , 2 )
end
local frame = assert ( self . frames [ # self . frames ] , "unknown field outside structure" )
assert ( frame . kind == "structure" or frame . kind == "union" , "unknown field outside structure" )
local name = ( field ) . name
assert ( not frame . names [ name ] , "unknown field collides with a logical member" )
frame . names [ name ] = true
frame . fields [
# frame . fields + 1
] = _G.setmetatable({ name =  name ,  value =  fromContents ( adapter , value , self . depth + # self . frames ) }, documents.Entry)
end ;_G.nupp.__reflect.link(Output,__nuppT1[2],{ __nuppT1[1] , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["Output"]=Output


local Capture = {} Capture.__index = Capture


function Capture:apply(adapter, value) 
local writer = _G.setmetatable({ source =  self . context ,  depth =  self . depth ,  frames =  {} ,  closed =  false }, Output)
adapter : write ( value , writer )
return writer : finish ( )
end


fromContents = function ( adapter , value , depth ) 
assert ( depth <= 128 , "document nesting limit exceeded" )
return adapter : contents ( ) : accept ( _G.setmetatable({ context =  adapter : context ( value ) ,  depth =  depth }, Capture) , value )
end

fromBinding=function ( binding , value , context ) 
return binding : accept ( _G.setmetatable({ context =  context ,  depth =  0 }, Capture) , value )
end ;__nuppExports["fromBinding"]=fromBinding
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Output]="nupp.serde.internal.documentwriter\0Output"; end);if not __nuppOk then package.loaded["nupp.serde.internal.documentwriter"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.documentwriter"]=__nuppExports;return __nuppExports