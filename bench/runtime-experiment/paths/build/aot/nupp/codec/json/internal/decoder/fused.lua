_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitBor=bit.bor;local __nuppBitRshift=bit.rshift;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math"));const __nuppModule = require("nupp.simd"); local __nuppSwitchMap1={102,97,108,115};local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






























































local _valueBuilder = require ( "nupp.codec.valuebuilder" )
local _jsonBuilder = require ( "nupp.codec.json.internal.builder" )
local array = require ( "nupp.mem.array" )
local simd = require ( "nupp.simd" )


local fused = { }







local function nibbleTable (
zero ,
e0 ,
e1 ,
e2 ,
e3 ,
e4 ,
e5 ,
e6 ,
e7 ,
e8 ,
e9 ,
e10 ,
e11 ,
e12 ,
e13 ,
e14 ,
e15
) 
return __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", zero , 1 , e0 ) ,
2 , e1 ) ,
3 , e2 ) ,
4 , e3 ) ,
5 , e4 ) ,
6 , e5 ) ,
7 , e6 ) ,
8 , e7 ) ,
9 , e8 ) ,
10 , e9 ) ,
11 , e10 ) ,
12 , e11 ) ,
13 , e12 ) ,
14 , e13 ) ,
15 , e14 ) ,
16 , e15 )
end














