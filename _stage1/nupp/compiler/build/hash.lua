_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






















local hash = { }




local band , bxor = bit . band , bit . bxor
local bnot , rshift , ror = bit . bnot , bit . rshift , bit . ror
local rol = bit . rol

local K = {
0x428a2f98 ,
0x71374491 ,
0xb5c0fbcf ,
0xe9b5dba5 ,
0x3956c25b ,
0x59f111f1 ,
0x923f82a4 ,
0xab1c5ed5 ,
0xd807aa98 ,
0x12835b01 ,
0x243185be ,
0x550c7dc3 ,
0x72be5d74 ,
0x80deb1fe ,
0x9bdc06a7 ,
0xc19bf174 ,
0xe49b69c1 ,
0xefbe4786 ,
0x0fc19dc6 ,
0x240ca1cc ,
0x2de92c6f ,
0x4a7484aa ,
0x5cb0a9dc ,
0x76f988da ,
0x983e5152 ,
0xa831c66d ,
0xb00327c8 ,
0xbf597fc7 ,
0xc6e00bf3 ,
0xd5a79147 ,
0x06ca6351 ,
0x14292967 ,
0x27b70a85 ,
0x2e1b2138 ,
0x4d2c6dfc ,
0x53380d13 ,
0x650a7354 ,
0x766a0abb ,
0x81c2c92e ,
0x92722c85 ,
0xa2bfe8a1 ,
0xa81a664b ,
0xc24b8b70 ,
0xc76c51a3 ,
0xd192e819 ,
0xd6990624 ,
0xf40e3585 ,
0x106aa070 ,
0x19a4c116 ,
0x1e376c08 ,
0x2748774c ,
0x34b0bcb5 ,
0x391c0cb3 ,
0x4ed8aa4a ,
0x5b9cca4f ,
0x682e6ff3 ,
0x748f82ee ,
0x78a5636f ,
0x84c87814 ,
0x8cc70208 ,
0x90befffa ,
0xa4506ceb ,
0xbef9a3f7 ,
0xc67178f2 ,
}

local function add ( ... )
local n = 0
for j = 1 , select ( "#" , ... ) do
n = bit . tobit ( n + select ( j , ... ) )
end

return n
end

local function word ( s , offset )
local a , b , c , d = s : byte ( offset , offset + 3 )
return bit . tobit ( a * 0x1000000 + b * 0x10000 + c * 0x100 + d )
end

