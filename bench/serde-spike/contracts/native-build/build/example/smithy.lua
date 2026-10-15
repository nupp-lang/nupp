_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.smithy"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local binding;__nuppExports["binding"]=function(...) return binding(...) end;local load;__nuppExports["load"]=function(...) return load(...) end;local memberAdapter;__nuppExports["memberAdapter"]=function(...) return memberAdapter(...) end;local parse;__nuppExports["parse"]=function(...) return parse(...) end;local policy;__nuppExports["policy"]=function(...) return policy(...) end;local root;__nuppExports["root"]=function(...) return root(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.smithy\0runtime\0001") , _G.nupp.__reflect.declaration("example.smithy\0runtime\0002") , _G.nupp.__reflect.declaration("example.smithy\0runtime\0003") , _G.nupp.__reflect.declaration("example.smithy\0runtime\0004") };

local __serdeJson = require ( "nupp.serde.json" )

const util = require ( "nupp.util" )

local core = require ( "nupp.serde" )
local documents = require ( "nupp.serde.document" )
local jsonDocument = require ( "nupp.serde.json" )

local Shape = {} Shape.__index = Shape






function Shape:member(name) 
for _ , member in ipairs ( self . members ) do
if member . name == name then
return member
end
end

return nil
end

function Shape:size() 
return # self . members
end

