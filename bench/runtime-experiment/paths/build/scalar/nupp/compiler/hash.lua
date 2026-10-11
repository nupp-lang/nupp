_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






























local digest = require ( "nupp.digest.internal.sha256" )
local bitops = require ( "nupp.compiler.bitops" )

local hash = { }

function hash . sha256 ( input ) 
return digest . sha256 ( input )
end

local function u32 ( value ) 
return value % 4294967296
end

const P1_HI = 2654435761
const P1_LO = 2246822535
const P2_HI = 3266489917
const P2_LO = 668265295
const P3_HI = 374761393
const P3_LO = 2654435833
const P4_HI = 2246822519
const P4_LO = 3266489955
const P5_HI = 668265263
const P5_LO = 374761413






local function add64 ( aHi , aLo , bHi , bLo ) 
local lo = aLo + bLo
local carry = 0
if lo >= 4294967296 then
carry = 1
lo = lo - 4294967296
end

return ( ( aHi + bHi + carry ) % 4294967296 ) , lo
end

local function xor64 ( aHi , aLo , bHi , bLo ) 
return u32 ( bitops . bxor ( aHi , bHi ) ) , u32 ( bitops . bxor ( aLo , bLo ) )
end




local function rotl64 ( hi , lo , count ) 
if count == 0 then
return hi , lo
elseif count == 32 then
return lo , hi
elseif count < 32 then
return u32 (
bitops . bor ( bitops . lshift ( hi , count ) , bitops . rshift ( lo , 32 - count ) )
) , u32 ( bitops . bor ( bitops . lshift ( lo , count ) , bitops . rshift ( hi , 32 - count ) ) )
else
local rest = count - 32
return u32 (
bitops . bor ( bitops . lshift ( lo , rest ) , bitops . rshift ( hi , 32 - rest ) )
) , u32 ( bitops . bor ( bitops . lshift ( hi , rest ) , bitops . rshift ( lo , 32 - rest ) ) )
end
end




local function rshift64 ( hi , lo , count ) 
if count == 0 then
return hi , lo
elseif count == 32 then
return 0 , hi
elseif count < 32 then
return u32 ( bitops . rshift ( hi , count ) ) , u32 ( bitops . bor ( bitops . rshift ( lo , count ) , bitops . lshift ( hi , 32 - count ) ) )
else
return 0 , u32 ( bitops . rshift ( hi , count - 32 ) )
end
end







local function mul64 ( aHi , aLo , bHi , bLo ) 
local a0 , a1 = bitops . band ( aLo , 65535 ) , bitops . band ( bitops . rshift ( aLo , 16 ) , 65535 )
local a2 , a3 = bitops . band ( aHi , 65535 ) , bitops . band ( bitops . rshift ( aHi , 16 ) , 65535 )
local b0 , b1 = bitops . band ( bLo , 65535 ) , bitops . band ( bitops . rshift ( bLo , 16 ) , 65535 )
local b2 , b3 = bitops . band ( bHi , 65535 ) , bitops . band ( bitops . rshift ( bHi , 16 ) , 65535 )

local c0 = a0 * b0
local c1 = math . floor ( c0 / 65536 )
c0 = c0 % 65536
c1 = c1 + a1 * b0
local c2 = math . floor ( c1 / 65536 )
c1 = c1 % 65536
c1 = c1 + a0 * b1
c2 = c2 + math . floor ( c1 / 65536 )
c1 = c1 % 65536
c2 = c2 + a2 * b0
local c3 = math . floor ( c2 / 65536 )
c2 = c2 % 65536
c2 = c2 + a1 * b1
c3 = c3 + math . floor ( c2 / 65536 )
c2 = c2 % 65536
c2 = c2 + a0 * b2
c3 = c3 + math . floor ( c2 / 65536 )
c2 = c2 % 65536
c3 = ( c3 + a3 * b0 + a2 * b1 + a1 * b2 + a0 * b3 ) % 65536

return c3 * 65536 + c2 , c1 * 65536 + c0
end

local function round ( accHi , accLo , inHi , inLo ) 
local mulHi , mulLo = mul64 ( inHi , inLo , 3266489917 , 668265295 )
local sumHi , sumLo = add64 ( accHi , accLo , mulHi , mulLo )
local rotHi , rotLo = rotl64 ( sumHi , sumLo , 31 )

return mul64 ( rotHi , rotLo , 2654435761 , 2246822535 )
end

local function mergeRound ( accHi , accLo , valHi , valLo ) 
local roundedHi , roundedLo = round ( 0 , 0 , valHi , valLo )
local xoredHi , xoredLo = xor64 ( accHi , accLo , roundedHi , roundedLo )
local mulHi , mulLo = mul64 ( xoredHi , xoredLo , 2654435761 , 2246822535 )

return add64 ( mulHi , mulLo , 2246822519 , 3266489955 )
end





local function wordAt ( input , offset ) 
local b1 , b2 , b3 , b4 , b5 , b6 , b7 , b8 = input : byte ( offset + 1 , offset + 8 )

return u32 (
bitops . bor ( b5 , bitops . lshift ( b6 , 8 ) , bitops . lshift ( b7 , 16 ) , bitops . lshift ( b8 , 24 ) )
) , u32 ( bitops . bor ( b1 , bitops . lshift ( b2 , 8 ) , bitops . lshift ( b3 , 16 ) , bitops . lshift ( b4 , 24 ) ) )
end

local function halfAt ( input , offset ) 
local b1 , b2 , b3 , b4 = input : byte ( offset + 1 , offset + 4 )

