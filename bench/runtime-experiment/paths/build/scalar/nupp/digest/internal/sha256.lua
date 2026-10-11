_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitLshift=bit.lshift;local __nuppBitRshift=bit.rshift;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math"));local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

































local valuebuilder = require ( "nupp.codec.valuebuilder" )

local digest = { }





local function u32 ( value ) 
return (__nuppBitTobit( value )%4294967296)
end

local function add ( a , b ) 
return __nuppBitTobit(( a )+( b ))
end






local function signed ( value ) 
return __nuppBitTobit( value )
end

local function unsigned ( value ) 
return (__nuppBitTobit( value )%4294967296)
end






local function rotateRight ( value , right , left ) 
return ( value >> right ) | ( value << left )
end


local function smallSigmaZero ( word ) 
return ( ( word >> 7 ) | ( word << 25 ) ) ~ ( ( word >> 18 ) | ( word << 14 ) ) ~ ( word >> 3 )
end

local function smallSigmaOne ( word ) 
return ( ( word >> 17 ) | ( word << 15 ) ) ~ ( ( word >> 19 ) | ( word << 13 ) ) ~ ( word >> 10 )
end

local function bigSigmaZero ( a ) 
return ( ( a >> 2 ) | ( a << 30 ) ) ~ ( ( a >> 13 ) | ( a << 19 ) ) ~ ( ( a >> 22 ) | ( a << 10 ) )
end

local function bigSigmaOne ( e ) 
return ( ( e >> 6 ) | ( e << 26 ) ) ~ ( ( e >> 11 ) | ( e << 21 ) ) ~ ( ( e >> 25 ) | ( e << 7 ) )
end

local function choose ( e , f , g ) 
return ( e & f ) ~ ( ( ~ e ) & g )
end

local function majority ( a , b , c ) 
return ( a & b ) ~ ( a & c ) ~ ( b & c )
end




local function hexDigit ( nibble ) 
return (__nuppBitTobit((
(__nuppBitTobit(( nibble )+( 48 ))%4294967296) )+(
nupp . math . u32 . mul ( (__nuppBitRshift( (__nuppBitTobit(( nibble )+( 6 ))%4294967296) ,__nuppBitBand( 4 ,31))%4294967296) , 39 ) ))%4294967296)

end





local function bigEndianWord ( word ) 
return unsigned (
( ( __nuppBitTobit( word ) ) << 24 )
| ( ( ( __nuppBitTobit( word ) ) & 65280 ) << 8 )
| ( ( ( __nuppBitTobit( word ) ) >> 8 ) & 65280 )
| ( ( ( __nuppBitTobit( word ) ) >> 24 ) & 255 )
)
end





















const ROUND_CONSTANTS = "ò/äBëD7qœ˚¿µ•€µÈ[¬V9Ò\17ÒY§Ç?í’^\28´ò™\7ÿ\1[É\18æÖ1$√}\12Ut]ær˛±ﬁÄß\6‹õtÒõ¡¡iõ‰ÜGæÔ∆ù¡\15Ã°\12$o,È-™ÑtJ‹©∞\\⁄à˘vRQ>òm∆1®»'\3∞«\127YøÛ\11‡∆Gëß’Qc \6g))\20Ö\n∑'8!\27.¸m,M\19\0138STs\neª\njv.…¬ÅÖ,rí°Ëø¢Kf\26®pãK¬£Ql«\25Ëí—$\6ô÷Ö5\14Ùp†j\16\22¡§\25\8l7\30LwH'µº∞4≥\12\0289J™ÿNO ú[Ûo.hÓÇètoc•x\20x»Ñ\8\2«å˙ˇæêÎlP§˜£˘æÚxq∆"




const NEVER_NULL = { }
















local function digestHex ( source , nullValue ) 
local builder = valuebuilder . newSized ( nullValue , 2 , 64 )
local scratch = valuebuilder . newFixedByteScratch ( 64 )
local schedule = valuebuilder . newFixedWordScratch ( 64 )





local tail = valuebuilder . newFixedByteScratch ( 128 )

local length = valuebuilder . length ( source )
local rest = (__nuppBitBand( length , 63 )%4294967296)
local whole = (__nuppBitTobit(( length )-( rest ))%4294967296)

local carrying = 0
while carrying < rest do
valuebuilder . setScratchByte ( tail , carrying , valuebuilder . byte ( source , (__nuppBitTobit(( whole )+( carrying ))%4294967296) ) )
carrying = (__nuppBitTobit(( carrying )+( 1 ))%4294967296)
end






