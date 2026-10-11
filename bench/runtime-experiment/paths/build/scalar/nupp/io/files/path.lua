_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.io.files.path"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local browser;__nuppExports["browser"]=function(...) return browser(...) end;local descriptor;__nuppExports["descriptor"]=function(...) return descriptor(...) end;local encodeIdentity;__nuppExports["encodeIdentity"]=function(...) return encodeIdentity(...) end;local is;__nuppExports["is"]=function(...) return is(...) end;local native;__nuppExports["native"]=function(...) return native(...) end;


const utf8 = require ( "nupp.text.utf8" )
const paths = require ( "nupp.io.path" )











local descriptors = setmetatable ( { } , { __mode = "k" } )

local function validText ( value , what , level ) 
if type ( value ) ~= "string" or value == "" then
error ( "nupp: io.files " .. what .. " must be a non-empty string" , level )
end
if not utf8 . isValid ( value ) then
error ( "nupp: io.files " .. what .. " must be valid UTF-8" , level )
end

return value
end

local function reservedDevice ( value ) 
local base = ( value : match ( "^([^.]*)" ) or value ) : upper ( )
return base == "CON"
or base == "PRN"
or base == "AUX"
or base == "NUL"
or base : match ( "^COM[1-9]$" ) ~= nil
or base : match ( "^LPT[1-9]$" ) ~= nil


or base == "COM¹" or base == "COM²" or base == "COM³" or base == "LPT¹" or base == "LPT²" or base == "LPT³"
end

local function hex ( byte ) 
return ("%%%02X") : format ( byte )
end


encodeIdentity=function ( value , what ) 
local text = validText ( value , what or "application identity" , 3 )
local reserved = reservedDevice ( text )
local out = { }
for index = 1 , # text do
local byte = text : byte ( index )
local character = text : sub ( index , index )
local escape = byte < 32
or byte == 127
or character == "%"
or character == "/"
or character == "\\"
or character == "<"
or character == ">"
or character == ":"
or character == '"'
or character == "|"
or character == "?"
or character == "*"
or index == # text and ( character == "." or character == " " )
or index == 1 and ( text == "." or text == ".." or reserved )
out [ # out + 1 ] = escape and ( ("%%%02X") : format ( byte ) ) or character
end

return table . concat ( out )
end ;__nuppExports["encodeIdentity"]=encodeIdentity

local function component ( value , level ) 
local text = validText ( value , "ApplicationPath component" , level + 1 )
if text == "." or text == ".." then
error ( "nupp: io.files ApplicationPath component must not be '.' or '..'" , level )
end
if text : sub ( -1 ) == "." or text : sub ( -1 ) == " " then
error ( "nupp: io.files ApplicationPath component must not end in a dot or space" , level )
end
if text : find ( "[/\\]" , 1 ) or text : find ( "[<>:\"|?*]" ) or reservedDevice ( text ) then
error ( "nupp: io.files ApplicationPath component is not portable" , level )
end
for index = 1 , # text do
local byte = text : byte ( index )
if byte < 32 or byte == 127 then
error ( "nupp: io.files ApplicationPath component contains a control byte" , level )
end
end

return text
end

local newPath

local PathImpl = {} PathImpl.__index = PathImpl


function PathImpl:join(...) 
local descriptor = assert ( descriptors [ self ] )
local parts = { }
for index = 1 , # descriptor . parts do
parts [ index ] = descriptor . parts [ index ]
end
for index = 1 , select ( "#" , ... ) do
parts [ # parts + 1 ] = component ( select ( index , ... ) , 2 )
end

return newPath ( descriptor . provider , descriptor . root , parts )
end

function PathImpl:toString() 
return self . _text
end




newPath = function ( provider , root , parts ) 
local text
if provider == "native" then
local built = paths . newPath ( root )
for _ , part in ipairs ( parts ) do
built = built : join ( part )
end
text = built : toString ( )
else
text = "opfs:/" .. table . concat ( parts , "/" )
end
local value = _G.setmetatable({ _text =  text }, PathImpl)
descriptors [ value ] = { provider = provider , root = root , parts = parts , }

return value
end

;
( PathImpl ) . __tostring = function ( self ) 
return self : toString ( )
end



native=function ( root , organization , application ) 
return newPath ( "native" , root , {
encodeIdentity ( organization , "organization" ) ,
encodeIdentity ( application , "application" )
} )
end ;__nuppExports["native"]=native

browser=function ( kind , organization , application ) 
return newPath ( "browser" , kind , {
kind ,
encodeIdentity ( organization , "organization" ) ,
encodeIdentity ( application , "application" )
} )
end ;__nuppExports["browser"]=browser

is=function ( value ) 
return type ( value ) == "table" and descriptors [ value ] ~= nil
end ;__nuppExports["is"]=is

descriptor=function ( value ) 
return assert ( descriptors [ value ] , "nupp.io.files: path is not an ApplicationPath" )
end ;__nuppExports["descriptor"]=descriptor
 end);if not __nuppOk then package.loaded["nupp.io.files.path"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.files.path"]=__nuppExports;return __nuppExports