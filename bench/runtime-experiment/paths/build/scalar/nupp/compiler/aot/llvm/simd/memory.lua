_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.simd.memory\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.simd.memory\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.simd.memory\0runtime\0003") };
















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local expressions = require ( "nupp.compiler.aot.llvm.expressions" )
local lanes = require ( "nupp.compiler.aot.llvm.simd.lanes" )
local prelude = require ( "nupp.compiler.aot.llvm.prelude" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local simdbounds = require ( "nupp.compiler.aot.simdbounds" )
local species = require ( "nupp.compiler.aot.llvm.simd.species" )
local types = require ( "nupp.compiler.aot.llvm.types" )

local memory = { }






local function wholeLoad ( ctx , found , address , align ) 
local count = found . lanes
local powerOfTwo = count > 0 and ( count & ( count - 1 ) ) == 0
if ctx . vectorRegister ~= "" or powerOfTwo then
return context . value ( ctx , ("load %s, ptr %s, align %d") : format ( found . vector , address , align ) )
end
local vector = "poison"
local laneAlign = math . max ( math . floor ( found . bits / 8 ) , 1 )
for lane = 0 , count - 1 do
local at = context . value ( ctx , ("getelementptr inbounds %s, ptr %s, i32 %d") : format ( found . scalar , address , lane ) )
local value = context . value ( ctx , ("load %s, ptr %s, align %d") : format ( found . scalar , at , laneAlign ) )
vector = context . value (
ctx ,
("insertelement %s %s, %s %s, i32 %d") : format ( found . vector , vector , found . scalar , value , lane )
)
end

return vector
end



function memory . first ( ctx , offset ) 
if offset . op == "int_to_f64" then
local inner = ( offset ) . value
local value , t = expressions . value ( ctx , inner )
local wide = expressions . convert ( ctx , value , t , types . signed ( t ) and "i64" or "u64" )
local positive = types . signed ( t ) and context . value ( ctx , ("icmp sgt i64 %s, 0") : format ( wide ) )
or context . value ( ctx , ("icmp ne i64 %s, 0") : format ( wide ) )
local less = context . value ( ctx , ("sub i64 %s, 1") : format ( wide ) )

return context . value ( ctx , ("select i1 %s, i64 %s, i64 -1") : format ( positive , less ) )
end
local value , t = expressions . value ( ctx , offset )
local x = expressions . convert ( ctx , value , t , "f64" )
local floor = prelude . intrinsic ( ctx . module , "llvm.floor.f64" , "double @NAME(double)" )
local atLeastOne = context . value ( ctx , ("fcmp oge double %s, 1.0") : format ( x ) )
local floored = context . value ( ctx , ("call double %s(double %s)") : format ( floor , x ) )
local integral = context . value ( ctx , ("fcmp oeq double %s, %s") : format ( x , floored ) )
local less = context . value ( ctx , ("fsub double %s, 1.0") : format ( x ) )

local small = context . value ( ctx , ("fcmp olt double %s, 0x43F0000000000000") : format ( less ) )
local both = context . value ( ctx , ("and i1 %s, %s") : format ( atLeastOne , integral ) )
local valid = context . value ( ctx , ("and i1 %s, %s") : format ( both , small ) )
local converted = context . value ( ctx , ("fptoui double %s to i64") : format ( less ) )

return context . value ( ctx , ("select i1 %s, i64 %s, i64 -1") : format ( valid , converted ) )
end


memory.Window = {} memory.Window.__index = memory.Window ;_G.nupp.__reflect.link(memory.Window,__nuppT1[1],{ })
















function memory . window (
ctx ,
name ,
first ,
width ,
storage
) 
local span = ctx . spans [ name ]
if span == nil then
error ( "no span " .. name , 0 )
end
local count = context . count ( ctx , name )
local inside = context . value ( ctx , ("icmp ult i64 %s, %s") : format ( first , count ) )
local left = context . value ( ctx , ("sub i64 %s, %s") : format ( count , first ) )
local capped = context . value (
ctx ,
("select i1 %s, i64 %s, i64 %d")

: format ( context . value ( ctx , ("icmp ult i64 %s, %d") : format ( left , width ) ) , left , width )
)
local room64 = context . value ( ctx , ("select i1 %s, i64 %s, i64 0") : format ( inside , capped ) )
local room = context . value ( ctx , ("trunc i64 %s to i32") : format ( room64 ) )
local start = context . value ( ctx , ("select i1 %s, i64 %s, i64 0") : format ( inside , first ) )
local address = context . value (
ctx ,
("getelementptr inbounds %s, ptr %s, i64 %s") : format ( storage , ( span ) . pointer , start )
)

return ( _G.setmetatable({ address =  address ,  room =  room ,  first =  first ,  inside =  inside }, memory.Window) )
end


local function roomMask ( ctx , count , room ) 
local bound = lanes . splat ( ctx , count , "i32" , room )

return context . value ( ctx , ("icmp ult %s, %s") : format ( lanes . indices ( count , "i32" ) , bound ) )
end



local function choose (
ctx ,
condition ,
resultType ,
yes ,
no
) 
local f = ctx . f
local yesLabel = builder . label ( f , "simd.yes" )
local noLabel = builder . label ( f , "simd.no" )
local joinLabel = builder . label ( f , "simd.join" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( condition , yesLabel , noLabel ) )
builder . start ( f , yesLabel )
local a = yes ( )
local aEnd = f . current
builder . jump ( f , joinLabel )
builder . start ( f , noLabel )
local b = no ( )
local bEnd = f . current
builder . start ( f , joinLabel )
if resultType == nil then
return nil
end

return context . value (
ctx ,
("phi %s [ %s, %%%s ], [ %s, %%%s ]") : format ( resultType , tostring ( a ) , aEnd , tostring ( b ) , bEnd )
)
end



local function split (
ctx ,
window ,
count ,
resultType ,
whole ,
partial
) 
local full = context . value ( ctx , ("icmp eq i32 %s, %d") : format ( window . room , count ) )

return choose ( ctx , full , resultType , whole , partial )
end




memory.Proof = {} memory.Proof.__index = memory.Proof ;_G.nupp.__reflect.link(memory.Proof,__nuppT1[2],{ })





local function proved ( ctx , simd , found , ways ) 
if simd . cursor == nil or simd . cursorUniqueName == nil then
return nil
end
local base , _ , count = simdbounds . offset ( simd . args [ 2 ] )
if base == nil or ( base ) . uniqueName ~= simd . cursorUniqueName then
return nil
end
local slot = ctx . locals [ tostring ( simd . cursorUniqueName ) ]
local span = ctx . spans [ tostring ( simd . span ) ]
if slot == nil or span == nil then
return nil
end
local k = math . floor ( count or 0 )
local cursor = context . value ( ctx , ("load i32, ptr %s") : format ( ( slot ) . pointer ) )
local wide = context . value ( ctx , ("zext i32 %s to i64") : format ( cursor ) )
local safe = "true"
if not ctx . wideCursors then
local reach = context . value ( ctx , ("add nuw i64 %s, %d") : format ( wide , ( k + ways ) * found . lanes ) )
safe = context . value ( ctx , ("icmp ule i64 %s, 4294967295") : format ( reach ) )
end
local start = context . value ( ctx , ("add nuw i64 %s, %d") : format ( wide , k * found . lanes ) )
local storage = found . scalar
if simd . layout ~= nil then
storage = expressions . layoutType ( ctx , tostring ( simd . layout ) )
end
local address = context . value (
ctx ,
("getelementptr %s%s, ptr %s, i64 %s")

: format ( expressions . inbounds ( ctx ) , storage , ( span ) . pointer , start )
)

return ( _G.setmetatable({ safe =  safe ,  address =  address }, memory.Proof) )
end

local function maskedLoad (
ctx ,
vector ,
suffix ,
address ,
align ,
mask ,
count
) 
local callee = prelude . intrinsic (
ctx . module ,
"llvm.masked.load." .. suffix .. ".p0" ,
("%s @NAME(ptr, <%d x i1>, %s)") : format ( vector , count , vector )
)

return context . value (
ctx ,
("call %s %s(ptr align %d %s, <%d x i1> %s, %s zeroinitializer)")

: format ( vector , callee , align , address , count , mask , vector )
)
end

local function maskedStore (
ctx ,
vector ,
suffix ,
value ,
address ,
align ,
mask ,
count
) 
local callee = prelude . intrinsic (
ctx . module ,
"llvm.masked.store." .. suffix .. ".p0" ,
("void @NAME(%s, ptr, <%d x i1>)") : format ( vector , count )
)
context . emit (
ctx ,
("call void %s(%s %s, ptr align %d %s, <%d x i1> %s)")

: format ( callee , vector , value , align , address , count , mask )
)
end


memory.Access = {} memory.Access.__index = memory.Access ;_G.nupp.__reflect.link(memory.Access,__nuppT1[3],{ })







local function access ( scalar , count , address , align ) 
return ( _G.setmetatable({ vector =
"<" .. tostring ( count ) .. " x " .. scalar .. ">" ,  scalar =
scalar ,  count =
count ,  address =
address ,  align =
align }, memory.Access) )

end






local function hardwareMasks ( ctx , a ) 
return ctx . maskedMemory and ( a . align == 4 or a . align == 8 )
end




local function laneLoop (
ctx ,
room ,
carryType ,
initial ,
step
) 
local f = ctx . f
local before = f . current
local head = builder . label ( f , "lanes.head" )
local body = builder . label ( f , "lanes.body" )
local latch = builder . label ( f , "lanes.latch" )
local done = builder . label ( f , "lanes.done" )
local lane = builder . temp ( f )
local nextLane = builder . temp ( f )
local carry = carryType ~= nil and builder . temp ( f ) or nil
builder . start ( f , head )
builder . emit ( f , ("%s = phi i32 [ 0, %%%s ], [ %s, %%%s ]") : format ( lane , before , nextLane , latch ) )
local carrySlot = 0
if carry ~= nil then
builder . emit ( f , "" )
carrySlot = # f . lines
end
local more = context . value ( ctx , ("icmp ult i32 %s, %s") : format ( lane , room ) )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( more , body , done ) )
builder . start ( f , body )
local produced = step ( lane , carry )
builder . start ( f , latch )
builder . emit ( f , ("%s = add nuw i32 %s, 1") : format ( nextLane , lane ) )
builder . terminate ( f , "br label %" .. head )
builder . start ( f , done )
if carry == nil then
return nil
end
f . lines [
carrySlot
] = ("  %s = phi %s [ %s, %%%s ], [ %s, %%%s ]")

