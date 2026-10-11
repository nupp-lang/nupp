_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.compiler.runtime.math"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local install;__nuppExports["install"]=function(...) return install(...) end;
























local bitops = require ( "nupp.runtime.bitops" )

const band = bitops . band
const bnot = bitops . bnot
const bor = bitops . bor
const bxor = bitops . bxor
const lshift = bitops . lshift
const rshift = bitops . rshift
const arshift = bitops . arshift


const tobit = bitops . tobit or function ( value ) 
return band ( value , -1 )
end

const rol = bitops . rol or function ( value , count ) 
local places = count % 32

return bor ( lshift ( value , places ) , rshift ( value , ( 32 - places ) % 32 ) )
end
const ror = bitops . ror or function ( value , count ) 
local places = count % 32

return bor ( rshift ( value , places ) , lshift ( value , ( 32 - places ) % 32 ) )
end

const pi = math . pi
const tau = 2 * math . pi









local function ui32 ( value ) 
return tobit ( value ) % 4294967296
end






local function mul32 ( a , c ) 
local al , cl = a % 65536 , c % 65536
local ah , ch = math . floor ( a / 65536 ) , math . floor ( c / 65536 )

return tobit ( al * cl + ( ( ah * cl + al * ch ) % 65536 ) * 65536 )
end

const CANON = 2143289344
const PINF = 2139095040
const NINF = 4286578688
const MAX = 2139095039
const NMAX = 4286578687
const SIGN = 2147483648


local function nanbits ( bits ) 
return band ( bits , 2139095040 ) == 2139095040 and band ( bits , 8388607 ) ~= 0
end







local function decode32 ( bits ) 
local sign = 1
if bits >= 2147483648 then
sign , bits = -1 , bits - 2147483648
end
local exponent = ( bits - bits % 8388608 ) / 8388608
local significand = bits % 8388608
if exponent == 255 then
if significand == 0 then
return sign * ( 1 / 0 )
end








return math . abs ( 0 / 0 )
elseif exponent == 0 then
return sign * significand * 2 ^ -149
end

return sign * ( significand + 8388608 ) * 2 ^ ( exponent - 150 )
end






local function encode32 ( value ) 
if value ~= value then
return 2143289344
end
local sign = 0
if value < 0 or ( value == 0 and 1 / value < 0 ) then
sign , value = 2147483648 , - value
end
if value == 1 / 0 then
return sign + 2139095040
end
if value == 0 then
return sign
end

local exponent = 0
if value >= 2 then
while value >= 2 do
value , exponent = value / 2 , exponent + 1
end
else
while value < 1 do
value , exponent = value * 2 , exponent - 1
end
end
local biased = exponent + 127
local significand
if biased <= 0 then


significand = value * 2 ^ ( exponent + 149 )
biased = 0
else
significand = value * 8388608
end
local whole = significand - significand % 1
local fraction = significand - whole
if fraction > 0.5 or ( fraction == 0.5 and whole % 2 == 1 ) then
whole = whole + 1
end
if biased == 0 then


return sign + whole
end
if whole == 16777216 then
whole , biased = 8388608 , biased + 1
end
if biased >= 255 then
return sign + 2139095040
end

return sign + biased * 8388608 + ( whole - 8388608 )
end






local function putbits ( bits ) 
return decode32 ( ( band ( bits , 2139095040 ) == 2139095040 and band ( bits , 8388607 ) ~= 0 ) and 2143289344 or bits )
end


local function bits32 ( value ) 
return encode32 ( value )
end


local function round32 ( value ) 
return decode32 ( encode32 ( value ) )
end







local function narrow32 ( value ) 
if value ~= value then
return value
end

return decode32 ( encode32 ( value ) )
end


local function comparedd ( hi , lo , value ) 
local difference = hi - value
if difference > - lo then
return 1
elseif difference < - lo then
return -1
end

return 0
end


