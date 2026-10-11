_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local ffi = require ( "ffi" )
local span = require ( "nupp.mem.span" )
local utf8 = require ( "nupp.text.utf8" )

local values = {


MAX_STRING_BYTES= 65536 ,


MAX_OUTBOUND_BYTES= 67108864 ,


MAX_INBOUND_BYTES= 8388608 ,


CHUNK_BYTES= 1048576 , }

local sharedRef = rawget ( span , "__sharedRef" )
local foreignByteSpan = rawget ( span , "__foreignByteSpan" )
local byteTypes = { }

local function isByteType ( pointer ) 
local ctype = ffi . typeof ( pointer )
local id = tonumber ( ctype )
local known = byteTypes [ id ]
if known ~= nil then
return known
end
local name = tostring ( ctype ) : gsub ( "^ctype<" , "" ) : gsub ( ">$" , "" ) : gsub ( "const " , "" )
local accepted = name : match ( "^unsigned char[ %*%[]" ) ~= nil
or name : match ( "^char[ %*%[]" ) ~= nil
or name : match ( "^signed char[ %*%[]" ) ~= nil
byteTypes [ id ] = accepted

return accepted
end

local function refuse ( kind , position , problem ) 
error ( string . format ( "nupp: host %s argument %d %s" , kind , position , problem ) , 0 )
end





function values . classify ( kind , position , value ) 
local kindOf = type ( value )
if kindOf == "nil" then
return "nil" , nil , nil
elseif kindOf == "boolean" then
return "boolean" , value , nil
elseif kindOf == "number" then
if value ~= value or value == math . huge or value == - math . huge then
refuse ( kind , position , "is not a finite number" )
end
return "number" , value , nil
elseif kindOf == "string" then
if # value > values . MAX_STRING_BYTES then
refuse ( kind , position , "is a string longer than 64 KiB; send it as bytes" )
end
if not utf8 . isValid ( value ) then
refuse ( kind , position , "is a string that is not UTF-8; send binary data as bytes" )
end
return "string" , value , nil
elseif kindOf == "table" then
local pointer , count = sharedRef ( value )
if pointer ~= nil then
if not isByteType ( pointer ) then
refuse ( kind , position , "is a span of non-byte elements" )
end
if count > values . MAX_OUTBOUND_BYTES then
refuse ( kind , position , "is a byte span larger than 64 MiB" )
end
return "bytes" , pointer , count
end
end
refuse ( kind , position , "is a " .. kindOf .. ", which cannot cross to the host" )

return "nil" , nil , nil
end




function values . byteSpan ( anchor , pointer , count ) 
return foreignByteSpan ( anchor , pointer , 0 , count )
end

local __nuppExportValue= values ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.host.internal.values"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.host.internal.values"]=__nuppExports;return __nuppExports