valuebuilder . setScratchByte ( tail , rest , 128 )
local upTo = 56
if rest >= 56 then
upTo = 120
end




local high = (__nuppBitRshift( length ,__nuppBitBand( 29 ,31))%4294967296)
local low = (__nuppBitLshift( length ,__nuppBitBand( 3 ,31))%4294967296)
local counting = 0
while counting < 4 do
local shift = (__nuppBitTobit(( 24 )-( (__nuppBitLshift( counting ,__nuppBitBand( 3 ,31))%4294967296) ))%4294967296)
valuebuilder . setScratchByte (
tail ,
(__nuppBitTobit(( upTo )+( counting ))%4294967296) ,
(__nuppBitBand( (__nuppBitRshift( high ,__nuppBitBand( shift ,31))%4294967296) , 255 )%4294967296)
)
valuebuilder . setScratchByte (
tail ,
(__nuppBitTobit(( (__nuppBitTobit(( upTo )+( 4 ))%4294967296) )+( counting ))%4294967296) ,
(__nuppBitBand( (__nuppBitRshift( low ,__nuppBitBand( shift ,31))%4294967296) , 255 )%4294967296)
)
counting = (__nuppBitTobit(( counting )+( 1 ))%4294967296)
end






local h0 = signed ( 1779033703 )
local h1 = signed ( 3144134277 )
local h2 = signed ( 1013904242 )
local h3 = signed ( 2773480762 )
local h4 = signed ( 1359893119 )
local h5 = signed ( 2600822924 )
local h6 = signed ( 528734635 )
local h7 = signed ( 1541459225 )

local total = (__nuppBitTobit(( whole )+( (__nuppBitTobit(( upTo )+( 8 ))%4294967296) ))%4294967296)
local offset = 0
while offset < total do