local function nextup ( value , bits ) 
if bits == 2139095040 then
return value , bits
end
if bits == 4286578688 then
return ( decode32 ( ( band ( 4286578687 , 2139095040 ) == 2139095040 and band ( 4286578687 , 8388607 ) ~= 0 ) and 2143289344 or 4286578687 ) ) , 4286578687
end
local stepped
if band ( bits , 2147483648 ) ~= 0 then
if bits == 2147483648 then
return ( decode32 ( ( band ( 1 , 2139095040 ) == 2139095040 and band ( 1 , 8388607 ) ~= 0 ) and 2143289344 or 1 ) ) , 1
end
stepped = bits - 1
else
stepped = bits + 1
end

return putbits ( stepped ) , stepped
end


local function nextdown ( value , bits ) 
if bits == 4286578688 then
return value , bits
end
if bits == 2139095040 then
return ( decode32 ( ( band ( 2139095039 , 2139095040 ) == 2139095040 and band ( 2139095039 , 8388607 ) ~= 0 ) and 2143289344 or 2139095039 ) ) , 2139095039
end
local stepped
if band ( bits , 2147483648 ) ~= 0 then
stepped = bits + 1
else
if bits == 0 then
return ( decode32 ( ( band ( 2147483649 , 2139095040 ) == 2139095040 and band ( 2147483649 , 8388607 ) ~= 0 ) and 2143289344 or 2147483649 ) ) , 2147483649
end
stepped = bits - 1
end

return putbits ( stepped ) , stepped
end







local function rounddd ( hi , lo ) 
local value = ( decode32 ( encode32 ( hi ) ) )
local bits = ( encode32 ( value ) )
if ( band ( bits , 2139095040 ) == 2139095040 and band ( bits , 8388607 ) ~= 0 ) then
return ( decode32 ( ( band ( 2143289344 , 2139095040 ) == 2139095040 and band ( 2143289344 , 8388607 ) ~= 0 ) and 2143289344 or 2143289344 ) )
end


if bits == 2139095040 then
return comparedd ( hi , lo , 3.4028235677973366e38 ) < 0 and ( decode32 ( ( band ( 2139095039 , 2139095040 ) == 2139095040 and band ( 2139095039 , 8388607 ) ~= 0 ) and 2143289344 or 2139095039 ) ) or value
elseif bits == 4286578688 then
return comparedd ( hi , lo , - 3.4028235677973366e38 ) > 0 and ( decode32 ( ( band ( 4286578687 , 2139095040 ) == 2139095040 and band ( 4286578687 , 8388607 ) ~= 0 ) and 2143289344 or 4286578687 ) ) or value
end
local side = comparedd ( hi , lo , value )
if side == 0 then
return value
end
local step = side > 0 and nextup or nextdown
local other , otherbits = step ( value , bits )
local toward = comparedd ( hi , lo , ( value + other ) * 0.5 )
if side < 0 then
toward = - toward
end
if toward > 0 or toward == 0 and band ( bits , 1 ) ~= 0 then
return ( decode32 ( ( band ( otherbits , 2139095040 ) == 2139095040 and band ( otherbits , 8388607 ) ~= 0 ) and 2143289344 or otherbits ) )
end

return value
end


local i32 = { }

function i32 . wrap ( a ) 
return tobit ( a )
end

function i32 . add ( a , c ) 
return tobit ( a + c )
end

function i32 . sub ( a , c ) 
return tobit ( a - c )
end

function i32 . mul ( a , c ) 
return mul32 ( ( tobit ( a ) % 4294967296 ) , ( tobit ( c ) % 4294967296 ) )
end

function i32 . andBits ( a , c ) 
return band ( a , c )
end

function i32 . orBits ( a , c ) 
return bor ( a , c )
end

function i32 . xorBits ( a , c ) 
return bxor ( a , c )
end

function i32 . notBits ( a ) 
return bnot ( a )
end

function i32 . shiftLeft ( a , c ) 
return lshift ( a , band ( c , 31 ) )
end

function i32 . shiftRightArithmetic ( a , c ) 
return arshift ( a , band ( c , 31 ) )
end

function i32 . rotateLeft ( a , c ) 
return rol ( a , band ( c , 31 ) )
end

function i32 . rotateRight ( a , c ) 
return ror ( a , band ( c , 31 ) )
end

