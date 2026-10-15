_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local numberSyntax = require ( "nupp.codec.json.number" )





















local newDecoder = require (
"nupp.runtime.vendor.lunajson.decoder"
)
local newEncoder = require ( "nupp.runtime.vendor.lunajson.encoder" )
local contracts = require ( "nupp.codec.json.spi" )
local core = { decode = newDecoder ( ) , encode = newEncoder ( ) , }
local json = __nuppNew(0,3)

local ARRAY_MARKER , OBJECT_MARKER , ARRAY_SHAPE = { } , { } , { }
local ENCODED_VALUE , ENCODED_STRING = { } , { }
local encodedStrings = setmetatable ( { } , { __mode = "v" } )
local verifiedStrings = setmetatable ( { } , { __mode = "v" } )

local function validUtf8 ( text ) 
local at , length = 1 , # text
while at <= length do
local first = text : byte ( at )
if first < 128 then
at = at + 1
else
local count = first >= 194 and first <= 223 and 1
or first >= 224 and first <= 239 and 2
or first >= 240 and first <= 244 and 3
or 0
if count == 0 or at + count > length then
return false
end
local second = text : byte ( at + 1 )
if second < 128
or second > 191
or first == 224 and second < 160
or first == 237 and second > 159
or first == 240 and second < 144
or first == 244 and second > 143
then
return false
end
for offset = 2 , count do
local continuation = text : byte ( at + offset )
if continuation < 128 or continuation > 191 then
return false
end
end
at = at + count + 1
end
end

return true
end

json . NULL = { }
json . EMPTY_ARRAY = setmetatable ( { } , ARRAY_MARKER )
json . EMPTY_OBJECT = setmetatable ( { } , OBJECT_MARKER )

local function classify ( value ) 
local marker = getmetatable ( value )
local numberKeys , stringKeys = false , false
local count = 0
local highest = 0
for key in pairs ( value ) do
count = count + 1
if type ( key ) == "number" and key >= 1 and key % 1 == 0 then
numberKeys = true
highest = math . max ( highest , math . floor ( key ) )
elseif type ( key ) == "string" then
stringKeys = true
else
error ( "JSON object keys must be strings and array indexes must be positive integers" , 0 )
end
end
if numberKeys and stringKeys then
error ( "a JSON container cannot mix array indexes and object keys" , 0 )
end
if marker == ARRAY_MARKER and stringKeys then
error ( "an array-marked table cannot contain object keys" , 0 )
end
if marker == OBJECT_MARKER and numberKeys then
error ( "an object-marked table cannot contain array indexes" , 0 )
end
if numberKeys then
if count ~= highest then
error ( "JSON arrays cannot contain holes" , 0 )
end

return "array" , highest
end
if marker == ARRAY_MARKER then
return "array" , 0
end

return "object" , count
end

local function mark ( value , nullValue ) 

if type ( value ) ~= "table" or value == json . NULL or nullValue ~= nil and value == nullValue then
return value
end
local length = value [ 0 ]
if type ( length ) == "number" then
value [ 0 ] = nil
setmetatable ( value , ARRAY_MARKER )
local into = 1
for index = 1 , length do
local child = value [ index ]
value [ index ] = nil
if child ~= nil then
value [ into ] = mark ( child , nullValue )
into = into + 1
end
end
else
setmetatable ( value , OBJECT_MARKER )
for key , child in pairs ( value ) do
value [ key ] = mark ( child , nullValue )
end
end

return value
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
return { [ ARRAY_SHAPE ] = shape == nil and true or shape , }
end





local function vendorProblem ( problem ) 
local text = tostring ( problem )
text = text : gsub ( "^%a:[^\n:]-:%d+: " , "" , 1 )
text = text : gsub ( "^[^\n:]-:%d+: " , "" , 1 )
local at , reason = text : match ( "^parse error at (%d+): (.*)$" )
if at ~= nil then
return "invalid JSON at byte " .. at .. ": " .. reason
end

return text
end

