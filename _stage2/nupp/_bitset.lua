_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






















local bitset = { }
local ffi = require ( "ffi" )

const band = bit . band
const bnot = bit . bnot
const bor = bit . bor
const bxor = bit . bxor
const lshift = bit . lshift
const rshift = bit . rshift
const tobit = bit . tobit




bitset . WORD_BITS = 32



const BITS_PER_WORD = 32
const WORD_SHIFT = 5
const BIT_MASK = 31
const ALL_ONES = - 1
const DEFAULT_BITS = 64

const HALF_MASK = 0xFFFF
const HALF_SHIFT = 16










local POPCOUNT_HALF = ffi . new ( "uint8_t[65536]" )
local CTZ_HALF = ffi . new ( "uint8_t[65536]" )

do


POPCOUNT_HALF [ 0 ] = 0
for value = 1 , 65535 do
POPCOUNT_HALF [ value ] = POPCOUNT_HALF [ band ( value , value - 1 ) ] + 1
end



CTZ_HALF [ 0 ] = 16
for value = 1 , 65535 do
CTZ_HALF [ value ] = band ( value , 1 ) == 1 ? 0 : CTZ_HALF [ rshift ( value , 1 ) ] + 1
end
end


local function popcount ( word )
do
return (
POPCOUNT_HALF [ band ( word , HALF_MASK ) ] + POPCOUNT_HALF [ band ( rshift ( word , HALF_SHIFT ) , HALF_MASK ) ]
)
end
end


local function lowestBit ( word )
do
local half = band ( word , HALF_MASK )
if half ~= 0 then
return CTZ_HALF [ half ]
end

return ( HALF_SHIFT + CTZ_HALF [ band ( rshift ( word , HALF_SHIFT ) , HALF_MASK ) ] )
end
end


local function wordsFor ( bits )
local words = rshift ( bits + BIT_MASK , WORD_SHIFT )
return words < 1 ? 1 : words
end












bitset.Bitset = {} bitset.Bitset.__index = bitset.Bitset
























function bitset.Bitset:reserve(bits)
local needed = wordsFor ( bits )
if needed <= self . capacity then
return
end

local doubled = self . capacity * 2
local grown = needed > doubled ? needed : doubled
local fresh = ffi . new ( "uint32_t[?]" , grown )
ffi . copy ( fresh , self . words , self . capacity * 4 )
self . words = fresh
self . capacity = grown
end




function bitset.Bitset:set(index)




if index < 0 then
error ( "bitset index cannot be negative" , 2 )
end

local word = rshift ( index , WORD_SHIFT )
if word >= self . capacity then
self : reserve ( index + 1 )
end

do
local previous = tobit ( self . words [ word ] )
local mask = lshift ( 1 , band ( index , BIT_MASK ) )
if band ( previous , mask ) == 0 then
self . words [ word ] = bor ( previous , mask )
if not self . stale then
self . population = self . population + 1
end
if word >= self . used then
self . used = word + 1
end
end
end
end





function bitset.Bitset:clear(index)
local word = rshift ( index , WORD_SHIFT )
if word >= self . used then
return
end

do
local previous = tobit ( self . words [ word ] )
local mask = lshift ( 1 , band ( index , BIT_MASK ) )
if band ( previous , mask ) ~= 0 then
self . words [ word ] = band ( previous , bnot ( mask ) )
if not self . stale then
self . population = self . population - 1
end
end
end
end





function bitset.Bitset:get(index)
local word = rshift ( index , WORD_SHIFT )
if word >= self . used then
return false
end

do
return band ( tobit ( self . words [ word ] ) , lshift ( 1 , band ( index , BIT_MASK ) ) ) ~= 0
end
end







function bitset.Bitset:setRange(low, high)
if high < low then
return
end
if low < 0 then
error ( "bitset range cannot start below zero" , 2 )
end

self : reserve ( high + 1 )

