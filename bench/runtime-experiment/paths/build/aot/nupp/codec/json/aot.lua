_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local numberSyntax = require ( "nupp.codec.json.number" )





















local eagerDecoder = require ( "nupp.codec.json.internal.decoder.eager" )
local pullDecoder = require ( "nupp.codec.json.internal.decode" )
local serdeDecoder = require ( "nupp.codec.json.internal.decoder.serde" )
local newBuffer = require ( "nupp.text" ) . newBuffer
local bit = require ( "bit" )
local contracts = require ( "nupp.codec.json.spi" )

local json = __nuppNew(0,3)
local ARRAY_MARKER , OBJECT_MARKER , ARRAY_SHAPE = { } , { } , { }
local SERDE_ALIASES , SERDE_WILDCARD , SERDE_REJECT , SERDE_METATABLE , SERDE_ORDER , SERDE_KEYS = { } , { } , { } , { } , { } , { }
local SERDE_REQUIRED , SERDE_DEFAULTS , SERDE_NULLABLE = { } , { } , { }
local SERDE_SCALAR , SERDE_LITERAL , SERDE_FACTORY , SERDE_TUPLE , SERDE_UNION = { } , { } , { } , { } , { }
local SERDE_MARKERS = {
SERDE_ALIASES ,
SERDE_WILDCARD ,
SERDE_REJECT ,
SERDE_METATABLE ,
SERDE_ORDER ,
SERDE_KEYS ,
SERDE_REQUIRED ,
SERDE_DEFAULTS ,
SERDE_NULLABLE ,
SERDE_SCALAR ,
SERDE_LITERAL ,
SERDE_FACTORY ,
SERDE_TUPLE ,
SERDE_UNION ,
}
local ENCODED_VALUE , ENCODED_STRING = { } , { }
local encodedStrings = setmetatable ( { } , { __mode = "v" } )
local verifiedStrings = setmetatable ( { } , { __mode = "v" } )

json . NULL = setmetatable ( { } , {
__tostring = function ( ) 
return "null"
end
} )
json . EMPTY_ARRAY = setmetatable ( { } , ARRAY_MARKER )
json . EMPTY_OBJECT = setmetatable ( { } , OBJECT_MARKER )




local function withoutPosition ( problem ) 
local text = tostring ( problem )
text = text : gsub ( "^%a:[^\n:]-:%d+: " , "" , 1 )
text = text : gsub ( "^[^\n:]-:%d+: " , "" , 1 )

return text
end



local function outOfRange ( text , position ) 
local token = text : match ( "^%-?%d+%.?%d*[eE]?[-+]?%d*" , position )
local value = token ~= nil and tonumber ( token ) or nil

return value == math . huge or value == - math . huge
end

local function failDecode ( code , position , source ) 
local message = code == 2 and "invalid UTF-8"
or code == 3 and "unescaped control byte"
or code == 4 and "backslash outside a string"
or code == 5 and "structural index overflow"
or code == 1 and outOfRange ( source , position ) and "number is out of range"
or "invalid syntax"
error ( "invalid JSON at byte " .. tostring ( position ) .. ": " .. message , 0 )
end

function json . decode ( text , nullValue ) 
local ok , value , code , position = pcall (
eagerDecoder . decode ,
text ,
nullValue ,
ARRAY_MARKER ,
OBJECT_MARKER ,
nil ,
ARRAY_SHAPE ,
SERDE_MARKERS
)
if not ok then
error ( withoutPosition ( value ) , 0 )
end
if code ~= 0 then
failDecode ( code , position , text )
end

return value
end

local function classify ( value ) 
local marker = getmetatable ( value )
local count , highest = 0 , 0
local numbers , strings = false , false
for key in pairs ( value ) do
count = count + 1
if type ( key ) == "number" and key >= 1 and key % 1 == 0 then
numbers = true
highest = math . max ( highest , math . floor ( key ) )
elseif type ( key ) == "string" then
strings = true
else
error ( "JSON object keys must be strings and array indexes must be positive integers" , 0 )
end
end
if numbers and strings then
error ( "a JSON container cannot mix array indexes and object keys" , 0 )
elseif marker == ARRAY_MARKER and strings then
error ( "an array-marked table cannot contain object keys" , 0 )
elseif marker == OBJECT_MARKER and numbers then
error ( "an object-marked table cannot contain array indexes" , 0 )
elseif numbers and count ~= highest then
error ( "JSON arrays cannot contain holes" , 0 )
end
local kind = "object"
local size = count
if numbers or marker == ARRAY_MARKER then
kind = "array"
size = highest
end