return u32 ( bitops . bor ( b1 , bitops . lshift ( b2 , 8 ) , bitops . lshift ( b3 , 16 ) , bitops . lshift ( b4 , 24 ) ) )
end





local function xxh64 ( input , seedHi , seedLo ) 
local size = # input
local at = 0
local hHi , hLo = 0 , 0

if size >= 32 then
local sp1Hi , sp1Lo = add64 ( seedHi , seedLo , 2654435761 , 2246822535 )
local v1Hi , v1Lo = add64 ( sp1Hi , sp1Lo , 3266489917 , 668265295 )
local v2Hi , v2Lo = add64 ( seedHi , seedLo , 3266489917 , 668265295 )
local v3Hi , v3Lo = seedHi , seedLo
local negP1Hi , negP1Lo = add64 ( u32 ( bitops . bnot ( 2654435761 ) ) , u32 ( bitops . bnot ( 2246822535 ) ) , 0 , 1 )
local v4Hi , v4Lo = add64 ( seedHi , seedLo , negP1Hi , negP1Lo )

local stripes = ( _G.math.floor(( size ) / ( 32 )) ) * 4
local w = 0
repeat
v1Hi , v1Lo = round ( v1Hi , v1Lo , wordAt ( input , w * 8 ) )
v2Hi , v2Lo = round ( v2Hi , v2Lo , wordAt ( input , ( w + 1 ) * 8 ) )
v3Hi , v3Lo = round ( v3Hi , v3Lo , wordAt ( input , ( w + 2 ) * 8 ) )
v4Hi , v4Lo = round ( v4Hi , v4Lo , wordAt ( input , ( w + 3 ) * 8 ) )
w = w + 4
until w >= stripes
at = w * 8

hHi , hLo = rotl64 ( v1Hi , v1Lo , 1 )
hHi , hLo = add64 ( hHi , hLo , rotl64 ( v2Hi , v2Lo , 7 ) )
hHi , hLo = add64 ( hHi , hLo , rotl64 ( v3Hi , v3Lo , 12 ) )
hHi , hLo = add64 ( hHi , hLo , rotl64 ( v4Hi , v4Lo , 18 ) )
hHi , hLo = mergeRound ( hHi , hLo , v1Hi , v1Lo )
hHi , hLo = mergeRound ( hHi , hLo , v2Hi , v2Lo )
hHi , hLo = mergeRound ( hHi , hLo , v3Hi , v3Lo )
hHi , hLo = mergeRound ( hHi , hLo , v4Hi , v4Lo )
else
hHi , hLo = add64 ( seedHi , seedLo , 668265263 , 374761413 )
end
hHi , hLo = add64 ( hHi , hLo , 0 , size )

while size - at >= 8 do
hHi , hLo = xor64 ( hHi , hLo , round ( 0 , 0 , wordAt ( input , at ) ) )
hHi , hLo = rotl64 ( hHi , hLo , 27 )
hHi , hLo = mul64 ( hHi , hLo , 2654435761 , 2246822535 )
hHi , hLo = add64 ( hHi , hLo , 2246822519 , 3266489955 )
at = at + 8
end

if size - at >= 4 then
hHi , hLo = xor64 ( hHi , hLo , mul64 ( 0 , halfAt ( input , at ) , 2654435761 , 2246822535 ) )
hHi , hLo = rotl64 ( hHi , hLo , 23 )
hHi , hLo = mul64 ( hHi , hLo , 3266489917 , 668265295 )
hHi , hLo = add64 ( hHi , hLo , 374761393 , 2654435833 )
at = at + 4
end

while at < size do
hHi , hLo = xor64 ( hHi , hLo , mul64 ( 0 , assert ( input : byte ( at + 1 ) ) , 668265263 , 374761413 ) )
hHi , hLo = rotl64 ( hHi , hLo , 11 )
hHi , hLo = mul64 ( hHi , hLo , 2654435761 , 2246822535 )
at = at + 1
end

hHi , hLo = xor64 ( hHi , hLo , rshift64 ( hHi , hLo , 33 ) )
hHi , hLo = mul64 ( hHi , hLo , 3266489917 , 668265295 )
hHi , hLo = xor64 ( hHi , hLo , rshift64 ( hHi , hLo , 29 ) )
hHi , hLo = mul64 ( hHi , hLo , 374761393 , 2654435833 )

return xor64 ( hHi , hLo , rshift64 ( hHi , hLo , 32 ) )
end


local function hex64 ( hi , lo ) 
return ("%08x%08x") : format ( hi , lo )
end




const SEED_A_HI , SEED_A_LO = 0 , 0
const SEED_B_HI , SEED_B_LO = 2654435769 , 2135587861





function hash . digest ( input ) 
return hex64 ( xxh64 ( input , 0 , 0 ) ) .. hex64 ( xxh64 ( input , 2654435769 , 2135587861 ) )
end

















function hash . trailerDigest ( payload ) 
local hi , lo = xxh64 ( payload , 0 , 0 )

return string . char (
bitops . band ( lo , 255 ) ,
bitops . band ( bitops . rshift ( lo , 8 ) , 255 ) ,
bitops . band ( bitops . rshift ( lo , 16 ) , 255 ) ,
bitops . band ( bitops . rshift ( lo , 24 ) , 255 ) ,
bitops . band ( hi , 255 ) ,
bitops . band ( bitops . rshift ( hi , 8 ) , 255 ) ,
bitops . band ( bitops . rshift ( hi , 16 ) , 255 ) ,
bitops . band ( bitops . rshift ( hi , 24 ) , 255 )
)
end

hash . xxh64 = xxh64
hash . hex64 = hex64

local __nuppExportValue= hash ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.hash"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.hash"]=__nuppExports;return __nuppExports