local function encodeValue ( value , nullValue , visiting , depth ) 
local marker = getmetatable ( value )
if marker == ENCODED_VALUE or marker == ENCODED_STRING then
return value . bytes
end
if value == json . NULL or nullValue ~= nil and value == nullValue then
return "null"
end
if type ( value ) ~= "table" then
if type ( value ) == "string" and not validUtf8 ( value ) then
error ( "cannot encode invalid UTF-8 as JSON" , 0 )
end
return core . encode ( value , json . NULL )
end
if depth >= 1024 then
error ( "JSON serialization nesting exceeds 1024" , 0 )
end
if visiting [ value ] then
error ( "cannot serialize a cyclic Lua table" , 0 )
end
visiting [ value ] = true
local kind , length = classify ( value )
local parts = { }
if kind == "array" then
for index = 1 , length do
parts [ index ] = encodeValue ( value [ index ] , nullValue , visiting , depth + 1 )
end
else
for key , child in pairs ( value ) do
if type ( key ) ~= "string" then
error ( "JSON object keys must be strings" , 0 )
end
if not validUtf8 ( key ) then
error ( "cannot encode invalid UTF-8 as JSON" , 0 )
end
parts [ # parts + 1 ] = core . encode ( key ) .. ":" .. encodeValue ( child , nullValue , visiting , depth + 1 )
end
end
visiting [ value ] = nil
local contents = table . concat ( parts , "," )

return kind == "array" and "[" .. contents .. "]" or "{" .. contents .. "}"
end

function json . encode ( value , nullValue ) 
local ok , encoded = pcall ( encodeValue , value , nullValue , { } , 0 )
if not ok then
error ( vendorProblem ( encoded ) , 0 )
end

return encoded
end

function json . decode ( text , nullValue ) 
if not validUtf8 ( text ) then
error ( "invalid UTF-8 in JSON" , 0 )
end
local ok , value = pcall ( core . decode , text , nil , nullValue , true )
if not ok then
error ( vendorProblem ( value ) , 0 )
end

return mark ( value , nullValue )
end

function json . isArray ( value ) 
if type ( value ) ~= "table" then
return false
end
local kind = classify ( value )

return kind == "array"
end

local function project ( value , shape , nullValue ) 
if shape == true then
return value
end
if type ( shape ) ~= "table" then
error ( "pull shape entries must be true, object shapes, or array shapes" , 0 )
end
local itemShape = shape [ ARRAY_SHAPE ]
if itemShape ~= nil then
if type ( value ) ~= "table"
or value == json . NULL
or nullValue ~= nil and value == nullValue
or getmetatable ( value ) ~= ARRAY_MARKER
then
error ( "pull array shape matched a non-array value" , 0 )
end
local out = json . asArray ( { } )
for _ , item in ipairs ( value ) do
out [ # out + 1 ] = project ( item , itemShape , nullValue )
end

return out
end
if type ( value ) ~= "table"
or value == json . NULL
or nullValue ~= nil and value == nullValue
or getmetatable ( value ) ~= OBJECT_MARKER
then
error ( "pull object shape matched a non-object value" , 0 )
end
local out = json . asObject ( { } )
for key , childShape in pairs ( shape ) do
if value [ key ] ~= nil then
out [ key ] = project ( value [ key ] , childShape , nullValue )
end
end

return out
end

function json . pull ( text , shape , nullValue ) 
return project ( json . decode ( text , nullValue ) , shape , nullValue )
end

function json . encoded ( value , nullValue ) 
return setmetatable ( { bytes = json . encode ( value , nullValue ) , } , ENCODED_VALUE )
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
if not validUtf8 ( value ) then
error ( "cannot encode invalid UTF-8 as JSON" , 0 )
end
local encoded = setmetatable ( { bytes = core . encode ( value ) , } , ENCODED_STRING )
encodedStrings [ value ] = encoded

return encoded
end

function json . verified ( text ) 
json . decode ( text , json . NULL )

return setmetatable ( { bytes = text , } , ENCODED_VALUE )
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

local verified = setmetatable ( { bytes = text , } , ENCODED_STRING )
verifiedStrings [ text ] = verified

return verified
end

function json . newWriter ( out , nullValue ) 
local parts , stack , root , closed = { } , { } , false , false
local pending = 0
local writer = { }

local function add ( text ) 
parts [ # parts + 1 ] = text
pending = pending + # text
if pending >= 65536 then
out : put ( table . concat ( parts ) )
parts = { }
pending = 0
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
prepare ( )
add ( "[" )
stack [ # stack + 1 ] = { kind = "array" , first = true , }

return self
end

function writer : startObject ( ) 
prepare ( )
add ( "{" )
stack [ # stack + 1 ] = { kind = "object" , first = true , value = false , }

return self
end

function writer : key ( name ) 
local frame = stack [ # stack ]
if closed or not frame or frame . kind ~= "object" or frame . value then
error ( "key() requires an open object with no pending key" , 2 )
end
local encoded
if getmetatable ( name ) == ENCODED_STRING then
encoded = name . bytes
else
if type ( name ) ~= "string" then
error ( "JSON object keys must be strings" , 2 )
end
if not validUtf8 ( name ) then
error ( "cannot encode invalid UTF-8 as JSON" , 0 )
end
encoded = core . encode ( name )
end
if not frame . first then
add ( "," )
end
frame . first = false
add ( encoded )
add ( ":" )
frame . value = true

return self
end

function writer : write ( value ) 
local marker = getmetatable ( value )
local encoded = ( marker == ENCODED_VALUE or marker == ENCODED_STRING ) and value . bytes
or json . encode ( value , nullValue )
prepare ( )
add ( encoded )

return self
end

function writer : null ( ) 
prepare ( )
add ( "null" )

return self
end

local function finish ( kind , name ) 
local frame = stack [ # stack ]
if closed or not frame or frame . kind ~= kind then
error ( name .. " requires an open " .. kind , 2 )
end
if frame . value then
error ( "the final object key has no value" , 2 )
end
stack [ # stack ] = nil
add ( kind == "array" and "]" or "}" )

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
if # parts > 0 then
out : put ( table . concat ( parts ) )
parts = { }
pending = 0
end
end

local aborted = false

function writer : abort ( ) 
aborted , closed = true , true
parts , stack = { } , { }
pending = 0
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
parts = { }
error ( "close() requires one complete root value" , 2 )
end
if # parts > 0 then
out : put ( table . concat ( parts ) )
parts = { }
pending = 0
end
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
}

local __nuppExportValue= checked ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.lunajson"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.lunajson"]=__nuppExports;return __nuppExports