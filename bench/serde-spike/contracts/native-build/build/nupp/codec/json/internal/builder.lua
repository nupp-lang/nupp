_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











const valuebuilder = require ( "nupp.codec.valuebuilder" )

local stream = { }








function stream . newPull (
nullValue ,
maxDepth ,
stringCapacity ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
error ( "newPull exists only inside an @aot function" , 2 )
end







function stream . newSerde (
nullValue ,
maxDepth ,
stringCapacity ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
error ( "newSerde exists only inside an @aot function" , 2 )
end




function stream . stringEscapes (
builder ,
source ,
start ,
length ,
escapes ,
escapeStart ,
escapeCount
) 
error ( "stringEscapes exists only inside an @aot function" , 2 )
end




function stream . keyEscapes (
builder ,
source ,
start ,
length ,
escapes ,
escapeStart ,
escapeCount
) 
error ( "keyEscapes exists only inside an @aot function" , 2 )
end

















function stream . numberToken ( builder , source , start , limit ) 
local text = source
local at = start
if limit > # text or limit >= 2147483648 or start >= limit then
return (__nuppBitTobit( (__nuppBitTobit(( start )+( 1 ))%4294967296) )%4294967296)
end





local function digits ( ) 
local first = at
while at < limit and text : byte ( at + 1 ) >= 48 and text : byte ( at + 1 ) <= 57 do
at = at + 1
end

return at - first
end

if at < limit and text : byte ( at + 1 ) == 45 then
at = at + 1
end
if at >= limit then
return (__nuppBitTobit( at + 1 )%4294967296)
end
local lead = text : byte ( at + 1 )
if lead == 48 then
at = at + 1
if at < limit and text : byte ( at + 1 ) >= 48 and text : byte ( at + 1 ) <= 57 then
return (__nuppBitTobit( at + 1 )%4294967296)
end
elseif lead >= 49 and lead <= 57 then
digits ( )
else
return (__nuppBitTobit( at + 1 )%4294967296)
end
if at < limit and text : byte ( at + 1 ) == 46 then
at = at + 1
if digits ( ) == 0 then
return (__nuppBitTobit( at + 1 )%4294967296)
end
end
if at < limit and ( text : byte ( at + 1 ) == 101 or text : byte ( at + 1 ) == 69 ) then
at = at + 1
if at < limit and ( text : byte ( at + 1 ) == 43 or text : byte ( at + 1 ) == 45 ) then
at = at + 1
end
if digits ( ) == 0 then
return (__nuppBitTobit( at + 1 )%4294967296)
end
end

local value = tonumber ( text : sub ( (__nuppBitTobit(( start )+( 1 ))%4294967296) , at ) )
if value == nil then
return (__nuppBitTobit( at + 1 )%4294967296)
end


if value == math . huge or value == - math . huge then
return (__nuppBitTobit( (__nuppBitTobit(( start )+( 1 ))%4294967296) )%4294967296)
end
valuebuilder . number ( builder , value )

return (__nuppBitTobit( at + 2147483648 )%4294967296)
end



function stream . scratchEscapeWord ( scratch , index ) 
error ( "scratchEscapeWord exists only inside an @aot function" , 2 )
end



function stream . scratchEscapeLength ( scratch ) 
error ( "scratchEscapeLength exists only inside an @aot function" , 2 )
end

local __nuppExportValue= stream ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.json.internal.builder"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json.internal.builder"]=__nuppExports;return __nuppExports