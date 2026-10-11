_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.util.internal.bitset\0runtime\0001") };

local data = { }
local bit = require ( "nupp.runtime.bitops" )
local physical = require ( "nupp.runtime.storage" )
const band = bit . band
const bnot = bit . bnot
const bor = bit . bor
const bxor = bit . bxor
const lshift = bit . lshift
const rshift = bit . rshift
const tobit = bit . tobit or function ( value ) 
return band ( value , -1 )
end
data . WORD_BITS = 32
const BITS_PER_WORD = 32
const WORD_SHIFT = 5
const BIT_MASK = 31
const ALL_ONES = 4294967295
const DEFAULT_BITS = 64





const MAX_INDEX = 2147483647

const HALF_MASK = 65535
const HALF_SHIFT = 16















local POPCOUNT_HALF = nil
local CTZ_HALF = nil

local function buildTables ( ) 
if POPCOUNT_HALF ~= nil then
return
end
local population = physical . allocateBytes ( 65536 )
local trailing = physical . allocateBytes ( 65536 )
do


population [ 0 ] = 0
for value = 1 , 65535 do
population [ value ] = (__nuppBitTobit(( population [ band ( value , value - 1 ) ] )+( 1 ))%4294967296)
end




trailing [ 0 ] = 16
for value = 1 , 65535 do
trailing [ value ] = band ( value , 1 ) == 1 ? 0 : (__nuppBitTobit(( trailing [ rshift ( value , 1 ) ] )+( 1 ))%4294967296)
end
end
POPCOUNT_HALF = population
CTZ_HALF = trailing
end





local function popcount ( word ) 
local halves = POPCOUNT_HALF
do
return ( (__nuppBitTobit(( halves [ band ( word , 65535 ) ] )+( halves [ band ( rshift ( word , 16 ) , 65535 ) ] ))%4294967296) )
end
end


local function lowestBit ( word ) 
local halves = CTZ_HALF
do
local half = band ( word , 65535 )
if half ~= 0 then
return halves [ half ]
end

return ( (__nuppBitTobit(( 16 )+( halves [ band ( rshift ( word , 16 ) , 65535 ) ] ))%4294967296) )
end
end



local function wordsFor ( bits ) 
local words = math . floor ( ( bits + 31 ) / 32 )
return words >= 1 ? words : 1
end



local function isPosition ( index ) 
return index % 1 == 0 and index >= 0 and index <= 2147483647
end








data.Bitset = {} data.Bitset.__index = data.Bitset


























function data.Bitset.__nuppCtor1(capacityBits) local self = _G.setmetatable({}, data.Bitset)  local __nuppT8=self; 
local bits = capacityBits ?? DEFAULT_BITS
if bits > MAX_INDEX + 1 then
error ( "nupp: bitset cannot hold more than 2^31 bits" , 2 )
end
buildTables ( )
local words = wordsFor ( bits )
self . words = physical . allocateArray ( physical . scalar ( "uint32" ) , words )
self . capacity = words
self . used = 0
self . population = 0
self . stale = false
return __nuppT8 end






function data.Bitset:reserve(bits) 
if not ( bits <= MAX_INDEX + 1 ) then
error ( "nupp: bitset cannot hold more than 2^31 bits" , 2 )
end
local needed = wordsFor ( bits )
if needed <= self . capacity then
return
end

local doubled = self . capacity * 2
local grown = needed > doubled ? needed : doubled
local fresh = physical . allocateArray ( physical . scalar ( "uint32" ) , grown )
physical . copy ( fresh , self . words , self . capacity * 4 )
self . words = fresh
self . capacity = grown
end




function data.Bitset:set(index) 




if not ( index % 1 == 0 and index >= 0 and index <= 2147483647 ) then
error ( "nupp: bitset index cannot be negative, fractional or past 2^31 - 1" , 2 )
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





function data.Bitset:clear(index) 
if not ( index % 1 == 0 and index >= 0 and index <= 2147483647 ) then
return
end
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





function data.Bitset:get(index) 
if not ( index % 1 == 0 and index >= 0 and index <= 2147483647 ) then
return false
end
local word = rshift ( index , WORD_SHIFT )
if word >= self . used then
return false
end

do
return band ( tobit ( self . words [ word ] ) , lshift ( 1 , band ( index , BIT_MASK ) ) ) ~= 0
end
end








function data.Bitset:setRange(low, high) 
if high < low then
return
end
if not ( low % 1 == 0 and low >= 0 and low <= 2147483647 ) then
error ( "nupp: bitset range cannot start below zero or at a non-integer" , 2 )
end
if not ( high % 1 == 0 and high >= 0 and high <= 2147483647 ) then
error ( "nupp: bitset range must end at an integer no greater than 2^31 - 1" , 2 )
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





function data.Bitset:count() 
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



function data.Bitset:isEmpty() 
return self : count ( ) == 0
end



function data.Bitset:clearAll() 
if self . used > 0 then
physical . fill ( self . words , self . used * 4 , 0 )
self . used = 0
end
self . population = 0
self . stale = false
end





function data.Bitset:setOnly(index) 
if not ( index % 1 == 0 and index >= 0 and index <= 2147483647 ) then
error ( "nupp: bitset index cannot be negative, fractional or past 2^31 - 1" , 2 )
end
self : clearAll ( )
self : set ( index )
end





function data.Bitset:wordCount() 
return self . used
end






function data.Bitset:wordAt(index) 
if not ( index >= 0 and index < self . used ) then
return 0
end

do
return tobit ( self . words [ index ] )
end
end







function data.Bitset:nextSetBit(from) 
local start = from < 0 ? 0 : from
if not ( start <= MAX_INDEX ) then
return - 1
end
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


















function data.Bitset:positionsInto(target, capacity, from) 
if capacity < 0 then
error ( "nupp: bitset target capacity cannot be negative" , 2 )
end

local start = from < 0 ? 0 : from
if not ( start <= MAX_INDEX ) then
return 0 , - 1
end
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
do break end
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





function data.Bitset:containsAll(other) 
local otherUsed = other . used
if otherUsed == 0 then
return true
end

local shared = self . used < otherUsed ? self . used : otherUsed
local words , theirWords = self . words , other . words
do
for word = 0 , shared - 1 do
local theirs = tobit ( theirWords [ word ] )
if band ( tobit ( words [ word ] ) , theirs ) ~= theirs then
return false
end
end



for word = shared , otherUsed - 1 do
if tobit ( theirWords [ word ] ) ~= 0 then
return false
end
end
end

return true
end





function data.Bitset:overlaps(other) 
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




function data.Bitset:disjoint(other) 
return not self : overlaps ( other )
end




function data.Bitset:copyFrom(other) 
local otherUsed = other . used
if otherUsed > self . capacity then
self : reserve ( otherUsed * BITS_PER_WORD )
end

if otherUsed > 0 then
physical . copy ( self . words , other . words , otherUsed * 4 )
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







function data.Bitset:orWith(other) 
local otherUsed = other . used
if otherUsed == 0 then
return
end
if otherUsed > self . capacity then
self : reserve ( otherUsed * BITS_PER_WORD )
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




function data.Bitset:andWith(other) 
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




function data.Bitset:andNotWith(other) 
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



function data.Bitset:xorWith(other) 
local otherUsed = other . used
if otherUsed == 0 then
return
end
if otherUsed > self . capacity then
self : reserve ( otherUsed * BITS_PER_WORD )
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
end ;_G.nupp.__reflect.link(data.Bitset,__nuppT1[1],{ })


local __nuppExportValue= data ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.util.internal.bitset"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.util.internal.bitset"]=__nuppExports;return __nuppExports