function i32 . lessThan ( a , c ) 
return tobit ( a ) < tobit ( c )
end

function i32 . lessOrEqual ( a , c ) 
return tobit ( a ) <= tobit ( c )
end

function i32 . fromU32 ( a ) 
return tobit ( a )
end

function i32 . toU32 ( a ) 
return ( tobit ( a ) % 4294967296 )
end


local u32 = { }

function u32 . wrap ( a ) 
return ( tobit ( a ) % 4294967296 )
end

function u32 . add ( a , c ) 
return ( tobit ( ( a + c ) ) % 4294967296 )
end

function u32 . sub ( a , c ) 
return ( tobit ( ( a - c ) ) % 4294967296 )
end

function u32 . mul ( a , c ) 
return ui32 ( mul32 ( ( tobit ( a ) % 4294967296 ) , ( tobit ( c ) % 4294967296 ) ) )
end


function u32 . div ( a , c ) 
local divisor = ( tobit ( c ) % 4294967296 )
return divisor == 0 and 0 or math . floor ( ( tobit ( a ) % 4294967296 ) / divisor )
end


function u32 . mod ( a , c ) 
local divisor = ( tobit ( c ) % 4294967296 )
return divisor == 0 and 0 or ( tobit ( a ) % 4294967296 ) % divisor
end

function u32 . andBits ( a , c ) 
return ui32 ( band ( a , c ) )
end

function u32 . orBits ( a , c ) 
return ui32 ( bor ( a , c ) )
end

function u32 . xorBits ( a , c ) 
return ui32 ( bxor ( a , c ) )
end

function u32 . notBits ( a ) 
return ui32 ( bnot ( a ) )
end

function u32 . shiftLeft ( a , c ) 
return ui32 ( lshift ( a , band ( c , 31 ) ) )
end

function u32 . shiftRightLogical ( a , c ) 
return ui32 ( rshift ( a , band ( c , 31 ) ) )
end

function u32 . rotateLeft ( a , c ) 
return ui32 ( rol ( a , band ( c , 31 ) ) )
end

function u32 . rotateRight ( a , c ) 
return ui32 ( ror ( a , band ( c , 31 ) ) )
end

function u32 . lessThan ( a , c ) 
return ( tobit ( a ) % 4294967296 ) < ( tobit ( c ) % 4294967296 )
end

function u32 . lessOrEqual ( a , c ) 
return ( tobit ( a ) % 4294967296 ) <= ( tobit ( c ) % 4294967296 )
end

function u32 . fromI32 ( a ) 
return ( tobit ( a ) % 4294967296 )
end

function u32 . toI32 ( a ) 
return tobit ( a )
end

function u32 . popcount ( a ) 
local remaining = ( tobit ( a ) % 4294967296 )
local count = 0
while remaining ~= 0 do
remaining = ui32 ( band ( remaining , remaining - 1 ) )
count = count + 1
end

return count
end

function u32 . trailingZeros ( a ) 
local remaining = ( tobit ( a ) % 4294967296 )
if remaining == 0 then
return 32
end
local count = 0
while band ( remaining , 1 ) == 0 do
remaining = rshift ( remaining , 1 )
count = count + 1
end

return count
end

function u32 . leadingZeros ( a ) 
local remaining = ( tobit ( a ) % 4294967296 )
if remaining == 0 then
return 32
end
local count = 0
local probe = 2147483648
while band ( remaining , probe ) == 0 do
probe = rshift ( probe , 1 )
count = count + 1
end

return count
end


local u64 = { }

function u64 . andBits ( a , b ) 
return a & b
end

function u64 . sub ( a , b ) 
return a - b
end

function u64 . rotateLeft ( a , count ) 
local amount = band ( count , 63 )
return ( a << amount ) | ( a >> band ( - amount , 63 ) )
end

function u64 . rotateRight ( a , count ) 
local amount = band ( count , 63 )
return ( a >> amount ) | ( a << band ( - amount , 63 ) )
end




function u64 . popcount ( a ) 
local remaining = a
local count = 0
while remaining ~= 0ULL do
remaining = remaining & ( remaining - 1ULL )
count = count + 1
end

