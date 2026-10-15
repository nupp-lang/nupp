_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






















const _DYNAMIC_REQUIRES = "@requires-dynamically nothing"

local codec = { }

local SENDABLE = { [ "nil" ] = true , boolean = true , number = true , string = true , }
local MAX_DEPTH = 32













local function recordAddress ( metatable ) 
local namespace = _G . nupp and rawget ( _G . nupp , "__workerRecords" )
local address = type ( namespace ) == "table" and ( namespace ) [ metatable ] or nil

return type ( address ) == "string" and address or nil
end





function codec . unsendable ( value , path , depth , state ) 
local kind = type ( value )
if SENDABLE [ kind ] then
return nil
end

if kind ~= "table" then
return ("%s is a %s") : format ( path , kind )
end
local metatable = getmetatable ( value )
if metatable ~= nil then
local address = recordAddress ( metatable )
if address == nil then
return ("%s has a metatable") : format ( path )
end
local records = state . records
local prior = records ~= nil and records [ address ] or nil
if prior ~= nil and prior ~= metatable then
return ("%s has an ambiguous record metatable") : format ( path )
end
if prior == nil then
if records == nil then
records = { }
state . records = records
end
( records ) [ address ] = metatable
local addresses = state . addresses
if addresses == nil then
addresses = { }
state . addresses = addresses
end
( addresses ) [ # ( addresses ) + 1 ] = address
end
end
if depth >= 32 then
return ("%s nests deeper than %d tables") : format ( path , 32 )
end
if state . seen [ value ] then
return ("%s repeats a table already present in the message") : format ( path )
end
state . seen [ value ] = true
for key , item in next , value do
local keyKind = type ( key )
if not SENDABLE [ keyKind ] then
return ("%s has a %s key") : format ( path , keyKind )
end
if not SENDABLE [ type ( item ) ] then
local rejected = codec . unsendable ( item , ("%s[%s]") : format ( path , tostring ( key ) ) , depth + 1 , state )
if rejected ~= nil then
return rejected
end
end
end

return nil
end



function codec . validate ( captures , arguments ) 
local transfer = { seen = { } , records = nil , addresses = nil }
local rejectedCaptures = codec . unsendable ( captures . values , "captures" , 0 , transfer )
if rejectedCaptures ~= nil then
error ( "nupp: cannot copy task captures: " .. rejectedCaptures , 3 )
end
local rejected = codec . unsendable ( arguments . values , "arguments" , 0 , transfer )
if rejected ~= nil then
error ( "nupp: cannot copy task arguments: " .. rejected , 3 )
end

return transfer
end



local function resolveRecord ( address ) 
local moduleName , memberPath = address : match ( "^(.-)%z(.+)$" )
if moduleName == nil or moduleName == "" or memberPath == nil then
error ( "nupp: a worker value names an invalid record" , 0 )
end
for _ , path in ipairs ( { moduleName , memberPath } ) do
if path : sub ( 1 , 1 ) == "." or path : sub ( -1 ) == "." or path : find ( ".." , 1 , true ) then
error ( "nupp: a worker value names an invalid record" , 0 )
end
for member in path : gmatch ( "[^.]+" ) do
if not member : match ( "^[%a_][%w_]*$" ) then
error ( "nupp: a worker value names an invalid record" , 0 )
end
end
end
local value = require ( moduleName )
for member in ( memberPath ) : gmatch ( "[^.]+" ) do
if type ( value ) ~= "table" then
error ( "nupp: a worker value names an invalid record" , 0 )
end
value = ( value ) [ member ]
end
local namespace = _G . nupp and rawget ( _G . nupp , "__workerRecords" )
if type ( value ) ~= "table" or type ( namespace ) ~= "table" or ( namespace ) [ value ] ~= address then
error ( "nupp: a worker value names an unknown record" , 0 )
end

return value
end



local resolvedRecords = setmetatable ( { } , { __mode = "v" } )

local function resolveRecordCached ( address ) 
local metatable = resolvedRecords [ address ]
if metatable == nil then
metatable = resolveRecord ( address )
resolvedRecords [ address ] = metatable
end

return metatable
end




local NIL = "N"
local FALSE = "F"
local TRUE = "T"
local NUMBER = "D"
local POSITIVE_INFINITY = "I"
local NEGATIVE_INFINITY = "i"
local NOT_A_NUMBER = "X"
local STRING = "S"
local TABLE = "t"
local RECORD = "r"

local function writeString ( out , value ) 
out [ # out + 1 ] = ("%d:") : format ( # value )
out [ # out + 1 ] = value
end

local function writeValue ( out , value ) 
local kind = type ( value )
if value == nil then
out [ # out + 1 ] = "N"
elseif kind == "boolean" then
out [ # out + 1 ] = value == true and "T" or "F"
elseif kind == "number" then
local number = value
if number ~= number then
out [ # out + 1 ] = "X"
elseif number == math . huge then
out [ # out + 1 ] = "I"
elseif number == - math . huge then
out [ # out + 1 ] = "i"
else
out [ # out + 1 ] = "D"
writeString ( out , ("%.17g") : format ( number ) )
end
elseif kind == "string" then
out [ # out + 1 ] = "S"
writeString ( out , value )
elseif kind == "table" then
local metatable = getmetatable ( value )
local address = metatable ~= nil and recordAddress ( metatable ) or nil
local entries = { }
local count = 0
for key , item in next , value do
count = count + 1
entries [ # entries + 1 ] = key
entries [ # entries + 1 ] = item
end
if address ~= nil then
out [ # out + 1 ] = "r"
writeString ( out , address )
else
out [ # out + 1 ] = "t"
end
out [ # out + 1 ] = ("%d:") : format ( count )
for index = 1 , # entries do
writeValue ( out , entries [ index ] )
end
else
error ( "nupp: a worker value of type " .. kind .. " cannot be copied" , 0 )
end
end


function codec . encode ( packed ) 
local out = { ("%d:") : format ( packed . count ) }
for index = 1 , packed . count do
writeValue ( out , packed . values [ index ] )
end

return table . concat ( out )
end



local function readLength ( bytes , cursor ) 
local digits , following = bytes : match ( "^(%d+):()" , cursor . at )
if digits == nil then
error ( "nupp: a worker message is malformed" , 0 )
end
local length = tonumber ( digits )
if length == nil or length > # bytes or ( # digits > 1 and digits : sub ( 1 , 1 ) == "0" ) then
error ( "nupp: a worker message is malformed" , 0 )
end
cursor . at = following

return length
end

local function readString ( bytes , cursor ) 
local length = readLength ( bytes , cursor )
local finish = cursor . at + length
if finish > # bytes + 1 then
error ( "nupp: a worker message is malformed" , 0 )
end
local value = bytes : sub ( cursor . at , finish - 1 )
cursor . at = finish

return value
end

local function readValue ( bytes , cursor , depth ) 
if depth > 32 then
error ( "nupp: a worker message nests too deeply" , 0 )
end
local tag = bytes : sub ( cursor . at , cursor . at )
cursor . at = cursor . at + 1
if tag == "N" then
return nil
elseif tag == "T" then
return true
elseif tag == "F" then
return false
elseif tag == "I" then
return math . huge
elseif tag == "i" then
return - math . huge
elseif tag == "X" then
return 0 / 0
elseif tag == "D" then
local text = readString ( bytes , cursor )
local number = tonumber ( text )
if number == nil
or number ~= number
or number == math . huge
or number == - math . huge
or ("%.17g") : format ( number ) ~= text
then
error ( "nupp: a worker message is malformed" , 0 )
end

return number
elseif tag == "S" then
return readString ( bytes , cursor )
elseif tag == "t" or tag == "r" then
if depth >= 32 then
error ( "nupp: a worker message nests too deeply" , 0 )
end
local address = nil
if tag == "r" then
address = readString ( bytes , cursor )
end
local count = readLength ( bytes , cursor )
local value = { }
for _ = 1 , count do
local key = readValue ( bytes , cursor , depth + 1 )
local item = readValue ( bytes , cursor , depth + 1 )
local keyKind = type ( key )
if key == nil
or ( keyKind ~= "boolean" and keyKind ~= "number" and keyKind ~= "string" )
or key ~= key
or item == nil
or value [ key ] ~= nil
then
error ( "nupp: a worker message is malformed" , 0 )
end
value [ key ] = item
end
if address ~= nil then
setmetatable ( value , resolveRecordCached ( address ) )
end

return value
end
error ( "nupp: a worker message is malformed" , 0 )
end



function codec . decode ( bytes ) 
local cursor = { at = 1 }
local count = readLength ( bytes , cursor )
local values = { }
for index = 1 , count do
values [ index ] = readValue ( bytes , cursor , 0 )
end
if cursor . at ~= # bytes + 1 then
error ( "nupp: a worker message is malformed" , 0 )
end

return { values = values , count = count }
end

local __nuppExportValue= codec ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.workercodec"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.workercodec"]=__nuppExports;return __nuppExports