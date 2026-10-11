_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.document"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local atom;__nuppExports["atom"]=function(...) return atom(...) end;local bigInteger;__nuppExports["bigInteger"]=function(...) return bigInteger(...) end;local boolean;__nuppExports["boolean"]=function(...) return boolean(...) end;local bytes;__nuppExports["bytes"]=function(...) return bytes(...) end;local decimal;__nuppExports["decimal"]=function(...) return decimal(...) end;local document;__nuppExports["document"]=function(...) return document(...) end;local documentAdapter;__nuppExports["documentAdapter"]=function(...) return documentAdapter(...) end;local float;__nuppExports["float"]=function(...) return float(...) end;local integer;__nuppExports["integer"]=function(...) return integer(...) end;local list;__nuppExports["list"]=function(...) return list(...) end;local map;__nuppExports["map"]=function(...) return map(...) end;local null;__nuppExports["null"]=function(...) return null(...) end;local numberToken;__nuppExports["numberToken"]=function(...) return numberToken(...) end;local object;__nuppExports["object"]=function(...) return object(...) end;local policy;__nuppExports["policy"]=function(...) return policy(...) end;local string;__nuppExports["string"]=function(...) return string(...) end;local timestamp;__nuppExports["timestamp"]=function(...) return timestamp(...) end;local tuple;__nuppExports["tuple"]=function(...) return tuple(...) end;local union;__nuppExports["union"]=function(...) return union(...) end;local withContext;__nuppExports["withContext"]=function(...) return withContext(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.document\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.document\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.serde.internal.document\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.serde.internal.document\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.serde.internal.document\0runtime\0005") };

local core = require ( "nupp.serde.internal.value" )
local plans = require ( "nupp.serde.internal.json.plan" )
local json = require ( "nupp.codec.json" )
local timestamps = require ( "nupp.serde.internal.timestamps" )


local Member = {} Member.__index = Member ;_G.nupp.__reflect.link(Member,__nuppT1[1],{ }) ;__nuppExports["Member"]=Member




local Entry = {} Entry.__index = Entry ;_G.nupp.__reflect.link(Entry,__nuppT1[2],{ __nuppT1[5] }) ;__nuppExports["Entry"]=Entry







local Name = {} Name.__index = Name

function Name:diagnosticLabel() 
return self . name
end ;_G.nupp.__reflect.link(Name,__nuppT1[3],{ }) ;__nuppExports["Name"]=Name


local MapEntry = {} MapEntry.__index = MapEntry ;_G.nupp.__reflect.link(MapEntry,__nuppT1[4],{ __nuppT1[5] }) ;__nuppExports["MapEntry"]=MapEntry







local Document = {} Document.__index = Document






















function Document:size() 
if self . kind == "structure" or self . kind == "union" then
return # self . fields
elseif self . kind == "map" then
return # ( self . entries )
else
return # self . elements
end
end





function Document:at(index) 
local value = self . elements [ index ]
if value == nil then
error ( "document index out of range" , 2 )
end

return value
end






function Document:get(name) 
for _ , field in ipairs ( self . fields ) do
if field . name == name then
return field . value
end
end

return nil
end



function Document:string() 
assert ( self . kind == "string" , "document is not a string" )
return self . text
end




function Document:numberToken() 
assert ( self . kind == "numberToken" , "document is not a number token" )
return self . text
end



function Document:boolean() 
assert ( self . kind == "boolean" , "document is not a boolean" )
return self . flag
end




function Document:integer() 
assert ( self . kind == "integer" , "document is not an integer" )
return self . integerValue
end




function Document:decimal() 
assert ( self . kind == "decimal" , "document is not a decimal" )
return self . decimalValue
end




function Document:float() 
assert ( self . kind == "float" , "document is not a float" )
return self . floatValue
end




function Document:bytes() 
assert ( self . kind == "bytes" , "document is not bytes" )
return self . text
end




function Document:bigInteger() 
assert ( self . kind == "bigInteger" , "document is not a big integer" )
return self . text
end



function Document:timestamp() 
assert ( self . kind == "timestamp" , "document is not a timestamp" )
return self . time
end





function Document:atom() 
assert ( self . kind == "atom" , "document is not an atom" )
return ( self . atomValue ) : snapshot ( )
end