return count
end

function u64 . trailingZeros ( a ) 
local remaining = a
if remaining == 0ULL then
return 64
end
local count = 0
while ( remaining & 1ULL ) == 0ULL do
remaining = remaining >> 1ULL
count = count + 1
end

return count
end

function u64 . leadingZeros ( a ) 
if a == 0ULL then
return 64
end
local count = 0
local probe = 9223372036854775808ULL
while ( a & probe ) == 0ULL do
probe = probe >> 1ULL
count = count + 1
end

return count
end

function u64 . prefixXor ( a ) 
local bits = a
bits = bits ~ ( bits << 1ULL )
bits = bits ~ ( bits << 2ULL )
bits = bits ~ ( bits << 4ULL )
bits = bits ~ ( bits << 8ULL )
bits = bits ~ ( bits << 16ULL )
bits = bits ~ ( bits << 32ULL )

return bits
end


local f32 = { }

function f32 . narrow ( a ) 
return narrow32 ( a )
end

function f32 . round ( a ) 
return ( decode32 ( encode32 ( a ) ) )
end

function f32 . add ( a , c ) 
return round32 ( ( decode32 ( encode32 ( a ) ) ) + ( decode32 ( encode32 ( c ) ) ) )
end

function f32 . sub ( a , c ) 
return round32 ( ( decode32 ( encode32 ( a ) ) ) - ( decode32 ( encode32 ( c ) ) ) )
end

function f32 . mul ( a , c ) 
return round32 ( ( decode32 ( encode32 ( a ) ) ) * ( decode32 ( encode32 ( c ) ) ) )
end

function f32 . div ( a , c ) 
return round32 ( ( decode32 ( encode32 ( a ) ) ) / ( decode32 ( encode32 ( c ) ) ) )
end

function f32 . sqrt ( a ) 
return round32 ( math . sqrt ( ( decode32 ( encode32 ( a ) ) ) ) )
end


function f32 . min ( a , c ) 
local left , right = ( decode32 ( encode32 ( a ) ) ) , ( decode32 ( encode32 ( c ) ) )
if left ~= left or right ~= right then
return ( decode32 ( ( band ( 2143289344 , 2139095040 ) == 2139095040 and band ( 2143289344 , 8388607 ) ~= 0 ) and 2143289344 or 2143289344 ) )
end
if left == right then
if left == 0 and ( band ( ( encode32 ( left ) ) , 2147483648 ) ~= 0 or band ( ( encode32 ( right ) ) , 2147483648 ) ~= 0 ) then
return ( decode32 ( ( band ( 2147483648 , 2139095040 ) == 2139095040 and band ( 2147483648 , 8388607 ) ~= 0 ) and 2143289344 or 2147483648 ) )
end

return left
end

return left < right and left or right
end


function f32 . max ( a , c ) 
local left , right = ( decode32 ( encode32 ( a ) ) ) , ( decode32 ( encode32 ( c ) ) )
if left ~= left or right ~= right then
return ( decode32 ( ( band ( 2143289344 , 2139095040 ) == 2139095040 and band ( 2143289344 , 8388607 ) ~= 0 ) and 2143289344 or 2143289344 ) )
end
if left == right then
if left == 0 and band ( ( encode32 ( left ) ) , 2147483648 ) ~= 0 and band ( ( encode32 ( right ) ) , 2147483648 ) ~= 0 then
return ( decode32 ( ( band ( 2147483648 , 2139095040 ) == 2139095040 and band ( 2147483648 , 8388607 ) ~= 0 ) and 2143289344 or 2147483648 ) )
elseif left == 0 then
return ( decode32 ( ( band ( 0 , 2139095040 ) == 2139095040 and band ( 0 , 8388607 ) ~= 0 ) and 2143289344 or 0 ) )
end

return left
end

return left > right and left or right
end






function f32 . fma ( a , c , d ) 
local left , right , addend = ( decode32 ( encode32 ( a ) ) ) , ( decode32 ( encode32 ( c ) ) ) , ( decode32 ( encode32 ( d ) ) )
local product = left * right
if product ~= product or product == math . huge or product == - math . huge then
return ( decode32 ( encode32 ( ( product + addend ) ) ) )
end
local sum = product + addend
local carry = sum - product

