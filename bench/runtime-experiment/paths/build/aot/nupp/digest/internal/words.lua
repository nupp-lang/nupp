_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.digest.internal.words"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local create;__nuppExports["create"]=function(...) return create(...) end;












const bit = require ( "nupp.runtime.bitops" )
const span = require ( "nupp.mem.span" )
const hex = require ( "nupp.codec.hex" )
const streaming = require ( "nupp.digest.internal.streaming" )
const constants = require ( "nupp.digest.internal.constants" )

local function unsigned ( value ) 
return value < 0 and value + 4294967296 or value
end

local function add64 ( ah , al , bh , bl ) 
local low = ( al < 0 and al + 4294967296 or al ) + ( bl < 0 and bl + 4294967296 or bl )
return bit . tobit ( ah + bh + math . floor ( low / 4294967296 ) ) , bit . tobit ( low )
end

local function rotate64 ( h , l , n ) 
if n == 32 then
return l , h
end
if n > 32 then
h , l , n = l , h , n - 32
end

return bit . bor ( bit . rshift ( h , n ) , bit . lshift ( l , 32 - n ) ) , bit . bor ( bit . rshift ( l , n ) , bit . lshift ( h , 32 - n ) )
end

local function shift64 ( h , l , n ) 
return bit . rshift ( h , n ) , bit . bor ( bit . rshift ( l , n ) , bit . lshift ( h , 32 - n ) )
end

local function sigma ( h , l , a , b , c , small ) 
local ah , al = rotate64 ( h , l , a )
local bh , bl = rotate64 ( h , l , b )
local ch
local cl
if small then
ch , cl = shift64 ( h , l , c )
else
ch , cl = rotate64 ( h , l , c )
end

return bit . bxor ( ah , bh , ch ) , bit . bxor ( al , bl , cl )
end

local Engine = {} Engine.__index = Engine












local function readWord ( bytes , at , little ) 
local a , b , c , d = bytes : byte ( at , at + 3 )
if little then
a , b , c , d = d , c , b , a
end

return bit . tobit ( ( ( a * 256 + b ) * 256 + c ) * 256 + d )
end

local function md5 ( self ) 
local state , words = self . state , self . schedule
local a , b , c , d = state [ 1 ] , state [ 2 ] , state [ 3 ] , state [ 4 ]
local shifts = constants . md5Shifts
for round = 0 , 63 do
local f
local g
if round < 16 then
f , g = bit . bor ( bit . band ( b , c ) , bit . band ( bit . bnot ( b ) , d ) ) , round
elseif round < 32 then
f , g = bit . bor ( bit . band ( d , b ) , bit . band ( bit . bnot ( d ) , c ) ) , ( 5 * round + 1 ) % 16
elseif round < 48 then
f , g = bit . bxor ( b , c , d ) , ( 3 * round + 5 ) % 16
else
f , g = bit . bxor ( c , bit . bor ( b , bit . bnot ( d ) ) ) , ( 7 * round ) % 16
end
local rotated = bit . rol ( bit . tobit ( a + f + constants . md5 [ round + 1 ] + words [ g + 1 ] ) , shifts [ round + 1 ] )
a , d , c , b = d , c , b , bit . tobit ( b + rotated )
end
state [ 1 ] , state [ 2 ] = bit . tobit ( state [ 1 ] + a ) , bit . tobit ( state [ 2 ] + b )
state [ 3 ] , state [ 4 ] = bit . tobit ( state [ 3 ] + c ) , bit . tobit ( state [ 4 ] + d )
end