local at = 0
if offset < whole then
while at < 16 do
local reading = (__nuppBitTobit(( (__nuppBitRshift( offset ,__nuppBitBand( 2 ,31))%4294967296) )+( at ))%4294967296)
local nativeWord = valuebuilder . word ( source , reading )
valuebuilder . setScratchWord ( schedule , at , ( unsigned ( ( ( __nuppBitTobit( nativeWord ) ) << 24 ) | ( ( ( __nuppBitTobit( nativeWord ) ) & 65280 ) << 8 ) | ( ( ( __nuppBitTobit( nativeWord ) ) >> 8 ) & 65280 ) | ( ( ( __nuppBitTobit( nativeWord ) ) >> 24 ) & 255 ) ) ) )
at = (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
else
local base = (__nuppBitTobit(( offset )-( whole ))%4294967296)
while at < 16 do
local within = (__nuppBitTobit(( base )+( (__nuppBitLshift( at ,__nuppBitBand( 2 ,31))%4294967296) ))%4294967296)
valuebuilder . setScratchWord (
schedule ,
at ,
unsigned (
( signed ( valuebuilder . scratchByte ( tail , within ) ) << 24 )
| ( signed ( valuebuilder . scratchByte ( tail , (__nuppBitTobit(( within )+( 1 ))%4294967296) ) ) << 16 )
| ( signed ( valuebuilder . scratchByte ( tail , (__nuppBitTobit(( within )+( 2 ))%4294967296) ) ) << 8 )
| signed ( valuebuilder . scratchByte ( tail , (__nuppBitTobit(( within )+( 3 ))%4294967296) ) )
)
)
at = (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
end

local extending = 16
while extending < 64 do
local word = add (
add (
signed ( valuebuilder . scratchWord ( schedule , (__nuppBitTobit(( extending )-( 16 ))%4294967296) ) ) ,
smallSigmaZero ( signed ( valuebuilder . scratchWord ( schedule , (__nuppBitTobit(( extending )-( 15 ))%4294967296) ) ) )
) ,
add (
signed ( valuebuilder . scratchWord ( schedule , (__nuppBitTobit(( extending )-( 7 ))%4294967296) ) ) ,
smallSigmaOne ( signed ( valuebuilder . scratchWord ( schedule , (__nuppBitTobit(( extending )-( 2 ))%4294967296) ) ) )
)
)
valuebuilder . setScratchWord ( schedule , extending , ( (__nuppBitTobit( word )%4294967296) ) )
extending = (__nuppBitTobit(( extending )+( 1 ))%4294967296)
end

local a , b , c , d = h0 , h1 , h2 , h3
local e , f , g , h = h4 , h5 , h6 , h7

local round = 0
while round < 64 do
local first = add (
add ( h , ( ( ( e >> 6 ) | ( e << 26 ) ) ~ ( ( e >> 11 ) | ( e << 21 ) ) ~ ( ( e >> 25 ) | ( e << 7 ) ) ) ) ,
add (
add ( ( ( e & f ) ~ ( ( ~ e ) & g ) ) , signed ( valuebuilder . word ( "ò/äBëD7qœ˚¿µ•€µÈ[¬V9Ò\17ÒY§Ç?í’^\28´ò™\7ÿ\1[É\18æÖ1$√}\12Ut]ær˛±ﬁÄß\6‹õtÒõ¡¡iõ‰ÜGæÔ∆ù¡\15Ã°\12$o,È-™ÑtJ‹©∞\\⁄à˘vRQ>òm∆1®»'\3∞«\127YøÛ\11‡∆Gëß’Qc \6g))\20Ö\n∑'8!\27.¸m,M\19\0138STs\neª\njv.…¬ÅÖ,rí°Ëø¢Kf\26®pãK¬£Ql«\25Ëí—$\6ô÷Ö5\14Ùp†j\16\22¡§\25\8l7\30LwH'µº∞4≥\12\0289J™ÿNO ú[Ûo.hÓÇètoc•x\20x»Ñ\8\2«å˙ˇæêÎlP§˜£˘æÚxq∆" , round ) ) ) ,
signed ( valuebuilder . scratchWord ( schedule , round ) )
)
)
local second = add ( ( ( ( a >> 2 ) | ( a << 30 ) ) ~ ( ( a >> 13 ) | ( a << 19 ) ) ~ ( ( a >> 22 ) | ( a << 10 ) ) ) , ( ( a & b ) ~ ( a & c ) ~ ( b & c ) ) )
h = g
g = f
f = e
e = add ( d , first )
d = c
c = b
b = a
a = ( __nuppBitTobit(( first )+( second )) )
round = (__nuppBitTobit(( round )+( 1 ))%4294967296)
end

h0 = add ( h0 , a )
h1 = add ( h1 , b )
h2 = add ( h2 , c )
h3 = add ( h3 , d )
h4 = add ( h4 , e )
h5 = add ( h5 , f )
h6 = add ( h6 , g )
h7 = add ( h7 , h )

offset = (__nuppBitTobit(( offset )+( 64 ))%4294967296)
end

valuebuilder . setScratchWord ( schedule , 0 , unsigned ( h0 ) )
valuebuilder . setScratchWord ( schedule , 1 , unsigned ( h1 ) )
valuebuilder . setScratchWord ( schedule , 2 , unsigned ( h2 ) )
valuebuilder . setScratchWord ( schedule , 3 , unsigned ( h3 ) )
valuebuilder . setScratchWord ( schedule , 4 , unsigned ( h4 ) )
valuebuilder . setScratchWord ( schedule , 5 , unsigned ( h5 ) )
valuebuilder . setScratchWord ( schedule , 6 , unsigned ( h6 ) )
valuebuilder . setScratchWord ( schedule , 7 , unsigned ( h7 ) )

local word = 0
while word < 8 do
local value = valuebuilder . scratchWord ( schedule , word )
local nibble = 0
while nibble < 8 do
valuebuilder . setScratchByte (
scratch ,
(__nuppBitTobit(( (__nuppBitLshift( word ,__nuppBitBand( 3 ,31))%4294967296) )+( nibble ))%4294967296) ,
hexDigit (
(__nuppBitBand(
(__nuppBitRshift(
value ,__nuppBitBand(
(__nuppBitTobit(( 28 )-( (__nuppBitLshift( nibble ,__nuppBitBand( 2 ,31))%4294967296) ))%4294967296) ,31))%4294967296) ,

15 )%4294967296)

)
)
nibble = (__nuppBitTobit(( nibble )+( 1 ))%4294967296)
end
word = (__nuppBitTobit(( word )+( 1 ))%4294967296)
end

valuebuilder . stringScratch ( builder , scratch , 0 , 64 )

return valuebuilder . finish ( builder )
end







function digest . sha256 ( value ) 
if # value > 2147483647 then
error ( "nupp: SHA-256 input is too long" , 2 )
end
return digestHex ( value , NEVER_NULL )
end

local __nuppExportValue= digest ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.digest.internal.sha256"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.digest.internal.sha256"]=__nuppExports;return __nuppExports