function hash . sha256 ( input )
local bitLength = # input * 8
input = input .. "\128"
local padding = ( 56 - ( # input % 64 ) ) % 64
input = input .. string . rep ( "\0" , padding )


local high = math . floor ( bitLength / 4294967296 )
local low = bitLength % 4294967296
input = input .. string . char (
band ( rshift ( high , 24 ) , 0xff ) ,
band ( rshift ( high , 16 ) , 0xff ) ,
band ( rshift ( high , 8 ) , 0xff ) ,
band ( high , 0xff ) ,
band ( rshift ( low , 24 ) , 0xff ) ,
band ( rshift ( low , 16 ) , 0xff ) ,
band ( rshift ( low , 8 ) , 0xff ) ,
band ( low , 0xff )
)

local h = { 0x6a09e667 , 0xbb67ae85 , 0x3c6ef372 , 0xa54ff53a , 0x510e527f , 0x9b05688c , 0x1f83d9ab , 0x5be0cd19 , }
local w = { }
for chunk = 1 , # input , 64 do
for j = 0 , 15 do
w [ j ] = word ( input , chunk + j * 4 )
end
for j = 16 , 63 do
local x , y = w [ j - 15 ] , w [ j - 2 ]
local s0 = bxor ( ror ( x , 7 ) , ror ( x , 18 ) , rshift ( x , 3 ) )
local s1 = bxor ( ror ( y , 17 ) , ror ( y , 19 ) , rshift ( y , 10 ) )
w [ j ] = add ( w [ j - 16 ] , s0 , w [ j - 7 ] , s1 )
end
local a , b , c , d = h [ 1 ] , h [ 2 ] , h [ 3 ] , h [ 4 ]
local e , f , g , hh = h [ 5 ] , h [ 6 ] , h [ 7 ] , h [ 8 ]
for j = 0 , 63 do
local s1 = bxor ( ror ( e , 6 ) , ror ( e , 11 ) , ror ( e , 25 ) )
local ch = bxor ( band ( e , f ) , band ( bnot ( e ) , g ) )
local t1 = add ( hh , s1 , ch , K [ j + 1 ] , w [ j ] )
local s0 = bxor ( ror ( a , 2 ) , ror ( a , 13 ) , ror ( a , 22 ) )
local maj = bxor ( band ( a , b ) , band ( a , c ) , band ( b , c ) )
local t2 = add ( s0 , maj )
hh , g , f , e = g , f , e , add ( d , t1 )
d , c , b , a = c , b , a , add ( t1 , t2 )
end
h [ 1 ] , h [ 2 ] , h [ 3 ] , h [ 4 ] = add ( h [ 1 ] , a ) , add ( h [ 2 ] , b ) , add ( h [ 3 ] , c ) , add ( h [ 4 ] , d )
h [ 5 ] , h [ 6 ] , h [ 7 ] , h [ 8 ] = add ( h [ 5 ] , e ) , add ( h [ 6 ] , f ) , add ( h [ 7 ] , g ) , add ( h [ 8 ] , hh )
end
local out = { }
for _ , value in ipairs ( h ) do
out [ # out + 1 ] = bit . tohex ( value , 8 )
end

return table . concat ( out )
end

local P1 = 0x9E3779B185EBCA87ULL
local P2 = 0xC2B2AE3D27D4EB4FULL
local P3 = 0x165667B19E3779F9ULL
local P4 = 0x85EBCA77C2B2AE63ULL
local P5 = 0x27D4EB2F165667C5ULL

local function round ( acc , input )
acc = acc + input * P2
acc = rol ( acc , 31 )
return acc * P1
end

local function mergeRound ( acc , value )
value = round ( 0ULL , value )
acc = bxor ( acc , value )
return acc * P1 + P4
end



local function wordAt ( words , index )
do
return words [ index ]
end
end

local function halfAt ( halves , index )
do
return halves [ index ]
end
end

local function byteAt ( bytes , index )
do
return bytes [ index ]
end
end







local function xxh64 ( input , seed )
local size = # input
local words = __nuppFfi.cast("const uint64_t *" , input )
local h



local at = 0
if size >= 32 then
local v1 , v2 = seed + P1 + P2 , seed + P2
local v3 , v4 = seed + 0ULL , seed - P1
local stripes = ( math.floor(( size ) / ( 32 )) ) * 4
local w = 0
repeat
v1 = round ( v1 , wordAt ( words , w ) )
v2 = round ( v2 , wordAt ( words , w + 1 ) )
v3 = round ( v3 , wordAt ( words , w + 2 ) )
v4 = round ( v4 , wordAt ( words , w + 3 ) )
w = w + 4
until w >= stripes
at = w * 8
h = rol ( v1 , 1 ) + rol ( v2 , 7 ) + rol ( v3 , 12 ) + rol ( v4 , 18 )
h = mergeRound ( h , v1 )
h = mergeRound ( h , v2 )
h = mergeRound ( h , v3 )
h = mergeRound ( h , v4 )
else
h = seed + P5
end
h = h + size
while size - at >= 8 do
h = bxor ( h , round ( 0ULL , wordAt ( words , math.floor(( at ) / ( 8 )) ) ) )
h = rol ( h , 27 ) * P1 + P4
at = at + 8
end
if size - at >= 4 then
local halves = __nuppFfi.cast("const uint32_t *" , input )
h = bxor ( h , __nuppFfi.cast("uint64_t" , halfAt ( halves , math.floor(( at ) / ( 4 )) ) ) * P1 )
h = rol ( h , 23 ) * P2 + P3
at = at + 4
end
if at < size then
local bytes = __nuppFfi.cast("const uint8_t *" , input )
while at < size do
h = bxor ( h , __nuppFfi.cast("uint64_t" , byteAt ( bytes , at ) ) * P5 )
h = rol ( h , 11 ) * P1
at = at + 1
end
end
h = bxor ( h , rshift ( h , 33 ) )
h = h * P2
h = bxor ( h , rshift ( h , 29 ) )
h = h * P3

return __nuppFfi.cast("uint64_t" , bxor ( h , rshift ( h , 32 ) ) )
end





local function hex64 ( value )
local high = tonumber ( band ( rshift ( value , 32 ) , 0xFFFFFFFFULL ) )
local low = tonumber ( band ( value , 0xFFFFFFFFULL ) )
return ( "%08x%08x" ) : format ( high , low )
end





local SEED_A = 0ULL
local SEED_B = 0x9E3779B97F4A7C15ULL





function hash . digest ( input )
return hex64 ( xxh64 ( input , SEED_A ) ) .. hex64 ( xxh64 ( input , SEED_B ) )
end





hash . DIGEST = "xxh64x2"

hash . xxh64 = xxh64
hash . hex64 = hex64

return hash