local function sha1 ( self ) 
local state , words = self . state , self . schedule
for i = 17 , 80 do
words [ i ] = bit . rol ( bit . bxor ( words [ i - 3 ] , words [ i - 8 ] , words [ i - 14 ] , words [ i - 16 ] ) , 1 )
end
local a , b , c , d , e = state [ 1 ] , state [ 2 ] , state [ 3 ] , state [ 4 ] , state [ 5 ]
for i = 1 , 80 do
local f
local k
if i <= 20 then
f , k = bit . bor ( bit . band ( b , c ) , bit . band ( bit . bnot ( b ) , d ) ) , 1518500249
elseif i <= 40 then
f , k = bit . bxor ( b , c , d ) , 1859775393
elseif i <= 60 then
f , k = bit . bor ( bit . band ( b , c ) , bit . band ( b , d ) , bit . band ( c , d ) ) , 2400959708
else
f , k = bit . bxor ( b , c , d ) , 3395469782
end
local temp = bit . tobit ( bit . rol ( a , 5 ) + f + e + k + words [ i ] )
e , d , c , b , a = d , c , bit . rol ( b , 30 ) , a , temp
end
state [ 1 ] , state [ 2 ] , state [ 3 ] = bit . tobit ( state [ 1 ] + a ) , bit . tobit ( state [ 2 ] + b ) , bit . tobit ( state [ 3 ] + c )
state [ 4 ] , state [ 5 ] = bit . tobit ( state [ 4 ] + d ) , bit . tobit ( state [ 5 ] + e )
end

local function sha512 ( self ) 
local s , w , k = self . state , self . schedule , constants . sha512
for i = 17 , 80 do
local at = i * 2 - 1
local xh , xl = sigma ( w [ at - 30 ] , w [ at - 29 ] , 1 , 8 , 7 , true )
local yh , yl = sigma ( w [ at - 4 ] , w [ at - 3 ] , 19 , 61 , 6 , true )
local h , l = add64 ( w [ at - 32 ] , w [ at - 31 ] , xh , xl )
h , l = add64 ( h , l , w [ at - 14 ] , w [ at - 13 ] )
w [ at ] , w [ at + 1 ] = add64 ( h , l , yh , yl )
end
local ah , al , bh , bl , ch , cl , dh , dl = s [ 1 ] , s [ 2 ] , s [ 3 ] , s [ 4 ] , s [ 5 ] , s [ 6 ] , s [ 7 ] , s [ 8 ]
local eh , el , fh , fl , gh , gl , hh , hl = s [ 9 ] , s [ 10 ] , s [ 11 ] , s [ 12 ] , s [ 13 ] , s [ 14 ] , s [ 15 ] , s [ 16 ]
for i = 1 , 80 do
local at = i * 2 - 1
local sh , sl = sigma ( eh , el , 14 , 18 , 41 , false )
local th , tl = add64 ( hh , hl , sh , sl )
th , tl = add64 (
th ,
tl ,
bit . bxor ( bit . band ( eh , fh ) , bit . band ( bit . bnot ( eh ) , gh ) ) ,
bit . bxor ( bit . band ( el , fl ) , bit . band ( bit . bnot ( el ) , gl ) )
)
th , tl = add64 ( th , tl , k [ at ] , k [ at + 1 ] )
th , tl = add64 ( th , tl , w [ at ] , w [ at + 1 ] )
sh , sl = sigma ( ah , al , 28 , 34 , 39 , false )
sh , sl = add64 (
sh ,
sl ,
bit . bxor ( bit . band ( ah , bh ) , bit . band ( ah , ch ) , bit . band ( bh , ch ) ) ,
bit . bxor ( bit . band ( al , bl ) , bit . band ( al , cl ) , bit . band ( bl , cl ) )
)
hh , hl , gh , gl , fh , fl = gh , gl , fh , fl , eh , el
eh , el = add64 ( dh , dl , th , tl )
dh , dl , ch , cl , bh , bl = ch , cl , bh , bl , ah , al
ah , al = add64 ( th , tl , sh , sl )
end
s [ 1 ] , s [ 2 ] = add64 ( s [ 1 ] , s [ 2 ] , ah , al )
s [ 3 ] , s [ 4 ] = add64 ( s [ 3 ] , s [ 4 ] , bh , bl )
s [ 5 ] , s [ 6 ] = add64 ( s [ 5 ] , s [ 6 ] , ch , cl )
s [ 7 ] , s [ 8 ] = add64 ( s [ 7 ] , s [ 8 ] , dh , dl )
s [ 9 ] , s [ 10 ] = add64 ( s [ 9 ] , s [ 10 ] , eh , el )
s [ 11 ] , s [ 12 ] = add64 ( s [ 11 ] , s [ 12 ] , fh , fl )
s [ 13 ] , s [ 14 ] = add64 ( s [ 13 ] , s [ 14 ] , gh , gl )
s [ 15 ] , s [ 16 ] = add64 ( s [ 15 ] , s [ 16 ] , hh , hl )
end

