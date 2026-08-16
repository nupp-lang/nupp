_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local T = require ( "nupp.compiler.types" )
local hash = require ( "nupp.compiler.build.hash" )
local stable = require ( "nupp.compiler.build.cache" ) . stable






const typeblueprint = {} typeblueprint.__index = typeblueprint






typeblueprint . SCHEMA = 1
typeblueprint . MAX_NODES = 10000
typeblueprint . MAX_MEMBERS = 1000

local PRIMITIVES = {
any = T . any ,
unknown = T . unknown ,
never = T . never ,
[ "nil" ] = T . nil_ ,
boolean = T . boolean ,
string = T . string ,
number = T . number ,
integer = T . integer ,
[ "table" ] = T . table_ ,
thread = T . thread ,
userdata = T . userdata ,
float = T . float ,
cdata = T . cdata ,
cstring = T . cstring ,
voidptr = T . voidptr ,
int8 = T . int8 ,
int16 = T . int16 ,
int32 = T . int32 ,
int64 = T . int64 ,
uint8 = T . uint8 ,
uint16 = T . uint16 ,
uint32 = T . uint32 ,
uint64 = T . uint64 ,
}

local function failure ( message )
return { code = "NUPP2415" , message = message }
end

function typeblueprint . validate ( envelope , permittedReferences )
if type (
envelope
) ~= "table"
or envelope . kind ~= "type-blueprint"
or envelope . provider ~= "types"
or envelope . schema ~= typeblueprint . SCHEMA
or envelope . family ~= "Type"
and envelope . family ~= "Pack"
or type (
envelope . payload
) ~= "table" or type ( envelope . fingerprint ) ~= "string" then
return nil , failure ( "the comptime worker returned a malformed type blueprint envelope" )
end
local payload , nodes = envelope . payload , envelope . payload . nodes
if type (
nodes
) ~= "table" or # nodes < 1 or # nodes > typeblueprint . MAX_NODES or type (
payload . root
) ~= "number" or payload . root ~= math . floor ( payload . root ) or payload . root < 1 or payload . root > # nodes then
return nil , failure ( "type blueprint has an invalid graph root or node count" )
end
local expectedFingerprint = hash . sha256 ( "nupp.types\0v1\0" .. stable ( payload ) )
if envelope . fingerprint ~= expectedFingerprint then
return nil , failure ( "type blueprint fingerprint does not match its payload" )
end

local built , active = { } , { }
local build
local function edge ( index , label )
if type ( index ) ~= "number" or index ~= math . floor ( index ) or index < 1 or index > # nodes then
return nil , label .. " has an invalid type edge"
end
return build ( index )
end

local function edgeArray ( values , label )
if type ( values ) ~= "table" or # values > typeblueprint . MAX_MEMBERS then
return nil , label .. " has an invalid or oversized member array"
end
local out = { }
for position , index in ipairs ( values ) do
local value , why = edge ( index , label .. " member " .. tostring ( position ) )
if not value then
return nil , why
end
if value . tag == "pack" then
return nil , label .. " contains a type pack where a type is required"
end
out [ position ] = value
end

return out , nil
end