local function decodeFused (
source ,
variant ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
local sourceCount = _valueBuilder . length ( source )
if sourceCount > 2147483647 then
return nullValue , 5 , 1
end

local tape = _valueBuilder . newWordScratch ( sourceCount )
local scanCursor = 0
local tapeCount = 0
local inString = false
local stringEscaped = false




local slashOdd = false
local haveSlash = false
local lastSlash = 0




local owed = 0
local constraint = 0
local haveNonAscii = false
local lastNonAscii = 0
local seeded = false


local previousNonAscii = false
local one = 1ULL



local vectorsOff = false






while scanCursor < sourceCount or not seeded do
local events = 0ULL
local width = 0
do local __nuppT3 = simd . vectors ( array . uint8 ) if __nuppT3 ~= nil then local species = __nuppT3
if not vectorsOff and (__nuppBitTobit(( scanCursor )+( species . lanes ))%4294967296) <= sourceCount then
local bytes = _valueBuilder . bytes ( source )
local block = species :load( bytes , (__nuppBitTobit(( scanCursor )+( 1 ))%4294967296) )
local structural = __nuppModule.lane.binary("|","mask", __nuppModule.lane.binary("|","mask", __nuppModule.lane.binary("|","mask", ( __nuppModule.lane.binary("==","uint8", block , 123 ) ) , ( __nuppModule.lane.binary("==","uint8", block , 125 ) ) ) , ( __nuppModule.lane.binary("==","uint8", block , 91 ) ) ) , ( __nuppModule.lane.binary("==","uint8", block , 93 ) ) )
local separators = __nuppModule.lane.binary("|","mask", ( __nuppModule.lane.binary("==","uint8", block , 58 ) ) , ( __nuppModule.lane.binary("==","uint8", block , 44 ) ) )
local strings = __nuppModule.lane.binary("|","mask", ( __nuppModule.lane.binary("==","uint8", block , 34 ) ) , ( __nuppModule.lane.binary("==","uint8", block , 92 ) ) )
local eventMask = __nuppModule.lane.binary("|","mask", __nuppModule.lane.binary("|","mask", __nuppModule.lane.binary("|","mask", structural , separators ) , strings ) , ( __nuppModule.lane.binary("<","uint8", block , 32 ) ) )
local validateUtf8 = false
if previousNonAscii then
events = __nuppModule.lane.method("bits","mask", eventMask )
validateUtf8 = true
else
local nonAscii = __nuppModule.lane.binary(">=","uint8", block , 128 )



events = __nuppModule.lane.method("bits","mask", ( __nuppModule.lane.binary("|","mask", eventMask , nonAscii ) ) )
if events ~= 0 then
validateUtf8 = __nuppModule.lane.method("any","mask", nonAscii )
if validateUtf8 then


events = __nuppModule.lane.method("bits","mask", eventMask )
end
end
end



if validateUtf8 then






local previous = species :load( bytes , (__nuppBitTobit(( (__nuppBitTobit(( scanCursor )-( species . lanes ))%4294967296) )+( 1 ))%4294967296) )
local previous1 = __nuppModule.lane.method("align","uint8", block , previous , 1 )
local previous2 = __nuppModule.lane.method("align","uint8", block , previous , 2 )
local previous3 = __nuppModule.lane.method("align","uint8", block , previous , 3 )








local zero = species :splat( 0 )
local byte1High = ( __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", zero , 1 , 2 ) , 2 , 2 ) , 3 , 2 ) , 4 , 2 ) , 5 , 2 ) , 6 , 2 ) , 7 , 2 ) , 8 , 2 ) , 9 , 128 ) , 10 , 128 ) , 11 , 128 ) , 12 , 128 ) , 13 , 33 ) , 14 , 1 ) , 15 , 21 ) , 16 , 73 ) )
local byte1Low = ( __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", zero , 1 , 231 ) , 2 , 163 ) , 3 , 131 ) , 4 , 131 ) , 5 , 139 ) , 6 , 203 ) , 7 , 203 ) , 8 , 203 ) , 9 , 203 ) , 10 , 203 ) , 11 , 203 ) , 12 , 203 ) , 13 , 203 ) , 14 , 219 ) , 15 , 203 ) , 16 , 203 )

















)
local byte2High = ( __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", zero , 1 , 1 ) , 2 , 1 ) , 3 , 1 ) , 4 , 1 ) , 5 , 1 ) , 6 , 1 ) , 7 , 1 ) , 8 , 1 ) , 9 , 230 ) , 10 , 174 ) , 11 , 186 ) , 12 , 186 ) , 13 , 1 ) , 14 , 1 ) , 15 , 1 ) , 16 , 1 ) )
local special =

__nuppModule.lane.binary("&","uint8", __nuppModule.lane.binary("&","uint8", __nuppModule.lane.method("swizzle","uint8", byte1High , __nuppModule.lane.binary("+","uint8", ( __nuppModule.lane.binary(">>","uint8", previous1 , 4 ) ) , 1 ) ) , __nuppModule.lane.method("swizzle","uint8", byte1Low , __nuppModule.lane.binary("+","uint8", ( __nuppModule.lane.binary("&","uint8", previous1 , 15 ) ) , 1 ) ) ) , __nuppModule.lane.method("swizzle","uint8", byte2High , __nuppModule.lane.binary("+","uint8", ( __nuppModule.lane.binary(">>","uint8", block , 4 ) ) , 1 ) ) )





local required = __nuppModule.lane.method("select","mask", ( __nuppModule.lane.binary("|","mask", ( __nuppModule.lane.binary(">=","uint8", previous2 , 224 ) ) , ( __nuppModule.lane.binary(">=","uint8", previous3 , 240 ) ) ) ) , 128 , 0 )
if __nuppModule.lane.method("any","mask", ( __nuppModule.lane.binary("~=","uint8", ( __nuppModule.lane.binary("~","uint8", special , required ) ) , 0 ) ) ) then







vectorsOff = true
else



previousNonAscii = __nuppModule.lane.method("extract","uint8", __nuppModule.lane.method("align","uint8", block , block , 1 ) , 1 ) >= 128
end
else
previousNonAscii = false
end
if not vectorsOff then
width = species . lanes
else
events = 0ULL
end
end
end end
if width == 0 and not seeded then





seeded = true
local back = 1
local walking = true
while walking and back <= 3 and back <= scanCursor do
local earlier = _valueBuilder . byte ( source , (__nuppBitTobit(( scanCursor )-( back ))%4294967296) )
if earlier < 128 then
walking = false
elseif earlier >= 192 then



if earlier < 194 or earlier > 244 then
return nullValue , 2 , (__nuppBitTobit(( (__nuppBitTobit(( scanCursor )-( back ))%4294967296) )+( 1 ))%4294967296)
end
local need = 3
if earlier <= 223 then
need = 1
elseif earlier <= 239 then
need = 2
end
if need >= back then
owed = (__nuppBitTobit(( (__nuppBitTobit(( need )-( back ))%4294967296) )+( 1 ))%4294967296)
haveNonAscii = true
lastNonAscii = (__nuppBitTobit(( scanCursor )-( 1 ))%4294967296)


if back == 1 then
if earlier == 224 then
constraint = 1
elseif earlier == 237 then
constraint = 2
elseif earlier == 240 then
constraint = 3
elseif earlier == 244 then
constraint = 4
end
end
end
walking = false
else
back = (__nuppBitTobit(( back )+( 1 ))%4294967296)
end
end
elseif width == 0 then



if scanCursor < sourceCount then
local byte = _valueBuilder . byteAt ( source , scanCursor )
if byte == 34
or byte == 92
or byte < 32
or byte == 123
or byte == 125
or byte == 91
or byte == 93
or byte == 58
or byte == 44
or byte >= 128
then
events = one
end
end
width = 1
end

while events ~= 0 do
local lane = nupp . math . u64 . trailingZeros ( events )
events = events & ( events - 1 )
local position = (__nuppBitTobit(( scanCursor )+( lane ))%4294967296)
if position < sourceCount then
local byte = _valueBuilder . byteAt ( source , position )



if owed ~= 0 and ( not haveNonAscii or position ~= (__nuppBitTobit(( lastNonAscii )+( 1 ))%4294967296) ) then
return nullValue , 2 , (__nuppBitTobit(( lastNonAscii )+( 2 ))%4294967296)
end
if byte >= 128 then
local isContinuation = byte <= 191
if owed ~= 0 then
if not isContinuation then
return nullValue , 2 , (__nuppBitTobit(( position )+( 1 ))%4294967296)
end
local constrained = constraint == 1 and byte < 160
or constraint == 2 and byte > 159
or constraint == 3 and byte < 144
or constraint == 4 and byte > 143
if constrained then
return nullValue , 2 , (__nuppBitTobit(( position )+( 1 ))%4294967296)
end
owed = (__nuppBitTobit(( owed )-( 1 ))%4294967296)
constraint = 0
elseif isContinuation or byte < 194 or byte > 244 then
return nullValue , 2 , (__nuppBitTobit(( position )+( 1 ))%4294967296)
elseif byte <= 223 then
owed = 1
elseif byte <= 239 then
owed = 2
if byte == 224 then
constraint = 1
elseif byte == 237 then
constraint = 2
end
else
owed = 3
if byte == 240 then
constraint = 3
elseif byte == 244 then
constraint = 4
end
end
haveNonAscii = true
lastNonAscii = position
haveSlash = false
slashOdd = false
elseif owed ~= 0 then

return nullValue , 2 , (__nuppBitTobit(( position )+( 1 ))%4294967296)
elseif byte == 92 then
if not inString then
return nullValue , 4 , (__nuppBitTobit(( position )+( 1 ))%4294967296)
end
if haveSlash and position == (__nuppBitTobit(( lastSlash )+( 1 ))%4294967296) then
slashOdd = not slashOdd
else
slashOdd = true
end
haveSlash = true
lastSlash = position
stringEscaped = true
else
local escaped = haveSlash and position == (__nuppBitTobit(( lastSlash )+( 1 ))%4294967296) and slashOdd
if byte == 34 and not escaped then



if inString then
local word = position
if stringEscaped then
word = (__nuppBitBor( position , 2147483648 )%4294967296)
end
_valueBuilder . setScratchWord ( tape , tapeCount , word )
inString = false
else
_valueBuilder . setScratchWord ( tape , tapeCount , position )
inString = true
stringEscaped = false
end
tapeCount = (__nuppBitTobit(( tapeCount )+( 1 ))%4294967296)
elseif byte < 32 then
local whitespace = byte == 9 or byte == 10 or byte == 13
if inString or not whitespace then
return nullValue , 3 , (__nuppBitTobit(( position )+( 1 ))%4294967296)
end
elseif not inString then


_valueBuilder . setScratchWord ( tape , tapeCount , position )
tapeCount = (__nuppBitTobit(( tapeCount )+( 1 ))%4294967296)
end
haveSlash = false
slashOdd = false
end
end
end

scanCursor = (__nuppBitTobit(( scanCursor )+( width ))%4294967296)
end

if owed ~= 0 then


return nullValue , 2 , (__nuppBitTobit(( lastNonAscii )+( 2 ))%4294967296)
end

local builderDepth = 1024
if sourceCount <= 32 then
builderDepth = 16
end
local __nuppT4= variant ; local __nuppT5;
if  __nuppT4== 0  then  __nuppT5= _jsonBuilder . newPull (
nullValue ,
builderDepth ,
sourceCount ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
)
elseif  __nuppT4== 1  then  __nuppT5= _jsonBuilder . newSerde (
nullValue ,
builderDepth ,
sourceCount ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
)
else  __nuppT5= _valueBuilder . newSized ( nullValue , builderDepth , sourceCount , arrayMarker , objectMarker )
end; local values = __nuppT5
local cursor = 0
tapeCount = _valueBuilder . scratchLength ( tape )
local tapeCursor = 0
local needValue = true
local done = false





local pending = 0
while not done do
local skipping = true
pending = 0
while skipping and cursor < sourceCount do
pending = _valueBuilder . byteAt ( source , cursor )
if pending == 32 or pending == 9 or pending == 10 or pending == 13 then
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
else
skipping = false
end
end

if needValue then
if cursor >= sourceCount then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end

local tag = 0
local start = cursor
local length = 0
local flags = 0
local containerCapacity = 0
local byte = pending

if byte == 34 then
tag = 4
if tapeCursor < tapeCount then
local opening = _valueBuilder . scratchWord ( tape , tapeCursor )
if opening ~= cursor then
return nullValue , 5 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
else
return nullValue , 5 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
if tapeCursor < tapeCount then
local closingWord = _valueBuilder . scratchWord ( tape , tapeCursor )
local closing = (__nuppBitBand( closingWord , 2147483647 )%4294967296)
if (__nuppBitBand( closingWord , 2147483648 )%4294967296) ~= 0 then
flags = 1
end
start = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
length = (__nuppBitTobit(( closing )-( start ))%4294967296)



cursor = (__nuppBitTobit(( closing )+( 1 ))%4294967296)
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
else
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
elseif byte == 91 or byte == 123 then
if _valueBuilder . depth ( values ) >= builderDepth then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
if byte == 91 then
tag = 5
else
tag = 6
end
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
if tapeCursor < tapeCount then
if byte == 123 then


containerCapacity = 4
elseif _valueBuilder . depth ( values ) == 0 then




containerCapacity = (__nuppBitRshift( sourceCount ,__nuppBitBand( 5 ,31))%4294967296)
if containerCapacity > 262144 then
containerCapacity = 262144
end
else
containerCapacity = 4
end
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
else
return nullValue , 5 , cursor
end
elseif byte == 116 then
tag = 1
local matched = 0
while matched < 4 do
local at = (__nuppBitTobit(( cursor )+( matched ))%4294967296)
if at < sourceCount then
local actual = _valueBuilder . byteAt ( source , at )
local __nuppT6= matched ; local __nuppT7;
if  __nuppT6== 0  then  __nuppT7= 116
elseif  __nuppT6== 1  then  __nuppT7= 114
elseif  __nuppT6== 2  then  __nuppT7= 117
else  __nuppT7= 101
end; local expected = __nuppT7
if actual ~= expected then
return nullValue , 1 , (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
else
return nullValue , 1 , (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
matched = (__nuppBitTobit(( matched )+( 1 ))%4294967296)
end
length = 4
cursor = (__nuppBitTobit(( cursor )+( 4 ))%4294967296)
elseif byte == 102 then
tag = 2
local matched = 0
while matched < 5 do
local at = (__nuppBitTobit(( cursor )+( matched ))%4294967296)
if at < sourceCount then
local actual = _valueBuilder . byteAt ( source , at )
local __nuppT8=__nuppSwitchMap1[ matched +1]; if __nuppT8==nil then __nuppT8=101 end; local expected = __nuppT8






if actual ~= expected then
return nullValue , 1 , (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
else
return nullValue , 1 , (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
matched = (__nuppBitTobit(( matched )+( 1 ))%4294967296)
end
length = 5
cursor = (__nuppBitTobit(( cursor )+( 5 ))%4294967296)
elseif byte == 110 then
tag = 0
local matched = 0
while matched < 4 do
local at = (__nuppBitTobit(( cursor )+( matched ))%4294967296)
if at < sourceCount then
local actual = _valueBuilder . byteAt ( source , at )
local __nuppT9= matched ; local __nuppT10;
if  __nuppT9== 0  then  __nuppT10= 110
elseif  __nuppT9== 1  then  __nuppT10= 117
else  __nuppT10= 108
end; local expected = __nuppT10
if actual ~= expected then
return nullValue , 1 , (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
else
return nullValue , 1 , (__nuppBitTobit(( at )+( 1 ))%4294967296)
end
matched = (__nuppBitTobit(( matched )+( 1 ))%4294967296)
end
length = 4
cursor = (__nuppBitTobit(( cursor )+( 4 ))%4294967296)
elseif byte == 45 or byte >= 48 and byte <= 57 then
tag = 3
local parsed = _jsonBuilder . numberToken ( values , source , cursor , sourceCount )
if parsed < 2147483648 then
return nullValue , 1 , parsed
end
cursor = (__nuppBitTobit(( parsed )-( 2147483648 ))%4294967296)
length = (__nuppBitTobit(( cursor )-( start ))%4294967296)
else
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end

if tag == 0 then
_valueBuilder . null ( values )
elseif tag == 1 then
_valueBuilder . boolean ( values , true )
elseif tag == 2 then
_valueBuilder . boolean ( values , false )
elseif tag == 4 then
_valueBuilder . string ( values , source , start , length , flags == 1 )
elseif tag == 5 then
_valueBuilder . openArray ( values , containerCapacity )
elseif tag == 6 then
_valueBuilder . openObject ( values , containerCapacity )
end
needValue = false
elseif _valueBuilder . depth ( values ) == 0 then
if cursor < sourceCount then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
done = true
else
if cursor >= sourceCount then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
local builderState = _valueBuilder . state ( values )
local byte = pending
local kind = (__nuppBitBand( builderState , 255 )%4294967296)
local hasValue = (__nuppBitBand( builderState , 256 )%4294967296) ~= 0
local closing = kind == 5 and byte == 93 or kind == 6 and byte == 125
if closing then
if tapeCursor >= tapeCount or _valueBuilder . scratchWord ( tape , tapeCursor ) ~= cursor then
return nullValue , 5 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
_valueBuilder . close ( values )
elseif kind == 5 then
if not hasValue then
needValue = true
elseif byte == 44 then
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
if tapeCursor >= tapeCount then
return nullValue , 5 , cursor
end
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
needValue = true
else
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
else
if hasValue then
if byte ~= 44 then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
if tapeCursor >= tapeCount then
return nullValue , 5 , cursor
end
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
local keySkipping = true
while keySkipping and cursor < sourceCount do
local keyByte = _valueBuilder . byteAt ( source , cursor )
if keyByte == 32 or keyByte == 9 or keyByte == 10 or keyByte == 13 then
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
else
keySkipping = false
end
end
end
if cursor >= sourceCount or _valueBuilder . byte ( source , cursor ) ~= 34 then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
local opening = cursor
if tapeCursor >= tapeCount or _valueBuilder . scratchWord ( tape , tapeCursor ) ~= opening then
return nullValue , 5 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
if tapeCursor >= tapeCount then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
local closingWord = _valueBuilder . scratchWord ( tape , tapeCursor )
local closingQuote = (__nuppBitBand( closingWord , 2147483647 )%4294967296)
local escaped = (__nuppBitBand( closingWord , 2147483648 )%4294967296) ~= 0
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
local keyStart = (__nuppBitTobit(( opening )+( 1 ))%4294967296)
local keyLength = (__nuppBitTobit(( closingQuote )-( keyStart ))%4294967296)
_valueBuilder . key ( values , source , keyStart , keyLength , escaped )
cursor = (__nuppBitTobit(( closingQuote )+( 1 ))%4294967296)
local colonSkipping = true
while colonSkipping and cursor < sourceCount do
local colonByte = _valueBuilder . byteAt ( source , cursor )
if colonByte == 32 or colonByte == 9 or colonByte == 10 or colonByte == 13 then
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
else
colonSkipping = false
end
end
if cursor >= sourceCount or _valueBuilder . byte ( source , cursor ) ~= 58 then
return nullValue , 1 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
if tapeCursor >= tapeCount or _valueBuilder . scratchWord ( tape , tapeCursor ) ~= cursor then
return nullValue , 5 , (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
end
cursor = (__nuppBitTobit(( cursor )+( 1 ))%4294967296)
tapeCursor = (__nuppBitTobit(( tapeCursor )+( 1 ))%4294967296)
needValue = true
end
end
end

return _valueBuilder . finish ( values ) , 0 , 0
end


function fused . decodePull (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
return decodeFused ( source , 0 , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end




function fused . decodeSerde (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
return decodeFused ( source , 1 , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end


function fused . decodeEager (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
return decodeFused ( source , 2 , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end

local __nuppExportValue= fused ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.json.internal.decoder.fused"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json.internal.decoder.fused"]=__nuppExports;return __nuppExports