return kind , math . floor ( size )
end

local simpleEscapes = { [ 8 ] = "\\b" , [ 9 ] = "\\t" , [ 10 ] = "\\n" , [ 12 ] = "\\f" , [ 13 ] = "\\r" , [ 34 ] = "\\\"" , [ 92 ] = "\\\\" , }

local hex = "0123456789abcdef"



local function refuseUtf8 ( ) 
error ( "cannot encode invalid UTF-8 as JSON" , 0 )
end













local function quote ( value ) 
local out = newBuffer ( )
out : put ( "\"" )
local first , at , length = 1 , 1 , # value
while at <= length do
local byte = value : byte ( at )
if byte < 128 then
local replacement = simpleEscapes [ byte ]
if replacement ~= nil or byte < 32 then
if at > first then
out : put ( value : sub ( first , at - 1 ) )
end
if replacement ~= nil then
out : put ( replacement )
else
local high = math . floor ( byte / 16 )
local low = byte % 16
out : put ( "\\u00" .. ("0123456789abcdef") : sub ( high + 1 , high + 1 ) .. ("0123456789abcdef") : sub ( low + 1 , low + 1 ) )
end
first = at + 1
end
at = at + 1
elseif byte < 224 then
if byte < 194 or at + 1 > length then
refuseUtf8 ( )
end
local second = value : byte ( at + 1 )
if second < 128 or second > 191 then
refuseUtf8 ( )
end
at = at + 2
elseif byte < 240 then
if at + 2 > length then
refuseUtf8 ( )
end
local second = value : byte ( at + 1 )
local third = value : byte ( at + 2 )
if second < 128 or second > 191 or third < 128 or third > 191 then
refuseUtf8 ( )
end
if ( byte == 224 and second < 160 ) or ( byte == 237 and second > 159 ) then
refuseUtf8 ( )
end
at = at + 3
elseif byte < 245 then
if at + 3 > length then
refuseUtf8 ( )
end
local second = value : byte ( at + 1 )
local third = value : byte ( at + 2 )
local fourth = value : byte ( at + 3 )
if second < 128 or second > 191 or third < 128 or third > 191 or fourth < 128 or fourth > 191 then
refuseUtf8 ( )
end
if ( byte == 240 and second < 144 ) or ( byte == 244 and second > 143 ) then
refuseUtf8 ( )
end
at = at + 4
else
refuseUtf8 ( )
end
end
if first <= length then
out : put ( value : sub ( first ) )
end
out : put ( "\"" )

return out : tostring ( )
end

local function encodedBytes ( value ) 
local marker = getmetatable ( value )
if marker == ENCODED_VALUE or marker == ENCODED_STRING then
return value . bytes
end

return nil
end

local encodeValue

encodeValue = function ( value , nullValue , visiting , depth ) 
local trusted = encodedBytes ( value )
if trusted ~= nil then
return trusted
end
if value == json . NULL or nullValue ~= nil and value == nullValue then
return "null"
end
local kind = type ( value )
if kind == "string" then
return quote ( value )
elseif kind == "boolean" then
return value and "true" or "false"
elseif kind == "number" then
if value ~= value or value == math . huge or value == - math . huge then
error ( "JSON numbers must be finite" , 0 )
end
local text = tostring ( value )
if tonumber ( text ) ~= value then


