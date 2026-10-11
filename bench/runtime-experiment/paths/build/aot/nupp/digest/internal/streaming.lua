_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitBnot=bit.bnot;local __nuppBitBor=bit.bor;local __nuppBitBxor=bit.bxor;local __nuppBitLshift=bit.lshift;local __nuppBitRor=bit.ror;local __nuppBitRshift=bit.rshift;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





























local span = require ( "nupp.mem.span" )
local hash = { }















const ROUND_CONSTANTS

= {
1116352408 ,
1899447441 ,
3049323471 ,
3921009573 ,
961987163 ,
1508970993 ,
2453635748 ,
2870763221 ,
3624381080 ,
310598401 ,
607225278 ,
1426881987 ,
1925078388 ,
2162078206 ,
2614888103 ,
3248222580 ,
3835390401 ,
4022224774 ,
264347078 ,
604807628 ,
770255983 ,
1249150122 ,
1555081692 ,
1996064986 ,
2554220882 ,
2821834349 ,
2952996808 ,
3210313671 ,
3336571891 ,
3584528711 ,
113926993 ,
338241895 ,
666307205 ,
773529912 ,
1294757372 ,
1396182291 ,
1695183700 ,
1986661051 ,
2177026350 ,
2456956037 ,
2730485921 ,
2820302411 ,
3259730800 ,
3345764771 ,
3516065817 ,
3600352804 ,
4094571909 ,
275423344 ,
430227734 ,
506948616 ,
659060556 ,
883997877 ,
958139571 ,
1322822218 ,
1537002063 ,
1747873779 ,
1955562222 ,
2024104815 ,
2227730452 ,
2361852424 ,
2428436474 ,
2756734187 ,
3204031479 ,
3329325298 ,
}

local function i32 ( value ) 
return __nuppBitTobit( value )
end

local function add ( a , b ) 
return __nuppBitTobit(( a )+( b ))
end

local function xor ( a , b ) 
return __nuppBitBxor( a , b )
end

local function logicalRight ( value , count ) 
return __nuppBitTobit( (__nuppBitRshift( (__nuppBitTobit( value )%4294967296) ,__nuppBitBand( count ,31))%4294967296) )
end

local function rotateRight ( value , count ) 
return __nuppBitRor( value ,__nuppBitBand( count ,31))
end

local function smallSigmaZero ( word ) 
return xor ( xor ( ( __nuppBitRor( word ,__nuppBitBand( 7 ,31)) ) , ( __nuppBitRor( word ,__nuppBitBand( 18 ,31)) ) ) , ( __nuppBitTobit( (__nuppBitRshift( (__nuppBitTobit( word )%4294967296) ,__nuppBitBand( 3 ,31))%4294967296) ) ) )
end

local function smallSigmaOne ( word ) 
return xor ( xor ( ( __nuppBitRor( word ,__nuppBitBand( 17 ,31)) ) , ( __nuppBitRor( word ,__nuppBitBand( 19 ,31)) ) ) , ( __nuppBitTobit( (__nuppBitRshift( (__nuppBitTobit( word )%4294967296) ,__nuppBitBand( 10 ,31))%4294967296) ) ) )
end

local function bigSigmaZero ( word ) 
return xor ( xor ( ( __nuppBitRor( word ,__nuppBitBand( 2 ,31)) ) , ( __nuppBitRor( word ,__nuppBitBand( 13 ,31)) ) ) , ( __nuppBitRor( word ,__nuppBitBand( 22 ,31)) ) )
end

local function bigSigmaOne ( word ) 
return xor ( xor ( ( __nuppBitRor( word ,__nuppBitBand( 6 ,31)) ) , ( __nuppBitRor( word ,__nuppBitBand( 11 ,31)) ) ) , ( __nuppBitRor( word ,__nuppBitBand( 25 ,31)) ) )
end

local function choose ( e , f , g ) 
return xor ( __nuppBitBand( e , f ) , __nuppBitBand( __nuppBitBnot( e ) , g ) )
end

local function majority ( a , b , c ) 
return xor ( xor ( __nuppBitBand( a , b ) , __nuppBitBand( a , c ) ) , __nuppBitBand( b , c ) )
end

local function wordAt ( words , index ) 
return i32 ( words [ index ] )
end

local function unsignedWordAt ( words , index ) 
return (__nuppBitTobit( words [ index ] )%4294967296)
end

local Sha256 = {} Sha256.__index = Sha256





