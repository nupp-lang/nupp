_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitBor=bit.bor;local __nuppBitLshift=bit.lshift;local __nuppBitRshift=bit.rshift;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

























local valuebuilder = require ( "nupp.codec.valuebuilder" )

local base64 = { }

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


const INVERSE = "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ"



const INVALID = { }

local function u32 ( value ) 
return (__nuppBitTobit( value )%4294967296)
end

local function add ( a , b ) 
return (__nuppBitTobit(( a )+( b ))%4294967296)
end

local function shr ( value , count ) 
return (__nuppBitRshift( value ,__nuppBitBand( count ,31))%4294967296)
end

local function shl ( value , count ) 
return (__nuppBitLshift( value ,__nuppBitBand( count ,31))%4294967296)
end

local function andBits ( a , b ) 
return (__nuppBitBand( a , b )%4294967296)
end

local function orBits ( a , b ) 
return (__nuppBitBor( a , b )%4294967296)
end




local function reversed ( word ) 
return orBits (
orBits ( shl ( word , 24 ) , shl ( andBits ( word , 65280 ) , 8 ) ) ,
orBits ( andBits ( shr ( word , 8 ) , 65280 ) , shr ( word , 24 ) )
)
end



local function encodeAot ( source , nullValue ) 
local length = valuebuilder . length ( source )


local bound = add ( add ( length , shr ( length , 1 ) ) , 4 )
local builder = valuebuilder . newSized ( nullValue , 2 , bound )
local scratch = valuebuilder . newByteScratch ( bound )

local at = 0
local out = 0
while add ( at , 12 ) <= length do
local wi = shr ( at , 2 )
local w0 = reversed ( valuebuilder . word ( source , wi ) )
local w1 = reversed ( valuebuilder . word ( source , add ( wi , 1 ) ) )
local w2 = reversed ( valuebuilder . word ( source , add ( wi , 2 ) ) )

local g0 = shr ( w0 , 8 )
local g1 = orBits ( shl ( andBits ( w0 , 255 ) , 16 ) , shr ( w1 , 16 ) )
local g2 = orBits ( shl ( andBits ( w1 , 65535 ) , 8 ) , shr ( w2 , 24 ) )
local g3 = andBits ( w2 , 16777215 )

valuebuilder . setScratchBytes4 (
scratch ,
out ,
orBits (
orBits (
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g0 , 18 ) , 63 ) ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g0 , 12 ) , 63 ) ) , 8 )
) ,
orBits (
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g0 , 6 ) , 63 ) ) , 16 ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( g0 , 63 ) ) , 24 )
)
)
)
valuebuilder . setScratchBytes4 (
scratch ,
add ( out , 4 ) ,
orBits (
orBits (
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g1 , 18 ) , 63 ) ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g1 , 12 ) , 63 ) ) , 8 )
) ,
orBits (
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g1 , 6 ) , 63 ) ) , 16 ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( g1 , 63 ) ) , 24 )
)
)
)
valuebuilder . setScratchBytes4 (
scratch ,
add ( out , 8 ) ,
orBits (
orBits (
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g2 , 18 ) , 63 ) ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g2 , 12 ) , 63 ) ) , 8 )
) ,
orBits (
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g2 , 6 ) , 63 ) ) , 16 ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( g2 , 63 ) ) , 24 )
)
)
)
valuebuilder . setScratchBytes4 (
scratch ,
add ( out , 12 ) ,
orBits (
orBits (
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g3 , 18 ) , 63 ) ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g3 , 12 ) , 63 ) ) , 8 )
) ,
orBits (
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( shr ( g3 , 6 ) , 63 ) ) , 16 ) ,
shl ( valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( g3 , 63 ) ) , 24 )
)
)
)

at = add ( at , 12 )
out = add ( out , 16 )
end

while add ( at , 3 ) <= length do
local b0 = valuebuilder . byte ( source , at )
local b1 = valuebuilder . byte ( source , add ( at , 1 ) )
local b2 = valuebuilder . byte ( source , add ( at , 2 ) )
valuebuilder . setScratchByte ( scratch , out , valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , shr ( b0 , 2 ) ) )
valuebuilder . setScratchByte (
scratch ,
add ( out , 1 ) ,
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , orBits ( shl ( andBits ( b0 , 3 ) , 4 ) , shr ( b1 , 4 ) ) )
)
valuebuilder . setScratchByte (
scratch ,
add ( out , 2 ) ,
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , orBits ( shl ( andBits ( b1 , 15 ) , 2 ) , shr ( b2 , 6 ) ) )
)
valuebuilder . setScratchByte ( scratch , add ( out , 3 ) , valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , andBits ( b2 , 63 ) ) )
at = add ( at , 3 )
out = add ( out , 4 )
end

