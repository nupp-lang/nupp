_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math"));local __nuppExports={};package.loaded["nupp.serde.internal.numbers"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local floating;__nuppExports["floating"]=function(...) return floating(...) end;local integer;__nuppExports["integer"]=function(...) return integer(...) end;

local core = require ( "nupp.serde.internal.value" )
local signedMax = { [ 8 ] = "127" , [ 16 ] = "32767" , [ 32 ] = "2147483647" , [ 64 ] = "9223372036854775807" }
local signedMin = { [ 8 ] = "128" , [ 16 ] = "32768" , [ 32 ] = "2147483648" , [ 64 ] = "9223372036854775808" }
local unsignedMax

= { [ 8 ] = "255" , [ 16 ] = "65535" , [ 32 ] = "4294967295" , [ 64 ] = "18446744073709551615" }

integer=function ( text , width , signed ) 
if not text : match ( "^%-?%d+$" ) then
error ( "expected an integer lexeme" , 2 )
end
local negative = text : sub ( 1 , 1 ) == "-"
local digits = negative and text : sub ( 2 ) or text
if # digits > 1 and digits : sub ( 1 , 1 ) == "0" then
error ( "integer has leading zeroes" , 2 )
end
if negative and not signed then
error ( "unsigned integer is negative" , 2 )
end
local limit = signed and ( negative and signedMin [ width ] or signedMax [ width ] ) or unsignedMax [ width ]
if limit == nil or # digits > # limit or # digits == # limit and digits > limit then
error ( "integer is out of range" , 2 )
end

return ( _G.setmetatable({ decimal =  text ,  width =  width ,  signed =  signed }, core.Integer) )
end ;__nuppExports["integer"]=integer

floating=function ( value , width , allowNonfinite ) 
if not allowNonfinite and ( value ~= value or value == math . huge or value == - math . huge ) then
error ( "non-finite JSON float" , 2 )
end
if width == 32 and math . abs ( value ) ~= math . huge and math . abs ( value ) > 3.4028234663852886e38 then
error ( "float32 is out of range" , 2 )
end
if width == 32 then
return nupp . math . f32 . narrow ( value )
else
return value
end
end ;__nuppExports["floating"]=floating
 end);if not __nuppOk then package.loaded["nupp.serde.internal.numbers"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.numbers"]=__nuppExports;return __nuppExports