_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math"));local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















































const utf8 = require ( "nupp.text.utf8" )






local valuebuilder = { }

local function readU32 ( bytes , offset ) 
local first = bytes : byte ( offset + 1 )
local second = bytes : byte ( offset + 2 )
local third = bytes : byte ( offset + 3 )
local fourth = bytes : byte ( offset + 4 )
if first == nil or second == nil or third == nil or fourth == nil then
error ( "value stream word is out of bounds" , 0 )
end

return first + second * 256 + third * 65536 + fourth * 16777216
end

local function sourceSlice ( source , first , length , what ) 
local text = source
if first < 0 or length < 0 or first > # text or length > # text - first then
error ( "value stream " .. what .. " range is out of bounds" , 0 )
end

return text : sub ( first + 1 , first + length )
end
















local function decodeString ( source , first , length , escaped ) 
local bytes = sourceSlice ( source , first , length , "string" )
if not escaped then
return bytes
end

local parts = { }
local start = 1
local position = 1
local simple = {
[ 34 ] = "\"" ,
[ 92 ] = "\\" ,
[ 47 ] = "/" ,
[ 98 ] = "\8" ,
[ 102 ] = "\12" ,
[ 110 ] = "\n" ,
[ 114 ] = "\13" ,
[ 116 ] = "\9" ,
}
while position <= # bytes do
if bytes : byte ( position ) ~= 92 then
position = position + 1
else
parts [ # parts + 1 ] = bytes : sub ( start , position - 1 )
position = position + 1
local escapedByte = bytes : byte ( position )
local replacement = escapedByte and simple [ escapedByte ] or nil
if replacement ~= nil then
parts [ # parts + 1 ] = replacement
position = position + 1
elseif escapedByte == 117 then



local hex = bytes : sub ( position + 1 , position + 4 )
if # hex < 4 or hex : find ( "%X" ) ~= nil then
error ( "invalid value stream Unicode escape" , 0 )
end
local codepoint = tonumber ( hex , 16 )
if codepoint == nil then
error ( "invalid value stream Unicode escape" , 0 )
end
position = position + 5
if codepoint >= 55296 and codepoint <= 56319 then
if bytes : byte ( position ) ~= 92 or bytes : byte ( position + 1 ) ~= 117 then
error ( "unmatched value stream high surrogate" , 0 )
end
local lowHex = bytes : sub ( position + 2 , position + 5 )
if # lowHex < 4 or lowHex : find ( "%X" ) ~= nil then
error ( "invalid value stream low surrogate" , 0 )
end
local low = tonumber ( lowHex , 16 )
if low == nil or low < 56320 or low > 57343 then
error ( "invalid value stream low surrogate" , 0 )
end
position = position + 6
codepoint = 65536 + ( codepoint - 55296 ) * 1024 + low - 56320
elseif codepoint >= 56320 and codepoint <= 57343 then
error ( "unmatched value stream low surrogate" , 0 )
end
parts [ # parts + 1 ] = utf8 . encode ( codepoint )
else
error ( "unknown value stream escape" , 0 )
end
start = position
end
end
parts [ # parts + 1 ] = bytes : sub ( start )

return table . concat ( parts )
end










































function valuebuilder . new ( nullValue ) 
return { nullValue = nullValue , stack = { } , result = nil , hasResult = false }
end



















function valuebuilder . newSized (
nullValue ,
maxDepth ,
stringCapacity ,
arrayMarker ,
objectMarker
) 
return {
nullValue = nullValue ,
stack = { } ,
result = nil ,
hasResult = false ,
maxDepth = maxDepth ,
stringCapacity = stringCapacity ,
arrayMarker = arrayMarker ,
objectMarker = objectMarker
}
end








function valuebuilder . integer64 ( builder , magnitude , negative ) 
error ( "integer64 exists only inside an @aot function" , 2 )
end





function valuebuilder . decimal64 (
builder ,
source ,
start ,
length ,
magnitude ,
exponent ,
negative ,
exact
) 
error ( "decimal64 exists only inside an @aot function" , 2 )
end






local function put ( builder , value ) 
local stack = builder . stack
local frame = stack [ # stack ]
if frame == nil then
if builder . hasResult then
error ( "value stream has more than one root" , 2 )
end
builder . result = value
builder . hasResult = true
elseif frame . kind == 5 then


frame . count = frame . count + 1
if value == nil then
return
end
frame . value [ frame . next ] = value
frame . next = frame . next + 1
else
if frame . key == nil then
error ( "value stream object needs a key" , 2 )
end
frame . count = frame . count + 1
if value == nil then


frame . dropped = frame . dropped or { }
frame . dropped [ frame . key ] = true
frame . key = nil
return
end
frame . value [ frame . key ] = value
frame . key = nil
end
end













function valuebuilder . length ( bytes ) 
return (__nuppBitTobit( # bytes )%4294967296)
end
























function valuebuilder . bytes ( bytes ) 




if type ( bytes ) ~= "string" then
error ( "value stream bytes need a rooted string outside an AOT entry" , 2 )
end

return require ( "nupp.mem.span" ) . fromString ( bytes )
end










function valuebuilder . byte ( bytes , offset ) 
local value = bytes : byte ( (__nuppBitTobit(( offset )+( 1 ))%4294967296) )
if value == nil then
error ( "value stream byte is out of bounds" , 2 )
end

return (__nuppBitTobit( value )%4294967296)
end












function valuebuilder . byteAt ( bytes , offset ) 
return valuebuilder . byte ( bytes , offset )
end










function valuebuilder . word ( bytes , index ) 
local offset = nupp.math.u32.mul( index , 4 )
if offset > # bytes - 4 then
error ( "value stream word is out of bounds" , 2 )
end

return (__nuppBitTobit( readU32 ( bytes , offset ) )%4294967296)
end





local function zeroed ( capacity ) 
local values = { }
for index = 1 , capacity do
values [ index ] = 0
end

return values
end






















function valuebuilder . newFixedWordScratch ( capacity ) 




return { capacity = capacity , length = capacity , words = zeroed ( capacity ) , }
end













function valuebuilder . newWordScratch ( capacity ) 
return { capacity = capacity , length = 0 , words = { } }
end









function valuebuilder . scratchWord ( scratch , index ) 
if index >= scratch . length then
error ( "value stream scratch read is out of bounds" , 2 )
end
local value = tonumber ( scratch . words [ (__nuppBitTobit(( index )+( 1 ))%4294967296) ] )
if value == nil then
error ( "value stream scratch word is invalid" , 2 )
end

return (__nuppBitTobit( value )%4294967296)
end




function valuebuilder . scratchLength ( scratch ) 
return (__nuppBitTobit( scratch . length )%4294967296)
end











function valuebuilder . setScratchWord ( scratch , index , value ) 
if index > scratch . length or index >= scratch . capacity then
error ( "value stream scratch write is out of bounds" , 2 )
end
if index == scratch . length then
scratch . length = scratch . length + 1
end
scratch . words [ (__nuppBitTobit(( index )+( 1 ))%4294967296) ] = value
end





























function valuebuilder . newFixedByteScratch ( capacity ) 




return { capacity = capacity , length = capacity , bytes = zeroed ( capacity ) , fixed = true , }
end















function valuebuilder . newByteScratch ( capacity ) 
return { capacity = capacity , length = 0 , bytes = { } }
end






function valuebuilder . scratchByte ( scratch , index ) 
if index >= scratch . length then
error ( "value stream byte scratch read is out of bounds" , 2 )
end
return (__nuppBitTobit( tonumber ( scratch . bytes [ (__nuppBitTobit(( index )+( 1 ))%4294967296) ] ) )%4294967296)
end









function valuebuilder . setScratchByte ( scratch , index , value ) 
if index > scratch . length or index >= scratch . capacity or value > 255 then
error ( "value stream byte scratch write is out of bounds" , 2 )
end
if index == scratch . length then
scratch . length = scratch . length + 1
end
scratch . bytes [ (__nuppBitTobit(( index )+( 1 ))%4294967296) ] = value
end





















function valuebuilder . setScratchBytes4 ( scratch , index , value ) 
if index > scratch . length or (__nuppBitTobit(( index )+( 4 ))%4294967296) > scratch . capacity then
error ( "value stream byte scratch write is out of bounds" , 2 )
end
if index < scratch . length and (__nuppBitTobit(( index )+( 4 ))%4294967296) > scratch . length then
error ( "value stream byte scratch write straddles the length" , 2 )
end
if index == scratch . length then
scratch . length = scratch . length + 4
end
scratch . bytes [ (__nuppBitTobit(( index )+( 1 ))%4294967296) ] = value % 256
scratch . bytes [ (__nuppBitTobit(( index )+( 2 ))%4294967296) ] = math . floor ( value / 256 ) % 256
scratch . bytes [ (__nuppBitTobit(( index )+( 3 ))%4294967296) ] = math . floor ( value / 65536 ) % 256
scratch . bytes [ (__nuppBitTobit(( index )+( 4 ))%4294967296) ] = math . floor ( value / 16777216 ) % 256
end









function valuebuilder . resetByteScratch ( scratch ) 



if scratch . fixed then
error ( "value stream fixed byte scratch cannot be reset" , 2 )
end
scratch . length = 0
end

local function scratchString ( scratch , start , length ) 
local parts = { }


for offset = 1 , length do
parts [ offset ] = string . char ( tonumber ( scratch . bytes [ start + offset ] ) )
end

return table . concat ( parts )
end













function valuebuilder . stringScratch ( builder , scratch , start , length ) 
if start > scratch . length or length > scratch . length - start then
error ( "value stream byte scratch range is out of bounds" , 2 )
end
put ( builder , scratchString ( scratch , start , length ) )
end











function valuebuilder . keyScratch ( builder , scratch , start , length ) 
local frame = builder . stack [ # builder . stack ]
if frame == nil or frame . kind ~= 6 or frame . key ~= nil then
error ( "value stream key is outside an object" , 2 )
end
if start > scratch . length or length > scratch . length - start then
error ( "value stream byte scratch range is out of bounds" , 2 )
end
frame . key = scratchString ( scratch , start , length )
end








function valuebuilder . openArray ( builder , capacity ) 
local stack = builder . stack
stack [ # stack + 1 ] = { kind = 5 , value = { } , next = 1 , count = 0 }
end









function valuebuilder . openObject ( builder , capacity ) 
local stack = builder . stack
stack [ # stack + 1 ] = { kind = 6 , value = { } , count = 0 }
end








function valuebuilder . depth ( builder ) 
return (__nuppBitTobit( # builder . stack )%4294967296)
end









function valuebuilder . kind ( builder ) 
local frame = builder . stack [ # builder . stack ]
if frame == nil then
error ( "value stream has no current container" , 2 )
end

return (__nuppBitTobit( frame . kind )%4294967296)
end









function valuebuilder . count ( builder ) 
local frame = builder . stack [ # builder . stack ]
if frame == nil then
error ( "value stream has no current container" , 2 )
end

return (__nuppBitTobit( frame . count )%4294967296)
end












function valuebuilder . state ( builder ) 
local frame = builder . stack [ # builder . stack ]
if frame == nil then
return 0
end
local state = frame . kind
if frame . count > 0 then
state = state + 256
end

return (__nuppBitTobit( state )%4294967296)
end

















function valuebuilder . key ( builder , source , start , length , escaped ) 
local frame = builder . stack [ # builder . stack ]
if frame == nil or frame . kind ~= 6 or frame . key ~= nil then
error ( "value stream key is outside an object" , 2 )
end
local name = decodeString ( source , start , length , escaped )


if frame . value [ name ] ~= nil or frame . dropped ~= nil and frame . dropped [ name ] then
error ( "invalid JSON at byte " .. tostring ( start ) .. ": duplicate member name" , 0 )
end
frame . key = name
end













function valuebuilder . string ( builder , source , start , length , escaped ) 
put ( builder , decodeString ( source , start , length , escaped ) )
end









function valuebuilder . number ( builder , value ) 
put ( builder , value )
end













function valuebuilder . numberSlice ( builder , source , start , length ) 
local value = tonumber ( sourceSlice ( source , start , length , "number" ) )
if value == nil then
error ( "value stream number is invalid" , 2 )
end
put ( builder , value )
end














function valuebuilder . integerSlice ( builder , source , start , length ) 
local bytes = sourceSlice ( source , start , length , "integer" )
if bytes : match ( "^%-?%d+$" ) == nil then
error ( "value stream integer is invalid" , 2 )
end
local value = tonumber ( bytes )
if value == nil then
error ( "value stream integer is invalid" , 2 )
end
put ( builder , value )
end





function valuebuilder . boolean ( builder , value ) 
put ( builder , value )
end





function valuebuilder . null ( builder ) 
put ( builder , builder . nullValue )
end










function valuebuilder . close ( builder ) 
local stack = builder . stack
local frame = stack [ # stack ]
if frame == nil then
error ( "value stream close has no container" , 2 )
end
if frame . kind == 6 and frame . key ~= nil then
error ( "value stream object has an unmatched key" , 2 )
end
local marker = frame . kind == 5 and builder . arrayMarker or builder . objectMarker
if marker ~= nil then
setmetatable ( frame . value , marker )
end
stack [ # stack ] = nil
put ( builder , frame . value )
end













function valuebuilder . finish ( builder ) 
if # builder . stack ~= 0 then
error ( "value stream has an unclosed container" , 2 )
end
if not builder . hasResult then
error ( "value stream has no root" , 2 )
end

return builder . result
end

local __nuppExportValue= valuebuilder ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.valuebuilder"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.valuebuilder"]=__nuppExports;return __nuppExports