function Sha256.__nuppCtor1() local self = _G.setmetatable({}, Sha256)  local __nuppT14=self; 
self . state = {
( __nuppBitTobit( 0x6A09E667 ) ) ,
( __nuppBitTobit( 0xBB67AE85 ) ) ,
( __nuppBitTobit( 0x3C6EF372 ) ) ,
( __nuppBitTobit( 0xA54FF53A ) ) ,
( __nuppBitTobit( 0x510E527F ) ) ,
( __nuppBitTobit( 0x9B05688C ) ) ,
( __nuppBitTobit( 0x1F83D9AB ) ) ,
( __nuppBitTobit( 0x5BE0CD19 ) ) ,
}
self . tail = ""
self . length = { (__nuppBitTobit( 0 )%4294967296) , (__nuppBitTobit( 0 )%4294967296) }
self . schedule = { }
return __nuppT14 end







local function compress ( self , source , offset ) 
local words = self . schedule
for index = 1 , 16 do
local a , b , c , d = source : byte ( offset , offset + 3 )
words [ index ] = ( __nuppBitTobit( ( ( ( a * 256 + b ) * 256 + c ) * 256 + d ) ) )
offset = offset + 4
end
for index = 17 , 64 do
words [
index
] = add (
add ( ( i32 ( words [ ( index - 16 ) ] ) ) , smallSigmaZero ( ( i32 ( words [ ( index - 15 ) ] ) ) ) ) ,
add ( ( i32 ( words [ ( index - 7 ) ] ) ) , smallSigmaOne ( ( i32 ( words [ ( index - 2 ) ] ) ) ) )
)
end

local state = self . state
local a = ( i32 ( state [ 1 ] ) )
local b = ( i32 ( state [ 2 ] ) )
local c = ( i32 ( state [ 3 ] ) )
local d = ( i32 ( state [ 4 ] ) )
local e = ( i32 ( state [ 5 ] ) )
local f = ( i32 ( state [ 6 ] ) )
local g = ( i32 ( state [ 7 ] ) )
local h = ( i32 ( state [ 8 ] ) )
for index = 1 , 64 do
local first = add (
add ( h , bigSigmaOne ( e ) ) ,
add ( add ( choose ( e , f , g ) , i32 ( ROUND_CONSTANTS [ index ] ) ) , ( i32 ( words [ index ] ) ) )
)
local second = add ( bigSigmaZero ( a ) , majority ( a , b , c ) )
h , g , f = g , f , e
e = add ( d , first )
d , c , b = c , b , a
a = ( __nuppBitTobit(( first )+( second )) )
end

state [ 1 ] = add ( ( i32 ( state [ 1 ] ) ) , a )
state [ 2 ] = add ( ( i32 ( state [ 2 ] ) ) , b )
state [ 3 ] = add ( ( i32 ( state [ 3 ] ) ) , c )
state [ 4 ] = add ( ( i32 ( state [ 4 ] ) ) , d )
state [ 5 ] = add ( ( i32 ( state [ 5 ] ) ) , e )
state [ 6 ] = add ( ( i32 ( state [ 6 ] ) ) , f )
state [ 7 ] = add ( ( i32 ( state [ 7 ] ) ) , g )
state [ 8 ] = add ( ( i32 ( state [ 8 ] ) ) , h )
end

local function addLength ( self , count ) 
local before = unsignedWordAt ( self . length , 1 )
local after = (__nuppBitTobit(( before )+( (__nuppBitTobit( count )%4294967296) ))%4294967296)
self . length [ 1 ] = after
if after < before then
self . length [ 2 ] = (__nuppBitTobit(( unsignedWordAt ( self . length , 2 ) )+( 1 ))%4294967296)
end
end