local firstWord = rshift ( low , WORD_SHIFT )
local lastWord = rshift ( high , WORD_SHIFT )
local lowBit = band ( low , BIT_MASK )
local highBit = band ( high , BIT_MASK )
local head = bnot ( lshift ( 1 , lowBit ) - 1 )
local tail = highBit == BIT_MASK ? ALL_ONES : lshift ( 1 , highBit + 1 ) - 1










local exact = not self . stale
local added = 0


local words = self . words
local used = self . used
do
if firstWord == lastWord then
local old = tobit ( words [ firstWord ] )
local new = bor ( old , band ( head , tail ) )
words [ firstWord ] = new
if exact then
added = popcount ( new ) - popcount ( old )
end
else
local old = tobit ( words [ firstWord ] )
local new = bor ( old , head )
words [ firstWord ] = new
if exact then
added = popcount ( new ) - popcount ( old )
end



local lastMiddle = lastWord - 1
local reached = used - 1 < lastMiddle ? used - 1 : lastMiddle
local counted = reached < firstWord ? firstWord : reached
if exact then
for word = firstWord + 1 , counted do
added = added + BITS_PER_WORD - popcount ( tobit ( words [ word ] ) )
words [ word ] = ALL_ONES
end
if counted < lastMiddle then
added = added + BITS_PER_WORD * ( lastMiddle - counted )
end
for word = counted + 1 , lastMiddle do
words [ word ] = ALL_ONES
end
else
for word = firstWord + 1 , lastMiddle do
words [ word ] = ALL_ONES
end
end

old = tobit ( words [ lastWord ] )
new = bor ( old , tail )
words [ lastWord ] = new
if exact then
added = added + popcount ( new ) - popcount ( old )
end
end

if exact then
self . population = ( self . population + added )
end
end

if lastWord >= self . used then
self . used = lastWord + 1
end
end





function bitset.Bitset:count()
if not self . stale then
return self . population
end



local words = self . words
local total = 0
do
for word = 0 , self . used - 1 do
total = total + popcount ( tobit ( words [ word ] ) )
end
end
local resolved = total
self . population = resolved
self . stale = false

return resolved
end



function bitset.Bitset:isEmpty()
return self : count ( ) == 0
end



function bitset.Bitset:clearAll()
if self . used > 0 then
ffi . fill ( self . words , self . used * 4 , 0 )
self . used = 0
end
self . population = 0
self . stale = false
end




function bitset.Bitset:setOnly(index)
self : clearAll ( )
self : set ( index )
end





function bitset.Bitset:wordCount()
return self . used
end






function bitset.Bitset:wordAt(index)
if index < 0 or index >= self . used then
return 0
end

do
return tobit ( self . words [ index ] )
end
end







function bitset.Bitset:nextSetBit(from)
local start = from < 0 ? 0 : from
local first = rshift ( start , WORD_SHIFT )
local used = self . used
if first >= used then
return - 1
end

local words = self . words





do
local partial = tobit ( words [ first ] )
local offset = band ( start , BIT_MASK )
if offset ~= 0 then
partial = band ( partial , bnot ( lshift ( 1 , offset ) - 1 ) )
end
if partial ~= 0 then
return lshift ( first , WORD_SHIFT ) + lowestBit ( partial )
end

for word = first + 1 , used - 1 do
local bits = tobit ( words [ word ] )
if bits ~= 0 then
return lshift ( word , WORD_SHIFT ) + lowestBit ( bits )
end
end
end

return - 1
end


















function bitset.Bitset:positionsInto(target, capacity, from)
if capacity < 0 then
error ( "bitset target capacity cannot be negative" , 2 )
end

local start = from < 0 ? 0 : from
local first = rshift ( start , WORD_SHIFT )
local used = self . used
if first >= used then
return 0 , - 1
end
if capacity == 0 then
return 0 , start
end

local words = self . words
local offset = band ( start , BIT_MASK )
local written = 0



