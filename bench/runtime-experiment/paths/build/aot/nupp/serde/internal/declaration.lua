_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.compiler.runtime.reflect").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.declaration"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local annotations;__nuppExports["annotations"]=function(...) return annotations(...) end;local binding;__nuppExports["binding"]=function(...) return binding(...) end;local label;__nuppExports["label"]=function(...) return label(...) end;local nativeEncoding;__nuppExports["nativeEncoding"]=function(...) return nativeEncoding(...) end;local nativeRecipe;__nuppExports["nativeRecipe"]=function(...) return nativeRecipe(...) end;local policy;__nuppExports["policy"]=function(...) return policy(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.declaration\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.declaration\0runtime\0002") };

local core = require ( "nupp.serde.internal.value" )
local access = require ( "nupp.serde.internal.accessors" )
local structure = require ( "nupp.serde.internal.structure" )
local plans = require ( "nupp.serde.internal.json.plan" )
local json = require ( "nupp.codec.json" )
local numbers = require ( "nupp.serde.internal.numbers" )
local timestamps = require ( "nupp.serde.internal.timestamps" )
local lowering = require ( "nupp.serde.internal.json.lower" )






















const iso8601Seconds = "iso8601Seconds" ;__nuppExports["iso8601Seconds"]=iso8601Seconds
local FieldOptions = {} FieldOptions.__index = FieldOptions ;_G.nupp.__reflect.link(FieldOptions,__nuppT1[1],{ }) ;__nuppExports["FieldOptions"]=FieldOptions

















local Options = {} Options.__index = Options ;_G.nupp.__reflect.link(Options,__nuppT1[2],{ __nuppT1[1] , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/declaration.nupp\0View\0interface\0module\0001","nupp.serde.internal.declaration") }) ;__nuppExports["Options"]=Options


























local cacheKey = { }
local wideRuntime

local function wide ( ) 
if wideRuntime == nil then
local ok , runtime = pcall ( _G . require , "ffi" )
if not ok then
error ( "declaration binding: this target has no exact 64-bit carrier" , 2 )
end
wideRuntime = runtime
end

return wideRuntime
end

local Member = {} Member.__index = Member








local Description = {} Description.__index = Description









local Scalar = {} Scalar.__index = Scalar



function Scalar:describe(direction) 
if self . description . kind == "integer" and self . description . width == 64 then
wide ( )
end
return self . description
end

function Scalar:write(value, writer) 
local member = self . description . member
local kind = self . description . kind
if kind == "string" then
writer : writeString ( member , ( value ) : sub ( 1 ) )
elseif kind == "boolean" then
writer : writeBoolean ( member , value == true )
elseif kind == "float" then
writer : writeFloat ( member , ( value ) * 1 , self . description . width )
elseif kind == "numberToken" then
local number = ( value ) + 0
assert (
number == number and number ~= math . huge and number ~= - math . huge and number % 1 == 0 ,
"expected a finite integer"
)
writer : writeNumberToken ( member , ( "%.17g" ) : format ( number ) )
elseif kind == "integer" then
local decimal
if self . description . width == 64 then

decimal = tostring ( value ) : gsub ( "[Uu]?[Ll][Ll]$" , "" )
else
decimal = ( "%.0f" ) : format ( ( value ) + 0 )
end
writer : writeInteger (
member ,
_G.setmetatable({ decimal =
decimal ,  width =
self . description . width ,  signed =
self . description . signed == true }, core.Integer)

)
elseif kind == "null" then
writer : writeNull ( member )
else
error ( "declaration field requires an explicit value adapter" , 2 )
end
end

function Scalar:read(reader) 
local member = self . description . member
local kind = self . description . kind
if kind == "string" then
return reader : readString ( member )
elseif kind == "boolean" then
return reader : readBoolean ( member )
elseif kind == "float" then
return reader : readFloat ( member , self . description . width )
elseif kind == "numberToken" then
local number = tonumber ( reader : readNumberToken ( member ) )
assert (
number ~= nil and number == number and number ~= math . huge and number ~= - math . huge and number % 1 == 0 ,
"expected a finite integer"
)
return number
elseif kind == "integer" then
local decimal = reader : readInteger (
member ,
self . description . width ,
self . description . signed == true
) . decimal
if self . description . width == 64 then
local runtime = wide ( )
local magnitude = runtime . new ( "uint64_t" , 0 )
local negative = decimal : sub ( 1 , 1 ) == "-"
for position = negative and 2 or 1 , # decimal do
magnitude = magnitude * 10 + ( assert ( decimal : byte ( position ) ) - 48 )
end
if self . description . signed then
if negative then
return runtime . cast ( "int64_t" , 0 - magnitude )
end
return runtime . cast ( "int64_t" , magnitude )
end
return magnitude
end
return tonumber ( decimal )
elseif kind == "null" then
reader : readNull ( member )
return nil
else
error ( "declaration field requires an explicit value adapter" , 2 )
end
end


local EpochSeconds = {} EpochSeconds.__index = EpochSeconds

function EpochSeconds:describe(direction) 
return self . description
end

function EpochSeconds:write(value, writer) 
local seconds = ( value ) + 0
assert (
seconds == seconds and seconds % 1 == 0 and math . abs ( seconds ) <= 9007199254740991 ,
"expected exact integer epoch seconds"
)
writer : writeTimestamp (
self . description . member ,
_G.setmetatable({ seconds =  ( "%.0f" ) : format ( seconds ) ,  nanos =  0 }, core.Timestamp)
)
end

function EpochSeconds:read(reader) 
local timestamp = reader : readTimestamp ( self . description . member )
local seconds = tonumber ( timestamp . seconds )
assert (
timestamp . nanos == 0 and seconds ~= nil and math . abs ( seconds ) <= 9007199254740991 ,
"timestamp does not fit integer epoch seconds"
)

return seconds
end


local Link = {} Link.__index = Link

function Link:describe(direction) 
return assert ( self . target , "incomplete declaration graph" ) : describe ( direction )
end

function Link:write(value, writer) 
assert ( self . target , "incomplete declaration graph" ) : write ( value , writer )
end

function Link:read(reader) 
return assert ( self . target , "incomplete declaration graph" ) : read ( reader )
end


local LiteralSet = {} LiteralSet.__index = LiteralSet


function LiteralSet:describe(direction) 
return self . target : describe ( direction )
end

function LiteralSet:write(value, writer) 
assert ( self . values [ value ] , "value is outside the declaration's literals" )
self . target : write ( value , writer )
end

function LiteralSet:read(reader) 
local value = self . target : read ( reader )
assert ( self . values [ value ] , "value is outside the declaration's literals" )
return value
end


local Nullable = {} Nullable.__index = Nullable




function Nullable:describe(direction) 
local prior
if direction == "write" then
prior = self . writeDescription
else
prior = self . readDescription
end
if prior ~= nil then
return prior
end
local target = self . target : describe ( direction )
local result = _G.setmetatable({ member =
self . member ,  kind =
target . kind ,  nullable =
true ,  width =
target . width ,  signed =
target . signed ,  canRead =
target . canRead ,  children =
target . children }, Description)

if direction == "write" then
self . writeDescription = result
else
self . readDescription = result
end

return result
end

function Nullable:write(value, writer) 
if value == nil then
writer : writeNull ( self . member )
else
self . target : write ( value , writer )
end
end

function Nullable:read(reader) 
if reader : isNull ( ) then
reader : readNull ( self . member )
return nil
end

return self . target : read ( reader )
end


local Construction = {} Construction.__index = Construction

function Construction:begin() 
return self . selected : begin ( )
end

function Construction:finish(state) 
return self . selected : finish ( state )
end


local Checked = {} Checked.__index = Checked



function Checked:describe(direction) 
if direction == "read" and self . problem ~= nil then
error ( self . problem , 2 )
end
return self . target : describe ( direction )
end

function Checked:write(value, writer) 
self . target : write ( value , writer )
end

function Checked:read(reader) 
assert ( self . problem == nil , self . problem )
return self . target : read ( reader )
end


local Child = {} Child.__index = Child




function Child:describe(direction) 
return self . adapter : describe ( direction )
end


local SequenceState = {} SequenceState.__index = SequenceState




local EmitElements = {} EmitElements.__index = EmitElements


function EmitElements:apply(source, writer) 
local count = self . tuple and # self . adapters or # ( source )
for index = 1 , count do
self . adapters [ self . tuple and index or 1 ] : write ( ( source ) [ index ] , writer )
end
end


local ReadElements = {} ReadElements.__index = ReadElements


function ReadElements:apply(state, index, reader) 
assert ( index == state . count + 1 , "nonsequential element" )
local value = self . adapters [ self . tuple and index or 1 ] : read ( reader )
assert (
self . tuple or value ~= nil ,
"a Nupp array cannot retain a null element; use a document or explicit mapping"
)
state . values [ index ] = value
state . count = index
end


local Sequence = {} Sequence.__index = Sequence



function Sequence:describe(direction) 
return self . description
end

function Sequence:write(value, writer) 
if self . elements . tuple then
writer : writeTuple ( self . description . member , # self . elements . adapters , value , self . elements )
else
writer : writeList ( self . description . member , # ( value ) , value , self . elements )
end
end

function Sequence:read(reader) 
local state = _G.setmetatable({ values =  {} ,  count =  0 }, SequenceState)
if self . elements . tuple then
reader : readTuple ( self . description . member , # self . elements . adapters , state , self . consume )
else
reader : readList ( self . description . member , state , self . consume )
end

return state . values
end


local One = {} One.__index = One

function One:apply(source, writer) 
self . adapter : write ( source , writer )
end


local MapState = {} MapState.__index = MapState




local EmitEntries = {} EmitEntries.__index = EmitEntries


function EmitEntries:apply(source, writer) 
for key , value in pairs ( source ) do
writer : writeEntry ( key , self . key , value , self . value )
end
end


local ReadEntries = {} ReadEntries.__index = ReadEntries


function ReadEntries:apply(state, key, value) 





local name = self . key . adapter : read ( key )
assert ( name ~= nil and name == name , "invalid map key" )
assert ( not state . seen [ name ] , "duplicate map key" )
local item = self . value . adapter : read ( value )
assert ( item ~= nil , "a Nupp map cannot retain a null value; use a document or explicit mapping" )
state . seen [ name ] = true
state . values [ name ] = item
end


local Map = {} Map.__index = Map



function Map:describe(direction) 
return self . description
end

function Map:write(value, writer) 
writer : writeMap ( self . description . member , nil , value , self . entries )
end

function Map:read(reader) 
local state = _G.setmetatable({ values =  {} ,  seen =  {} }, MapState)
reader : readMap ( self . description . member , state , self . consume )
return state . values
end


local Graph = {} Graph.__index = Graph







local resolve

local function typeLabel ( info , index , seen ) 
if seen [ index ] then
return nil
end
seen [ index ] = true
local node = info . types [ index ]
if node . kind == "record" or node . kind == "struct" then
return node . name
elseif node . kind == "const" then
return typeLabel ( info , node . element , seen )
elseif node . kind == "union" then
local result
for _ , child in ipairs ( node . members ) do
if info . types [ child ] . kind ~= "nil" then
local selected = typeLabel ( info , child , seen )
if selected == nil or result ~= nil then
return nil
end
result = selected
end
end
return result
end

return nil
end

local function wireName ( name , naming ) 
if naming == "snakeCase" then
return name : gsub ( "(%u)(%u%l)" , "%1_%2" ) : gsub ( "(%l)(%u)" , "%1_%2" ) : lower ( )
elseif naming == "camelCase" then
local result = name : gsub ( "_([%a])" , string . upper )
return result
else
return name
end
end

local Ignore = {} Ignore.__index = Ignore
function Ignore:apply(state, field, reader) 
reader : skipValue ( )
end


local function recordAdapter ( graph , index , member ) 
local selected = graph . accesses [ index ]
if selected == nil then
selected = graph . root : nested ( index )
graph . accesses [ index ] = selected
end
local members = graph . members [ index ]
if members == nil then
members = { }
local whitelist = index == graph . root . typeIndex and graph . options . fields or nil
local known = { }
for position , field in ipairs ( selected . fields ) do
known [ field . name ] = true
local options = whitelist ~= nil and whitelist [ field . name ] or nil
members [
position
] = _G.setmetatable({ name =
field . name ,  index =
position ,  annotations =
field . annotations ,  label =
typeLabel ( selected . info , field . typeIndex , { } ) ,  wireName =
options ~= nil and options . name or wireName ( field . name , graph . options . naming ) ,  representation =
options ~= nil and options . representation or nil }, Member)

end
if whitelist ~= nil then
for name in pairs ( whitelist ) do
assert ( known [ name ] , "unknown declaration field: " .. name )
end
end
graph . members [ index ] = members
end
local parameters = { }
for _ , parameter in ipairs ( selected . parameters ) do
parameters [ parameter . name ] = parameter
end
local matched = { }
local fields = { }
local whitelist = index == graph . root . typeIndex and graph . options . fields or nil
for position , field in ipairs ( selected . fields ) do
if whitelist == nil or whitelist [ field . name ] ~= nil then
local parameter = parameters [ field . name ]
local compatible = parameter ~= nil and parameter . typeIndex == field . typeIndex
if compatible then
matched [ field . name ] = true
end
local child = resolve ( graph , field . typeIndex , members [ position ] )
local target = _G.setmetatable({ target =
child ,  problem =
not compatible and ( "field " .. field . name .. " requires an explicit construction mapping" )
or nil }, Checked)

local fieldOptions = whitelist ~= nil and whitelist [ field . name ] or nil
local present
if fieldOptions ~= nil and fieldOptions . omitEmpty then
present = function ( source ) 
local value = selected : get ( source , field )
if value == nil or value == "" or value == false then
return false
end
if type ( value ) == "table" then
for _ in pairs ( value ) do
return true
end
return false
end

return true
end
end
fields [ # fields + 1 ] = structure . field (
members [ position ] ,
function ( value ) 
return selected : get ( value , field )
end ,
function ( state , value ) 
state : set ( assert ( parameter , "field has no construction parameter" ) , value )
end ,
target ,
parameter ~= nil and not parameter . optional ,
field . hasDefault or parameter == nil ,
present
)
end
end
local problem = selected : constructionError ( )
for _ , parameter in ipairs ( selected . parameters ) do
if not matched [ parameter . name ] and not parameter . optional then
problem = "constructor requires an explicit mapping for " .. parameter . name
end
end

return ( _G.setmetatable({ target =
structure . adapter (
member ,
fields ,
_G.setmetatable({ selected =  selected }, Construction) ,
graph . options . unknownMembers == "ignore" and _G.setmetatable({ }, Ignore) or nil ,
nil ,
true
) ,  problem =
problem ,  declarationAccess =
# fields == # selected . fields and selected or nil }, Checked) )

end

local ShapeState = {} ShapeState.__index = ShapeState



function ShapeState:close() 
self . closed = true
self . values , self . present = { } , { }
end


local ShapeConstruction = {} ShapeConstruction.__index = ShapeConstruction

function ShapeConstruction:begin() 
return ( _G.setmetatable({ values =  {} ,  present =  {} ,  closed =  false }, ShapeState) )
end

function ShapeConstruction:finish(state) 
assert ( not state . closed , "shape construction is closed" )
for _ , name in ipairs ( self . required ) do
assert ( state . present [ name ] , "missing construction field: " .. name )
end
local result = state . values
state : close ( )

return result
end


local function nullable ( info , index ) 
local node = info . types [ index ]
if node . kind == "nil" then
return true
end
if node . kind == "const" then
return nullable ( info , node . element )
end
if node . kind == "union" then
for _ , member in ipairs ( node . members ) do
if info . types [ member ] . kind == "nil" then
return true
end
end
end

return false
end

local function shapeAdapter ( graph , index , member ) 
local node = graph . root . info . types [ index ]
assert ( node . index == nil or next ( node . index ) == nil , "shape indexers require an explicit binding" )
local fields = { }
local required = { }
for position , field in ipairs ( node . fields ) do
assert ( field . read ~= nil , "shape field is not readable" )
local name = field . name
local child = _G.setmetatable({ name =
name ,  index =
position ,  wireName =
wireName ( name , graph . options . naming ) ,  label =
typeLabel ( graph . root . info , field . read , { } ) ,  annotations =  {} }, Member)

local needed = not nullable ( graph . root . info , field . read )
if needed then
required [ # required + 1 ] = name
end
fields [ # fields + 1 ] = structure . field (
child ,
function ( value ) 
return ( value ) [ name ]
end ,
function ( state , value ) 
assert ( not state . closed and not state . present [ name ] , "shape field was already assigned" )
state . present [ name ] = true
state . values [ name ] = value
end ,
resolve ( graph , field . read , child ) ,
needed ,
false
)
end

return structure . adapter (
member ,
fields ,
_G.setmetatable({ required =  required }, ShapeConstruction) ,
graph . options . unknownMembers == "ignore" and _G.setmetatable({ }, Ignore) or nil
)
end

resolve = function ( graph , index , member ) 
local slots = graph . nodes [ member ]
if slots == nil then
slots = { }
graph . nodes [ member ] = slots
end
local prior = slots [ index ]
if prior ~= nil then
return prior
end
local link = _G.setmetatable({ }, Link)
slots [ index ] = link
local node = graph . root . info . types [ index ]
local kind = node . kind
local view = graph . options . view
if view ~= nil then
local customized = view : resolve ( graph . root . info , index , member )
if customized ~= nil then
link . target = customized ;
return link
end
end
if member . representation == "iso8601Seconds" then
assert (
kind == "const"
or kind == "literal"
or kind == "union"
or kind == "integer"
or kind == "int8"
or kind == "uint8"
or kind == "int16"
or kind == "uint16"
or kind == "int32"
or kind == "uint32" ,
"ISO epoch-seconds mapping requires a Lua integer carrier"
)
end
if kind == "record" or kind == "struct" then
link . target = recordAdapter ( graph , index , member )
elseif kind == "shape" then
link . target = shapeAdapter ( graph , index , member )
elseif kind == "array" or kind == "tuple" then
local adapters = { }
local children = { }
local elements = kind == "array" and { node . element } or node . members
for position , element in ipairs ( elements ) do
local child = _G.setmetatable({ name =
tostring ( position ) ,  index =
position ,  label =
typeLabel ( graph . root . info , element , { } ) ,  annotations =  {} }, Member)

adapters [ position ] = resolve ( graph , element , child )
children [ position ] = _G.setmetatable({ member =  child ,  adapter =  adapters [ position ] ,  required =  true ,  hasDefault =  false }, Child)
end
link . target = _G.setmetatable({ description =
_G.setmetatable({ member =
member ,  kind =
kind == "array" and "list" or "tuple" ,  children =
children ,  nullable =  false ,  canRead =  true }, Description) ,  elements =

_G.setmetatable({ adapters =  adapters ,  tuple =  kind == "tuple" }, EmitElements) ,  consume =
_G.setmetatable({ adapters =  adapters ,  tuple =  kind == "tuple" }, ReadElements) }, Sequence)

elseif kind == "map" and node . readKey ~= nil and node . readValue ~= nil then
local key = _G.setmetatable({ name =  "key" ,  index =  1 ,  label =  typeLabel ( graph . root . info , node . readKey , { } ) ,  annotations =  {} }, Member)
local value = _G.setmetatable({ name =  "value" ,  index =  2 ,  label =  typeLabel ( graph . root . info , node . readValue , { } ) ,  annotations =  {} }, Member)
local keyAdapter = resolve ( graph , node . readKey , key )
local valueAdapter = resolve ( graph , node . readValue , value )
link . target = _G.setmetatable({ description =
_G.setmetatable({ member =
member ,  kind =
"map" ,  children =
{
_G.setmetatable({ member =  key ,  adapter =  keyAdapter ,  required =  true ,  hasDefault =  false }, Child) ,
_G.setmetatable({ member =  value ,  adapter =  valueAdapter ,  required =  true ,  hasDefault =  false }, Child)
} ,  nullable =  false ,  canRead =  true }, Description) ,  entries =

_G.setmetatable({ key =  _G.setmetatable({ adapter =  keyAdapter }, One) ,  value =  _G.setmetatable({ adapter =  valueAdapter }, One) }, EmitEntries) ,  consume =
_G.setmetatable({ key =  _G.setmetatable({ adapter =  keyAdapter }, One) ,  value =  _G.setmetatable({ adapter =  valueAdapter }, One) }, ReadEntries) }, Map)

elseif kind == "const" then
link . target = resolve ( graph , node . element , member )
elseif kind == "literal" then
link . target = _G.setmetatable({ target =  resolve ( graph , node . base , member ) ,  values =  { [ node . value ] = true } }, LiteralSet)
elseif kind == "union" then
local target = nil
local nullable = false
for _ , alternative in ipairs ( node . members ) do
if graph . root . info . types [ alternative ] . kind == "nil" then
nullable = true
elseif target == nil then
target = alternative
else
target = -1
end
end
if target ~= nil and target > 0 and nullable then
link . target = _G.setmetatable({ member =  member ,  target =  resolve ( graph , target , member ) }, Nullable)
else
local base = nil
local category = nil
local values = { }
local supported = true
for _ , alternative in ipairs ( node . members ) do
local choice = graph . root . info . types [ alternative ]
if choice . kind ~= "nil" then
if choice . kind ~= "literal" then
supported = false
do break end
end
local primitive = graph . root . info . types [ choice . base ] . kind
local family = primitive == "integer" and "number" or primitive
if category ~= nil and category ~= family then
supported = false
do break end
end
category = family
if base == nil or primitive == "number" then
base = choice . base
end
values [ choice . value ] = true
end
end
if supported and base ~= nil then
local literals = _G.setmetatable({ target =
resolve ( graph , base , member ) ,  values =
values }, LiteralSet)

link . target = nullable and _G.setmetatable({ member =  member ,  target =  literals }, Nullable) or literals
else
link . target = _G.setmetatable({ description =
_G.setmetatable({ member =  member ,  kind =  "opaque" ,  canRead =  false ,  nullable =  false ,  children =  {} }, Description) ,  integer =  false }, Scalar)

end
end
else
local scalar = "opaque"
local width = nil
local signed = nil
if kind == "string" or kind == "boolean" then
scalar = kind
elseif kind == "nil" then
scalar = "null"
elseif kind == "integer" then
scalar = "numberToken"
elseif kind == "number" or kind == "float" then
scalar , width = "float" , kind == "float" and 32 or 64
elseif kind == "int8"
or kind == "uint8"
or kind == "int16"
or kind == "uint16"
or kind == "int32"
or kind == "uint32"
or kind == "int64"
or kind == "uint64"
then
scalar , width , signed = "integer" , tonumber ( kind : match ( "%d+" ) ) , kind : sub ( 1 , 1 ) == "i"
end
if member . representation == "iso8601Seconds" then
assert (
kind == "integer" or scalar == "integer" and width ~= 64 ,
"ISO epoch-seconds mapping requires a Lua integer carrier"
)
link . target = _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "timestamp" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, EpochSeconds)
return link
end
link . target = _G.setmetatable({ description =
_G.setmetatable({ member =
member ,  kind =
scalar ,  width =
width ,  signed =
signed ,  canRead =
scalar ~= "opaque" ,  nullable =  false ,  children =  {} }, Description) ,  integer =  false }, Scalar)


end

return link
end

local Root = {} Root.__index = Root

function Root:describe(direction) 
return self . target : describe ( direction )
end

function Root:write(value, writer) 
self . target : write ( value , writer )
end

function Root:read(reader) 
return self . target : read ( reader )
end


binding=function ( target , options ) 
local selected = access . of ( target )
local cached = rawget ( selected . info , cacheKey )
if options == nil and cached ~= nil then
return cached
end
local root = selected
local whitelist
if options ~= nil and options . fields ~= nil then
whitelist = { }
for name , field in pairs ( options . fields ) do
whitelist [
name
] = _G.setmetatable({ name =  field . name ,  representation =  field . representation ,  omitEmpty =  field . omitEmpty }, FieldOptions)
end
end
local snapshot = _G.setmetatable({ fields =
whitelist ,  naming =
options ~= nil and options . naming or "identity" ,  unknownMembers =
options ~= nil and options . unknownMembers or "reject" ,  view =
options ~= nil and options . view or nil }, Options)

local graph = _G.setmetatable({ root =  root ,  options =  snapshot ,  nodes =  {} ,  members =  {} ,  accesses =  {} }, Graph)
graph . accesses [ selected . typeIndex ] = root
local member = _G.setmetatable({ name =  selected . info . name ,  label =  selected . info . name ,  annotations =  {} }, Member)
local result = _G.setmetatable({ adapter =
_G.setmetatable({ target =  resolve ( graph , selected . typeIndex , member ) }, Root) }, core.Bound)

if options == nil then
rawset ( selected . info , cacheKey , result )
end

return result
end ;__nuppExports["binding"]=binding

local Policy = {} Policy.__index = Policy
function Policy:name(member) 
assert ( getmetatable ( member ) == Member , "declaration policy requires declaration members" )
return ( member ) . wireName or member . name
end

function Policy:select(member, direction) 
assert ( getmetatable ( member ) == Member , "declaration policy requires declaration members" )
return "traverse"
end

function Policy:timestamp(member, value) 
assert (
getmetatable ( member ) == Member and ( member ) . representation == "iso8601Seconds" ,
"a timestamp requires an explicit declaration mapping"
)

return json . encoded ( timestamps . dateTime ( value ) )
end

function Policy:parseTimestamp(member, text, kind) 
assert (
getmetatable ( member ) == Member and ( member ) . representation == "iso8601Seconds" ,
"a timestamp requires an explicit declaration mapping"
)
assert ( kind == "string" , "ISO timestamp requires a JSON string" )

return timestamps . parseDateTime ( text )
end


local Factory = {} Factory.__index = Factory
function Factory:policy(member) 
assert ( getmetatable ( member ) == Member , "declaration policy requires a declaration binding" )
return ( _G.setmetatable({ }, Policy) )
end


policy=function ( ) 
return ( _G.setmetatable({ }, Factory) )
end ;__nuppExports["policy"]=policy

annotations=function ( member ) 
if getmetatable ( member ) ~= Member then
return nil
end
return ( member ) . annotations
end ;__nuppExports["annotations"]=annotations

label=function ( member ) 
if getmetatable ( member ) ~= Member then
return nil
end
return ( member ) . label
end ;__nuppExports["label"]=label




local function nativeCarrier ( info , index , syntax ) 
local node = info . types [ index ]
local kind = node . kind
if kind == "const" then
return nativeCarrier ( info , node . element , syntax )
elseif kind == "array" then
return syntax . kind == "list" and nativeCarrier ( info , node . element , syntax . element )
elseif kind == "map" then
return syntax . kind == "map"
and info . types [ node . readKey ] . kind == "string"
and nativeCarrier ( info , node . readValue , syntax . value )
elseif kind == "tuple" then
if syntax . kind ~= "tuple" or # node . members ~= # syntax . items then
return false
end
for position , member in ipairs ( node . members ) do
if not nativeCarrier ( info , member , syntax . items [ position ] ) then
return false
end
end
return true
elseif kind == "record" then
return syntax . access == "record" and syntax . typeObject == nupp . reflect . runtimeType ( info , index )
elseif kind == "string" or kind == "boolean" then
return syntax . kind == kind
elseif kind == "number" then
return syntax . kind == "number" or syntax . kind == "integer" or syntax . kind == "unsigned"
elseif kind == "integer" then
return syntax . kind == "integer" or syntax . kind == "unsigned"
elseif kind == "int8"
or kind == "int16"
or kind == "int32"
or kind == "uint8"
or kind == "uint16"
or kind == "uint32"
then
local width = assert ( tonumber ( kind : match ( "%d+" ) ) )
local signed = kind : sub ( 1 , 1 ) == "i"
local limit = 2 ^ ( width - ( signed and 1 or 0 ) )
return ( syntax . kind == "integer" or syntax . kind == "unsigned" )
and syntax . minimum ~= nil
and syntax . maximum ~= nil
and syntax . minimum >= ( signed and - limit or 0 )
and syntax . maximum < limit
end

return false
end

local function directRecord ( selected , recipe ) 
local node = selected . info . types [ selected . typeIndex ]
if node . kind ~= "record"
or node . construction == nil
or node . construction . declared
or recipe . syntax . kind ~= "structure"
then
return
end
local fields = { }
local count = 0
for _ , field in ipairs ( node . fields ) do
if field . stored then
if not field . readable then
return
end
fields [ field . name ] = field
count += 1
end
end
if count ~= # recipe . syntax . fields then
return
end
for _ , field in ipairs ( recipe . syntax . fields ) do
local stored = fields [ field . name ]
if stored == nil or not nativeCarrier ( selected . info , stored . read , field . target ) then
return
end
local default = stored . defaultValue
if stored . hasDefault
and default ~= nil
and type ( default ) ~= "number"
and type ( default ) ~= "string"
and type ( default ) ~= "boolean"
then
return
end
end
for _ , field in ipairs ( recipe . syntax . fields ) do
local stored = fields [ field . name ]
field . hasDefault = stored . hasDefault == true
field . defaultValue = stored . defaultValue
end
recipe . syntax . access = "record"
recipe . syntax . typeObject = assert ( nupp . reflect . runtimeType ( selected . info , selected . typeIndex ) )
recipe . syntax . factory = nil
end



local function inertRecipe ( syntax ) 
if syntax . factory ~= nil then
return false
end
if syntax . kind == "structure" then
if syntax . access ~= "record" then
return false
end
for _ , field in ipairs ( syntax . fields ) do
if not inertRecipe ( field . target ) then
return false
end
end
elseif syntax . kind == "list" then
return inertRecipe ( syntax . element )
elseif syntax . kind == "map" then
return inertRecipe ( syntax . value )
elseif syntax . kind == "tuple" then
for _ , item in ipairs ( syntax . items ) do
if not inertRecipe ( item ) then
return false
end
end
end

return true
end



nativeRecipe=function (
adapter ,
plan ,
resolver ,
path
) 
local identity = getmetatable ( adapter )
if identity == Root or identity == Checked or identity == Link then
local wrapper = adapter
local result = resolver : resolve ( wrapper . target , plan , path )
if result ~= nil and identity == Checked then
local selected = ( adapter ) . declarationAccess
if selected ~= nil then
directRecord ( selected , result )
end
end
return result
elseif identity == Sequence then
local sequence = adapter
local items = { }
for index , child in ipairs ( sequence . description . children ) do
local nested = assert ( plan : child ( child . member ) )
local target = sequence . elements . adapters [ index ]
local recipe = resolver : resolve ( target , nested , path )
if recipe == nil or not inertRecipe ( recipe . syntax ) then
return nil
end
items [ index ] = recipe . syntax
end
return ( _G.setmetatable({ syntax =
sequence . elements . tuple and { kind = "tuple" , items = items } or { kind = "list" , element = items [ 1 ] } }, lowering.Recipe) )

elseif identity == Map then
local mapping = adapter
local children = mapping . description . children
local key = resolver : resolve (
mapping . entries . key . adapter ,
assert ( plan : child ( children [ 1 ] . member ) ) ,
path
)
if key == nil or key . syntax . kind ~= "string" then
return nil
end
local value = resolver : resolve (
mapping . entries . value . adapter ,
assert ( plan : child ( children [ 2 ] . member ) ) ,
path
)
if value == nil or not inertRecipe ( value . syntax ) then
return nil
end
return ( _G.setmetatable({ syntax =  { kind = "map" , value = value . syntax } }, lowering.Recipe) )
elseif identity == Scalar then
local scalar = adapter
local description = scalar . description
local kind = description . kind
if kind == "string" or kind == "boolean" or kind == "float" and description . width == 64 then
return ( _G.setmetatable({ syntax =  { kind = kind == "float" and "number" or kind } }, lowering.Recipe) )
elseif kind == "integer" and description . width ~= 64 then
local width = description . width
local signed = description . signed == true
local limit = 2 ^ ( width - ( signed and 1 or 0 ) )
return ( _G.setmetatable({ syntax =
{
kind = signed and "integer" or "unsigned" ,
minimum = signed and - limit or 0 ,
maximum = limit - 1 ,
strictInteger = true ,
width = width ,
signed = signed
} }, lowering.Recipe) )

elseif kind == "numberToken" then
return ( _G.setmetatable({ syntax =  { kind = "integer" } }, lowering.Recipe) )
end
end

return nil
end ;__nuppExports["nativeRecipe"]=nativeRecipe

local ScalarEncoding = {} ScalarEncoding.__index = ScalarEncoding



function ScalarEncoding:write(value, sink, budget) 
if budget ~= nil then
budget : step ( self . path )
end
local kind = self . description . kind
if kind == "string" then
sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( ( value ) : sub ( 1 ) )
elseif kind == "boolean" then
sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( value == true )
elseif kind == "float" then
sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( numbers . floating ( ( value ) * 1 , self . description . width ) )
elseif kind == "numberToken" then
local number = ( value ) + 0
assert (
number == number and number ~= math . huge and number ~= - math . huge and number % 1 == 0 ,
"expected a finite integer"
)
sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( json . numberToken ( ( "%.17g" ) : format ( number ) ) )
else
local decimal = ( "%.0f" ) : format ( ( value ) + 0 )
numbers . integer ( decimal , self . description . width , self . description . signed == true )
sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( json . numberToken ( decimal ) )
end
end


local errors = require ( "nupp.serde.internal.errors" )
local SequenceEncoding = {} SequenceEncoding.__index = SequenceEncoding




function SequenceEncoding:write(value, sink, budget) 
assert ( budget ) : step ( self . path )
local values = value
local count = self . tuple and # self . items or # values
sink : startArray ( )
for index = 1 , count do
local child = self . items [ self . tuple and index or 1 ]
local ok , problem = pcall ( child . write , child , values [ index ] , sink , budget )
if not ok then
error ( errors . prefix ( problem , self . path .. "[" .. tostring ( index ) .. "]" ) , 0 )
end
end
sink : endArray ( )
end

local MapEncoding = {} MapEncoding.__index = MapEncoding



function MapEncoding:write(value, sink, budget) 
assert ( budget ) : step ( self . path )
sink : startObject ( )
for key , item in pairs ( value ) do
sink :__nupp_m_d9930e4662ee507090a52ff19d65f1844d2ce3c0cfdf6a56bcf88945d7356737 ( key )
local ok , problem = pcall ( self . item . write , self . item , item , sink , budget )
if not ok then
error ( errors . prefix ( problem , self . path .. "[" .. json . encode ( key ) .. "]" ) , 0 )
end
end
sink : endObject ( )
end


local function stringKey ( adapter ) 
local identity = getmetatable ( adapter )
if identity == Checked or identity == Link then
return stringKey ( ( adapter ) . target )
end

return identity == Scalar and ( adapter ) . description . kind == "string"
end

nativeEncoding=function (
adapter ,
plan ,
resolver ,
path
) 
local identity = getmetatable ( adapter )
if identity == Root or identity == Checked or identity == Link then
local wrapper = adapter
return resolver : resolve ( wrapper . target , plan , path )
elseif identity == Sequence then
local sequence = adapter
local items = { }
for index , child in ipairs ( sequence . description . children ) do
local nested = assert ( plan : child ( child . member ) )
local item = resolver : resolve (
sequence . elements . adapters [ index ] ,
nested ,
"$"
)
if item == nil then
return nil
end
items [ index ] = item
end
return ( _G.setmetatable({ items =
items ,  tuple =
sequence . elements . tuple ,  path =
path ,  dynamic =  true }, SequenceEncoding) )

elseif identity == Map then
local mapping = adapter
if not stringKey ( mapping . entries . key . adapter ) then
return nil
end
local nested = assert ( plan : child ( mapping . description . children [ 2 ] . member ) )
local item = resolver : resolve ( mapping . entries . value . adapter , nested , "$" )
if item == nil then
return nil
end
return ( _G.setmetatable({ item =  item ,  path =  path ,  dynamic =  true }, MapEncoding) )
elseif identity == Scalar then
local scalar = adapter
local kind = scalar . description . kind
if kind == "string"
or kind == "boolean"
or kind == "float"
or kind == "numberToken"
or kind == "integer" and scalar . description . width ~= 64
then
return ( _G.setmetatable({ description =  scalar . description ,  path =  path ,  dynamic =  false }, ScalarEncoding) )
end
end

return nil
end ;__nuppExports["nativeEncoding"]=nativeEncoding
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[FieldOptions]="nupp.serde.internal.declaration\0FieldOptions";__nuppWorkerRecords[Options]="nupp.serde.internal.declaration\0Options"; end);if not __nuppOk then package.loaded["nupp.serde.internal.declaration"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.declaration"]=__nuppExports;return __nuppExports