function Document:entry(index) 
assert ( self . kind == "map" , "document is not a map" )
return assert ( ( self . entries ) [ index ] , "document entry out of range" )
end






function Document:field(index) 
assert ( self . kind == "structure" or self . kind == "union" , "document has no named members" )
return assert ( self . fields [ index ] , "document member out of range" )
end



function Document:document() 
assert ( self . kind == "document" , "document is not a boundary" )
return self . elements [ 1 ]
end






function Document:context() 
return self . source
end ;_G.nupp.__reflect.link(Document,__nuppT1[5],{ _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0004","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0002","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0003","nupp.serde.internal.value") , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/value.nupp\0Atom\0interface\0module\0001","nupp.serde.internal.value") , __nuppT1[4] , __nuppT1[5] , __nuppT1[2] , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") }) ;__nuppExports["Document"]=Document


local root = _G.setmetatable({ name =  "$document" }, Member)
local element = _G.setmetatable({ name =  "$element" }, Member)
local write
local read
local adapter

local Fields = {} Fields.__index = Fields
function Fields:apply(value, writer) 
for _ , field in ipairs ( value . fields ) do
write ( field . value , _G.setmetatable({ name =  field . name }, Member) , writer )
end
end

local Elements = {} Elements.__index = Elements
function Elements:apply(value, writer) 
for _ , child in ipairs ( value . elements ) do
write ( child , element , writer )
end
end

local One = {} One.__index = One
function One:apply(value, writer) 
write ( value , element , writer )
end

local one = _G.setmetatable({ }, One)
local Entries = {} Entries.__index = Entries
function Entries:apply(value, writer) 
for _ , entry in ipairs ( value . entries ) do
writer : writeEntry ( entry . key , one , entry . value , one )
end
end

local fields , elements , entries = _G.setmetatable({ }, Fields) , _G.setmetatable({ }, Elements) , _G.setmetatable({ }, Entries)

write = function ( value , member , writer ) 
if value . kind == "null" then
writer : writeNull ( member )
elseif value . kind == "boolean" then
writer : writeBoolean ( member , value . flag )
elseif value . kind == "string" then
writer : writeString ( member , value . text )
elseif value . kind == "numberToken" then
writer : writeNumberToken ( member , value . text )
elseif value . kind == "bytes" then
writer : writeBytes ( member , value . text )
elseif value . kind == "timestamp" then
writer : writeTimestamp ( member , value . time )
elseif value . kind == "integer" then
writer : writeInteger ( member , value . integerValue )
elseif value . kind == "decimal" then
writer : writeDecimal ( member , value . decimalValue )
elseif value . kind == "float" then
local item = value . floatValue
writer : writeFloat ( member , item . value , item . width )
elseif value . kind == "bigInteger" then
writer : writeBigInteger ( member , value . text )
elseif value . kind == "atom" then
writer : writeAtom ( member , value . atomValue )
elseif value . kind == "document" then
writer : writeDocument ( member , value : document ( ) , adapter )
elseif value . kind == "map" then
writer : writeMap ( member , value : size ( ) , value , entries )
elseif value . kind == "tuple" then
writer : writeTuple ( member , # value . elements , value , elements )
elseif value . kind == "union" then
writer : writeUnion ( member , value , fields )
elseif value . kind == "structure" then
writer : writeStruct ( member , value , fields )
elseif value . kind == "list" then
writer : writeList ( member , # value . elements , value , elements )
else
error ( "unsupported document kind: " .. value . kind , 2 )
end
end

local AddElement = {} AddElement.__index = AddElement
function AddElement:apply(state, index, reader) 
state [ index ] = read ( reader )
end

local AddField = {} AddField.__index = AddField
function AddField:apply(state, name, reader) 
state [ # state + 1 ] = _G.setmetatable({ name =  name ,  value =  read ( reader ) }, Entry)
end

local AddEntry = {} AddEntry.__index = AddEntry
function AddEntry:apply(state, key, value) 





local keyValue = read ( key )
state [ # state + 1 ] = _G.setmetatable({ key =  keyValue ,  value =  read ( value ) }, MapEntry)
end

local addElement , addField , addEntry = _G.setmetatable({ }, AddElement) , _G.setmetatable({ }, AddField) , _G.setmetatable({ }, AddEntry)

read = function ( reader ) 
local kind = reader : kind ( )
local source = reader : context ( )
local text = nil
local flag = nil
local time = nil
local integerValue = nil
local decimalValue = nil
local floatValue = nil
local atomValue = nil
local mapEntries = { }
local items = { }
local members = { }
if kind == "null" then
reader : readNull ( )
elseif kind == "boolean" then
flag = reader : readBoolean ( )
elseif kind == "string" then
text = reader : readString ( )
elseif kind == "numberToken" then
text = reader : readNumberToken ( )
elseif kind == "bytes" then
text = reader : readBytes ( )
elseif kind == "timestamp" then
time = reader : readTimestamp ( )
elseif kind == "integer" then
integerValue = reader : readInteger ( )
elseif kind == "decimal" then
decimalValue = reader : readDecimal ( )
elseif kind == "float" then
floatValue = reader : readFloat ( )
elseif kind == "bigInteger" then
text = reader : readBigInteger ( )
elseif kind == "atom" then
atomValue = reader : readAtom ( )
elseif kind == "document" then
items [ 1 ] = reader : readDocument ( adapter )
elseif kind == "map" then
reader : readMap ( mapEntries , addEntry )
elseif kind == "tuple" then
reader : readTuple ( items , addElement )
elseif kind == "union" then
reader : readUnion ( members , addField )
elseif kind == "list" then
reader : readList ( items , addElement )
elseif kind == "structure" then
reader : readStruct ( members , addField )
else
error ( "unsupported document input: " .. kind , 2 )
end

return ( _G.setmetatable({ kind =
kind ,  text =
text ,  flag =
flag ,  time =
time ,  integerValue =
integerValue ,  decimalValue =
decimalValue ,  floatValue =
floatValue ,  atomValue =
atomValue ,  entries =
mapEntries ,  elements =
items ,  fields =
members ,  source =
source }, Document) )

end

local Description = {} Description.__index = Description








local description = _G.setmetatable({ kind =  "dynamic" ,  member =  root ,  nullable =  true ,  canRead =  false ,  children =  { } }, Description)

local Contents = {} Contents.__index = Contents
function Contents:describe(direction) 
return description
end

function Contents:write(value, writer) 
write ( value , root , writer )
end

function Contents:read(reader) 
error ( "document input uses the document contents reader" , 2 )
end


local Adapter = {} Adapter.__index = Adapter
function Adapter:discard(value) 
local _copy = value
end


function Adapter:context(document) 
return document . source
end

function Adapter:contents() 
return self . binding
end

function Adapter:readContents(reader) 
return read ( reader )
end

adapter = _G.setmetatable({ binding =  _G.setmetatable({ adapter =  _G.setmetatable({ }, Contents) }, core.Bound) }, Adapter)

documentAdapter=function ( ) 
return adapter
end ;__nuppExports["documentAdapter"]=documentAdapter

string=function ( value ) 
return ( _G.setmetatable({ kind =  "string" ,  text =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["string"]=string

numberToken=function ( value ) 
json . numberToken ( value )
return ( _G.setmetatable({ kind =  "numberToken" ,  text =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["numberToken"]=numberToken

document=function ( value ) 
return ( _G.setmetatable({ kind =  "document" ,  elements =  { value } ,  fields =  { } }, Document) )
end ;__nuppExports["document"]=document

null=function ( ) 
return ( _G.setmetatable({ kind =  "null" ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["null"]=null

list=function ( values ) 
local copy = { }
for index , value in ipairs ( values ) do
copy [ index ] = value
end

return ( _G.setmetatable({ kind =  "list" ,  elements =  copy ,  fields =  { } }, Document) )
end ;__nuppExports["list"]=list

object=function ( values ) 
local copy = { }
local seen = { }
for index , value in ipairs ( values ) do
if seen [ value . name ] then
error ( "duplicate document member" , 2 )
end
seen [ value . name ] = true
copy [ index ] = value
end

return ( _G.setmetatable({ kind =  "structure" ,  elements =  { } ,  fields =  copy }, Document) )
end ;__nuppExports["object"]=object

boolean=function ( value ) 
return ( _G.setmetatable({ kind =  "boolean" ,  flag =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["boolean"]=boolean

integer=function ( value ) 
return ( _G.setmetatable({ kind =  "integer" ,  integerValue =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["integer"]=integer

decimal=function ( value ) 
return ( _G.setmetatable({ kind =  "decimal" ,  decimalValue =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["decimal"]=decimal

float=function ( value ) 
return ( _G.setmetatable({ kind =  "float" ,  floatValue =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["float"]=float

bigInteger=function ( value ) 
assert (
value : match ( "^-?[0-9]+$" ) and ( value == "0" or value == "-0" or value : match ( "^-?[1-9][0-9]*$" ) ) ,
"invalid big integer"
)

return ( _G.setmetatable({ kind =  "bigInteger" ,  text =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["bigInteger"]=bigInteger

bytes=function ( value ) 
return ( _G.setmetatable({ kind =  "bytes" ,  text =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["bytes"]=bytes

timestamp=function ( value ) 
assert ( value . nanos >= 0 and value . nanos < 1000000000 , "invalid timestamp nanos" )
return ( _G.setmetatable({ kind =  "timestamp" ,  time =  value ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["timestamp"]=timestamp

atom=function ( value ) 
return ( _G.setmetatable({ kind =  "atom" ,  atomValue =  value : snapshot ( ) ,  elements =  { } ,  fields =  { } }, Document) )
end ;__nuppExports["atom"]=atom

tuple=function ( values ) 
local copy = { }
for index , value in ipairs ( values ) do
copy [ index ] = value
end

return ( _G.setmetatable({ kind =  "tuple" ,  elements =  copy ,  fields =  { } }, Document) )
end ;__nuppExports["tuple"]=tuple

union=function ( name , value ) 
return ( _G.setmetatable({ kind =  "union" ,  elements =  { } ,  fields =  { _G.setmetatable({ name =  name ,  value =  value }, Entry) } }, Document) )
end ;__nuppExports["union"]=union

map=function ( values ) 
local copy = { }
for index , value in ipairs ( values ) do
copy [ index ] = value
end

return ( _G.setmetatable({ kind =  "map" ,  elements =  { } ,  fields =  { } ,  entries =  copy }, Document) )
end ;__nuppExports["map"]=map

withContext=function ( value , context ) 
return ( _G.setmetatable({ kind =
value . kind ,  text =
value . text ,  flag =
value . flag ,  time =
value . time ,  integerValue =
value . integerValue ,  decimalValue =
value . decimalValue ,  floatValue =
value . floatValue ,  atomValue =
value . atomValue ,  entries =
value . entries ,  elements =
value . elements ,  fields =
value . fields ,  source =
context }, Document) )

end ;__nuppExports["withContext"]=withContext

local Policy = {} Policy.__index = Policy

function Policy:name(member) 
return member . name
end

function Policy:select(member, direction) 
return "traverse"
end

function Policy:timestamp(member, value) 
return self . epoch and json . numberToken ( timestamps . epoch ( value ) ) or json . encoded ( timestamps . dateTime ( value ) )
end

function Policy:parseTimestamp(member, text, kind) 
if kind == "number" then
return timestamps . parseEpoch ( text )
else
return timestamps . parseDateTime ( text )
end
end


local NameFactory = {} NameFactory.__index = NameFactory

function NameFactory:policy(member) 
return ( _G.setmetatable({ epoch =  self . epoch }, Policy) )
end



const memberNames = _G.setmetatable({ epoch =  false }, NameFactory) ;__nuppExports["memberNames"]=memberNames

policy=function ( member , epoch ) 
if getmetatable ( member ) ~= Member then
return nil
end
return ( _G.setmetatable({ epoch =  epoch }, Policy) )
end ;__nuppExports["policy"]=policy
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Document]="nupp.serde.internal.document\0Document";__nuppWorkerRecords[Entry]="nupp.serde.internal.document\0Entry";__nuppWorkerRecords[MapEntry]="nupp.serde.internal.document\0MapEntry";__nuppWorkerRecords[Member]="nupp.serde.internal.document\0Member";__nuppWorkerRecords[Name]="nupp.serde.internal.document\0Name"; end);if not __nuppOk then package.loaded["nupp.serde.internal.document"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.document"]=__nuppExports;return __nuppExports