function Shape:at(index) 
return assert ( self . members [ index ] , "shape member index out of range" )
end ;_G.nupp.__reflect.link(Shape,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") , __nuppT1[2] }) ;__nuppExports["Shape"]=Shape


local Member = {} Member.__index = Member






function Member:trait(id) 

return self . traits : get ( id ) or self . target . traits : get ( id )
end ;_G.nupp.__reflect.link(Member,__nuppT1[2],{ __nuppT1[1] , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["Member"]=Member


local Model = {} Model.__index = Model


function Model:shape(id) 
return assert ( self . shapes [ id ] , "unknown Smithy shape: " .. id )
end ;_G.nupp.__reflect.link(Model,__nuppT1[3],{ __nuppT1[1] }) ;__nuppExports["Model"]=Model


local function traits ( node ) 
local value = node : get ( "traits" )
if value ~= nil then
assert ( value . kind == "structure" , "Smithy traits must be an object" )
return value
end

return documents . object ( { } )
end

load=function ( ast ) 
assert ( ast . kind == "structure" , "Smithy AST must be an object" )
assert ( assert ( ast : get ( "smithy" ) , "missing Smithy version" ) : string ( ) == "2.0" , "unsupported Smithy version" )
local source = assert ( ast : get ( "shapes" ) , "missing Smithy shapes" )
assert ( source . kind == "structure" , "Smithy shapes must be an object" )
local shapes = { }
local prelude

= {
String = "string" ,
Boolean = "boolean" ,
Byte = "byte" ,
Short = "short" ,
Integer = "integer" ,
Long = "long" ,
Float = "float" ,
Double = "double" ,
BigInteger = "bigInteger" ,
BigDecimal = "bigDecimal" ,
Blob = "blob" ,
Timestamp = "timestamp" ,
Document = "document" ,
Unit = "structure"
}
for name , kind in pairs ( prelude ) do
shapes [
"smithy.api#" .. name
] = _G.setmetatable({ id =
"smithy.api#" .. name ,  kind =
kind ,  traits =
documents . object ( { } ) ,  definition =
documents . object ( { } ) ,  members =  {} }, Shape)

end
for index = 1 , source : size ( ) do
local field = source : field ( index )
assert ( field . name : match ( "^[%w_.]+#[%w_]+$" ) , "invalid shape identity" )
assert ( shapes [ field . name ] == nil , "duplicate shape identity" )
shapes [
field . name
] = _G.setmetatable({ id =
field . name ,  kind =
assert ( field . value : get ( "type" ) , "missing shape type" ) : string ( ) ,  traits =
traits ( field . value ) ,  definition =
field . value ,  members =  {} }, Shape)

end



local function add ( container , name , value ) 
local target = assert ( value : get ( "target" ) , "missing member target" ) : string ( )
container . members [
# container . members + 1
] = _G.setmetatable({ name =
name ,  index =
# container . members + 1 ,  container =
container ,  target =
assert ( shapes [ target ] , "unknown member target: " .. target ) ,  traits =
traits ( value ) }, Member)

end

for index = 1 , source : size ( ) do
local field = source : field ( index )
local shape = assert ( shapes [ field . name ] )
if shape . kind == "structure" or shape . kind == "union" then
local members = field . value : get ( "members" )
if members ~= nil then
assert ( members . kind == "structure" , "members must be an object" )
for position = 1 , members : size ( ) do
local member = members : field ( position )
assert ( shape : member ( member . name ) == nil , "duplicate member" )
add ( shape , member . name , member . value )
end
end
elseif shape . kind == "list" then
add ( shape , "member" , assert ( field . value : get ( "member" ) , "missing list member" ) )
elseif shape . kind == "map" then
add ( shape , "key" , assert ( field . value : get ( "key" ) , "missing map key" ) )
add ( shape , "value" , assert ( field . value : get ( "value" ) , "missing map value" ) )
end
end

return ( _G.setmetatable({ shapes =  shapes }, Model) )
end ;__nuppExports["load"]=load

parse=function ( source ) 
return load ( jsonDocument . decodeDocument ( documents . adapter ( ) , source ) )
end ;__nuppExports["parse"]=parse

local plans = require ( "nupp.serde.json" )
local json = require ( "nupp.codec.json" )
local timestamps = require ( "nupp.serde.codec" )

const schemaContext = util . newKey ( ) ;__nuppExports["schemaContext"]=schemaContext
const memberContext = util . newKey ( ) ;__nuppExports["memberContext"]=memberContext
local wireFieldContext = util . newKey ( )
local UnknownField = {} UnknownField.__index = UnknownField ;_G.nupp.__reflect.link(UnknownField,__nuppT1[4],{ _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0WireField\0interface\0module\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["UnknownField"]=UnknownField



const unknownFieldsContext = util . newKey ( ) ;__nuppExports["unknownFieldsContext"]=unknownFieldsContext

local function defaultValue ( shape , value ) 
local numbers = require ( "nupp.serde.codec" )
if shape . kind == "string" or shape . kind == "enum" then
return documents . string ( value : string ( ) )
elseif shape . kind == "boolean" then
return documents . boolean ( value : boolean ( ) )
elseif shape . kind == "document" then
return documents . boundary ( value )
elseif shape . kind == "byte"
or shape . kind == "short"
or shape . kind == "integer"
or shape . kind == "intEnum"
or shape . kind == "long"
then
local width


= shape . kind == "byte" and 8 or shape . kind == "short" and 16 or shape . kind == "long" and 64 or 32
return documents . integer ( numbers . integer ( value : numberToken ( ) , width , true ) )
elseif shape . kind == "float" or shape . kind == "double" then
local width = shape . kind == "float" and 32 or 64
return documents . float (
_G.setmetatable({ value =  numbers . float ( assert ( tonumber ( value : numberToken ( ) ) ) , width ) ,  width =  width }, core.Float)
)
elseif shape . kind == "bigInteger" then
return documents . bigInteger ( value : numberToken ( ) )
end
error ( "unsupported default for Smithy fixture shape " .. shape . id , 2 )
end

local Description = {} Description.__index = Description









local Child = {} Child.__index = Child




function Child:describe(direction) 
return self . adapter : describe ( direction )
end


local State = {} State.__index = State






local Fields = {} Fields.__index = Fields


function Fields:apply(source, writer) 
for index = 1 , self . shape : size ( ) do
local member = self . shape : at ( index )
assert (
member . traits : get ( "smithy.api#required" ) == nil or source : get ( member . name ) ~= nil ,
"missing required member: " .. member . name
)
end
for index = 1 , source : size ( ) do
local field = source : field ( index )
local member = self . shape : member ( field . name )
if member ~= nil then
if writer : include ( member ) then
assert ( self . adapters [ member ] ) : write ( field . value , writer )
end
else
local context = field . value : context ( )
local identity = context ~= nil and context : get ( wireFieldContext ) or nil
writer : writeUnknown (
identity or _G.setmetatable({ name =  field . name }, jsonDocument.FieldName) ,
field . value ,
documents . adapter ( )
)
end
end
local context = source : context ( )
local unknown = context ~= nil and context : get ( unknownFieldsContext ) or nil
if unknown ~= nil then
for _ , entry in ipairs ( unknown ) do
writer : writeUnknown ( entry . field , entry . value , documents . adapter ( ) )
end
end
end


local ReadFields = {} ReadFields.__index = ReadFields

function ReadFields:apply(state, member, reader) 
local adapter = assert ( self . adapters [ member ] , "foreign Smithy member" )
state . fields [ # state . fields + 1 ] = _G.setmetatable({ name =  member . name ,  value =  adapter : read ( reader ) }, documents.Entry)
end


local Unknown = {} Unknown.__index = Unknown
function Unknown:apply(state, field, reader) 





local value = reader : captureValue ( documents . adapter ( ) )
if getmetatable ( field ) ~= jsonDocument . FieldName then
state . unknown [ # state . unknown + 1 ] = _G.setmetatable({ field =  field ,  value =  value }, UnknownField)
return
end
local context = assert ( value : context ( ) , "unknown JSON content requires its source context" )
local contexts = require ( "nupp.serde.codec" )
local metadata = contexts . contextBuilder ( context . codec , context . profile , context )
metadata : set ( wireFieldContext , field )
state . fields [
# state . fields + 1
] = _G.setmetatable({ name =
jsonDocument . fieldName ( field ) ,  value =
documents . withContext ( value , metadata : freeze ( ) ) }, documents.Entry)

end


local Elements = {} Elements.__index = Elements

function Elements:apply(source, writer) 
for index = 1 , source : size ( ) do
self . adapter : write ( source : at ( index ) , writer )
end
end

local ReadElements = {} ReadElements.__index = ReadElements

function ReadElements:apply(state, index, reader) 
assert ( index == # state . elements + 1 , "nonsequential Smithy list" )
state . elements [ index ] = self . adapter : read ( reader )
end

local One = {} One.__index = One

function One:apply(source, writer) 
self . adapter : write ( source , writer )
end

local Entries = {} Entries.__index = Entries


function Entries:apply(source, writer) 
for index = 1 , source : size ( ) do
local entry = source : entry ( index )
writer : writeEntry ( entry . key , self . key , entry . value , self . value )
end
end

local ReadEntries = {} ReadEntries.__index = ReadEntries


function ReadEntries:apply(state, key, value) 





state . entries [
# state . entries + 1
] = _G.setmetatable({ key =  self . key : read ( key ) ,  value =  self . value : read ( value ) }, documents.MapEntry)
end


local Adapter = {} Adapter.__index = Adapter





function Adapter:describe(direction) 
return self . description
end

function Adapter:write(value, writer) 
local kind = self . description . kind
local member = self . member
if kind == "document" then
writer : writeDocument ( member , value : document ( ) , documents . adapter ( ) )
elseif value . kind == "null" then
assert ( self . description . nullable or kind == "document" , "null is not allowed for this Smithy member" )
writer : writeNull ( member )
elseif kind == "string" then
writer : writeString ( member , value : string ( ) )
elseif kind == "boolean" then
writer : writeBoolean ( member , value : boolean ( ) )
elseif kind == "integer" then
local numbers = require ( "nupp.serde.codec" )
writer : writeInteger (
member ,
numbers . integer ( value : integer ( ) . decimal , self . description . width , true )
)
elseif kind == "float" then
writer : writeFloat ( member , value : float ( ) . value , self . description . width )
elseif kind == "bigInteger" then
writer : writeBigInteger ( member , value : bigInteger ( ) )
elseif kind == "decimal" then
writer : writeDecimal ( member , value : decimal ( ) )
elseif kind == "bytes" then
writer : writeBytes ( member , value : bytes ( ) )
elseif kind == "timestamp" then
writer : writeTimestamp ( member , value : timestamp ( ) )

elseif kind == "structure" then
writer : writeStruct ( member , value , _G.setmetatable({ shape =  member . target ,  adapters =  self . adapters }, Fields) )
elseif kind == "union" then
assert ( value : size ( ) == 1 , "Smithy unions contain exactly one member" )
writer : writeUnion ( member , value , _G.setmetatable({ shape =  member . target ,  adapters =  self . adapters }, Fields) )
elseif kind == "list" then
writer : writeList (
member ,
value : size ( ) ,
value ,
_G.setmetatable({ adapter =  assert ( self . adapters [ member . target : at ( 1 ) ] ) }, Elements)
)
elseif kind == "map" then
writer : writeMap (
member ,
value : size ( ) ,
value ,
_G.setmetatable({ key =
_G.setmetatable({ adapter =  assert ( self . adapters [ member . target : at ( 1 ) ] ) }, One) ,  value =
_G.setmetatable({ adapter =  assert ( self . adapters [ member . target : at ( 2 ) ] ) }, One) }, Entries)

)
else
error ( "unsupported Smithy shape: " .. member . target . kind , 2 )
end
end

function Adapter:read(reader) 
local context = reader : context ( )
local kind = self . description . kind
local member = self . member
local value
local unknown = { }
if kind == "document" then
value = documents . boundary ( reader : readDocument ( member , documents . adapter ( ) ) )
elseif reader : isNull ( ) then
assert ( self . description . nullable or kind == "document" , "null is not allowed for this Smithy member" )
reader : readNull ( member )
value = documents . null ( )
elseif kind == "string" then
value = documents . string ( reader : readString ( member ) )
elseif kind == "boolean" then
value = documents . boolean ( reader : readBoolean ( member ) )
elseif kind == "integer" then
value = documents . integer ( reader : readInteger ( member , self . description . width , true ) )
elseif kind == "float" then
value = documents . float (
_G.setmetatable({ value =
reader : readFloat ( member , self . description . width ) ,  width =
self . description . width }, core.Float)

)
elseif kind == "bigInteger" then
value = documents . bigInteger ( reader : readBigInteger ( member ) )
elseif kind == "decimal" then
value = documents . decimal ( reader : readDecimal ( member ) )
elseif kind == "bytes" then
value = documents . bytes ( reader : readBytes ( member ) )
elseif kind == "timestamp" then
value = documents . timestamp ( reader : readTimestamp ( member ) )

else
local state = _G.setmetatable({ unknown =  unknown ,  fields =  {} ,  elements =  {} ,  entries =  {} }, State)
if kind == "structure" then
reader : readStruct ( member , state , _G.setmetatable({ adapters =  self . adapters }, ReadFields) , _G.setmetatable({ }, Unknown) )
local present = { }
for _ , field in ipairs ( state . fields ) do
present [ field . name ] = true
end
for index = 1 , member . target : size ( ) do
local child = member . target : at ( index )
if not present [ child . name ] then
local default = self . defaults [ child ]
if default ~= nil then
state . fields [ # state . fields + 1 ] = _G.setmetatable({ name =  child . name ,  value =  default }, documents.Entry)
else
assert (
child . traits : get ( "smithy.api#required" ) == nil ,
"missing required member: " .. child . name
)
end
end
end
value = documents . object ( state . fields )
elseif kind == "union" then
reader : readUnion ( member , state , _G.setmetatable({ adapters =  self . adapters }, ReadFields) , _G.setmetatable({ }, Unknown) )
assert ( # state . fields == 1 , "Smithy unions contain exactly one member" )
value = documents . union ( state . fields [ 1 ] . name , state . fields [ 1 ] . value )
elseif kind == "list" then
reader : readList ( member , state , _G.setmetatable({ adapter =  assert ( self . adapters [ member . target : at ( 1 ) ] ) }, ReadElements) )
value = documents . list ( state . elements )
elseif kind == "map" then
reader : readMap (
member ,
state ,
_G.setmetatable({ key =
assert ( self . adapters [ member . target : at ( 1 ) ] ) ,  value =
assert ( self . adapters [ member . target : at ( 2 ) ] ) }, ReadEntries)

)
value = documents . map ( state . entries )
else
error ( "unsupported Smithy shape: " .. member . target . kind , 2 )
end
end
local contexts = require ( "nupp.serde.codec" )
local source = contexts . contextBuilder (
context ~= nil and context . codec or { } ,
context ~= nil and context . profile or { } ,
context
)
source : set ( schemaContext , member . target )
source : set ( memberContext , member )
if # unknown > 0 then
source : set ( unknownFieldsContext , unknown )
end

return documents . withContext ( value , source : freeze ( ) )
end


local function adapter ( member , seen ) 
local prior = seen [ member ]
if prior ~= nil then
return prior
end
local shape = member . target
local kind = "opaque"
local width = nil
if shape . kind == "string" or shape . kind == "enum" then
kind = "string"
elseif shape . kind == "boolean" then
kind = "boolean"
elseif shape . kind == "byte" then
kind , width = "integer" , 8
elseif shape . kind == "short" then
kind , width = "integer" , 16
elseif shape . kind == "integer" or shape . kind == "intEnum" then
kind , width = "integer" , 32
elseif shape . kind == "long" then
kind , width = "integer" , 64
elseif shape . kind == "float" then
kind , width = "float" , 32
elseif shape . kind == "double" then
kind , width = "float" , 64
elseif shape . kind == "bigInteger" then
kind = "bigInteger"
elseif shape . kind == "bigDecimal" then
kind = "decimal"
elseif shape . kind == "blob" then
kind = "bytes"
elseif shape . kind == "timestamp" then
kind = "timestamp"
elseif shape . kind == "document" then
kind = "document"
elseif shape . kind == "structure" or shape . kind == "union" or shape . kind == "list" or shape . kind == "map" then
kind = shape . kind
end
if member : trait ( "smithy.api#streaming" ) ~= nil then
kind = "opaque"
end
local nullable = member . container . traits : get ( "smithy.api#sparse" ) ~= nil
and ( member . container . kind == "list" or member . container . kind == "map" and member . name == "value" )
local description = _G.setmetatable({ member =
member ,  kind =
kind ,  width =
width ,  signed =
kind == "integer" and true or nil ,  nullable =
nullable ,  canRead =  true ,  children =  {} }, Description)

local result = _G.setmetatable({ member =  member ,  description =  description ,  adapters =  seen ,  defaults =  {} }, Adapter)
seen [ member ] = result
for index = 1 , shape : size ( ) do
local child = shape : at ( index )
local default = child : trait ( "smithy.api#default" )
if default ~= nil then
result . defaults [ child ] = defaultValue ( child . target , default )
end
description . children [
index
] = _G.setmetatable({ member =
child ,  required =
child . traits : get ( "smithy.api#required" ) ~= nil ,  hasDefault =
child : trait ( "smithy.api#default" ) ~= nil ,  adapter =
adapter ( child , seen ) }, Child)

end

return result
end

root=function ( shape ) 
return ( _G.setmetatable({ name =  shape . id ,  container =  shape ,  target =  shape ,  traits =  documents . object ( { } ) }, Member) )
end ;__nuppExports["root"]=root

memberAdapter=function ( member ) 
return adapter ( member , { } )
end ;__nuppExports["memberAdapter"]=memberAdapter

binding=function ( shape ) 
return ( _G.setmetatable({ adapter =  adapter ( root ( shape ) , { } ) }, core.Bound) )
end ;__nuppExports["binding"]=binding

local Policy = {} Policy.__index = Policy


function Policy:name(member) 
local trait = ( member ) : trait ( "smithy.api#jsonName" )
return self . rename and trait ~= nil and trait : string ( ) or member . name
end

function Policy:select(member, direction) 
assert ( getmetatable ( member ) == Member , "policy requires Smithy members" )
return "traverse"
end

function Policy:timestamp(member, value) 
local format = ( member ) : trait ( "smithy.api#timestampFormat" )
local epoch = format ~= nil and format : string ( ) == "epoch-seconds" or format == nil and self . epoch
if epoch then
return json . numberToken ( timestamps . formatEpoch ( value ) )
end
assert ( format == nil or format : string ( ) == "date-time" , "unsupported timestamp format in fixture" )

return json . encoded ( timestamps . formatDateTime ( value ) )
end

function Policy:parseTimestamp(member, value, kind) 
local format = ( member ) : trait ( "smithy.api#timestampFormat" )
local epoch = format ~= nil and format : string ( ) == "epoch-seconds" or format == nil and self . epoch
if epoch then
assert ( kind == "number" , "expected epoch seconds" )
return timestamps . parseEpoch ( value )
end
assert ( format == nil or format : string ( ) == "date-time" , "unsupported timestamp format in fixture" )
assert ( kind == "string" , "expected date-time" )

return timestamps . parseDateTime ( value )
end

local Factory = {} Factory.__index = Factory


function Factory:policy(member) 
local document = __serdeJson . documentPolicy ( member , self . epoch )
if document ~= nil then
return document
end
assert ( getmetatable ( member ) == Member , "policy requires Smithy members" )

return ( _G.setmetatable({ epoch =  self . epoch ,  rename =  self . rename }, Policy) )
end

policy=function ( epoch , rename ) 
return ( _G.setmetatable({ epoch =  epoch ,  rename =  rename }, Factory) )
end ;__nuppExports["policy"]=policy
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Member]="example.smithy\0Member";__nuppWorkerRecords[Model]="example.smithy\0Model";__nuppWorkerRecords[Shape]="example.smithy\0Shape";__nuppWorkerRecords[UnknownField]="example.smithy\0UnknownField"; end);if not __nuppOk then package.loaded["example.smithy"]=nil;error(__nuppWhy,0) end;package.loaded["example.smithy"]=__nuppExports;return __nuppExports