build = function ( index )
if built [ index ] then
return built [ index ]
end
if active [ index ] then
return nil , "type blueprint contains a structural cycle"
end
local node = nodes [ index ]
if type ( node ) ~= "table" or type ( node . kind ) ~= "string" then
return nil , "type blueprint node " .. tostring ( index ) .. " has no kind"
end
active [ index ] = true
local value , why
if node . kind == "primitive" then
value = PRIMITIVES [ node . name ]
if not value then
why = "type blueprint names an unknown primitive " .. tostring ( node . name )
end
elseif node . kind == "reference" then
local reference = type ( envelope . references ) == "table" and envelope . references [ node . reference ] or nil
local explicitlyPermitted = false
if (
type ( reference ) ~= "table" or not reference . source
) and type ( node . referenceId ) == "string" and type ( permittedReferences ) == "table" then
reference = permittedReferences [ node . referenceId ]
explicitlyPermitted = reference ~= nil
end
if ( type ( reference ) ~= "table" or not reference . source ) and type ( permittedReferences ) == "table" then
for _ , permitted in pairs ( permittedReferences ) do
if permitted . fingerprint == node . fingerprint then
reference = permitted
explicitlyPermitted = true
break
end
end
end
if type (
node . fingerprint
) ~= "string" or type (
reference
) ~= "table" or type (
reference . fingerprint
) ~= "string" or not reference . source or node . fingerprint ~= reference . fingerprint then
why = "type blueprint names an invalid permitted input reference " .. tostring (
node . referenceId or node . reference
)
else
local reflection = require ( "nupp.compiler.reflection" )
local described = reflection . describe ( reference . source )
if not explicitlyPermitted and described . fingerprint ~= reference . fingerprint then
why = "type blueprint input reference fingerprint is stale " .. tostring (
node . referenceId or node . reference
)
else
value = reference . source
end
end
elseif node . kind == "literal" then
local base
base , why = edge ( node . base , "literal base" )
if base and base . tag == "pack" then
why , base = "literal base is a type pack" , nil
end
if base then
local kind = type ( node . value )
if kind ~= "string" and kind ~= "boolean" and (
kind ~= "number" or node . value ~= math . floor ( node . value )
) then
why = "type blueprint literal is not a string, boolean, or exact integer"
else
value = T . literal ( node . value , base )
end
end
elseif node . kind == "array" then
local element
element , why = edge ( node . element , "array element" )
if element and element . tag ~= "pack" then
value = T . array ( element )
elseif element then
why = "array element is a type pack"
end
elseif node . kind == "carray" then
local element
element , why = edge ( node . element , "C-array element" )
if element and element . tag == "pack" then
why , element = "C-array element is a type pack" , nil
end
if element then
if node . count ~= nil and (
type ( node . count ) ~= "number" or node . count ~= math . floor ( node . count ) or node . count < 0
) then
why = "C-array count is not a non-negative exact integer"
else
value = T . carray ( element , node . count )
end
end
elseif node . kind == "ptr"
or node . kind == "const"
or node . kind == "borrowed"
or node . kind == "pinned"
or node . kind == "affine"
then
local inner
inner , why = edge ( node . inner , node . kind .. " inner type" )
if inner and inner . tag == "pack" then
why , inner = node . kind .. " inner value is a type pack" , nil
end
if inner then
if node . kind == "ptr" then
value = T . ptr ( inner )
elseif node . kind == "const" then
value = T . constOf ( inner )
elseif node . kind == "borrowed" then
value = T . borrowed ( inner )
elseif node . kind == "pinned" then
value = T . pinned ( inner )
elseif node . transferOnly == true then
if node . terminal ~= nil then
why = "transfer-only affine blueprint also names a terminal"
else
value = T . affine ( inner , nil , true )
end
elseif type ( node . terminal ) ~= "string" then
why = "affine blueprint has no permitted terminal identity"
else
local permitted = type (
permittedReferences
) == "table" and permittedReferences [ "function:" .. node . terminal ] or nil
local cleanup = permitted and permitted . cleanup or nil
if not cleanup or cleanup . key ~= node . terminal then
why = "affine blueprint names an unpermitted const-function terminal"
else
value = T . affine ( inner , { cleanup } )
end
end
end
elseif node . kind == "tuple" then
local members
members , why = edgeArray ( node . members , "tuple" )
if members then
value = T . tuple ( members )
end
elseif node . kind == "union" then
local members
members , why = edgeArray ( node . members , "union" )
if members then
value = T . union ( members )
end
elseif node . kind == "intersection" then
local members
members , why = edgeArray ( node . members , "intersection" )
if members then
value = T . intersection ( members )
end
elseif node . kind == "indexer" then
local values , labels = { } , { "read key" , "read value" , "write key" , "write value" }
local edges = { node . readKey , node . readValue , node . writeKey , node . writeValue }
for position = 1 , 4 do
local indexValue = edges [ position ]
if indexValue ~= nil then
values [ position ] , why = edge ( indexValue , "indexer " .. labels [ position ] )
if why or values [ position ] . tag == "pack" then
why = why or "indexer " .. labels [ position ] .. " is a type pack"
break
end
end
end
if not why then
if (
values [ 1 ] == nil
) ~= (
values [ 2 ] == nil
) or ( values [ 3 ] == nil ) ~= ( values [ 4 ] == nil ) or values [ 1 ] == nil and values [ 3 ] == nil then
why = "indexer capabilities do not contain complete key/value pairs"
else
value = T . indexer ( values [ 1 ] , values [ 2 ] , values [ 3 ] , values [ 4 ] )
end
end
elseif node . kind == "shape" then
if type ( node . fields ) ~= "table" or # node . fields > typeblueprint . MAX_MEMBERS then
why = "shape has an invalid or oversized field array"
else
local fields , seen = { } , { }
for position , field in ipairs ( node . fields ) do
if type (
field
) ~= "table" or type ( field . name ) ~= "string" or field . name == "" or seen [ field . name ] then
why = "shape has an invalid or repeated field at " .. tostring ( position )
break
end
local read , write
if field . read ~= nil then
read , why = edge ( field . read , "shape read field " .. field . name )
end
if not why and field . write ~= nil then
write , why = edge ( field . write , "shape write field " .. field . name )
end
if why
or read
and read . tag == "pack"
or write
and write . tag == "pack"
or not read
and not write
then
why = why or "shape field " .. field . name .. " has invalid capabilities"
break
end
seen [ field . name ] = true
fields [ # fields + 1 ] = { name = field . name , read = read , write = write }
end
local indexer
if not why and node . indexer ~= nil then
indexer , why = edge ( node . indexer , "shape indexer" )
if indexer and indexer . tag ~= "map" then
why , indexer = "shape indexer is not an indexer" , nil
end
end
if not why then
value = T . shape (
fields ,
indexer and {
readKey = indexer . readable and indexer . key or nil ,
readValue = indexer . readable and indexer . value or nil ,
writeKey = indexer . writeKey ,
writeValue = indexer . writeValue ,
} or nil
)
end
end
elseif node . kind == "function" then
local parameters , results
parameters , why = edge ( node . parameters , "function parameters" )
if not why then
results , why = edge ( node . results , "function results" )
end
if not why and ( parameters . tag ~= "pack" or results . tag ~= "pack" ) then
why = "function parameters and results must be type packs"
elseif not why then
local tail = parameters . tail
value = T . func (
parameters . head ,
results . head ,
tail ~= nil ,
parameters . modes ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
tail and tail . type or nil ,
nil ,
parameters ,
results
)
end
elseif node . kind == "pack" then
local head
head , why = edgeArray ( node . head , "pack" )
if head then
local modes = node . modes or { }
if type ( modes ) ~= "table" or # modes > # head then
why = "type blueprint pack modes do not align with its head"
else
local copiedModes = { }
for position = 1 , # head do
local mode = modes [ position ] or "plain"
if mode ~= "plain" and mode ~= "affine" and mode ~= "borrowed" and mode ~= "pinned" then
why = "type blueprint pack has an invalid mode at " .. tostring ( position )
break
end
copiedModes [ position ] = mode
end
local tail
if not why and node . tail ~= nil then
tail , why = edge ( node . tail , "pack tail" )
if tail and tail . tag == "pack" then
why , tail = "pack tail is a type pack" , nil
end
end
if not why then
value = T . pack ( head , tail and { kind = "homogeneous" , type = tail } or nil , copiedModes )
end
end
end
else
why = "type blueprint uses unsupported kind " .. tostring ( node . kind )
end
active [ index ] = nil
if not value then
return nil , why
end
built [ index ] = value

return value
end

local result , why = build ( payload . root )
if not result then
return nil , failure ( why )
end
if envelope . family == "Pack" and result . tag ~= "pack" then
return nil , failure ( "type blueprint claims a pack but returns a type" )
elseif envelope . family == "Type" and result . tag == "pack" then
return nil , failure ( "type blueprint claims a type but returns a pack" )
end

return result , nil
end

return typeblueprint
