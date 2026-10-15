_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.types.typeblueprint\0runtime\0001") };









local T = require ( "nupp.compiler.types" )
local constrain = require ( "nupp.compiler.types.constrain" )
local hash = require ( "nupp.compiler.hash" )
local stable = require ( "nupp.compiler.stable" )






local typeblueprint = {} typeblueprint.__index = typeblueprint ;_G.nupp.__reflect.link(typeblueprint,__nuppT1[1],{ })






typeblueprint . SCHEMA = 1
typeblueprint . MAX_NODES = 10000
typeblueprint . MAX_MEMBERS = 1000

local PRIMITIVES = {
any = T . any ,
unknown = T . unknown ,
never = T . never ,
open = T . open ,
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

local function exactInteger ( value ) 
return type ( value ) == "number" and value == math . floor ( value ) and value > - math . huge and value < math . huge
end




local function denseArrayLength ( values , limit ) 
if type ( values ) ~= "table" then
return nil
end
local count = 0
for key in pairs ( values ) do
if not ( type ( key ) == "number" and key == math . floor ( key ) and key > - math . huge and key < math . huge ) or key < 1 or key > limit then
return nil
end
count = count + 1
end
for position = 1 , count do
if values [ position ] == nil then
return nil
end
end

return count
end

local function sparseArrayKeysFit ( values , limit ) 
if type ( values ) ~= "table" then
return false
end
for key in pairs ( values ) do
if not ( type ( key ) == "number" and key == math . floor ( key ) and key > - math . huge and key < math . huge ) or key < 1 or key > limit then
return false
end
end

return true
end

function typeblueprint . validate ( envelope , permittedReferences ) 
if type ( envelope ) ~= "table"
or envelope . kind ~= "type-blueprint"
or envelope . provider ~= "types"
or envelope . schema ~= typeblueprint . SCHEMA
or envelope . family ~= "Type" and envelope . family ~= "Pack"
or type ( envelope . payload ) ~= "table"
or type ( envelope . fingerprint ) ~= "string"
then
return nil , failure ( "the comptime worker returned a malformed type blueprint envelope" )
end
local payload , nodes = envelope . payload , envelope . payload . nodes
local nodeCount = denseArrayLength ( nodes , typeblueprint . MAX_NODES )
if nodeCount == nil
or nodeCount < 1
or not exactInteger ( payload . root )
or payload . root < 1
or payload . root > nodeCount
then
return nil , failure ( "type blueprint has an invalid graph root or node count" )
end
local expectedFingerprint = hash . sha256 ( "nupp.types\0v1\0" .. stable ( payload ) )
if envelope . fingerprint ~= expectedFingerprint then
return nil , failure ( "type blueprint fingerprint does not match its payload" )
end

local built , active = { } , { }
local build

local function edge ( index , label ) 
if not ( type ( index ) == "number" and index == math . floor ( index ) and index > - math . huge and index < math . huge ) or index < 1 or index > ( nodeCount ) then
return nil , label .. " has an invalid type edge"
end
return build ( index )
end

local function edgeArray ( values , label ) 
local length = denseArrayLength ( values , typeblueprint . MAX_MEMBERS )
if length == nil then
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
if ( type ( reference ) ~= "table" or not reference . source )
and type ( node . referenceId ) == "string"
and type ( permittedReferences ) == "table"
then
reference = permittedReferences [ node . referenceId ]
explicitlyPermitted = reference ~= nil
end
if ( type ( reference ) ~= "table" or not reference . source ) and type ( permittedReferences ) == "table" then
for _ , permitted in pairs ( permittedReferences ) do
if permitted . fingerprint == node . fingerprint then
reference = permitted
explicitlyPermitted = true
do break end
end
end
end
if type ( node . fingerprint ) ~= "string"
or type ( reference ) ~= "table"
or type ( reference . fingerprint ) ~= "string"
or not reference . source
or node . fingerprint ~= reference . fingerprint
then
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
if kind ~= "string" and kind ~= "boolean" and ( kind ~= "number" or not exactInteger ( node . value ) ) then
why = "type blueprint literal is not a string, boolean, or exact integer"
elseif kind == "string" and base ~= T . string
or kind == "boolean" and base ~= T . boolean
or kind == "number" and base ~= T . integer
then
why = "type blueprint literal has the wrong primitive base"
else
value = T . literal ( node . value , base )
end
end
elseif node . kind == "constrained" then
local base
base , why = edge ( node . inner , "constrained base" )
if base and base . tag == "pack" then
why , base = "constrained base is a type pack" , nil
end
if base then
if not exactInteger ( node . low ) or not exactInteger ( node . high ) or type ( node . lengthwise ) ~= "boolean" then
why = "type blueprint constraint has invalid bounds"
base = nil
end
end
if base then



local built , reason = constrain . build ( base , node . low or 0 , node . high or 0 , node . lengthwise == true )
if built then
value = built
else
why = reason or "type blueprint constraint cannot be built"
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
if node . count ~= nil and ( not exactInteger ( node . count ) or node . count < 0 ) then
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
local permitted = type ( permittedReferences ) == "table"
and permittedReferences [ "function:" .. node . terminal ]
or nil
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
do break end
end
end
end
if not why then
if ( values [ 1 ] == nil ) ~= ( values [ 2 ] == nil )
or ( values [ 3 ] == nil ) ~= ( values [ 4 ] == nil )
or values [ 1 ] == nil and values [ 3 ] == nil
then
why = "indexer capabilities do not contain complete key/value pairs"
else
value = T . indexer ( values [ 1 ] , values [ 2 ] , values [ 3 ] , values [ 4 ] )
end
end
elseif node . kind == "shape" then
if denseArrayLength ( node . fields , typeblueprint . MAX_MEMBERS ) == nil then
why = "shape has an invalid or oversized field array"
else
local fields , seen = { } , { }
for position , field in ipairs ( node . fields ) do
if type ( field ) ~= "table"
or type ( field . name ) ~= "string"
or field . name == ""
or seen [ field . name ]
then
why = "shape has an invalid or repeated field at " .. tostring ( position )
do break end
end
local read , write
if field . read ~= nil then
read , why = edge ( field . read , "shape read field " .. field . name )
end
if not why and field . write ~= nil then
write , why = edge ( field . write , "shape write field " .. field . name )
end
if why
or read and read . tag == "pack"
or write and write . tag == "pack"
or not read and not write
then
why = why or "shape field " .. field . name .. " has invalid capabilities"
do break end
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
indexer
and {
readKey = indexer . readable and indexer . key or nil ,
readValue = indexer . readable and indexer . value or nil ,
writeKey = indexer . writeKey ,
writeValue = indexer . writeValue ,
}
or nil
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
if not sparseArrayKeysFit ( modes , # head ) then
why = "type blueprint pack modes do not align with its head"
else
local copiedModes = { }
for position = 1 , # head do
local mode = modes [ position ] or "plain"
if mode ~= "plain"
and mode ~= "affine"
and mode ~= "borrowed"
and mode ~= "exclusive"
and mode ~= "pinned"
and mode ~= "takes"
then
why = "type blueprint pack has an invalid mode at " .. tostring ( position )
do break end
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
local names = node . names
if names ~= nil and not sparseArrayKeysFit ( names , # head ) then
why = "type blueprint pack names do not align with its head"
else
for _ , name in pairs ( names or { } ) do
if type ( name ) ~= "string" then
why = "type blueprint pack has an invalid parameter name"
do break end
end
end
end
if not why then
value = T . pack (
head ,
tail and { kind = "homogeneous" , type = tail } or nil ,
copiedModes ,
names
)
end
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

local __nuppExportValue= typeblueprint ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.typeblueprint"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.typeblueprint"]=__nuppExports;return __nuppExports