do
for word = first , used - 1 do
local bits = tobit ( words [ word ] )
if word == first and offset ~= 0 then
bits = band ( bits , bnot ( lshift ( 1 , offset ) - 1 ) )
end

local base = lshift ( word , WORD_SHIFT )
for _ = 1 , BITS_PER_WORD do
if bits == 0 then
break
end

local position = base + lowestBit ( bits )
if written >= capacity then
return written , position
end
target [ written ] = position
written = ( written + 1 )


bits = band ( bits , bits - 1 )
end
end
end

return written , - 1
end





function bitset.Bitset:containsAll(other)
local otherUsed = other . used
if otherUsed == 0 then
return true
end
if self . used < otherUsed then
return false
end

local words , theirWords = self . words , other . words
do
for word = 0 , otherUsed - 1 do
local theirs = tobit ( theirWords [ word ] )
if band ( tobit ( words [ word ] ) , theirs ) ~= theirs then
return false
end
end
end

return true
end





function bitset.Bitset:overlaps(other)
local limit = self . used < other . used ? self . used : other . used

local words , theirWords = self . words , other . words
do
for word = 0 , limit - 1 do
if band ( tobit ( words [ word ] ) , tobit ( theirWords [ word ] ) ) ~= 0 then
return true
end
end
end

return false
end




function bitset.Bitset:disjoint(other)
return not self : overlaps ( other )
end




function bitset.Bitset:copyFrom(other)
local otherUsed = other . used
if otherUsed > self . capacity then
self : reserve ( lshift ( otherUsed , WORD_SHIFT ) )
end

if otherUsed > 0 then
ffi . copy ( self . words , other . words , otherUsed * 4 )
end
local words = self . words
do
for word = otherUsed , self . used - 1 do
words [ word ] = 0
end
end

self . used = otherUsed
self . population = other . population
self . stale = other . stale
end







function bitset.Bitset:orWith(other)
local otherUsed = other . used
if otherUsed == 0 then
return
end
if otherUsed > self . capacity then
self : reserve ( lshift ( otherUsed , WORD_SHIFT ) )
end


local words , theirWords = self . words , other . words
do
for word = 0 , otherUsed - 1 do
words [ word ] = bor ( tobit ( words [ word ] ) , tobit ( theirWords [ word ] ) )
end
end

if otherUsed > self . used then
self . used = otherUsed
end
self . stale = true
end




function bitset.Bitset:andWith(other)
local used = self . used
if used == 0 then
return
end

local shared = used < other . used ? used : other . used
local words , theirWords = self . words , other . words
do
for word = 0 , shared - 1 do
words [ word ] = band ( tobit ( words [ word ] ) , tobit ( theirWords [ word ] ) )
end
for word = shared , used - 1 do
words [ word ] = 0
end
end



self . used = shared
self . stale = true
end




function bitset.Bitset:andNotWith(other)
local limit = self . used < other . used ? self . used : other . used
if limit == 0 then
return
end

local words , theirWords = self . words , other . words
do
for word = 0 , limit - 1 do
words [ word ] = band ( tobit ( words [ word ] ) , bnot ( tobit ( theirWords [ word ] ) ) )
end
end

self . stale = true
end



function bitset.Bitset:xorWith(other)
local otherUsed = other . used
if otherUsed == 0 then
return
end
if otherUsed > self . capacity then
self : reserve ( lshift ( otherUsed , WORD_SHIFT ) )
end

local words , theirWords = self . words , other . words
do
for word = 0 , otherUsed - 1 do
words [ word ] = bxor ( tobit ( words [ word ] ) , tobit ( theirWords [ word ] ) )
end
end

if otherUsed > self . used then
self . used = otherUsed
end
self . stale = true
end







function bitset . create ( capacityBits )
local words = wordsFor ( capacityBits ?? DEFAULT_BITS )

return setmetatable({ words =
ffi . new ( "uint32_t[?]" , words ) ,  capacity =
words ,  used =
0 ,  population =
0 ,  stale =
false }, bitset.Bitset)

end

return bitset