return rounddd ( sum , ( product - ( sum - carry ) ) + ( addend - carry ) )
end







function f32 . exp ( value ) 
local x = f32 . max ( -104 , f32 . min ( value , 88 ) )
local y = f32 . mul ( x , 0.0078125 )
local out = f32 . narrow ( 0.0000000020876757 )
out = f32 . fma ( out , y , 0.000000025052108 )
out = f32 . fma ( out , y , 0.00000027557319 )
out = f32 . fma ( out , y , 0.0000027557319 )
out = f32 . fma ( out , y , 0.000024801587 )
out = f32 . fma ( out , y , 0.0001984127 )
out = f32 . fma ( out , y , 0.0013888889 )
out = f32 . fma ( out , y , 0.0083333333 )
out = f32 . fma ( out , y , 0.041666667 )
out = f32 . fma ( out , y , 0.16666667 )
out = f32 . fma ( out , y , 0.5 )
out = f32 . fma ( out , y , 1 )
out = f32 . fma ( out , y , 1 )
for _ = 1 , 7 do
out = f32 . mul ( out , out )
end

return out
end

function f32 . fromBits ( bits ) 
return putbits ( ( tobit ( bits ) % 4294967296 ) )
end

function f32 . toBits ( value ) 
return bits32 ( ( decode32 ( encode32 ( value ) ) ) )
end


function f32 . fromF16Bits ( value ) 
local bits = ( tobit ( value ) % 4294967296 ) % 65536
local sign = bits >= 32768 and 2147483648 or 0
local magnitude = bits % 32768
local exponent = math . floor ( magnitude / 1024 )
local mantissa = magnitude % 1024
if exponent == 31 then
return putbits ( mantissa == 0 and sign + 2139095040 or 2143289344 )
elseif exponent == 0 then
if mantissa == 0 then
return ( decode32 ( ( band ( sign , 2139095040 ) == 2139095040 and band ( sign , 8388607 ) ~= 0 ) and 2143289344 or sign ) )
end
local unbiased = -14
while mantissa < 1024 do
mantissa = mantissa * 2
unbiased = unbiased - 1
end
mantissa = mantissa - 1024

return putbits ( sign + ( unbiased + 127 ) * 8388608 + mantissa * 8192 )
end

return putbits ( sign + ( exponent + 112 ) * 8388608 + mantissa * 8192 )
end


function f32 . toF16Bits ( value ) 
local bits = bits32 ( ( decode32 ( encode32 ( value ) ) ) )
local sign = bits >= 2147483648 and 32768 or 0
local magnitude = bits % 2147483648
if magnitude >= 2139095040 then
return magnitude == 2139095040 and sign + 31744 or 32256
end
if magnitude >= 1199566848 then
return sign + 31744
end
if magnitude < 855638016 then
return sign
end

local exponent = math . floor ( magnitude / 8388608 )
local mantissa = magnitude % 8388608
if exponent >= 113 then
local out = sign + ( exponent - 112 ) * 1024 + math . floor ( mantissa / 8192 )
local remainder = mantissa % 8192
if remainder > 4096 or remainder == 4096 and out % 2 == 1 then
out = out + 1
end

return out
end

local significant = mantissa + 8388608
local shift = 126 - exponent
local divisor = 2 ^ shift
local out = math . floor ( significant / divisor )
local remainder = significant % divisor
local halfway = divisor / 2
if remainder > halfway or remainder == halfway and out % 2 == 1 then
out = out + 1
end

return sign + out
end


function f32 . fromBF16Bits ( value ) 
local bits = ( ( tobit ( value ) % 4294967296 ) % 65536 ) * 65536
local magnitude = bits % 2147483648
if magnitude > 2139095040 then
bits = 2143289344
end

return putbits ( bits )
end