: format ( carry , carryType , initial , before , tostring ( produced ) , latch )

return carry
end



local function copyLane (
ctx ,
a ,
from ,
to ,
lane ,
active
) 
local f = ctx . f
local skip = nil
if active ~= nil then
local on = context . value ( ctx , ("extractelement <%d x i1> %s, i32 %s") : format ( a . count , active , lane ) )
local write = builder . label ( f , "lanes.write" )
skip = builder . label ( f , "lanes.skip" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( on , write , skip ) )
builder . start ( f , write )
end
local at = context . value ( ctx , ("zext i32 %s to i64") : format ( lane ) )
local source = context . value ( ctx , ("getelementptr inbounds %s, ptr %s, i64 %s") : format ( a . scalar , from , at ) )
local target = context . value ( ctx , ("getelementptr inbounds %s, ptr %s, i64 %s") : format ( a . scalar , to , at ) )
local value = context . value ( ctx , ("load %s, ptr %s, align %d") : format ( a . scalar , source , a . align ) )
builder . emit ( f , ("store %s %s, ptr %s, align %d") : format ( a . scalar , value , target , a . align ) )
if skip ~= nil then
builder . start ( f , skip )
end
end


const CASCADE_LANES = 16





local function cascade (
ctx ,
count ,
room ,
carryType ,
lane
) 
local f = ctx . f
local top = f . current
local labels = { }
for k = 1 , count do
labels [ k ] = builder . label ( f , "tail.lane" )
end
local done = builder . label ( f , "tail.done" )
local cases = { }
for k = 1 , count do
cases [ # cases + 1 ] = ("i32 %d, label %%%s") : format ( k , labels [ k ] )
end
builder . terminate ( f , ("switch i32 %s, label %%%s [ %s ]") : format ( room , done , table . concat ( cases , " " ) ) )
local previous = nil
local previousLabel = nil
for k = count , 1 , -1 do
builder . start ( f , labels [ k ] )
local incoming = nil
if carryType ~= nil then
if previous == nil then
incoming = "zeroinitializer"
else
incoming = context . value (
ctx ,
("phi %s [ zeroinitializer, %%%s ], [ %s, %%%s ]")

: format ( carryType , top , previous , previousLabel )
)
end
end
previous = lane ( k - 1 , incoming )
previousLabel = f . current
builder . jump ( f , k > 1 and labels [ k - 1 ] or done )
end
builder . start ( f , done )
if carryType == nil then
return nil
end

return context . value (
ctx ,
("phi %s [ zeroinitializer, %%%s ], [ %s, %%%s ]")

: format ( carryType , top , tostring ( previous ) , tostring ( previousLabel ) )
)
end


local function buffer ( ctx , a ) 
return builder . alloca ( ctx . f , a . vector , 16 )
end




local function partialLoad ( ctx , a , room , active ) 
local lanesMask = "<" .. tostring ( a . count ) .. " x i1>"
if ( ctx . maskedMemory and ( a . align == 4 or a . align == 8 ) ) then
local mask = roomMask ( ctx , a . count , room )
if active ~= nil then
mask = context . value ( ctx , ("and %s %s, %s") : format ( lanesMask , mask , active ) )
end
return maskedLoad ( ctx , a . vector , lanes . suffix ( a . count , a . scalar ) , a . address , a . align , mask , a . count )
end
if a . count <= 16 then
local loaded = cascade ( ctx , a . count , room , a . vector , function ( k , carry ) 
local pointer = context . value (
ctx ,
("getelementptr inbounds %s, ptr %s, i64 %d") : format ( a . scalar , a . address , k )
)
local value = context . value ( ctx , ("load %s, ptr %s, align %d") : format ( a . scalar , pointer , a . align ) )

return context . value (
ctx ,
("insertelement %s %s, %s %s, i32 %d") : format ( a . vector , tostring ( carry ) , a . scalar , value , k )
)
end )
if active == nil then
return loaded
end
return context . value (
ctx ,
("select %s %s, %s %s, %s zeroinitializer") : format ( lanesMask , active , a . vector , loaded , a . vector )
)
end
local staging = ( builder . alloca ( ctx . f , a . vector , 16 ) )
context . emit ( ctx , ("store %s zeroinitializer, ptr %s, align 16") : format ( a . vector , staging ) )
laneLoop ( ctx , room , nil , nil , function ( lane , _ ) 
copyLane ( ctx , a , a . address , staging , lane , active )
return nil
end )

return context . value ( ctx , ("load %s, ptr %s, align 16") : format ( a . vector , staging ) )
end




local function partialStore ( ctx , a , value , room , active ) 
local lanesMask = "<" .. tostring ( a . count ) .. " x i1>"
if ( ctx . maskedMemory and ( a . align == 4 or a . align == 8 ) ) then
local mask = roomMask ( ctx , a . count , room )
if active ~= nil then
mask = context . value ( ctx , ("and %s %s, %s") : format ( lanesMask , mask , active ) )
end
maskedStore ( ctx , a . vector , lanes . suffix ( a . count , a . scalar ) , value , a . address , a . align , mask , a . count )
return
end
if a . count <= 16 then
cascade ( ctx , a . count , room , nil , function ( k , _ ) 
local f = ctx . f
local skip = nil
if active ~= nil then
local on = context . value ( ctx , ("extractelement %s %s, i32 %d") : format ( lanesMask , active , k ) )
local write = builder . label ( f , "tail.write" )
skip = builder . label ( f , "tail.skip" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( on , write , skip ) )
builder . start ( f , write )
end
local pointer = context . value (
ctx ,
("getelementptr inbounds %s, ptr %s, i64 %d") : format ( a . scalar , a . address , k )
)
local lane = context . value ( ctx , ("extractelement %s %s, i32 %d") : format ( a . vector , value , k ) )
builder . emit ( f , ("store %s %s, ptr %s, align %d") : format ( a . scalar , lane , pointer , a . align ) )
if skip ~= nil then
builder . start ( f , skip )
end

return nil
end )
return
end
local staging = ( builder . alloca ( ctx . f , a . vector , 16 ) )
context . emit ( ctx , ("store %s %s, ptr %s, align 16") : format ( a . vector , value , staging ) )
laneLoop ( ctx , room , nil , nil , function ( lane , _ ) 
copyLane ( ctx , a , staging , a . address , lane , active )
return nil
end )
end



local function tailCount ( ctx , mask ) 
if mask == nil or ( mask ) . op ~= "local" then
return nil
end

return ctx . tailCounts [ tostring ( ( ( mask ) ) . uniqueName ) ]
end


local function prefixRoom ( ctx , window , count ) 
local fewer = context . value ( ctx , ("icmp ult i32 %s, %s") : format ( count , window . room ) )
local room = context . value ( ctx , ("select i1 %s, i32 %s, i32 %s") : format ( fewer , count , window . room ) )

return ( _G.setmetatable({ address =  window . address ,  room =  room ,  first =  window . first ,  inside =  window . inside }, memory.Window) )
end


local function contiguousLoad (
ctx ,
found ,
span ,
first ,
active ,
prefix
) 
local align = math . floor ( found . bits / 8 )
local window = memory . window ( ctx , span , first , found . lanes , found . scalar )
if prefix ~= nil then

window = prefixRoom ( ctx , window , prefix )
active = nil
end

return split (
ctx ,
window ,
found . lanes ,
found . vector ,
function ( ) 
local loaded = wholeLoad ( ctx , found , window . address , align )
if active == nil then
return loaded
end

return context . value (
ctx ,
("select %s %s, %s %s, %s zeroinitializer")

: format ( found . mask , active , found . vector , loaded , found . vector )
)
end ,
function ( ) 
return partialLoad ( ctx , access ( found . scalar , found . lanes , window . address , align ) , window . room , active )
end
)
end






local function interleavedLoad ( ctx , found , simd , first ) 
local ways = simdbounds . ways ( simd . intrinsic )
local width = ways * found . lanes
local wide = "<" .. tostring ( width ) .. " x " .. found . scalar .. ">"
local align = math . floor ( found . bits / 8 )
local window = memory . window ( ctx , tostring ( simd . span ) , first , width , found . scalar )
local part = simd . part or 0
local picks = { }
for index = 0 , found . lanes - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( index * ways + part )
end

local function pick ( value ) 
return context . value (
ctx ,
("shufflevector %s %s, %s poison, <%d x i32> <%s>")

: format ( wide , value , wide , found . lanes , table . concat ( picks , ", " ) )
)
end

return split (
ctx ,
window ,
width ,
found . vector ,
function ( ) 
return pick ( context . value ( ctx , ("load %s, ptr %s, align %d") : format ( wide , window . address , align ) ) )
end ,
function ( ) 
return pick ( partialLoad ( ctx , access ( found . scalar , width , window . address , align ) , window . room , nil ) )
end
)
end



local function lanePointers (
ctx ,
found ,
span ,
indexNode ,
active
) 
local indexSpecies = lanes . of ( ctx , tostring ( indexNode . type ) )
local indices = expressions . operand ( ctx , indexNode )
local count = found . lanes
local i64s = "<" .. tostring ( count ) .. " x i64>"
local wide = indices
if indexSpecies . bits < 64 then
wide = context . value (
ctx ,
("%s %s %s to %s") : format ( indexSpecies . signed and "sext" or "zext" , indexSpecies . vector , indices , i64s )
)
end
local positive = indexSpecies . signed and context . value ( ctx , ("icmp sgt %s %s, zeroinitializer") : format ( i64s , wide ) )
or context . value ( ctx , ("icmp ne %s %s, zeroinitializer") : format ( i64s , wide ) )
local spanCount = lanes . splat ( ctx , count , "i64" , context . count ( ctx , span ) )
local within = context . value ( ctx , ("icmp ule %s %s, %s") : format ( i64s , wide , spanCount ) )
local enable = context . value ( ctx , ("and %s %s, %s") : format ( found . mask , positive , within ) )
if active ~= nil then
enable = context . value ( ctx , ("and %s %s, %s") : format ( found . mask , enable , active ) )
end
local less = context . value ( ctx , ("sub %s %s, splat (i64 1)") : format ( i64s , wide ) )
local safe = context . value (
ctx ,
("select %s %s, %s %s, %s zeroinitializer") : format ( found . mask , enable , i64s , less , i64s )
)
local base = ( ctx . spans [ span ] ) . pointer
local pointers = context . value ( ctx , ("getelementptr %s, ptr %s, %s %s") : format ( found . scalar , base , i64s , safe ) )

return pointers , enable
end





local function issued ( ctx , found ) 
if ctx . tier == "avx512f" and found . bits >= 32 and found . lanes < 8 then
return 8
end

return found . lanes
end



local function pad (
ctx ,
value ,
count ,
scalar ,
width ,
fill
) 
if width == count then
return value
end
local picks = { }
for lane = 0 , width - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( lane < count and lane or count )
end
local vector = "<" .. tostring ( count ) .. " x " .. scalar .. ">"

return context . value (
ctx ,
("shufflevector %s %s, %s %s, <%d x i32> <%s>")

: format ( vector , value , vector , fill , width , table . concat ( picks , ", " ) )
)
end

local function gather ( ctx , found , pointers , enable ) 
local width = issued ( ctx , found )
local align = math . floor ( found . bits / 8 )
local ptrs = "<" .. tostring ( width ) .. " x ptr>"
local vector = "<" .. tostring ( width ) .. " x " .. found . scalar .. ">"
local mask = "<" .. tostring ( width ) .. " x i1>"

local wideEnable = pad ( ctx , enable , found . lanes , "i1" , width , "zeroinitializer" )
local widePointers = pad ( ctx , pointers , found . lanes , "ptr" , width , pointers )
local callee = prelude . intrinsic (
ctx . module ,
"llvm.masked.gather." .. lanes . suffix ( width , found . scalar ) .. ".v" .. tostring ( width ) .. "p0" ,
("%s @NAME(%s, %s, %s)") : format ( vector , ptrs , mask , vector )
)
local gathered = context . value (
ctx ,
("call %s %s(%s align %d %s, %s %s, %s zeroinitializer)")

: format ( vector , callee , ptrs , align , widePointers , mask , wideEnable , vector )
)
if width == found . lanes then
return gathered
end
local picks = { }
for lane = 0 , found . lanes - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( lane )
end

return context . value (
ctx ,
("shufflevector %s %s, %s poison, <%d x i32> <%s>")

: format ( vector , gathered , vector , found . lanes , table . concat ( picks , ", " ) )
)
end

local function scatter (
ctx ,
found ,
value ,
pointers ,
enable
) 
local width = issued ( ctx , found )
local align = math . floor ( found . bits / 8 )
local ptrs = "<" .. tostring ( width ) .. " x ptr>"
local vector = "<" .. tostring ( width ) .. " x " .. found . scalar .. ">"
local mask = "<" .. tostring ( width ) .. " x i1>"
local wideEnable = pad ( ctx , enable , found . lanes , "i1" , width , "zeroinitializer" )
local widePointers = pad ( ctx , pointers , found . lanes , "ptr" , width , pointers )
local wideValue = pad ( ctx , value , found . lanes , found . scalar , width , "zeroinitializer" )
local callee = prelude . intrinsic (
ctx . module ,
"llvm.masked.scatter." .. lanes . suffix ( width , found . scalar ) .. ".v" .. tostring ( width ) .. "p0" ,
("void @NAME(%s, %s, %s)") : format ( vector , ptrs , mask )
)
context . emit (
ctx ,
("call void %s(%s %s, %s align %d %s, %s %s)")

: format ( callee , vector , wideValue , ptrs , align , widePointers , mask , wideEnable )
)
end



local function fieldPointers (
ctx ,
found ,
simd ,
first ,
active
) 
local layoutName = tostring ( simd . layout )
local structType = expressions . layoutType ( ctx , layoutName )
local layout = ctx . layouts [ layoutName ]
local fieldIndex = 0
for position , candidate in ipairs ( layout . fields ) do
if candidate . name == simd . field then
fieldIndex = position - 1
end
end
local window = memory . window ( ctx , tostring ( simd . span ) , first , found . lanes , structType )
local enable = roomMask ( ctx , found . lanes , window . room )
if active ~= nil then
enable = context . value ( ctx , ("and %s %s, %s") : format ( found . mask , enable , active ) )
end
local i64s = "<" .. tostring ( found . lanes ) .. " x i64>"
local offsets = context . value (
ctx ,
("select %s %s, %s, %s zeroinitializer") : format ( found . mask , enable , lanes . indices ( found . lanes , "i64" ) , i64s )
)
local pointers = context . value (
ctx ,
("getelementptr %s, ptr %s, %s %s, i32 %d") : format ( structType , window . address , i64s , offsets , fieldIndex )
)

return pointers , enable
end


local function load ( ctx , node ) 
local simd = node
local typeName = tostring ( simd . type )
local found = lanes . of ( ctx , typeName )
if simd . rooted ~= nil then


local viewed = { }
for key , value in pairs ( simd ) do
viewed [ key ] = value
end
viewed . span = "ks_bytes_" .. tostring ( ( simd . rooted ) . uniqueName )
viewed . rooted = nil
simd = viewed
end
local intrinsic = tostring ( simd . intrinsic )
if intrinsic == "gather" then
local active = simd . args [ 3 ] ~= nil and expressions . operand ( ctx , simd . args [ 3 ] ) or nil
local pointers , enable = lanePointers ( ctx , found , tostring ( simd . span ) , simd . args [ 2 ] , active )
return gather ( ctx , found , pointers , enable ) , typeName
end
local interleaved = simdbounds . interleaved ( intrinsic )
local active = not interleaved and simd . args [ 3 ] ~= nil and expressions . operand ( ctx , simd . args [ 3 ] )
or nil

local function checked ( ) 
local first = memory . first ( ctx , simd . args [ 2 ] )
if interleaved then
return interleavedLoad ( ctx , found , simd , first )
end

return contiguousLoad ( ctx , found , tostring ( simd . span ) , first , active , tailCount ( ctx , simd . args [ 3 ] ) )
end

local ways = simdbounds . ways ( intrinsic )
local proof = active == nil and proved ( ctx , simd , found , ways ) or nil
if proof == nil then
return checked ( ) , typeName
end
local align = math . floor ( found . bits / 8 )

return choose (
ctx ,
( proof ) . safe ,
found . vector ,
function ( ) 
if not interleaved then
return wholeLoad ( ctx , found , ( proof ) . address , align )
end
local wide = "<" .. tostring ( ways * found . lanes ) .. " x " .. found . scalar .. ">"
local run = context . value (
ctx ,
("load %s, ptr %s, align %d") : format ( wide , ( proof ) . address , align )
)
local picks = { }
for index = 0 , found . lanes - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( index * ways + ( simd . part or 0 ) )
end

return context . value (
ctx ,
("shufflevector %s %s, %s poison, <%d x i32> <%s>")

: format ( wide , run , wide , found . lanes , table . concat ( picks , ", " ) )
)
end ,
checked
) , typeName
end




const RUN_FIELDS = 4





local function uniformField ( ctx , simd , scalar ) 
local layout = ctx . layouts [ tostring ( simd . layout ) ]
local index = nil
for position , field in ipairs ( layout . fields ) do
if types . storage ( field . type , field . sourceType ) ~= scalar then
return nil , 0
end
if field . name == simd . field then
index = position - 1
end
end

return index , # layout . fields
end






local function fieldLoad ( ctx , node ) 
local simd = node
local typeName = tostring ( simd . type )
local found = lanes . of ( ctx , typeName )
local first = memory . first ( ctx , simd . args [ 2 ] )
local active = simd . args [ 3 ] ~= nil and expressions . operand ( ctx , simd . args [ 3 ] ) or nil
local index , fields = uniformField ( ctx , simd , found . scalar )

local function gathered ( ) 
local pointers , enable = fieldPointers ( ctx , found , simd , first , active )
return gather ( ctx , found , pointers , enable )
end

if ctx . oracle or index == nil or fields > 4 then
return gathered ( ) , typeName
end
local width = fields * found . lanes
local wide = "<" .. tostring ( width ) .. " x " .. found . scalar .. ">"
local align = math . floor ( found . bits / 8 )
local picks = { }
for lane = 0 , found . lanes - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( lane * fields + ( index ) )
end

local function run ( address ) 
local loaded = context . value ( ctx , ("load %s, ptr %s, align %d") : format ( wide , address , align ) )
local picked = context . value (
ctx ,
("shufflevector %s %s, %s poison, <%d x i32> <%s>")

: format ( wide , loaded , wide , found . lanes , table . concat ( picks , ", " ) )
)
if active == nil then
return picked
end

return context . value (
ctx ,
("select %s %s, %s %s, %s zeroinitializer") : format ( found . mask , active , found . vector , picked , found . vector )
)
end

local function checked ( ) 
local structType = expressions . layoutType ( ctx , tostring ( simd . layout ) )
local window = memory . window ( ctx , tostring ( simd . span ) , first , found . lanes , structType )
return split (
ctx ,
window ,
found . lanes ,
found . vector ,
function ( ) 
return run ( window . address )
end ,
gathered
)
end

local proof = active == nil and proved ( ctx , simd , found , 1 ) or nil
if proof == nil then
return checked ( ) , typeName
end

return choose (
ctx ,
( proof ) . safe ,
found . vector ,
function ( ) 
return run ( ( proof ) . address )
end ,
checked
) , typeName
end




local function interleave ( ctx , found , values ) 
local n = found . lanes
local ways = # values
local vector = found . vector

local function concat ( first , second ) 
local picks = { }
for lane = 0 , 2 * n - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( lane )
end

return context . value (
ctx ,
("shufflevector %s %s, %s %s, <%d x i32> <%s>")

: format ( vector , first , vector , second or "poison" , 2 * n , table . concat ( picks , ", " ) )
)
end

local left , right , half = values [ 1 ] , values [ 2 ] , vector
if ways > 2 then
left = concat ( values [ 1 ] , values [ 2 ] )
right = concat ( values [ 3 ] , values [ 4 ] )
half = "<" .. tostring ( 2 * n ) .. " x " .. found . scalar .. ">"
end


local picks = { }
for lane = 0 , n - 1 do
for way = 0 , ways - 1 do
picks [ lane * ways + way + 1 ] = "i32 " .. tostring ( way * n + lane )
end
end
local wide = "<" .. tostring ( n * ways ) .. " x " .. found . scalar .. ">"

return context . value (
ctx ,
("shufflevector %s %s, %s %s, <%d x i32> <%s>")

: format ( half , left , half , right , n * ways , table . concat ( picks , ", " ) )
) , wide
end



local function checkedInterleavedStore (
ctx ,
found ,
span ,
first ,
values ,
align
) 
local width = found . lanes * # values
local window = memory . window ( ctx , span , first , width , found . scalar )


split (
ctx ,
window ,
width ,
nil ,
function ( ) 
local wide , wideType = interleave ( ctx , found , values )
context . emit ( ctx , ("store %s %s, ptr %s, align %d") : format ( wideType , wide , window . address , align ) )
return nil
end ,
function ( ) 



local staged = access ( found . scalar , width , window . address , align )
local staging = ( builder . alloca ( ctx . f , staged . vector , 16 ) )
for way , value in ipairs ( values ) do
local slot = context . value (
ctx ,
("getelementptr inbounds %s, ptr %s, i64 %d") : format ( found . scalar , staging , ( way - 1 ) * found . lanes )
)
context . emit ( ctx , ("store %s %s, ptr %s, align %d") : format ( found . vector , value , slot , align ) )
end
laneLoop ( ctx , window . room , nil , nil , function ( element , _ ) 
local way = context . value ( ctx , ("urem i32 %s, %d") : format ( element , # values ) )
local lane = context . value ( ctx , ("udiv i32 %s, %d") : format ( element , # values ) )
local base = context . value ( ctx , ("mul nuw i32 %s, %d") : format ( way , found . lanes ) )
local from = context . value ( ctx , ("add nuw i32 %s, %s") : format ( base , lane ) )
local fromWide = context . value ( ctx , ("zext i32 %s to i64") : format ( from ) )
local toWide = context . value ( ctx , ("zext i32 %s to i64") : format ( element ) )
local source = context . value (
ctx ,
("getelementptr inbounds %s, ptr %s, i64 %s") : format ( found . scalar , staging , fromWide )
)
local target = context . value (
ctx ,
("getelementptr inbounds %s, ptr %s, i64 %s") : format ( found . scalar , window . address , toWide )
)
local value = context . value ( ctx , ("load %s, ptr %s, align %d") : format ( found . scalar , source , align ) )
context . emit ( ctx , ("store %s %s, ptr %s, align %d") : format ( found . scalar , value , target , align ) )

return nil
end )

return nil
end
)
end


local function checkedStore (
ctx ,
found ,
span ,
first ,
value ,
active ,
align ,
prefix
) 
local window = memory . window ( ctx , span , first , found . lanes , found . scalar )
if prefix ~= nil then

window = prefixRoom ( ctx , window , prefix )
active = nil
end
local shape = access ( found . scalar , found . lanes , window . address , align )
if active ~= nil then
partialStore ( ctx , shape , value , window . room , active )
return
end
split (
ctx ,
window ,
found . lanes ,
nil ,
function ( ) 
context . emit ( ctx , ("store %s %s, ptr %s, align %d") : format ( found . vector , value , window . address , align ) )
return nil
end ,
function ( ) 
partialStore ( ctx , shape , value , window . room , nil )

return nil
end
)
end

local function store ( ctx , node ) 
local simd = node
local intrinsic = tostring ( simd . intrinsic )
local found = lanes . of ( ctx , tostring ( simd . args [ 3 ] . type ) )
local span = tostring ( simd . span )
if intrinsic == "scatter" or intrinsic == "scatterUnchecked" then
local value = expressions . operand ( ctx , simd . args [ 3 ] )
local active = simd . args [ 4 ] ~= nil and expressions . operand ( ctx , simd . args [ 4 ] ) or nil
local pointers , enable = lanePointers ( ctx , found , span , simd . args [ 2 ] , active )
scatter ( ctx , found , value , pointers , enable )
return
end
local align = math . floor ( found . bits / 8 )
local interleaved = simdbounds . interleaved ( intrinsic )

local values = { }
for position = 3 , interleaved and # simd . args or 3 do
values [ # values + 1 ] = expressions . operand ( ctx , simd . args [ position ] )
end
local active = not interleaved and simd . args [ 4 ] ~= nil and expressions . operand ( ctx , simd . args [ 4 ] )
or nil

local function checked ( ) 
local first = memory . first ( ctx , simd . args [ 2 ] )
if interleaved then
checkedInterleavedStore ( ctx , found , span , first , values , align )
else
checkedStore ( ctx , found , span , first , values [ 1 ] , active , align , tailCount ( ctx , simd . args [ 4 ] ) )
end

return nil
end

local proof = active == nil and proved ( ctx , simd , found , simdbounds . ways ( intrinsic ) ) or nil
if proof == nil then
checked ( )
return
end
choose (
ctx ,
( proof ) . safe ,
nil ,
function ( ) 
if interleaved then
local wide , wideType = interleave ( ctx , found , values )
context . emit (
ctx ,
("store %s %s, ptr %s, align %d") : format ( wideType , wide , ( proof ) . address , align )
)
else
context . emit (
ctx ,
("store %s %s, ptr %s, align %d")

: format ( found . vector , values [ 1 ] , ( proof ) . address , align )
)
end

return nil
end ,
checked
)
end

local function fieldStore ( ctx , node ) 
local simd = node
local found = lanes . of ( ctx , tostring ( simd . args [ 3 ] . type ) )
local first = memory . first ( ctx , simd . args [ 2 ] )
local value = expressions . operand ( ctx , simd . args [ 3 ] )
local active = simd . args [ 4 ] ~= nil and expressions . operand ( ctx , simd . args [ 4 ] ) or nil
local pointers , enable = fieldPointers ( ctx , found , simd , first , active )
scatter ( ctx , found , value , pointers , enable )
end

memory . EXPRESSIONS = {
[ "simd_load" ] = load ,
[ "simd_field_load" ] = fieldLoad ,
}

memory . STATEMENTS = {
[ "simd_store" ] = store ,
[ "simd_field_store" ] = fieldStore ,
}

local __nuppExportValue= memory ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.simd.memory"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.simd.memory"]=__nuppExports;return __nuppExports