local rest = (__nuppBitTobit(( length )-( at ))%4294967296)
if rest == 1 then
local c0 = valuebuilder . byte ( source , at )
valuebuilder . setScratchByte ( scratch , out , valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , shr ( c0 , 2 ) ) )
valuebuilder . setScratchByte (
scratch ,
add ( out , 1 ) ,
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , shl ( andBits ( c0 , 3 ) , 4 ) )
)
valuebuilder . setScratchByte ( scratch , add ( out , 2 ) , 61 )
valuebuilder . setScratchByte ( scratch , add ( out , 3 ) , 61 )
out = add ( out , 4 )
elseif rest == 2 then
local d0 = valuebuilder . byte ( source , at )
local d1 = valuebuilder . byte ( source , add ( at , 1 ) )
valuebuilder . setScratchByte ( scratch , out , valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , shr ( d0 , 2 ) ) )
valuebuilder . setScratchByte (
scratch ,
add ( out , 1 ) ,
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , orBits ( shl ( andBits ( d0 , 3 ) , 4 ) , shr ( d1 , 4 ) ) )
)
valuebuilder . setScratchByte (
scratch ,
add ( out , 2 ) ,
valuebuilder . byte ( "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" , shl ( andBits ( d1 , 15 ) , 2 ) )
)
valuebuilder . setScratchByte ( scratch , add ( out , 3 ) , 61 )
out = add ( out , 4 )
end

valuebuilder . stringScratch ( builder , scratch , 0 , out )

return valuebuilder . finish ( builder )
end






local function decodeAot ( text , nullValue ) 
local length = valuebuilder . length ( text )
local builder = valuebuilder . newSized ( nullValue , 2 , add ( length , 4 ) )
local scratch = valuebuilder . newByteScratch ( add ( length , 4 ) )

local padding = 0
if length > 0 then
if valuebuilder . byte ( text , (__nuppBitTobit(( length )-( 1 ))%4294967296) ) == 61 then
padding = 1
end


if padding == 1 and length > 1 and valuebuilder . byte ( text , (__nuppBitTobit(( length )-( 2 ))%4294967296) ) == 61 then
padding = 2
end
end

local at = 0
local out = 0
local bad = 0
local whole = length
if padding > 0 then
whole = (__nuppBitTobit(( length )-( 4 ))%4294967296)
end
while at < whole do
local a = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , at ) )
local b = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , add ( at , 1 ) ) )
local c = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , add ( at , 2 ) ) )
local d = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , add ( at , 3 ) ) )
bad = orBits ( bad , orBits ( ( (__nuppBitBor( a , b )%4294967296) ) , ( (__nuppBitBor( c , d )%4294967296) ) ) )
local value = orBits ( orBits ( shl ( a , 18 ) , shl ( b , 12 ) ) , orBits ( shl ( c , 6 ) , d ) )
valuebuilder . setScratchByte ( scratch , out , andBits ( shr ( value , 16 ) , 255 ) )
valuebuilder . setScratchByte ( scratch , add ( out , 1 ) , andBits ( shr ( value , 8 ) , 255 ) )
valuebuilder . setScratchByte ( scratch , add ( out , 2 ) , andBits ( value , 255 ) )
at = add ( at , 4 )
out = add ( out , 3 )
end

if padding > 0 then
local a = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , at ) )
local b = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , add ( at , 1 ) ) )
local c = 0
if padding == 1 then
c = valuebuilder . byte ( "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ>ÿÿÿ?456789:;<=ÿÿÿÿÿÿÿ\0\1\2\3\4\5\6\7\8\9\n\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25ÿÿÿÿÿÿ\26\27\28\29\30\31 !\"#$%&'()*+,-./0123ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" , valuebuilder . byte ( text , add ( at , 2 ) ) )


bad = orBits ( bad , shl ( andBits ( c , 3 ) , 6 ) )
else


bad = orBits ( bad , shl ( andBits ( b , 15 ) , 6 ) )
end
bad = orBits ( bad , orBits ( ( (__nuppBitBor( a , b )%4294967296) ) , c ) )
local value = orBits ( orBits ( shl ( a , 18 ) , shl ( b , 12 ) ) , shl ( c , 6 ) )
valuebuilder . setScratchByte ( scratch , out , andBits ( shr ( value , 16 ) , 255 ) )
out = add ( out , 1 )
if padding == 1 then
valuebuilder . setScratchByte ( scratch , out , andBits ( shr ( value , 8 ) , 255 ) )
out = add ( out , 1 )
end
end

if bad > 63 then
valuebuilder . null ( builder )
else
valuebuilder . stringScratch ( builder , scratch , 0 , out )
end

return valuebuilder . finish ( builder )
end









function base64 . encode ( value ) 
return encodeAot ( value , false )
end















function base64 . decode ( text ) 
if # text % 4 ~= 0 then
return nil , "base64 input length is not a multiple of four"
end
local decoded = decodeAot ( text , INVALID )
if decoded == INVALID then
return nil , "base64 input is not canonical padded base64"
end

return decoded , nil
end

local __nuppExportValue= base64 ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.base64"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.base64"]=__nuppExports;return __nuppExports