function f32 . toBF16Bits ( value ) 
local bits = bits32 ( ( decode32 ( encode32 ( value ) ) ) )
local magnitude = bits % 2147483648
if magnitude > 2139095040 then
return 32704
end
local upper = math . floor ( bits / 65536 )
local lower = bits % 65536
if lower > 32768 or lower == 32768 and upper % 2 == 1 then
upper = ( upper + 1 ) % 65536
end

return upper
end






local vec2 = { }

function vec2 . add ( ax , ay , bx , by ) 
return ax + bx , ay + by
end

function vec2 . sub ( ax , ay , bx , by ) 
return ax - bx , ay - by
end

function vec2 . scale ( x , y , factor ) 
return x * factor , y * factor
end

function vec2 . dot ( ax , ay , bx , by ) 
return ax * bx + ay * by
end

function vec2 . cross ( ax , ay , bx , by ) 
return ax * by - ay * bx
end

function vec2 . lengthSquared ( x , y ) 
return x * x + y * y
end

function vec2 . length ( x , y ) 
return math . sqrt ( x * x + y * y )
end

function vec2 . distanceSquared ( ax , ay , bx , by ) 
local x , y = bx - ax , by - ay

return x * x + y * y
end

function vec2 . distance ( ax , ay , bx , by ) 
return math . sqrt ( vec2 . distanceSquared ( ax , ay , bx , by ) )
end

function vec2 . normalize ( x , y ) 
local length = vec2 . length ( x , y )
if length == 0 then
return 0 , 0
end

return x / length , y / length
end

function vec2 . lerp ( ax , ay , bx , by , t ) 
if t == 0 then
return ax , ay
elseif t == 1 then
return bx , by
end

return ax + ( bx - ax ) * t , ay + ( by - ay ) * t
end


function vec2 . moveTowards ( ax , ay , bx , by , distance ) 
if distance <= 0 then
return ax , ay
end
local x , y = bx - ax , by - ay
local squared = x * x + y * y
if squared == 0 or squared <= distance * distance then
return bx , by
end
local factor = distance / math . sqrt ( squared )

return ax + x * factor , ay + y * factor
end

function vec2 . rotate ( x , y , radians ) 
local c , s = math . cos ( radians ) , math . sin ( radians )

return x * c - y * s , x * s + y * c
end







local function atan2 ( y , x ) 
if x > 0 then
return math . atan ( y / x )
elseif x < 0 then


local below = y < 0 or ( y == 0 and 1 / y < 0 )

return math . atan ( y / x ) + ( below and - pi or pi )
elseif y > 0 then
return pi / 2
elseif y < 0 then
return - pi / 2
end

return 0
end

function vec2 . angle ( x , y ) 
if x == 0 and y == 0 then
return 0
end

return atan2 ( y , x )
end


function vec2 . angleBetween ( ax , ay , bx , by ) 
if ( ax == 0 and ay == 0 ) or ( bx == 0 and by == 0 ) then
return 0
end

return atan2 ( math . abs ( vec2 . cross ( ax , ay , bx , by ) ) , vec2 . dot ( ax , ay , bx , by ) )
end


function vec2 . signedAngleBetween ( ax , ay , bx , by ) 
if ( ax == 0 and ay == 0 ) or ( bx == 0 and by == 0 ) then
return 0
end
local turn = atan2 ( vec2 . cross ( ax , ay , bx , by ) , vec2 . dot ( ax , ay , bx , by ) )

return turn == pi and - pi or turn
end


function vec2 . project ( x , y , ox , oy ) 
local squared = ox * ox + oy * oy
if squared == 0 then
return 0 , 0
end
local factor = ( x * ox + y * oy ) / squared

return ox * factor , oy * factor
end


function vec2 . reflect ( x , y , nx , ny ) 
local squared = nx * nx + ny * ny
if squared == 0 then
return x , y
end
local factor = 2 * ( x * nx + y * ny ) / squared

return x - nx * factor , y - ny * factor
end
















local quat = { }


function quat . identity ( ) 
return 0 , 0 , 0 , 1
end

function quat . add (
ax ,
ay ,
az ,
aw ,
bx ,
by ,
bz ,
bw
) 
return ax + bx , ay + by , az + bz , aw + bw
end