function Sha256 : update ( bytes ) 
addLength ( self , # bytes )
local offset = 1
if # self . tail > 0 then
local needed = 64 - # self . tail
if # bytes < needed then
self . tail = self . tail .. bytes
return self
end
compress ( self , self . tail .. bytes : sub ( 1 , needed ) , 1 )
self . tail = ""
offset = needed + 1
end
while offset + 63 <= # bytes do
compress ( self , bytes , offset )
offset = offset + 64
end
if offset <= # bytes then
self . tail = bytes : sub ( offset )
end

return self
end

local function copy ( source ) 
local target = Sha256 .__nuppCtor1 ( )
for index = 1 , 8 do
target . state [ index ] = wordAt ( source . state , index )
end
target . tail = source . tail
target . length [ 1 ] = unsignedWordAt ( source . length , 1 )
target . length [ 2 ] = unsignedWordAt ( source . length , 2 )

return target
end

local function lengthBytes ( high , low ) 
local bytes = { }
local highNumber = high
local lowNumber = low
for shift = 24 , 0 , -8 do
bytes [ # bytes + 1 ] = string . char ( math . floor ( highNumber / 2 ^ shift ) % 256 )
end
for shift = 24 , 0 , -8 do
bytes [ # bytes + 1 ] = string . char ( math . floor ( lowNumber / 2 ^ shift ) % 256 )
end

return table . concat ( bytes )
end

local function finalState ( source ) 
local state = copy ( source )
local byteLengthLow = unsignedWordAt ( state . length , 1 )
local byteLengthHigh = unsignedWordAt ( state . length , 2 )
local high = (__nuppBitBor(
(__nuppBitLshift( byteLengthHigh ,__nuppBitBand( 3 ,31))%4294967296) ,
(__nuppBitRshift( byteLengthLow ,__nuppBitBand( 29 ,31))%4294967296) )%4294967296)

local low = (__nuppBitLshift( byteLengthLow ,__nuppBitBand( 3 ,31))%4294967296)
local tail = state . tail .. "€"
tail = tail .. string . rep ( "\0" , ( 56 - # tail % 64 ) % 64 ) .. lengthBytes ( high , low )
for offset = 1 , # tail , 64 do
compress ( state , tail , offset )
end

return state
end

local function rawDigest ( source ) 
local state = finalState ( source )

local bytes = { }
for index = 1 , 8 do
local value = (__nuppBitTobit( wordAt ( state . state , index ) )%4294967296)
for shift = 24 , 0 , -8 do
bytes [ # bytes + 1 ] = string . char ( math . floor ( value / 2 ^ shift ) % 256 )
end
end

return table . concat ( bytes )
end

local function hexadecimal ( raw ) 
local encoded = { }
for index = 1 , # raw do
encoded [ index ] = ("%02x") : format ( raw : byte ( index ) )
end

return table . concat ( encoded )
end

function Sha256 : digest ( ) 
return rawDigest ( self )
end

function Sha256 : hex ( ) 
return hexadecimal ( rawDigest ( self ) )
end

function Sha256 . writeDigest ( self , destination ) 
local state = finalState ( self )
for index = 1 , 8 do
local value = (__nuppBitTobit( wordAt ( state . state , index ) )%4294967296)
for byte = 0 , 3 do
destination :set( ( index - 1 ) * 4 + byte + 1 , math . floor ( value / 2 ^ ( 24 - byte * 8 ) ) % 256 )
end
end
end

local function sha256 ( ) 
return ( Sha256 .__nuppCtor1 ( ) )
end

local function xorPad ( key , pad ) 
local bytes = { }
local mask = (__nuppBitTobit( pad )%4294967296)
for index = 1 , 64 do
bytes [ index ] = string . char ( (__nuppBitBxor( (__nuppBitTobit( key : byte ( index ) )%4294967296) , mask )%4294967296) )
end

return table . concat ( bytes )
end

local Hmac = {} Hmac.__index = Hmac



function Hmac.__nuppCtor1(key) local self = _G.setmetatable({}, Hmac)  local __nuppT29=self; 
if # key > 64 then
key = ( Sha256 .__nuppCtor1 ( ) ) : update ( key ) : digest ( )
end
key = key .. string . rep ( "\0" , 64 - # key )
self . inner = ( Sha256 .__nuppCtor1 ( ) )
self . inner : update ( xorPad ( key , 0x36 ) )
self . outerPad = xorPad ( key , 0x5C )
return __nuppT29 end







function Hmac : update ( bytes ) 
self . inner : update ( bytes )
return self
end

function Hmac : digest ( ) 
local outer = ( Sha256 .__nuppCtor1 ( ) )
outer : update ( self . outerPad )
outer : update ( self . inner : digest ( ) )
return outer : digest ( )
end

function Hmac : hex ( ) 
return hexadecimal ( self : digest ( ) )
end

function Hmac . writeDigest ( self , destination ) 
local outer = ( Sha256 .__nuppCtor1 ( ) )
outer : update ( self . outerPad )
outer : update ( self . inner : digest ( ) )
outer : writeDigest ( destination )
end



function hash . sha256 ( ) 
return ( ( Sha256 .__nuppCtor1 ( ) ) )
end



function hash . hmac ( key ) 
return ( Hmac .__nuppCtor1 ( key ) )
end

local function oneShot ( key , message ) 
local mac = Hmac .__nuppCtor1 ( key )
mac : update ( message )

return mac
end






function hash . hmacDigest ( key , message ) 
return oneShot ( key , message ) : digest ( )
end






function hash . hmacHex ( key , message ) 
return oneShot ( key , message ) : hex ( )
end

local __nuppExportValue= hash ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.digest.internal.streaming"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.digest.internal.streaming"]=__nuppExports;return __nuppExports