text = ("%.17g") : format ( value )
end
return text
elseif kind ~= "table" then
error ( "cannot encode " .. kind .. " as JSON" , 0 )
elseif depth >= 1024 then
error ( "JSON serialization nesting exceeds 1024" , 0 )
elseif visiting [ value ] then
error ( "cannot serialize a cyclic Lua table" , 0 )
end
visiting [ value ] = true
local container , count = classify ( value )
local parts = { }
if container == "array" then
parts [ 1 ] = "["
for index = 1 , count do
if index > 1 then
parts [ # parts + 1 ] = ","
end
parts [ # parts + 1 ] = encodeValue ( value [ index ] , nullValue , visiting , depth + 1 )
end
parts [ # parts + 1 ] = "]"
else
parts [ 1 ] = "{"
local first = true
for key , child in pairs ( value ) do
if not first then
parts [ # parts + 1 ] = ","
end
first = false
parts [ # parts + 1 ] = quote ( key )
parts [ # parts + 1 ] = ":"
parts [ # parts + 1 ] = encodeValue ( child , nullValue , visiting , depth + 1 )
end
parts [ # parts + 1 ] = "}"
end
visiting [ value ] = nil

return table . concat ( parts )
end

function json . encode ( value , nullValue ) 
return encodeValue ( value , nullValue , { } , 0 )
end

function json . isArray ( value ) 
if type ( value ) ~= "table" then
return false
end
local kind = classify ( value )

return kind == "array"
end

function json . asArray ( value ) 
if type ( value ) ~= "table" then
error ( "json.asArray needs a table" , 2 )
end
local count = 0
local highest = 0
for key in pairs ( value ) do
if type ( key ) ~= "number" or key < 1 or key % 1 ~= 0 then
error ( "an array-marked table must contain consecutive positive indexes" , 2 )
end
count = count + 1
highest = math . max ( highest , math . floor ( key ) )
end
if count ~= highest then
error ( "an array-marked table must contain consecutive positive indexes" , 2 )
end

return setmetatable ( value , ARRAY_MARKER )
end

function json . asObject ( value ) 
if type ( value ) ~= "table" then
error ( "json.asObject needs a table" , 2 )
end
for key in pairs ( value ) do
if type ( key ) ~= "string" then
error ( "an object-marked table must contain string keys" , 2 )
end
end

return setmetatable ( value , OBJECT_MARKER )
end

function json . arrayOf ( shape ) 
return { [ ARRAY_SHAPE ] = shape == nil and true or shape }
end

function json . pull ( text , shape , nullValue ) 
if shape == nil then
error ( "pull shape entries must be true, false, object shapes, or array shapes" , 2 )
end
local ok , value , code , position = pcall (
pullDecoder . decode ,
text ,
nullValue ,
ARRAY_MARKER ,
OBJECT_MARKER ,
shape ,
ARRAY_SHAPE ,
nil
)
if not ok then
error ( withoutPosition ( value ) , 0 )
end
if code ~= 0 then
failDecode ( code , position , text )
end

return value
end

local function word32 ( value ) 
if value < 0 then
value = value + 4294967296
end
local a = value % 256
value = math . floor ( value / 256 )
local b = value % 256
value = math . floor ( value / 256 )
local c = value % 256
value = math . floor ( value / 256 )

return string . char ( a , b , c , value % 256 )
end

local function keyHash ( value ) 
local hash = -2128831035
for index = 1 , # value do
hash = bit . bxor ( hash , value : byte ( index ) )
hash = bit . tobit (
hash + bit . lshift (
hash ,
1
) + bit . lshift ( hash , 4 ) + bit . lshift ( hash , 7 ) + bit . lshift ( hash , 8 ) + bit . lshift ( hash , 24 )
)
end

return hash
end

local function compiledKeys (
keys ,
required ,
targets ,
aliases ,
defaults ,
factory
) 
local headers = { }
local bytes = { }
local offset = 0
local requiredLow , requiredHigh = 0 , 0
for index , key in ipairs ( keys ) do
local packed = ( key .. "\"" .. string . rep ( "\0" , 8 ) ) : sub ( 1 , 8 )
local target = targets [ index ]
local scalar = type ( target ) == "number" and target or 0
headers [ index ] = word32 ( # key ) .. word32 ( keyHash ( key ) ) .. packed .. word32 ( offset ) .. word32 ( scalar )
bytes [ index ] = key
offset = offset + # key
if required [ index ] then
if index <= 32 then
requiredLow = requiredLow + 2 ^ ( index - 1 )
else
requiredHigh = requiredHigh + 2 ^ ( index - 33 )
end
end
end

local flags = ( aliases and 2147483648 or 0 ) + ( defaults and 1073741824 or 0 ) + ( factory and 536870912 or 0 )

return word32 (
# keys + flags
) .. word32 ( requiredLow ) .. word32 ( requiredHigh ) .. table . concat ( headers ) .. table . concat ( bytes )
end

local function nativeScalarComplete ( plan ) 
if plan . kind == "boolean" or plan . kind == "string" or plan . kind == "number" then
return plan . minimum == nil and plan . maximum == nil
elseif plan . kind == "integer" then
return plan . minimum == nil and plan . maximum == nil
or plan . minimum == -128 and plan . maximum == 127
or plan . minimum == -32768 and plan . maximum == 32767
or plan . minimum == -2147483648 and plan . maximum == 2147483647
elseif plan . kind == "unsigned" then
return ( plan . minimum == nil or plan . minimum == 0 )
and ( plan . maximum == nil or plan . maximum == 255 or plan . maximum == 65535 or plan . maximum == 4294967295 )
end

return false
end

local function nativeComplete ( plan , visiting , known ) 
local prior = known [ plan ]
if prior ~= nil then
return prior
elseif visiting [ plan ] then
return true
end
visiting [ plan ] = true
local kind = plan . kind
local complete = plan . completeHint ~= false
if kind == "optional" or kind == "list" then
complete = complete and nativeComplete ( plan . element , visiting , known )
elseif kind == "map" then
complete = complete and nativeComplete ( plan . value , visiting , known )
elseif kind == "tuple" then
for _ , item in ipairs ( plan . items ) do
complete = complete and nativeComplete ( item , visiting , known )
end
elseif kind == "union" then
for _ , item in ipairs ( plan . choices ) do
complete = complete and item . hasLiteral == true and nativeComplete ( item , visiting , known )
end
elseif kind == "structure" then
complete = complete
and ( plan . access == "record" or plan . access == "struct" or plan . access == "dynamic" )
and # plan . fields <= 64
for _ , field in ipairs ( plan . fields ) do
complete = complete and nativeComplete ( field . target , visiting , known )
end
else
complete = complete and nativeScalarComplete ( plan )
end
visiting [ plan ] = nil
known [ plan ] = complete

return complete
end

local function scalarShape ( plan ) 
local code = plan . kind == "boolean" and 1
or plan . kind == "string" and 2
or plan . kind == "number" and 3
or plan . kind == "integer" and plan . minimum == -128 and plan . maximum == 127 and 9
or plan . kind == "integer" and plan . minimum == -32768 and plan . maximum == 32767 and 10
or plan . kind == "integer" and plan . minimum == -2147483648 and plan . maximum == 2147483647 and 11
or plan . kind == "integer" and 4
or plan . minimum == 0 and plan . maximum == 255 and 6
or plan . minimum == 0 and plan . maximum == 65535 and 7
or plan . minimum == 0 and plan . maximum == 4294967295 and 8
or 5

if plan . strictInteger then
code += 32
end

if plan . hasLiteral then
return { [ SERDE_SCALAR ] = code , [ SERDE_LITERAL ] = plan . literalValue , }
end

return code
end

local function nullableShape ( target ) 
if type ( target ) == "number" then
return - target
end
local shape = { }
for key , value in pairs ( target ) do
shape [ key ] = value
end
shape [ SERDE_NULLABLE ] = true

return shape
end

local function serdeShape ( plan , seen , rejectUnknown , validate ) 
local prior = seen [ plan ]
if prior ~= nil then
return prior
end
local kind = plan . kind
if kind == "optional" then
local target = serdeShape ( plan . element , seen , rejectUnknown , validate )
return validate and nullableShape ( target ) or target
elseif kind == "list" then
local shape = { }
seen [ plan ] = shape
shape [ ARRAY_SHAPE ] = serdeShape ( plan . element , seen , rejectUnknown , validate )
return shape
elseif kind == "map" then
local shape = { }
seen [ plan ] = shape
shape [ SERDE_WILDCARD ] = serdeShape ( plan . value , seen , rejectUnknown , validate )
return shape
elseif kind == "tuple" then
local shape = { }
local items = { [ SERDE_TUPLE ] = true }
seen [ plan ] = shape
shape [ ARRAY_SHAPE ] = items
for index , item in ipairs ( plan . items ) do
items [ index ] = serdeShape ( item , seen , rejectUnknown , validate )
end
return shape
elseif kind == "union" then
local shape = { }
local choices = { }
seen [ plan ] = shape
shape [ SERDE_UNION ] = choices
for index , item in ipairs ( plan . choices ) do
choices [ index ] = item . literalValue
end
return shape
elseif kind ~= "structure" then
return validate and scalarShape ( plan ) or true
end
local shape = { }
seen [ plan ] = shape
local order = { }
local aliases = { }
local required = { }
local defaults = { }
shape [ SERDE_ORDER ] = order
shape [ SERDE_REJECT ] = rejectUnknown
if plan . access == "record" then
shape [ SERDE_METATABLE ] = plan . typeObject
shape [ -65 ] = plan . typeObject
end
for index , field in ipairs ( plan . fields ) do
order [ index ] = field . wire
local output = plan . access == "dynamic" and index or field . name
local target = serdeShape ( field . target , seen , rejectUnknown , validate )
shape [ field . wire ] = target
shape [ index ] = target
if output ~= field . wire then
aliases [ field . wire ] = output
shape [ - index ] = output
end
if validate then
if field . required then
required [ # required + 1 ] = output
elseif field . hasDefault then
defaults [ output ] = field . defaultValue
end
end
end
if next ( aliases ) ~= nil then
shape [ SERDE_ALIASES ] = aliases
end
if validate and # required ~= 0 then
shape [ SERDE_REQUIRED ] = required
end
if validate and next ( defaults ) ~= nil then
shape [ SERDE_DEFAULTS ] = defaults
shape [ -66 ] = defaults
end
if plan . factory ~= nil then
shape [ SERDE_FACTORY ] = plan . factory
shape [ -67 ] = plan . factory
end
local requiredIndexes = { }
if validate then
for index , field in ipairs ( plan . fields ) do
requiredIndexes [ index ] = field . required == true
end
end
local compiled = compiledKeys (
order ,
requiredIndexes ,
shape ,
next ( aliases ) ~= nil ,
validate and next ( defaults ) ~= nil ,
plan . factory ~= nil
)
shape [ SERDE_KEYS ] = compiled
shape [ 0 ] = compiled

return shape
end

function json . compileSerde ( plan , unknownMembers ) 
local complete = nativeComplete ( plan , { } , { } )
local finish = plan . deferRoot and plan . factory or nil
local root = plan
if finish ~= nil then
root = { }
for key , value in pairs ( plan ) do
if key ~= "factory" then
root [ key ] = value
end
end
end

return {
plan = plan ,
shape = serdeShape ( root , { } , unknownMembers == "reject" , complete ) ,
complete = complete ,
finish = finish
}
end

function json . decodeSerde ( schema , text ) 
local ok , value , code , position = pcall (
serdeDecoder . decode ,
text ,
nil ,
ARRAY_MARKER ,
OBJECT_MARKER ,
schema . shape ,
ARRAY_SHAPE ,
SERDE_MARKERS
)
if not ok then
if type ( value ) ~= "string" then
error ( value , 0 )
end
error ( withoutPosition ( value ) , 0 )
end
if code ~= 0 then
failDecode ( code , position , text )
end

if schema . finish ~= nil then
value = schema . finish ( value )
end

return value , nil
end

function json . decodeSerdeBuffer ( schema , input ) 
local ok , value , code , position = pcall (
serdeDecoder . decode ,
input ,
nil ,
ARRAY_MARKER ,
OBJECT_MARKER ,
schema . shape ,
ARRAY_SHAPE ,
SERDE_MARKERS
)
if not ok then
if type ( value ) ~= "string" then
error ( value , 0 )
end
error ( withoutPosition ( value ) , 0 )
end
if code ~= 0 then
failDecode ( code , position , code == 1 and input : tostring ( ) or "" )
end

if schema . finish ~= nil then
value = schema . finish ( value )
end

return value , nil
end

function json . encoded ( value , nullValue ) 
return setmetatable ( { bytes = json . encode ( value , nullValue ) } , ENCODED_VALUE )
end

function json . numberToken ( text ) 
if not numberSyntax . valid ( text ) then
error ( "a JSON number token is required" , 2 )
end
return setmetatable ( { bytes = text } , ENCODED_VALUE )
end

function json . encodedString ( value ) 
local prior = encodedStrings [ value ]
if prior ~= nil then
return prior
end
local result = setmetatable ( { bytes = quote ( value ) } , ENCODED_STRING )
encodedStrings [ value ] = result

return result
end

function json . verified ( text ) 
json . decode ( text , json . NULL )
return setmetatable ( { bytes = text } , ENCODED_VALUE )
end

function json . verifiedString ( text ) 
local prior = verifiedStrings [ text ]
if prior ~= nil then
return prior
end
local value = json . decode ( text , json . NULL )
if type ( value ) ~= "string" then
error ( "a verified JSON string is required" , 2 )
end
local result = setmetatable ( { bytes = text } , ENCODED_STRING )
verifiedStrings [ text ] = result

return result
end

function json . newWriter ( out , nullValue ) 
local parts = { }
local bytes = 0
local stack = { }
local root , closed = false , false
local writer = { }

local function publish ( ) 
if # parts > 0 then
out : put ( table . concat ( parts ) ) ;
parts = { } ;
bytes = 0
end
end

local function add ( text ) 
parts [ # parts + 1 ] = text
bytes = bytes + # text
if bytes >= 65536 then
publish ( )
end
end

local function prepare ( ) 
if closed then
error ( "writer is already closed" , 2 )
end
if # stack == 0 then
if root then
error ( "writer already has a root value" , 2 )
end
root = true
return
end
local frame = stack [ # stack ]
if frame . kind == "array" then
if not frame . first then
add ( "," )
end
frame . first = false
elseif not frame . value then
error ( "an object value must follow key()" , 2 )
else
frame . value = false
end
end

function writer : startArray ( ) 
prepare ( ) ;
add ( "[" ) ;
stack [ # stack + 1 ] = { kind = "array" , first = true } ;
return self
end

function writer : startObject ( ) 
prepare ( ) ;
add ( "{" ) ;
stack [ # stack + 1 ] = { kind = "object" , first = true , value = false } ;
return self
end

function writer : key ( name ) 
local frame = stack [ # stack ]
if closed or frame == nil or frame . kind ~= "object" or frame . value then
error ( "key() requires an open object with no pending key" , 2 )
end
if not frame . first then
add ( "," )
end
frame . first = false
add ( encodedBytes ( name ) or quote ( name ) ) ;
add ( ":" ) ;
frame . value = true

return self
end

function writer : write ( value ) 
local encoded = encodedBytes ( value ) or json . encode ( value , nullValue )
prepare ( ) ;
add ( encoded ) ;
return self
end

function writer : null ( ) 
prepare ( ) ;
add ( "null" ) ;
return self
end

local function finish ( kind , name ) 
local frame = stack [ # stack ]
if closed or frame == nil or frame . kind ~= kind then
error ( name .. " requires an open " .. kind , 2 )
end
if frame . value then
error ( "the final object key has no value" , 2 )
end
stack [ # stack ] = nil ;
add ( kind == "array" and "]" or "}" ) ;

return writer
end

function writer : endArray ( ) 
return finish ( "array" , "endArray()" )
end

function writer : endObject ( ) 
return finish ( "object" , "endObject()" )
end

function writer : flush ( ) 
if closed then
error ( "writer is already closed" , 2 )
end
publish ( )
end

local aborted = false

function writer : abort ( ) 
aborted , closed = true , true
parts , stack = { } , { }
bytes = 0
end

function writer : close ( ) 
if aborted then
return
end
if closed then
error ( "writer is already closed" , 2 )
end
closed = true
if not root or # stack > 0 then
parts = { } ;
error ( "close() requires one complete root value" , 2 )
end
publish ( )
end

return writer
end





local checked = {
arrayOf = json . arrayOf ,






asArray = json . asArray ,
asObject = json . asObject ,
isArray = json . isArray ,
decode = json . decode ,
encode = json . encode ,
encoded = json . encoded ,
encodedString = json . encodedString ,
numberToken = json . numberToken ,
pull = json . pull ,
verified = json . verified ,
verifiedString = json . verifiedString ,
newWriter = json . newWriter ,
NULL = json . NULL ,
EMPTY_ARRAY = json . EMPTY_ARRAY ,
EMPTY_OBJECT = json . EMPTY_OBJECT ,
compileSerde = json . compileSerde ,
decodeSerde = json . decodeSerde ,
decodeSerdeBuffer = json . decodeSerdeBuffer ,
}

local __nuppExportValue= checked ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.json.aot"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json.aot"]=__nuppExports;return __nuppExports