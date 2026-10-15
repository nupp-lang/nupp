_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.richmodel"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local binding;__nuppExports["binding"]=function(...) return binding(...) end;local documentBinding;__nuppExports["documentBinding"]=function(...) return documentBinding(...) end;local indexed;__nuppExports["indexed"]=function(...) return indexed(...) end;local indexedValue;__nuppExports["indexedValue"]=function(...) return indexedValue(...) end;local knownChoice;__nuppExports["knownChoice"]=function(...) return knownChoice(...) end;local newModel;__nuppExports["newModel"]=function(...) return newModel(...) end;local policy;__nuppExports["policy"]=function(...) return policy(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.richmodel\0runtime\0001") , _G.nupp.__reflect.declaration("example.richmodel\0runtime\0004") , _G.nupp.__reflect.declaration("example.richmodel\0runtime\0005") , _G.nupp.__reflect.declaration("example.richmodel\0runtime\0006") , _G.nupp.__reflect.declaration("example.richmodel\0runtime\0008") , _G.nupp.__reflect.declaration("example.richmodel\0runtime\00010") , _G.nupp.__reflect.declaration("example.richmodel\0runtime\00011") };

local __serdeJson = require ( "nupp.serde.json" )

const util = require ( "nupp.util" )

local core = require ( "nupp.serde" )
local plans = require ( "nupp.serde.json" )
local json = require ( "nupp.codec.json" )
local timestamps = require ( "nupp.serde.codec" )
local documents = require ( "nupp.serde.document" )
local maps = require ( "example.maps" )
local contexts = require ( "nupp.serde.codec" )

local Member = {} Member.__index = Member ;_G.nupp.__reflect.link(Member,__nuppT1[1],{ })




local Description = {} Description.__index = Description








local Child = {} Child.__index = Child




function Child:describe(direction) 
return self . target
end


local Choice = {} Choice.__index = Choice



function Choice:unknownField() 
return self . field
end