function quat . sub (
ax ,
ay ,
az ,
aw ,
bx ,
by ,
bz ,
bw
) 
return ax - bx , ay - by , az - bz , aw - bw
end

function quat . scale ( x , y , z , w , factor ) 
return x * factor , y * factor , z * factor , w * factor
end

function quat . dot (
ax ,
ay ,
az ,
aw ,
bx ,
by ,
bz ,
bw
) 
return ax * bx + ay * by + az * bz + aw * bw
end

function quat . lengthSquared ( x , y , z , w ) 
return x * x + y * y + z * z + w * w
end

function quat . length ( x , y , z , w ) 
return math . sqrt ( x * x + y * y + z * z + w * w )
end






function quat . normalize ( x , y , z , w ) 
local length = math . sqrt ( x * x + y * y + z * z + w * w )
if length == 0 then
return 0 , 0 , 0 , 1
end

return x / length , y / length , z / length , w / length
end


function quat . conjugate ( x , y , z , w ) 
return - x , - y , - z , w
end






function quat . inverse ( x , y , z , w ) 
local squared = x * x + y * y + z * z + w * w
if squared == 0 then
return 0 , 0 , 0 , 1
end

return - x / squared , - y / squared , - z / squared , w / squared
end





function quat . multiply (
ax ,
ay ,
az ,
aw ,
bx ,
by ,
bz ,
bw
) 
local x = aw * bx + ax * bw + ay * bz - az * by
local y = aw * by - ax * bz + ay * bw + az * bx
local z = aw * bz + ax * by - ay * bx + az * bw
local w = aw * bw - ax * bx - ay * by - az * bz

return x , y , z , w
end






function quat . rotate (
qx ,
qy ,
qz ,
qw ,
x ,
y ,
z
) 
local tx = 2 * ( qy * z - qz * y )
local ty = 2 * ( qz * x - qx * z )
local tz = 2 * ( qx * y - qy * x )

return x + qw * tx + qy * tz - qz * ty , y + qw * ty + qz * tx - qx * tz , z + qw * tz + qx * ty - qy * tx
end





function quat . fromAxisAngle ( x , y , z , radians ) 
local length = math . sqrt ( x * x + y * y + z * z )
if length == 0 then
return 0 , 0 , 0 , 1
end
local half = radians / 2
local factor = math . sin ( half ) / length

return x * factor , y * factor , z * factor , math . cos ( half )
end







function quat . toAxisAngle ( x , y , z , w ) 
local length = math . sqrt ( x * x + y * y + z * z )
if length == 0 then
return 1 , 0 , 0 , w < 0 and 2 * pi or 0
end
local clamped = w < -1 and -1 or ( w > 1 and 1 or w )

return x / length , y / length , z / length , 2 * math . acos ( clamped )
end






function quat . fromTo (
ax ,
ay ,
az ,
bx ,
by ,
bz
) 
local alength = math . sqrt ( ax * ax + ay * ay + az * az )
local blength = math . sqrt ( bx * bx + by * by + bz * bz )
if alength == 0 or blength == 0 then
return 0 , 0 , 0 , 1
end
local ux , uy , uz = ax / alength , ay / alength , az / alength
local vx , vy , vz = bx / blength , by / blength , bz / blength
local d = ux * vx + uy * vy + uz * vz
local cx , cy , cz = uy * vz - uz * vy , uz * vx - ux * vz , ux * vy - uy * vx
local clength = math . sqrt ( cx * cx + cy * cy + cz * cz )
if d < 0 then
if clength == 0 then



local px , py , pz = 0 , 0 , 0
if math . abs ( ux ) <= math . abs ( uy ) and math . abs ( ux ) <= math . abs ( uz ) then
px = 1
elseif math . abs ( uy ) <= math . abs ( uz ) then
py = 1
else
pz = 1
end
cx , cy , cz = uy * pz - uz * py , uz * px - ux * pz , ux * py - uy * px
clength = math . sqrt ( cx * cx + cy * cy + cz * cz )

return cx / clength , cy / clength , cz / clength , 0
end