local function compress ( self , bytes , offset ) 
local count = self . name == "sha512" and 32 or 16
for i = 1 , count do
self . schedule [ i ] = readWord ( bytes , offset + ( i - 1 ) * 4 , self . name == "md5" )
end
if self . name == "md5" then
md5 ( self )
elseif self . name == "sha1" then
sha1 ( self )
else
sha512 ( self )
end
end

function Engine . update ( self , bytes ) 
local block = self . name == "sha512" and 128 or 64
local length = self . low + # bytes
self . low = length % 4294967296
self . high = ( self . high + math . floor ( length / 4294967296 ) ) % 4294967296
local offset = 1
if # self . tail > 0 then
local needed = block - # self . tail
if # bytes < needed then
self . tail = self . tail .. bytes ;
return self
end
compress ( self , self . tail .. bytes : sub ( 1 , needed ) , 1 )
self . tail = ""
offset = needed + 1
end
while offset + block - 1 <= # bytes do
compress ( self , bytes , offset )
offset = offset + block
end
if offset <= # bytes then
self . tail = bytes : sub ( offset )
end

return self
end

local function encodedWord ( value , little ) 
local v = ( value < 0 and value + 4294967296 or value )
local a , b , c , d = math . floor ( v / 16777216 ) % 256 , math . floor ( v / 65536 ) % 256 , math . floor ( v / 256 ) % 256 , v % 256
if little then
return string . char ( d , c , b , a )
end

return string . char ( a , b , c , d )
end

local function finish ( self ) 
local block = self . name == "sha512" and 128 or 64
local lengthSize = self . name == "sha512" and 16 or 8
local little = self . name == "md5"
local low = bit . tobit ( self . low * 8 )
local high = bit . tobit ( self . high * 8 + math . floor ( self . low / 536870912 ) )
local length = little and ( encodedWord ( low , true ) .. encodedWord ( high , true ) )
or ( encodedWord ( high , false ) .. encodedWord ( low , false ) )
if lengthSize == 16 then

length = encodedWord ( 0 , false ) .. encodedWord ( math . floor ( self . high / 536870912 ) , false ) .. length
end
local tail = self . tail .. "€"
tail = tail .. string . rep ( "\0" , ( block - lengthSize - # tail % block ) % block ) .. length
for offset = 1 , # tail , block do
compress ( self , tail , offset )
end
self . tail = ""
end

function Engine . writeDigest ( self , destination ) 
finish ( self )
local little = self . name == "md5"
for word = 1 , # self . state do
local value = unsigned ( self . state [ word ] )
for byte = 0 , 3 do
local shift = little and byte * 8 or 24 - byte * 8
destination :set( ( word - 1 ) * 4 + byte + 1 , math . floor ( value / 2 ^ shift ) % 256 )
end
end
end

function Engine . digest ( self ) 
finish ( self )
local bytes = { }
for _ , word in ipairs ( self . state ) do
bytes [ # bytes + 1 ] = encodedWord ( word , self . name == "md5" )
end

return table . concat ( bytes )
end

function Engine . hex ( self ) 
return hex . encode ( self : digest ( ) )
end

create=function ( name ) 
local state = { }
local initial = name == "sha512" and constants . sha512Initial or { 0x67452301 , 0xefcdab89 , 0x98badcfe , 0x10325476 }
for i , word in ipairs ( initial ) do
state [ i ] = bit . tobit ( word )
end
if name == "sha1" then
state [ 5 ] = bit . tobit ( 0xc3d2e1f0 )
end

return ( _G.setmetatable({ name =  name ,  state =  state ,  schedule =  { } ,  tail =  "" ,  low =  0 ,  high =  0 }, Engine) )
end ;__nuppExports["create"]=create
 end);if not __nuppOk then package.loaded["nupp.digest.internal.words"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.digest.internal.words"]=__nuppExports;return __nuppExports