function Choice:unknownValue() 
return self . payload
end ;_G.nupp.__reflect.link(Choice,__nuppT1[2],{ _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0WireField\0interface\0module\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["Choice"]=Choice

knownChoice=function ( text ) 
return ( _G.setmetatable({ text =  text }, Choice) )
end ;__nuppExports["knownChoice"]=knownChoice


local Packet = {} Packet.__index = Packet ;_G.nupp.__reflect.link(Packet,__nuppT1[3],{ _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0004","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") , __nuppT1[3] , __nuppT1[2] }) ;__nuppExports["Packet"]=Packet








local State = {} State.__index = State ;_G.nupp.__reflect.link(State,__nuppT1[4],{ _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0004","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") , __nuppT1[2] })





















local PacketStorage = {} PacketStorage.__index = PacketStorage
function PacketStorage:id(value) 
return value . id
end

function PacketStorage:created(value) 
return value . created
end

function PacketStorage:note(value) 
return value . note
end

function PacketStorage:noteState(value) 
return value . note == nil and "absent" or "value"
end

function PacketStorage:document(value) 
return value . document
end

function PacketStorage:labels(value) 
return value . labels
end

function PacketStorage:next(value) 
return value . next
end

function PacketStorage:choice(value) 
return value . choice
end

function PacketStorage:finish(state) 
assert ( state . notePresence ~= "null" , "Packet cannot retain explicit null separately from absence" )
return ( _G.setmetatable({ id =
assert ( state . id ) ,  created =
assert ( state . created ) ,  note =
state . note ,  document =
state . document ,  labels =
state . labels ,  next =
state . next ,  choice =
state . choice }, Packet) )

end

local Indexed = {} Indexed.__index = Indexed ;_G.nupp.__reflect.link(Indexed,__nuppT1[5],{ __nuppT1[2] , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") , __nuppT1[5] , _G.nupp.__reflect.reference("nupp.serde.internal.value\0runtime\0004","nupp.serde.internal.value") }) ;__nuppExports["Indexed"]=Indexed




local IndexedStorage = {} IndexedStorage.__index = IndexedStorage

function IndexedStorage:validate(value) 
if value . owner ~= self . owner then
error ( "indexed value belongs to another schema" , 2 )
end
end

function IndexedStorage:id(value) 
self : validate ( value )
local item = value . slots [ 1 ]
if type ( item ) ~= "string" then
error ( "invalid indexed id" , 2 )
end

return item
end

function IndexedStorage:created(value) 
self : validate ( value )
local item = value . slots [ 2 ]
if getmetatable ( item ) ~= core . Timestamp then
error ( "invalid indexed timestamp" , 2 )
end

return item
end

function IndexedStorage:note(value) 
self : validate ( value )
local item = value . slots [ 3 ]
if item ~= nil and type ( item ) ~= "string" then
error ( "invalid indexed note" , 2 )
end

return item
end

function IndexedStorage:noteState(value) 
self : validate ( value )
return value . notePresence
end

function IndexedStorage:document(value) 
self : validate ( value )
local item = value . slots [ 4 ]
if item ~= nil and getmetatable ( item ) ~= documents . Document then
error ( "invalid indexed document" , 2 )
end

return item
end

function IndexedStorage:labels(value) 
self : validate ( value )
local item = value . slots [ 5 ]
if item ~= nil and ( type ( item ) ~= "table" or getmetatable ( item ) ~= nil ) then
error ( "invalid indexed map" , 2 )
end

return item
end

function IndexedStorage:next(value) 
self : validate ( value )
local item = value . slots [ 6 ]
if item ~= nil and getmetatable ( item ) ~= Indexed then
error ( "invalid indexed child" , 2 )
end

return item
end

function IndexedStorage:choice(value) 
self : validate ( value )
local item = value . slots [ 7 ]
if item ~= nil and getmetatable ( item ) ~= Choice then
error ( "invalid indexed union" , 2 )
end

return item
end

function IndexedStorage:finish(state) 
return ( _G.setmetatable({ owner =
self . owner ,  notePresence =
state . notePresence ,  slots =
{
[ 1 ] = assert ( state . id ) ,
[ 2 ] = assert ( state . created ) ,
[ 3 ] = state . note ,
[ 4 ] = state . document ,
[ 5 ] = state . labels ,
[ 6 ] = state . next ,
[ 7 ] = state . choice
} }, Indexed) )

end

local Model = {} Model.__index = Model ;_G.nupp.__reflect.link(Model,__nuppT1[6],{ _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Description\0interface\0module\0001","nupp.serde.internal.value") , __nuppT1[1] , _G.nupp.__reflect.reference("example.maps\0runtime\0005","example.maps") }) ;__nuppExports["Model"]=Model













const schemaContext = util . newKey ( ) ;__nuppExports["schemaContext"]=schemaContext
const memberContext = util . newKey ( ) ;__nuppExports["memberContext"]=memberContext

local ModelDocument = {} ModelDocument.__index = ModelDocument



function ModelDocument:schema() 
return self . model
end

function ModelDocument:context() 
return self . state . sourceContext
end

function ModelDocument:next() 
return self . state . next
end

function ModelDocument:get(name) 
local state = self . state
local value = nil
if name == "id" then
value = documents . string ( assert ( state . id ) )
elseif name == "created" then
value = documents . timestamp ( assert ( state . created ) )
elseif name == "note" and state . notePresence == "null" then
value = documents . null ( )
elseif name == "note" and state . note ~= nil then
value = documents . string ( state . note )
elseif name == "document" then
value = state . document
elseif name == "labels" and state . labels ~= nil then
local entries = { }
for key , item in pairs ( state . labels ) do
entries [
# entries + 1
] = _G.setmetatable({ key =
documents . integer ( _G.setmetatable({ decimal =  tostring ( key ) ,  width =  32 ,  signed =  true }, core.Integer) ) ,  value =
documents . string ( item ) }, documents.MapEntry)

end
value = documents . map ( entries )
end
if value == nil then
return nil
end
if state . sourceContext == nil then
return value
end
local source = state . sourceContext
local context = contexts . contextBuilder ( source . codec , source . profile , source )
context : set ( schemaContext , self . model )
context : set ( memberContext , name )

return documents . withContext ( value , context : freeze ( ) )
end ;_G.nupp.__reflect.link(ModelDocument,__nuppT1[7],{ __nuppT1[6] , __nuppT1[4] }) ;__nuppExports["ModelDocument"]=ModelDocument


local DocumentStorage = {} DocumentStorage.__index = DocumentStorage

function DocumentStorage:validate(value) 
assert ( value . model == self . model , "document belongs to another schema" )
end

function DocumentStorage:id(value) 
self : validate ( value )
return assert ( value . state . id )
end

function DocumentStorage:created(value) 
self : validate ( value )
return assert ( value . state . created )
end

function DocumentStorage:note(value) 
self : validate ( value )
return value . state . note
end

function DocumentStorage:noteState(value) 
self : validate ( value )
return value . state . notePresence
end

function DocumentStorage:document(value) 
self : validate ( value )
return value . state . document
end

function DocumentStorage:labels(value) 
self : validate ( value )
return value . state . labels
end

function DocumentStorage:next(value) 
self : validate ( value )
return value . state . next
end

function DocumentStorage:choice(value) 
self : validate ( value )
return value . state . choice
end

function DocumentStorage:finish(state) 
return ( _G.setmetatable({ model =  self . model ,  state =  state }, ModelDocument) )
end


local EmitChoice = {} EmitChoice.__index = EmitChoice

function EmitChoice:apply(value, writer) 
if value . text ~= nil then
writer : writeString ( self . member , value . text )
elseif value . field ~= nil and value . payload ~= nil then
writer : writeUnknown ( value . field , value . payload , documents . adapter ( ) )
else
error ( "empty union carrier" , 2 )
end
end

local ChoiceState = {} ChoiceState.__index = ChoiceState


local ReadChoice = {} ReadChoice.__index = ReadChoice
function ReadChoice:apply(state, member, reader) 
state . value = _G.setmetatable({ text =  reader : readString ( member ) }, Choice)
end

local UnknownChoice = {} UnknownChoice.__index = UnknownChoice
function UnknownChoice:apply(state, field, reader) 





state . value = _G.setmetatable({ field =  field ,  payload =  reader : captureValue ( documents . adapter ( ) ) }, Choice)
end

local readChoice , unknownChoice = _G.setmetatable({ }, ReadChoice) , _G.setmetatable({ }, UnknownChoice)
local Fields = {} Fields.__index = Fields



function Fields:apply(source, writer) 
local model = self . model
if writer : include ( model . id ) then
writer : writeString ( model . id , self . storage : id ( source ) )
end
if writer : include ( model . created ) then
writer : writeTimestamp ( model . created , self . storage : created ( source ) )
end
if writer : include ( model . note ) then
local presence = self . storage : noteState ( source )
if presence == "null" then
writer : writeNull ( model . note )
elseif presence == "value" then
writer : writeString ( model . note , assert ( self . storage : note ( source ) ) )
end
end
if writer : include ( model . document ) then
local document = self . storage : document ( source )
if document ~= nil then
writer : writeDocument ( model . document , document , documents . adapter ( ) )
end
end
if writer : include ( model . labels ) then
local labels = self . storage : labels ( source )
if labels ~= nil then
model . mapping : write ( labels , writer )
end
end
if writer : include ( model . next ) then
local next = self . storage : next ( source )
if next ~= nil then
writer : writeStruct ( model . next , next , self )
end
end
if writer : include ( model . choice ) then
local choice = self . storage : choice ( source )
if choice ~= nil then
writer : writeUnion ( model . choice , choice , self . emitChoice )
end
end
end

local Unknown = {} Unknown.__index = Unknown
function Unknown:apply(state, field, reader) 





reader : skipValue ( )
end

local ReadFields = {} ReadFields.__index = ReadFields



function ReadFields:read(member, reader) 
local state = _G.setmetatable({ sourceContext =  reader : context ( ) ,  notePresence =  "absent" }, State)
reader : readStruct ( member , state , self , self . unknown )
if state . id == nil or state . created == nil then
error ( "missing required member" , 2 )
end

return self . storage : finish ( state )
end

function ReadFields:apply(state, member, reader) 
local model = self . model
if member == model . id then
state . id = reader : readString ( member )
elseif member == model . created then
state . created = reader : readTimestamp ( member )
elseif member == model . document then
state . document = reader : readDocument ( member , documents . adapter ( ) )
elseif member == model . note then
if reader : isNull ( ) then
reader : readNull ( member )
state . notePresence = "null"
else
state . note = reader : readString ( member )
state . notePresence = "value"
end
elseif member == model . labels then
state . labels = model . mapping : read ( reader )
elseif member == model . next then
state . next = self : read ( member , reader )
elseif member == model . choice then
local choice = _G.setmetatable({ }, ChoiceState)
reader : readUnion ( member , choice , readChoice , unknownChoice )
state . choice = assert ( choice . value )
else
error ( "foreign member" , 2 )
end
end

local Adapter = {} Adapter.__index = Adapter



function Adapter:describe(direction) 
return self . model . root
end

function Adapter:write(value, writer) 
writer : writeStruct ( self . model . root . member , value , self . fields )
end

function Adapter:read(reader) 
return self . consume : read ( self . model . root . member , reader )
end


local function scalar ( member , kind ) 
return ( _G.setmetatable({ kind =  kind ,  member =  member ,  nullable =  false ,  canRead =  true ,  children =  { } }, Description) )
end

local function child ( member , target , required ) 
return ( _G.setmetatable({ member =  member ,  required =  required == true ,  hasDefault =  false ,  target =  target }, Child) )
end

newModel=function ( collision ) 
local root = _G.setmetatable({ name =  "Packet" }, Member)
local id = _G.setmetatable({ name =  "id" ,  index =  1 ,  renamed =  "identifier" }, Member)
local created = _G.setmetatable({ name =  "created" ,  index =  2 ,  renamed =  collision and "identifier" or nil }, Member)
local note = _G.setmetatable({ name =  "note" ,  index =  3 }, Member)
local document = _G.setmetatable({ name =  "document" ,  index =  4 }, Member)
local labels = _G.setmetatable({ name =  "labels" ,  index =  5 }, Member)
local next = _G.setmetatable({ name =  "next" ,  index =  6 }, Member)
local choice = _G.setmetatable({ name =  "choice" ,  index =  7 }, Member)
local choiceValue = _G.setmetatable({ name =  "text" ,  index =  1 }, Member)
local key , value = _G.setmetatable({ name =  "key" ,  index =  1 }, Member) , _G.setmetatable({ name =  "value" ,  index =  2 }, Member)
local children

= {
child ( id , scalar ( id , "string" ) , true ) ,
child ( created , scalar ( created , "timestamp" ) , true ) ,
child ( note , _G.setmetatable({ kind =  "string" ,  member =  note ,  nullable =  true ,  canRead =  true ,  children =  { } }, Description) ) ,
child ( document , scalar ( document , "document" ) ) ,
child (
labels ,
_G.setmetatable({ kind =
"map" ,  member =
labels ,  nullable =
false ,  canRead =
true ,  children =
{
child (
key ,
_G.setmetatable({ kind =
"integer" ,  member =
key ,  nullable =
false ,  width =
32 ,  signed =
true ,  canRead =
true ,  children =
{ } }, Description)
,
true
) ,
child ( value , scalar ( value , "string" ) , true )
} }, Description)

) ,
child (
choice ,
_G.setmetatable({ kind =
"union" ,  member =
choice ,  nullable =
false ,  canRead =
true ,  children =
{ child ( choiceValue , scalar ( choiceValue , "string" ) ) } }, Description)

) ,
}
local description = _G.setmetatable({ kind =
"structure" ,  member =
root ,  nullable =
false ,  canRead =
true ,  children =
children }, Description)

table . insert ( children , 6 , child ( next , description ) )

return ( _G.setmetatable({ root =
description ,  id =
id ,  created =
created ,  note =
note ,  document =
document ,  labels =
labels ,  next =
next ,  choice =
choice ,  choiceValue =
choiceValue ,  mapping =
maps . mapping ( labels , key , value ) ,  owner =
{ } }, Model) )

end ;__nuppExports["newModel"]=newModel

local function bind ( model , storage ) 
return ( _G.setmetatable({ adapter =
_G.setmetatable({ model =
model ,  fields =
_G.setmetatable({ model =
model ,  storage =
storage ,  emitChoice =
_G.setmetatable({ member =  model . choiceValue }, EmitChoice) }, Fields) ,  consume =

_G.setmetatable({ model =  model ,  storage =  storage ,  unknown =  _G.setmetatable({ }, Unknown) }, ReadFields) }, Adapter) }, core.Bound) )


end

binding=function ( model ) 
return bind ( model , _G.setmetatable({ }, PacketStorage) )
end ;__nuppExports["binding"]=binding

indexed=function ( model ) 
return bind ( model , _G.setmetatable({ owner =  model . owner }, IndexedStorage) )
end ;__nuppExports["indexed"]=indexed

documentBinding=function ( model ) 
return bind ( model , _G.setmetatable({ model =  model }, DocumentStorage) )
end ;__nuppExports["documentBinding"]=documentBinding

indexedValue=function (
model ,
id ,
created ,
note ,
document ,
labels ,
next ,
choice
) 
return ( _G.setmetatable({ owner =
model . owner ,  notePresence =
note == nil and "absent" or "value" ,  slots =
{ [ 1 ] = id , [ 2 ] = created , [ 3 ] = note , [ 4 ] = document , [ 5 ] = labels , [ 6 ] = next , [ 7 ] = choice } }, Indexed) )

end ;__nuppExports["indexedValue"]=indexedValue

local Policy = {} Policy.__index = Policy

function Policy:name(member) 
if getmetatable ( member ) ~= Member then
error ( "policy requires this model's member handles" , 2 )
end
local selected = member

return self . rename and ( selected . renamed or selected . name ) or selected . name
end

function Policy:select(member, direction) 
return "traverse"
end

function Policy:timestamp(member, value) 
if self . rename then
return json . numberToken ( timestamps . formatEpoch ( value ) )
end
return json . encoded ( timestamps . formatDateTime ( value ) )
end

function Policy:parseTimestamp(member, value, kind) 
if self . rename then
assert ( kind == "number" , "expected epoch seconds" ) ;
return timestamps . parseEpoch ( value )
end
assert ( kind == "string" , "expected date-time string" )

return timestamps . parseDateTime ( value )
end

local Factory = {} Factory.__index = Factory

function Factory:policy(member) 
local documentPolicy = __serdeJson . documentPolicy ( member , self . rename )
if documentPolicy ~= nil then
return documentPolicy
end
if getmetatable ( member ) ~= Member then
error ( "policy requires this model's member handles" , 2 )
end

return ( _G.setmetatable({ rename =  self . rename }, Policy) )
end

policy=function ( rename ) 
return ( _G.setmetatable({ rename =  rename }, Factory) )
end ;__nuppExports["policy"]=policy
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Choice]="example.richmodel\0Choice";__nuppWorkerRecords[Indexed]="example.richmodel\0Indexed";__nuppWorkerRecords[Model]="example.richmodel\0Model";__nuppWorkerRecords[ModelDocument]="example.richmodel\0ModelDocument";__nuppWorkerRecords[Packet]="example.richmodel\0Packet"; end);if not __nuppOk then package.loaded["example.richmodel"]=nil;error(__nuppWhy,0) end;package.loaded["example.richmodel"]=__nuppExports;return __nuppExports