local clamped = d < -1 and -1 or d
local sinHalf = math . sqrt ( ( 1 - clamped ) / 2 )
local factor = sinHalf / clength

return cx * factor , cy * factor , cz * factor , clength / ( 2 * sinHalf )
end


local sw = 1 + d
local length = math . sqrt ( cx * cx + cy * cy + cz * cz + sw * sw )

return cx / length , cy / length , cz / length , sw / length
end







function quat . nlerp (
ax ,
ay ,
az ,
aw ,
bx ,
by ,
bz ,
bw ,
t
) 
if t == 0 then
return ax , ay , az , aw
end
local sign = ax * bx + ay * by + az * bz + aw * bw < 0 and -1 or 1
local u = 1 - t

return quat . normalize (
ax * u + bx * sign * t ,
ay * u + by * sign * t ,
az * u + bz * sign * t ,
aw * u + bw * sign * t
)
end








function quat . slerp (
ax ,
ay ,
az ,
aw ,
bx ,
by ,
bz ,
bw ,
t
) 
if t == 0 then
return ax , ay , az , aw
end
local d = ax * bx + ay * by + az * bz + aw * bw
local sign = 1
if d < 0 then
d , sign = - d , -1
end
if d > 1 then
d = 1
end
local u , v = 1 - t , t
if d < 0.9995 then
local angle = math . acos ( d )
local inverse = 1 / math . sin ( angle )
u , v = math . sin ( u * angle ) * inverse , math . sin ( t * angle ) * inverse
end

return quat . normalize (
ax * u + bx * sign * v ,
ay * u + by * sign * v ,
az * u + bz * sign * v ,
aw * u + bw * sign * v
)
end






function quat . basis (
x ,
y ,
z ,
w
) 
local xx , yy , zz = x * x , y * y , z * z
local xy , xz , yz = x * y , x * z , y * z
local wx , wy , wz = w * x , w * y , w * z

local m00 , m10 , m20 = 1 - 2 * ( yy + zz ) , 2 * ( xy + wz ) , 2 * ( xz - wy )
local m01 , m11 , m21 = 2 * ( xy - wz ) , 1 - 2 * ( xx + zz ) , 2 * ( yz + wx )
local m02 , m12 , m22 = 2 * ( xz + wy ) , 2 * ( yz - wx ) , 1 - 2 * ( xx + yy )

return m00 , m10 , m20 , m01 , m11 , m21 , m02 , m12 , m22
end






function quat . toMatrix ( x , y , z , w , out , offset ) 
local m00 , m10 , m20 , m01 , m11 , m21 , m02 , m12 , m22 = quat . basis ( x , y , z , w )
out [ offset ] , out [ offset + 1 ] , out [ offset + 2 ] , out [ offset + 3 ] = m00 , m10 , m20 , 0
out [ offset + 4 ] , out [ offset + 5 ] , out [ offset + 6 ] , out [ offset + 7 ] = m01 , m11 , m21 , 0
out [ offset + 8 ] , out [ offset + 9 ] , out [ offset + 10 ] , out [ offset + 11 ] = m02 , m12 , m22 , 0
out [ offset + 12 ] , out [ offset + 13 ] , out [ offset + 14 ] , out [ offset + 15 ] = 0 , 0 , 0 , 1
end





local function lerp ( from , to , t ) 
if t == 0 then
return from
elseif t == 1 then
return to
end

return from + ( to - from ) * t
end


local function wrapAngle ( radians ) 
return ( radians + pi ) % tau - pi
end


local function deltaAngle ( from , to ) 
return ( ( ( to - from ) + pi ) % tau - pi )
end







install=function ( namespace ) 
namespace . lerp = lerp
namespace . wrapAngle = wrapAngle
namespace . deltaAngle = deltaAngle
namespace . i32 = i32
namespace . u32 = u32
namespace . u64 = u64
namespace . f32 = f32
namespace . vec2 = vec2
namespace . quat = quat
end ;__nuppExports["install"]=install
 end);if not __nuppOk then package.loaded["nupp.compiler.runtime.math"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.runtime.math"]=__nuppExports;return __nuppExports