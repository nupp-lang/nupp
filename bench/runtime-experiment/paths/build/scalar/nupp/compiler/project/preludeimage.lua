_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















local T = require ( "nupp.compiler.types" )
local bundled = require ( "nupp.compiler.bundled" )
local image = { schema = 1 , }

local ROOT_NAMES = {
"annotationsByName" ,
"featureEffects" ,
"globalTypeDefs" ,
"globalTypes" ,
"globals" ,
"preludeComptimeFunctions" ,
"stringLib" ,
}

function image . new ( ) 
local data = assert ( bundled . source ( "/preludeimage.bin" ) , "portable prelude image is absent" )

assert ( data : sub ( 1 , 15 ) == "NUPP-PRELUDE-3\n" , "portable prelude image has an unsupported format" )
local cursor = 16

local function readInteger ( ) 
local result = 0
local scale = 1
for _ = 1 , 8 do
local byte = assert ( data : byte ( cursor ) , "portable prelude image is truncated inside an integer" )
cursor = cursor + 1
result = result + ( byte % 128 ) * scale
assert ( result <= 9007199254740991 , "portable prelude image integer is too large" )
if byte < 128 then
return result
end
scale = scale * 128
end
error ( "portable prelude image integer is too large" , 0 )
end

local function stringValue ( ) 
local length = readInteger ( )
local result = data : sub ( cursor , cursor + length - 1 )
assert ( # result == length , "portable prelude image is truncated inside a string" )
cursor = cursor + length

return result
end

local tableCount = readInteger ( )
local dictionaryCount = readInteger ( )
assert ( tableCount <= # data and dictionaryCount <= # data , "portable prelude image has invalid counts" )
local dictionary = { }
for index = 1 , dictionaryCount do
dictionary [ index ] = stringValue ( )
end
local tables = { }

local function value ( ) 
local tag = data : sub ( cursor , cursor )
cursor = cursor + 1
if tag == "z" then
return nil
elseif tag == "f" then
return false
elseif tag == "t" then
return true
elseif tag == "r" then
return assert ( tables [ readInteger ( ) ] , "portable prelude image has an invalid table reference" )
elseif tag == "d" then
return assert ( dictionary [ readInteger ( ) ] , "portable prelude image has an invalid string reference" )
elseif tag == "i" then
return readInteger ( )
elseif tag == "j" then
return - readInteger ( )
elseif tag == "n" then
local encoded = stringValue ( )
if encoded == "nan" then
return 0 / 0
elseif encoded == "inf" then
return math . huge
elseif encoded == "-inf" then
return - math . huge
end

return assert ( tonumber ( encoded ) , "portable prelude image has an invalid number" )
elseif tag == "s" then
return stringValue ( )
end
error ( "portable prelude image has an unknown value tag" , 0 )
end




local internedAs = { }
local internedKeys = { }
local arenas = T . identity ( ) . arenas
local internedCount = readInteger ( )
assert ( internedCount <= tableCount , "portable prelude image has an invalid interned count" )
for _ = 1 , internedCount do
local id = readInteger ( )
assert (
id >= 1 and id <= tableCount and internedAs [ id ] == nil ,
"portable prelude image has an invalid interned id"
)
local bucket = value ( )
local key = value ( )
assert ( type ( bucket ) == "string" and type ( key ) == "string" , "portable prelude image has an invalid interned key" )
assert ( arenas [ bucket ] ~= nil , "portable prelude image has an unknown interned arena" )
local keys = internedKeys [ bucket ]
if keys == nil then
keys = { }
internedKeys [ bucket ] = keys
end
assert ( not keys [ key ] , "portable prelude image has a duplicate interned key" )
keys [ key ] = true
internedAs [ id ] = { bucket , key }
end
local identity = { serial = readInteger ( ) , capability = readInteger ( ) , nominal = readInteger ( ) , }






local mine = { }
local adopting = { }
for index = 1 , tableCount do
local where = internedAs [ index ]
local live = where ~= nil and T . interned ( where [ 1 ] , where [ 2 ] ) or nil
if where ~= nil and live == nil then
adopting [ # adopting + 1 ] = index
end
tables [ index ] = live or { }
mine [ index ] = live == nil
end

local metatables = { }
for index = 1 , tableCount do
local memberCount = readInteger ( )
local target = mine [ index ] and tables [ index ] or nil
for _ = 1 , memberCount do
local key = value ( )
local member = value ( )
if target ~= nil then
target [ key ] = member
end
end
local metatableIndex = readInteger ( )
assert ( metatableIndex <= tableCount , "portable prelude image has an invalid metatable" )
metatables [ index ] = metatableIndex
end
for index , metatableIndex in ipairs ( metatables ) do
if metatableIndex ~= 0 and mine [ index ] then
setmetatable ( tables [ index ] , tables [ metatableIndex ] )
end
end

local roots = { }
for _ , name in ipairs ( ROOT_NAMES ) do
roots [ name ] = value ( )
end
roots . preludeRuntime = value ( )
assert ( cursor == # data + 1 , "portable prelude image has trailing bytes" )



for _ , index in ipairs ( adopting ) do
local where = assert ( internedAs [ index ] )
T . adopt ( where [ 1 ] , where [ 2 ] , tables [ index ] )
end
T . resumeIdentity ( identity )

return roots
end

local __nuppExportValue= image ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.preludeimage"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.preludeimage"]=__nuppExports;return __nuppExports