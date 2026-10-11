_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitBnot=bit.bnot;local __nuppBitBor=bit.bor;local __nuppBitBxor=bit.bxor;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math")) require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.simd\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0007") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0008") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\0009") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00010") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00011") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00012") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00013") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00014") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00015") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00016") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00017") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00018") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00019") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00020") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00021") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00022") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00023") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00024") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00025") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00026") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00027") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00028") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00029") , _G.nupp.__reflect.declaration("nupp.simd\0runtime\00030") };




















































const storageWitnesses = require ( "nupp.mem.array" )


local simd = { }





















local LANES_VECTOR = { }

local LANES_MASK = { }



local function lanesOf ( value ) 
if type ( value ) ~= "table" then
return nil
end
local mt = getmetatable ( value )
if mt == LANES_VECTOR or mt == LANES_MASK then
return ( value ) . n
end

return nil
end



local function laneAt ( value , i ) 
if lanesOf ( value ) ~= nil then
return ( value ) [ i ]
end

return value
end


local function activeAt ( active , i ) 
if active == nil then
return true
end

return laneAt ( active , i ) == true
end


local function elementOf ( value ) 
return ( value ) . element
end


local function vectorOf ( element , n , lanes ) 
local value = lanes
value . n = n
value . element = element

return setmetatable ( value , LANES_VECTOR )
end



local function maskOf ( element , n , lanes ) 
local value = lanes
value . n = n
value . element = element

return setmetatable ( value , LANES_MASK )
end


local function copyLanes ( value , n ) 
local lanes = { }
for i = 1 , n do
lanes [ i ] = laneAt ( value , i )
end

return lanes
end





































local reducer





































































= { }


local function keep ( value ) 
return value
end



const ROUNDING

= { [ storageWitnesses . number ] = keep , [ storageWitnesses . float ] = nupp . math . f32 . narrow , }





local function floating ( first , second ) 
if second == nil then
return keep , first
end
local round = ROUNDING [ first ]
if round == nil then
error ( "nupp: a floating-point reducer takes the float or number array witness" , 3 )
end

return round , ( round ) ( second )
end




local function floatingElement ( element ) 
if element == nil then
return keep
end
local round = ROUNDING [ element ]
if round == nil then
error ( "nupp: a floating-point reducer takes the float or number array witness" , 3 )
end

return round
end







simd.OrderedSum = {} simd.OrderedSum.__index = simd.OrderedSum








function simd.OrderedSum:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
self . total = self . round ( self . total + scalar )
end

function simd.OrderedSum:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.OrderedSum,__nuppT1[1],{ })








simd.PairwiseSum = {} simd.PairwiseSum.__index = simd.PairwiseSum









function simd.PairwiseSum:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
local carry = scalar
local occupied = self . count
local level = 1
while occupied % 2 == 1 do
carry = self . round ( ( self . partials [ level ] ) + carry )
self . partials [ level ] = nil
occupied = ( _G.math.floor(( occupied ) / ( 2 )) )
level = level + 1
end
self . partials [ level ] = carry
self . count = self . count + 1
end

function simd.PairwiseSum:value() 
local result = nil



local level = 1
local remaining = self . count
while remaining > 0 do
local partial = self . partials [ level ]
if partial ~= nil then
if result == nil then
result = partial
else
result = self . round ( partial + ( result ) )
end
end
level = level + 1
remaining = ( _G.math.floor(( remaining ) / ( 2 )) )
end

return result
end ;_G.nupp.__reflect.link(simd.PairwiseSum,__nuppT1[2],{ })











simd.AlgebraicSum = {} simd.AlgebraicSum.__index = simd.AlgebraicSum








function simd.AlgebraicSum:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
self . total = self . round ( self . total + scalar )
end

function simd.AlgebraicSum:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.AlgebraicSum,__nuppT1[3],{ })
























simd.CompensatedSum = {} simd.CompensatedSum.__index = simd.CompensatedSum









function simd.CompensatedSum:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
local round = self . round
local sum = round ( self . total + scalar )
if math . abs ( self . total ) >= math . abs ( scalar ) then
self . compensation = round ( self . compensation + round ( round ( self . total - sum ) + scalar ) )
else
self . compensation = round ( self . compensation + round ( round ( scalar - sum ) + self . total ) )
end
self . total = sum
end

function simd.CompensatedSum:value() 
return self . round ( self . total + self . compensation )
end ;_G.nupp.__reflect.link(simd.CompensatedSum,__nuppT1[4],{ })








simd.OrderedProduct = {} simd.OrderedProduct.__index = simd.OrderedProduct








function simd.OrderedProduct:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
self . total = self . round ( self . total * scalar )
end

function simd.OrderedProduct:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.OrderedProduct,__nuppT1[5],{ })








simd.PairwiseProduct = {} simd.PairwiseProduct.__index = simd.PairwiseProduct









function simd.PairwiseProduct:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
local carry = scalar
local occupied = self . count
local level = 1
while occupied % 2 == 1 do
carry = self . round ( ( self . partials [ level ] ) * carry )
self . partials [ level ] = nil
occupied = ( _G.math.floor(( occupied ) / ( 2 )) )
level = level + 1
end
self . partials [ level ] = carry
self . count = self . count + 1
end

function simd.PairwiseProduct:value() 
local result = nil



local level = 1
local remaining = self . count
while remaining > 0 do
local partial = self . partials [ level ]
if partial ~= nil then
if result == nil then
result = partial
else
result = self . round ( partial * ( result ) )
end
end
level = level + 1
remaining = ( _G.math.floor(( remaining ) / ( 2 )) )
end

return result
end ;_G.nupp.__reflect.link(simd.PairwiseProduct,__nuppT1[6],{ })








simd.AlgebraicProduct = {} simd.AlgebraicProduct.__index = simd.AlgebraicProduct








function simd.AlgebraicProduct:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = self . round ( value )
self . total = self . round ( self . total * scalar )
end

function simd.AlgebraicProduct:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.AlgebraicProduct,__nuppT1[7],{ })









simd.OrderedDot = {} simd.OrderedDot.__index = simd.OrderedDot








function simd.OrderedDot:add(left, right, active) 
local n = lanesOf ( left ) or lanesOf ( right )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( left , i ) , laneAt ( right , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local leftValue , rightValue = self . round ( left ) , self . round ( right )
self . total = self . round ( self . total + self . round ( leftValue * rightValue ) )
end

function simd.OrderedDot:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.OrderedDot,__nuppT1[8],{ })









simd.PairwiseDot = {} simd.PairwiseDot.__index = simd.PairwiseDot








function simd.PairwiseDot:add(left, right, active) 
local n = lanesOf ( left ) or lanesOf ( right )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( left , i ) , laneAt ( right , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local leftValue , rightValue = self . round ( left ) , self . round ( right )
self . sum : add ( self . round ( leftValue * rightValue ) )
end

function simd.PairwiseDot:value() 
return self . sum : value ( )
end ;_G.nupp.__reflect.link(simd.PairwiseDot,__nuppT1[9],{ __nuppT1[2] })










simd.AlgebraicDot = {} simd.AlgebraicDot.__index = simd.AlgebraicDot








function simd.AlgebraicDot:add(left, right, active) 
local n = lanesOf ( left ) or lanesOf ( right )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( left , i ) , laneAt ( right , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local leftValue , rightValue = self . round ( left ) , self . round ( right )
self . total = self . round ( self . total + self . round ( leftValue * rightValue ) )
end

function simd.AlgebraicDot:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.AlgebraicDot,__nuppT1[10],{ })








reducer . orderedSum = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  round =  round }, simd.OrderedSum) )
end )








reducer . pairwiseSum = ( function ( first , second ) 
local round , seed = floating ( first , second )
local out = _G.setmetatable({ partials =  { } ,  count =  0 ,  round =  round }, simd.PairwiseSum)
out : add ( seed )

return out
end )







reducer . algebraicSum = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  round =  round }, simd.AlgebraicSum) )
end )







reducer . compensatedSum = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  compensation =  0.0 ,  round =  round }, simd.CompensatedSum) )
end )







reducer . orderedProduct = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  round =  round }, simd.OrderedProduct) )
end )








reducer . pairwiseProduct = ( function ( first , second ) 
local round , seed = floating ( first , second )
local out = _G.setmetatable({ partials =  { } ,  count =  0 ,  round =  round }, simd.PairwiseProduct)
out : add ( seed )

return out
end )







reducer . algebraicProduct = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  round =  round }, simd.AlgebraicProduct) )
end )







reducer . orderedDot = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  round =  round }, simd.OrderedDot) )
end )







reducer . pairwiseDot = ( function ( first , second ) 
local round , seed = floating ( first , second )
local sum = _G.setmetatable({ partials =  { } ,  count =  0 ,  round =  round }, simd.PairwiseSum)
sum : add ( seed )

return ( _G.setmetatable({ sum =  sum ,  round =  round }, simd.PairwiseDot) )
end )







reducer . algebraicDot = ( function ( first , second ) 
local round , seed = floating ( first , second )
return ( _G.setmetatable({ total =  seed ,  round =  round }, simd.AlgebraicDot) )
end )





simd.WrappingSum = {} simd.WrappingSum.__index = simd.WrappingSum








function simd.WrappingSum:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
self . total = self . operation ( self . total , scalar )
end

function simd.WrappingSum:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.WrappingSum,__nuppT1[11],{ })



simd.WrappingProduct = {} simd.WrappingProduct.__index = simd.WrappingProduct








function simd.WrappingProduct:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
self . total = self . operation ( self . total , scalar )
end

function simd.WrappingProduct:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.WrappingProduct,__nuppT1[12],{ })



simd.AndBits = {} simd.AndBits.__index = simd.AndBits








function simd.AndBits:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
self . total = self . operation ( self . total , scalar )
end

function simd.AndBits:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.AndBits,__nuppT1[13],{ })



simd.OrBits = {} simd.OrBits.__index = simd.OrBits








function simd.OrBits:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
self . total = self . operation ( self . total , scalar )
end

function simd.OrBits:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.OrBits,__nuppT1[14],{ })



simd.XorBits = {} simd.XorBits.__index = simd.XorBits








function simd.XorBits:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
self . total = self . operation ( self . total , scalar )
end

function simd.XorBits:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.XorBits,__nuppT1[15],{ })


local function i64WrappingSum ( a , b ) 
return ( a + b )
end

local function i64WrappingProduct ( a , b ) 
return ( a * b )
end

local function i64AndBits ( a , b ) 
return ( a & b )
end

local function i64OrBits ( a , b ) 
return ( a | b )
end

local function i64XorBits ( a , b ) 
return ( a ~ b )
end

local function u64WrappingSum ( a , b ) 
return ( a + b )
end

local function u64WrappingProduct ( a , b ) 
return ( a * b )
end

local function u64AndBits ( a , b ) 
return ( a & b )
end

local function u64OrBits ( a , b ) 
return ( a | b )
end

local function u64XorBits ( a , b ) 
return ( a ~ b )
end





const EXACT

= {
[
storageWitnesses . int32
] = {
sum = nupp . math . i32 . add ,
product = nupp . math . i32 . mul ,
andBits = nupp . math . i32 . andBits ,
orBits = nupp . math . i32 . orBits ,
xorBits = nupp . math . i32 . xorBits ,
} ,
[
storageWitnesses . uint32
] = {
sum = nupp . math . u32 . add ,
product = nupp . math . u32 . mul ,
andBits = nupp . math . u32 . andBits ,
orBits = nupp . math . u32 . orBits ,
xorBits = nupp . math . u32 . xorBits ,
} ,
[
storageWitnesses . int64
] = {
sum = i64WrappingSum ,
product = i64WrappingProduct ,
andBits = i64AndBits ,
orBits = i64OrBits ,
xorBits = i64XorBits ,
} ,
[
storageWitnesses . uint64
] = {
sum = u64WrappingSum ,
product = u64WrappingProduct ,
andBits = u64AndBits ,
orBits = u64OrBits ,
xorBits = u64XorBits ,
} ,
}



local function exact ( element , operation ) 
local operations = EXACT [ element ]
if operations == nil then
error ( "nupp: an integer reducer takes the int32, uint32, int64 or uint64 array witness" , 3 )
end

return operations [ operation ]
end



function reducer . wrappingSum (
element ,
initial
) 
return ( _G.setmetatable({ total =  initial ,  operation =  exact ( element , "sum" ) }, simd.WrappingSum) )
end



function reducer . wrappingProduct (
element ,
initial
) 
return ( _G.setmetatable({ total =
initial ,  operation =
exact ( element , "product" ) }, simd.WrappingProduct) )

end



function reducer . andBits (
element ,
initial
) 
return ( _G.setmetatable({ total =  initial ,  operation =  exact ( element , "andBits" ) }, simd.AndBits) )
end



function reducer . orBits (
element ,
initial
) 
return ( _G.setmetatable({ total =  initial ,  operation =  exact ( element , "orBits" ) }, simd.OrBits) )
end




function reducer . xorBits (
element ,
initial
) 
return ( _G.setmetatable({ total =  initial ,  operation =  exact ( element , "xorBits" ) }, simd.XorBits) )
end



simd.Any = {} simd.Any.__index = simd.Any







function simd.Any:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
self . total = self . total or ( value )
end

function simd.Any:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.Any,__nuppT1[16],{ })




function reducer . any ( ) 
return ( _G.setmetatable({ total =  false }, simd.Any) )
end



simd.All = {} simd.All.__index = simd.All







function simd.All:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
self . total = self . total and ( value )
end

function simd.All:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.All,__nuppT1[17],{ })




function reducer . all ( ) 
return ( _G.setmetatable({ total =  true }, simd.All) )
end



simd.Count = {} simd.Count.__index = simd.Count







function simd.Count:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
self . total = self . total + ( ( value ) and 1ULL or 0ULL )
end

function simd.Count:value() 
return self . total
end ;_G.nupp.__reflect.link(simd.Count,__nuppT1[18],{ })




function reducer . count ( ) 
return ( _G.setmetatable({ total =  0ULL }, simd.Count) )
end

local function integerLess ( left , right ) 
return left < right
end



simd.IntegerMin = {} simd.IntegerMin.__index = simd.IntegerMin







function simd.IntegerMin:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
if integerLess ( scalar , self . best ) then
self . best = scalar
end
end

function simd.IntegerMin:value() 
return self . best
end ;_G.nupp.__reflect.link(simd.IntegerMin,__nuppT1[19],{ })




function reducer . integerMin (
element ,
initial
) 
exact ( element , "sum" )
return ( _G.setmetatable({ best =  initial }, simd.IntegerMin) )
end



simd.IntegerArgMin = {} simd.IntegerArgMin.__index = simd.IntegerArgMin












function simd.IntegerArgMin:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
self . count = self . count + 1
if ( active ) == false then
return
end
local scalar = value
if self . position == 0 or integerLess ( scalar , self . best ) then
self . best = scalar
self . position = self . count
end
end

function simd.IntegerArgMin:value() 
return self . position
end ;_G.nupp.__reflect.link(simd.IntegerArgMin,__nuppT1[20],{ })




function reducer . integerArgMin ( element ) 
exact ( element , "sum" )
return ( _G.setmetatable({ best =  nil ,  position =  0 ,  count =  0 }, simd.IntegerArgMin) )
end



simd.IntegerMax = {} simd.IntegerMax.__index = simd.IntegerMax







function simd.IntegerMax:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
if integerLess ( self . best , scalar ) then
self . best = scalar
end
end

function simd.IntegerMax:value() 
return self . best
end ;_G.nupp.__reflect.link(simd.IntegerMax,__nuppT1[21],{ })




function reducer . integerMax (
element ,
initial
) 
exact ( element , "sum" )
return ( _G.setmetatable({ best =  initial }, simd.IntegerMax) )
end



simd.IntegerArgMax = {} simd.IntegerArgMax.__index = simd.IntegerArgMax












function simd.IntegerArgMax:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
self . count = self . count + 1
if ( active ) == false then
return
end
local scalar = value
if self . position == 0 or integerLess ( self . best , scalar ) then
self . best = scalar
self . position = self . count
end
end

function simd.IntegerArgMax:value() 
return self . position
end ;_G.nupp.__reflect.link(simd.IntegerArgMax,__nuppT1[22],{ })




function reducer . integerArgMax ( element ) 
exact ( element , "sum" )
return ( _G.setmetatable({ best =  nil ,  position =  0 ,  count =  0 }, simd.IntegerArgMax) )
end





local function extremumWins ( candidate , best , maximum , propagate ) 
if candidate ~= candidate then
return propagate and best == best
elseif best ~= best then
return not propagate
elseif candidate == 0 and best == 0 then
return maximum and 1 / candidate > 1 / best or not maximum and 1 / candidate < 1 / best
end

return maximum and candidate > best or not maximum and candidate < best
end







simd.PropagatingMin = {} simd.PropagatingMin.__index = simd.PropagatingMin







function simd.PropagatingMin:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
if extremumWins ( scalar , self . best , false , true ) then
self . best = scalar
end
end

function simd.PropagatingMin:value() 
return ( self . best ~= self . best and math . abs ( 0 / 0 ) or self . best )
end ;_G.nupp.__reflect.link(simd.PropagatingMin,__nuppT1[23],{ })








reducer . propagatingMin = ( function ( first , second ) 
local _ , seed = floating ( first , second )
return ( _G.setmetatable({ best =  seed }, simd.PropagatingMin) )
end )







simd.PropagatingArgMin = {} simd.PropagatingArgMin.__index = simd.PropagatingArgMin












function simd.PropagatingArgMin:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
self . count = self . count + 1
if ( active ) == false then
return
end
local scalar = value
if self . position == 0 or extremumWins ( scalar , self . best , false , true ) then
self . best = scalar
self . position = self . count
end
end

function simd.PropagatingArgMin:value() 
return self . position
end ;_G.nupp.__reflect.link(simd.PropagatingArgMin,__nuppT1[24],{ })







reducer . propagatingArgMin = ( function ( element ) 
floatingElement ( element )
return ( _G.setmetatable({ best =  0.0 ,  position =  0 ,  count =  0 }, simd.PropagatingArgMin) )
end )







simd.PropagatingMax = {} simd.PropagatingMax.__index = simd.PropagatingMax







function simd.PropagatingMax:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
if extremumWins ( scalar , self . best , true , true ) then
self . best = scalar
end
end

function simd.PropagatingMax:value() 
return ( self . best ~= self . best and math . abs ( 0 / 0 ) or self . best )
end ;_G.nupp.__reflect.link(simd.PropagatingMax,__nuppT1[25],{ })








reducer . propagatingMax = ( function ( first , second ) 
local _ , seed = floating ( first , second )
return ( _G.setmetatable({ best =  seed }, simd.PropagatingMax) )
end )







simd.PropagatingArgMax = {} simd.PropagatingArgMax.__index = simd.PropagatingArgMax












function simd.PropagatingArgMax:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
self . count = self . count + 1
if ( active ) == false then
return
end
local scalar = value
if self . position == 0 or extremumWins ( scalar , self . best , true , true ) then
self . best = scalar
self . position = self . count
end
end

function simd.PropagatingArgMax:value() 
return self . position
end ;_G.nupp.__reflect.link(simd.PropagatingArgMax,__nuppT1[26],{ })







reducer . propagatingArgMax = ( function ( element ) 
floatingElement ( element )
return ( _G.setmetatable({ best =  0.0 ,  position =  0 ,  count =  0 }, simd.PropagatingArgMax) )
end )







simd.NumberMin = {} simd.NumberMin.__index = simd.NumberMin







function simd.NumberMin:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
if extremumWins ( scalar , self . best , false , false ) then
self . best = scalar
end
end

function simd.NumberMin:value() 
return ( self . best ~= self . best and math . abs ( 0 / 0 ) or self . best )
end ;_G.nupp.__reflect.link(simd.NumberMin,__nuppT1[27],{ })








reducer . numberMin = ( function ( first , second ) 
local _ , seed = floating ( first , second )
return ( _G.setmetatable({ best =  seed }, simd.NumberMin) )
end )







simd.NumberArgMin = {} simd.NumberArgMin.__index = simd.NumberArgMin












function simd.NumberArgMin:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
self . count = self . count + 1
if ( active ) == false then
return
end
local scalar = value
if self . position == 0 or extremumWins ( scalar , self . best , false , false ) then
self . best = scalar
self . position = self . count
end
end

function simd.NumberArgMin:value() 
return self . position
end ;_G.nupp.__reflect.link(simd.NumberArgMin,__nuppT1[28],{ })







reducer . numberArgMin = ( function ( element ) 
floatingElement ( element )
return ( _G.setmetatable({ best =  0.0 ,  position =  0 ,  count =  0 }, simd.NumberArgMin) )
end )







simd.NumberMax = {} simd.NumberMax.__index = simd.NumberMax







function simd.NumberMax:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
if ( active ) == false then
return
end
local scalar = value
if extremumWins ( scalar , self . best , true , false ) then
self . best = scalar
end
end

function simd.NumberMax:value() 
return ( self . best ~= self . best and math . abs ( 0 / 0 ) or self . best )
end ;_G.nupp.__reflect.link(simd.NumberMax,__nuppT1[29],{ })








reducer . numberMax = ( function ( first , second ) 
local _ , seed = floating ( first , second )
return ( _G.setmetatable({ best =  seed }, simd.NumberMax) )
end )







simd.NumberArgMax = {} simd.NumberArgMax.__index = simd.NumberArgMax












function simd.NumberArgMax:add(value, active) 
local n = lanesOf ( value )
if n ~= nil then
for i = 1 , n do
self : add ( laneAt ( value , i ) , activeAt ( active , i ) )
end
return
end
self . count = self . count + 1
if ( active ) == false then
return
end
local scalar = value
if self . position == 0 or extremumWins ( scalar , self . best , true , false ) then
self . best = scalar
self . position = self . count
end
end

function simd.NumberArgMax:value() 
return self . position
end ;_G.nupp.__reflect.link(simd.NumberArgMax,__nuppT1[30],{ })







reducer . numberArgMax = ( function ( element ) 
floatingElement ( element )
return ( _G.setmetatable({ best =  0.0 ,  position =  0 ,  count =  0 }, simd.NumberArgMax) )
end )

simd . reducer = reducer








































































































































































































































































































































































































































































































local ELEMENT_OF

= {
[ storageWitnesses . uint8 ] = "uint8" ,
[ storageWitnesses . int8 ] = "int8" ,
[ storageWitnesses . uint16 ] = "uint16" ,
[ storageWitnesses . int16 ] = "int16" ,
[ storageWitnesses . uint32 ] = "uint32" ,
[ storageWitnesses . int32 ] = "int32" ,
[ storageWitnesses . uint64 ] = "uint64" ,
[ storageWitnesses . int64 ] = "int64" ,
[ storageWitnesses . float ] = "float" ,
[ storageWitnesses . number ] = "number" ,
}

const BITS

= { uint8 = 8 , int8 = 8 , uint16 = 16 , int16 = 16 , uint32 = 32 , int32 = 32 , uint64 = 64 , int64 = 64 , }

const SIGNED = { int8 = true , int16 = true , int32 = true , int64 = true , }

local function isFloat ( element ) 
return element == "float" or element == "number"
end


local function wide ( value ) 
return type ( value ) == "cdata"
end


local function truncate ( value ) 
if value ~= value then
return 0
elseif value < 0 then
return math . ceil ( value )
end

return math . floor ( value )
end



local function wrap ( element , value ) 
if element == "number" then
return value
elseif element == "float" then
return nupp . math . f32 . narrow ( value )
elseif element == "uint32" then
return (__nuppBitTobit( truncate ( value ) )%4294967296)
elseif element == "int32" then
return __nuppBitTobit( truncate ( value ) )
elseif element == "uint64" then
return ( 0ULL + ( value ) )
elseif element == "int64" then
return ( 0LL + ( value ) )
end
local modulus = 2 ^ ( BITS [ element ] )
local unsigned = ( value ) % modulus
if SIGNED [ element ] and unsigned >= modulus / 2 then
return unsigned - modulus
end

return unsigned
end



local function pattern ( element , value ) 
local modulus = 2 ^ ( BITS [ element ] )

return (__nuppBitTobit( ( ( value ) % modulus ) )%4294967296)
end

local function integerDivide ( element , a , b ) 
if ( type ( a ) == "cdata" ) or ( type ( b ) == "cdata" ) then
if b == 0 then
return wrap ( element , 0 )
end
return wrap ( element , ( a ) / ( b ) )
end
if ( b ) == 0 then
return 0
end

return wrap ( element , truncate ( ( a ) / ( b ) ) )
end

local function shiftCount ( element , count ) 
return ( tonumber ( count ) ) % ( BITS [ element ] )
end

local function bitwise ( element , op , a , b ) 
if element == "number" or element == "float" then
error ( "bitwise SIMD operators require an integer vector element" , 3 )
end
if BITS [ element ] == 64 then
local left = ( SIGNED [ element ] and ( 0LL + ( a ) ) or ( 0ULL + ( a ) ) )
local right = ( SIGNED [ element ] and ( 0LL + ( b ) ) or ( 0ULL + ( b ) ) )
if op == "&" then
return ( left & right )
elseif op == "|" then
return ( left | right )
elseif op == "~" then
return ( left ~ right )
elseif op == "<<" then
return ( left << ( ( tonumber ( b ) ) % ( BITS [ element ] ) ) )
elseif op == ">>" then
return ( ( 0ULL + left ) >> ( ( tonumber ( b ) ) % ( BITS [ element ] ) ) )
end
return ( left ~>> ( ( tonumber ( b ) ) % ( BITS [ element ] ) ) )
end
local left = pattern ( element , a )
if op == "<<" then
return wrap ( element , ( left ) * 2 ^ ( ( tonumber ( b ) ) % ( BITS [ element ] ) ) )
elseif op == ">>" then
return wrap ( element , math . floor ( ( left ) / 2 ^ ( ( tonumber ( b ) ) % ( BITS [ element ] ) ) ) )
elseif op == "~>>" then
return wrap ( element , math . floor ( ( a ) / 2 ^ ( ( tonumber ( b ) ) % ( BITS [ element ] ) ) ) )
end

local right = pattern ( element , b )
if op == "&" then
return wrap ( element , (__nuppBitBand( left , right )%4294967296) )
elseif op == "|" then
return wrap ( element , (__nuppBitBor( left , right )%4294967296) )
end

return wrap ( element , (__nuppBitBxor( left , right )%4294967296) )
end

local function isNaN ( value ) 
return value ~= value
end


local function extremum ( a , b , minimum , propagating ) 
if ( a ~= a ) or ( b ~= b ) then
if propagating then
return 0 / 0
elseif ( a ~= a ) and ( b ~= b ) then
return 0 / 0
end
return ( a ~= a ) and b or a
end
if a == b and ( a ) == 0 then

local negativeA = 1 / ( a ) < 0
if minimum then
return negativeA and a or b
end
return negativeA and b or a
end
if minimum then
return ( a ) < ( b ) and a or b
end

return ( a ) > ( b ) and a or b
end






local lane = { }



local function binaryLane ( op , element , a , b ) 
if element == "mask" then
if op == "&" then
return a and b
elseif op == "|" then
return a or b
elseif op == "~" then
return a ~= b
elseif op == "==" then
return a == b
elseif op == "~=" then
return a ~= b
end
error ( "operator " .. op .. " is not a mask intrinsic" , 2 )
end
if op == "+" then
return wrap ( element , ( a ) + ( b ) )
elseif op == "-" then
return wrap ( element , ( a ) - ( b ) )
elseif op == "*" then
if BITS [ element ] == 32 then


return wrap ( element , nupp . math . u32 . mul ( pattern ( element , a ) , pattern ( element , b ) ) )
end
return wrap ( element , ( a ) * ( b ) )
elseif op == "/" then
if ( element == "float" or element == "number" ) then
return wrap ( element , ( a ) / ( b ) )
end
return integerDivide ( element , a , b )
elseif op == "%" then
if ( element == "float" or element == "number" ) then
return wrap ( element , ( a ) % ( b ) )
elseif b == 0 then
return wrap ( element , 0 )
end
return wrap ( element , ( a ) % ( b ) )
elseif op == "//" then
if ( element == "float" or element == "number" ) then
return wrap ( element , math . floor ( ( a ) / ( b ) ) )
elseif b == 0 then
return wrap ( element , 0 )
end
return wrap ( element , math . floor ( ( a ) / ( b ) ) )
elseif op == "==" then
return a == b
elseif op == "~=" then
return a ~= b
elseif op == "<" then
return ( a ) < ( b )
elseif op == "<=" then
return ( a ) <= ( b )
elseif op == ">" then
return ( a ) > ( b )
elseif op == ">=" then
return ( a ) >= ( b )
end

return bitwise ( element , op , a , b )
end


local function unaryLane ( op , element , a ) 
if element == "mask" then
return not a
end
if op == "-" then
return wrap ( element , - ( a ) )
end
if BITS [ element ] == 64 then
return ( ~ ( 0LL + ( a ) ) )
elseif BITS [ element ] == 32 then
return wrap ( element , (__nuppBitBnot( pattern ( element , a ) )%4294967296) )
end

return wrap ( element , 2 ^ ( BITS [ element ] ) - 1 - pattern ( element , a ) )
end


const COMPARISONS

= { [ "==" ] = true , [ "~=" ] = true , [ "<" ] = true , [ "<=" ] = true , [ ">" ] = true , [ ">=" ] = true , }




local function carriedElement ( element , a , b ) 
if lanesOf ( a ) ~= nil then
return elementOf ( a )
elseif lanesOf ( b ) ~= nil then
return elementOf ( b )
end

return element
end



function lane . binary ( op , element , a , b ) 
local n = lanesOf ( a ) or lanesOf ( b )
if n == nil then
return binaryLane ( op , element , a , b )
end
local lanes = { }
for i = 1 , n do
lanes [ i ] = binaryLane ( op , element , laneAt ( a , i ) , laneAt ( b , i ) )
end
local carried = carriedElement ( element , a , b )
if element == "mask" or COMPARISONS [ op ] then
return maskOf ( carried , n , lanes )
end

return vectorOf ( carried , n , lanes )
end


function lane . unary ( op , element , a ) 
local n = lanesOf ( a )
if n == nil then
return unaryLane ( op , element , a )
end
local lanes = { }
for i = 1 , n do
lanes [ i ] = unaryLane ( op , element , laneAt ( a , i ) )
end
if element == "mask" then
return maskOf ( elementOf ( a ) , n , lanes )
end

return vectorOf ( elementOf ( a ) , n , lanes )
end

local function saturate ( element , value ) 
if ( element == "float" or element == "number" ) then
return value
end
local bits = BITS [ element ]
local low = SIGNED [ element ] and - ( 2 ^ ( bits - 1 ) ) or 0
local high = SIGNED [ element ] and 2 ^ ( bits - 1 ) - 1 or 2 ^ bits - 1

return math . max ( low , math . min ( high , value ) )
end

local function popcount ( element , value ) 
if BITS [ element ] == 64 then
return nupp . math . u64 . popcount ( ( 0ULL + ( value ) ) )
end

return nupp . math . u32 . popcount ( pattern ( element , value ) )
end






function lane . fromStorage ( element , n , storage ) 
local lanes = { }
for i = 1 , n do
lanes [ i ] = wrap ( element , ( storage ) [ i - 1 ] )
end

return vectorOf ( element , n , lanes )
end




local METHODS = {
propagatingMin = function ( _element , a , b ) 
return extremum ( a , b , true , true )
end ,
propagatingMax = function ( _element , a , b ) 
return extremum ( a , b , false , true )
end ,
numberMin = function ( _element , a , b ) 
return extremum ( a , b , true , false )
end ,
numberMax = function ( _element , a , b ) 
return extremum ( a , b , false , false )
end ,
extract = function ( _element , a , index ) 
if index ~= 1 then
error ( "SIMD lane extraction index exceeds the logical species lanes" , 3 )
end
return a
end ,
insert = function ( element , _a , index , value ) 
if index ~= 1 then
error ( "SIMD lane insertion index exceeds the logical species lanes" , 3 )
end
return wrap ( element , value )
end ,
reverse = function ( _element , a ) 
return a
end ,
interleave = function ( _element , a , b ) 
return a , b
end ,
deinterleave = function ( _element , a , b ) 
return a , b
end ,
rotateLeft = function ( _element , a ) 
return a
end ,
rotateRight = function ( _element , a ) 
return a
end ,
align = function ( _element , a , previous , offset ) 
if offset == 0 then
return a
end
return previous
end ,
swizzle = function ( _element , a , index , second , third , fourth ) 
if index == 1 then
return a
elseif index == 2 and second ~= nil then
return second
elseif index == 3 and third ~= nil then
return third
elseif index == 4 and fourth ~= nil then
return fourth
end

return 0
end ,
compress = function ( _element , a , selected ) 
return selected and a or 0
end ,
expand = function ( _element , a , selected ) 
return selected and a or 0
end ,
orderedPrefixSum = function ( _element , a ) 
return a
end ,
prefixXor = function ( _element , a ) 
return a
end ,
fma = function ( element , a , b , c ) 
if element == "float" then
return nupp . math . f32 . fma (
nupp . math . f32 . narrow ( a ) ,
nupp . math . f32 . narrow ( b ) ,
nupp . math . f32 . narrow ( c )
)
end

return wrap ( element , ( a ) * ( b ) + ( c ) )
end ,
saturatingAdd = function ( element , a , b ) 
return wrap ( element , saturate ( element , ( a ) + ( b ) ) )
end ,
saturatingSub = function ( element , a , b ) 
return wrap ( element , saturate ( element , ( a ) - ( b ) ) )
end ,
popcount = function ( element , a ) 
return popcount ( element , a )
end ,
mulHigh = function ( element , a , b ) 
local bits = BITS [ element ]
if bits == 64 then
error ( "mulHigh on a 64-bit lane is not available in the one-lane species" , 3 )
end
if bits <= 16 then
return wrap ( element , math . floor ( ( a ) * ( b ) / 2 ^ bits ) )
end

local left = pattern ( element , a )
local right = pattern ( element , b )
local lowA , highA = left % 65536 , math . floor ( left / 65536 )
local lowB , highB = right % 65536 , math . floor ( right / 65536 )
local low = lowA * lowB
local cross = highA * lowB + lowA * highB + math . floor ( low / 65536 )
local high = highA * highB + math . floor ( cross / 65536 )
if SIGNED [ element ] then
if ( a ) < 0 then
high = high - right
end
if ( b ) < 0 then
high = high - left
end
end

return wrap ( element , high )
end ,

sqrt = function ( element , a ) 
return wrap ( element , math . sqrt ( a ) )
end ,
abs = function ( element , a ) 
return wrap ( element , math . abs ( a ) )
end ,
floor = function ( element , a ) 
return wrap ( element , math . floor ( a ) )
end ,
ceil = function ( element , a ) 
return wrap ( element , math . ceil ( a ) )
end ,

select = function ( _element , mask , yes , no ) 
if mask then
return yes
end
return no
end ,
any = function ( _element , mask ) 
return mask == true
end ,
all = function ( _element , mask ) 
return mask == true
end ,
count = function ( _element , mask ) 
return mask and 1 or 0
end ,
first = function ( _element , mask ) 
return mask and 1 or 0
end ,
bits = function ( _element , mask ) 
return mask and 1ULL or 0ULL
end ,
}



local function laneIndex ( index , n , what ) 
local i = tonumber ( index )
if i == nil or i < 1 or i > n or i % 1 ~= 0 then
error ( "SIMD lane " .. what .. " index exceeds the logical species lanes" , 4 )
end

return i
end




local WIDE = {
extract = function ( _element , n , a , index ) 
return laneAt ( a , laneIndex ( index , n , "extraction" ) )
end ,
insert = function ( element , n , a , index , value ) 
local lanes = copyLanes ( a , n )
lanes [ laneIndex ( index , n , "insertion" ) ] = wrap ( element , value )

return vectorOf ( element , n , lanes )
end ,
reverse = function ( element , n , a ) 
local lanes = { }
for i = 1 , n do
lanes [ i ] = laneAt ( a , n + 1 - i )
end

return vectorOf ( element , n , lanes )
end ,
interleave = function ( element , n , a , b ) 
local run = { }
for i = 1 , n do
run [ 2 * i - 1 ] = laneAt ( a , i )
run [ 2 * i ] = laneAt ( b , i )
end
local first = { }
local second = { }
for i = 1 , n do
first [ i ] = run [ i ]
second [ i ] = run [ n + i ]
end

return vectorOf ( element , n , first ) , vectorOf ( element , n , second )
end ,
deinterleave = function ( element , n , a , b ) 
local odd = { }
local even = { }
for run = 1 , 2 * n do
local value = run <= n and laneAt ( a , run ) or laneAt ( b , run - n )
if run % 2 == 1 then
odd [ ( ( run + 1 ) / 2 ) ] = value
else
even [ ( run / 2 ) ] = value
end
end

return vectorOf ( element , n , odd ) , vectorOf ( element , n , even )
end ,
rotateLeft = function ( element , n , a , count ) 
local by = ( tonumber ( count ) ) % n
local lanes = { }
for i = 1 , n do
lanes [ i ] = laneAt ( a , ( ( i - 1 + by ) % n + 1 ) )
end

return vectorOf ( element , n , lanes )
end ,
rotateRight = function ( element , n , a , count ) 
local by = ( tonumber ( count ) ) % n
local lanes = { }
for i = 1 , n do
lanes [ i ] = laneAt ( a , ( ( i - 1 - by ) % n + 1 ) )
end

return vectorOf ( element , n , lanes )
end ,
align = function ( element , n , a , previous , offset ) 
local by = tonumber ( offset )
if by == nil or by < 0 or by > n or by % 1 ~= 0 then
error ( "SIMD align offset exceeds the logical species lanes" , 3 )
end
local lanes = { }
for i = 1 , n do
if i <= by then
lanes [ i ] = laneAt ( previous , ( n - by + i ) )
else
lanes [ i ] = laneAt ( a , ( i - by ) )
end
end

return vectorOf ( element , n , lanes )
end ,
swizzle = function ( element , n , a , indices , other , third , fourth ) 
local run = copyLanes ( a , n )
for _ , more in ipairs ( { other , third , fourth } ) do
for i = 1 , n do
run [ # run + 1 ] = laneAt ( more , i )
end
end
local lanes = { }
for i = 1 , n do
local index = tonumber ( laneAt ( indices , i ) )
if index ~= nil and index >= 1 and index <= # run and index % 1 == 0 then
lanes [ i ] = run [ index ]
else
lanes [ i ] = wrap ( element , 0 )
end
end

return vectorOf ( element , n , lanes )
end ,
compress = function ( element , n , a , selected ) 
local lanes = { }
for i = 1 , n do
if laneAt ( selected , i ) == true then
lanes [ # lanes + 1 ] = laneAt ( a , i )
end
end
for i = # lanes + 1 , n do
lanes [ i ] = wrap ( element , 0 )
end

return vectorOf ( element , n , lanes )
end ,
expand = function ( element , n , a , selected ) 
local lanes = { }
local packed = 0
for i = 1 , n do
if laneAt ( selected , i ) == true then
packed = packed + 1
lanes [ i ] = laneAt ( a , packed )
else
lanes [ i ] = wrap ( element , 0 )
end
end

return vectorOf ( element , n , lanes )
end ,
orderedPrefixSum = function ( element , n , a ) 
local lanes = { }
lanes [ 1 ] = laneAt ( a , 1 )
for i = 2 , n do
lanes [ i ] = binaryLane ( "+" , element , lanes [ i - 1 ] , laneAt ( a , i ) )
end

return vectorOf ( element , n , lanes )
end ,
prefixXor = function ( element , n , a ) 
local lanes = { }
lanes [ 1 ] = laneAt ( a , 1 )
for i = 2 , n do
lanes [ i ] = binaryLane ( "~" , element , lanes [ i - 1 ] , laneAt ( a , i ) )
end

return vectorOf ( element , n , lanes )
end ,

select = function ( _element , n , mask , yes , no ) 
local element = carriedElement ( elementOf ( mask ) , yes , no )
local lanes = { }
for i = 1 , n do
if laneAt ( mask , i ) == true then
lanes [ i ] = wrap ( element , laneAt ( yes , i ) )
else
lanes [ i ] = wrap ( element , laneAt ( no , i ) )
end
end

return vectorOf ( element , n , lanes )
end ,
any = function ( _element , n , mask ) 
for i = 1 , n do
if laneAt ( mask , i ) == true then
return true
end
end

return false
end ,
all = function ( _element , n , mask ) 
for i = 1 , n do
if laneAt ( mask , i ) ~= true then
return false
end
end

return true
end ,
count = function ( _element , n , mask ) 
local total = 0
for i = 1 , n do
if laneAt ( mask , i ) == true then
total = total + 1
end
end

return total
end ,
first = function ( _element , n , mask ) 
for i = 1 , n do
if laneAt ( mask , i ) == true then
return i
end
end

return 0
end ,
bits = function ( _element , n , mask ) 
local total = 0ULL
for i = 1 , n do
if laneAt ( mask , i ) == true then
total = total + ( 2 ^ ( i - 1 ) )
end
end

return total
end ,
}



function lane . method ( name , element , receiver , ... ) 
local method = METHODS [ name ]
if method == nil then
error ( "method :" .. name .. " is not a SIMD lane operation" , 2 )
end
local n = lanesOf ( receiver )
if n == nil then
return method ( element , receiver , ... )
end
local wide = WIDE [ name ]
if wide ~= nil then
return wide ( element , n , receiver , ... )
end

local count = select ( "#" , ... )
local arguments = { ... }
local lanes = { }
for i = 1 , n do
local own = { }
for k = 1 , count do
own [ k ] = laneAt ( arguments [ k ] , i )
end
lanes [ i ] = method ( element , laneAt ( receiver , i ) , unpack ( own , 1 , count ) )
end

return vectorOf ( elementOf ( receiver ) , n , lanes )
end

simd . lane = lane



local function spanCount ( source ) 
return ( source ) . count
end


local function readAt ( source , offset , field ) 
local value = ( source ) : get ( offset )
if field ~= nil then
return ( value ) [ field ]
end

return value
end

local scalarSpecies


local function convertLane ( element , value ) 
if ( element == "float" or element == "number" ) then
return wrap ( element , tonumber ( value ) )
end
local number = tonumber ( value )
if number ~= number then
number = 0
end

return wrap ( element , truncate ( number ) )
end



local function reinterpretLane ( element , value ) 
if element == "float" then
return nupp . math . f32 . fromBits ( pattern ( "uint32" , value ) )
elseif BITS [ element ] == 32 and type ( value ) == "number" and value % 1 ~= 0 then

return wrap ( element , nupp . math . f32 . toBits ( nupp . math . f32 . narrow ( value ) ) )
elseif element == "number" or BITS [ element ] == 64 then
error ( "a 64-bit reinterpretation is not available as ordinary Lua" , 3 )
end

return wrap ( element , value )
end




local LuaSpecies = {} LuaSpecies.__index = LuaSpecies





function LuaSpecies:make(lanes) 
if self . lanes == 1 then
return lanes [ 1 ]
end

return vectorOf ( self . element , self . lanes , lanes )
end

function LuaSpecies:makeMask(lanes) 
if self . lanes == 1 then
return lanes [ 1 ]
end

return maskOf ( self . element , self . lanes , lanes )
end


function LuaSpecies:readOrZero(source, index) 
if index < 1 or index > spanCount ( source ) then
return wrap ( self . element , 0 )
end

return wrap ( self . element , ( source ) : get ( index ) )
end

function LuaSpecies:load(source, offset, third, fourth) 
local field = nil
local active = third
if type ( third ) == "string" then
field = third
active = fourth
end
local lanes = { }
for i = 1 , self . lanes do
if activeAt ( active , i ) then
lanes [ i ] = wrap ( self . element , readAt ( source , ( offset ) + i - 1 , field ) )
else
lanes [ i ] = wrap ( self . element , 0 )
end
end

return self : make ( lanes )
end

function LuaSpecies:store(destination, offset, third, fourth, fifth) 
local target = destination
if type ( third ) == "string" then
local field = third
for i = 1 , self . lanes do
if activeAt ( fifth , i ) then
local at = ( offset ) + i - 1
local row = target : get ( at )
row [ field ] = laneAt ( fourth , i )
target : set ( at , row )
end
end
return
end
for i = 1 , self . lanes do
if activeAt ( fourth , i ) then
target : set ( ( offset ) + i - 1 , laneAt ( third , i ) )
end
end
end

function LuaSpecies:gather(source, index, active) 
local lanes = { }
for i = 1 , self . lanes do
if activeAt ( active , i ) then
lanes [ i ] = self : readOrZero ( source , tonumber ( laneAt ( index , i ) ) )
else
lanes [ i ] = wrap ( self . element , 0 )
end
end

return self : make ( lanes )
end

function LuaSpecies:scatter(destination, index, value, active) 
local target = destination
local limit = spanCount ( destination )
for i = 1 , self . lanes do
local at = tonumber ( laneAt ( index , i ) )
if activeAt ( active , i ) and at >= 1 and at <= limit then
target : set ( at , laneAt ( value , i ) )
end
end
end

function LuaSpecies:scatterUnchecked(destination, index, value, active) 
self : scatter ( destination , index , value , active )
end

function LuaSpecies:convert(value) 
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = convertLane ( self . element , laneAt ( value , i ) )
end

return self : make ( lanes )
end

function LuaSpecies:reinterpret(value) 
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = reinterpretLane ( self . element , laneAt ( value , i ) )
end

return self : make ( lanes )
end


function LuaSpecies:widen(witness) 
return scalarSpecies ( witness , self . lanes > 1 and self . lanes or nil )
end

function LuaSpecies:narrow(witness) 
return scalarSpecies ( witness , self . lanes > 1 and self . lanes or nil )
end

function LuaSpecies:splat(value) 
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = wrap ( self . element , value )
end

return self : make ( lanes )
end

function LuaSpecies:iota(first, step) 
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = wrap ( self . element , ( first ) + ( i - 1 ) * ( step ) )
end

return self : make ( lanes )
end

function LuaSpecies:tail(active) 
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = i <= ( active )
end

return self : makeMask ( lanes )
end

function LuaSpecies:mask(value) 
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = laneAt ( value , i ) == true
end

return self : makeMask ( lanes )
end

function LuaSpecies:map(operation, ...) 
local count = select ( "#" , ... )
local arguments = { ... }
local apply = operation
local lanes = { }
for i = 1 , self . lanes do
local own = { }
for k = 1 , count do
own [ k ] = laneAt ( arguments [ k ] , i )
end
lanes [ i ] = wrap ( self . element , apply ( unpack ( own , 1 , count ) ) )
end

return self : make ( lanes )
end

function LuaSpecies:over(count) 
local n = self . lanes
local limit = count
local at = 1 - n
local full = self : tail ( n )

return function ( ) 
at = at + n
if at > limit then
return nil , nil
end
local room = limit - at + 1
if room >= n then
return at , full
end

return at , self : tail ( room )
end
end




function LuaSpecies:loadRun(source, offset, k) 
local vectors = { }
for j = 1 , k do
local lanes = { }
for i = 1 , self . lanes do
lanes [ i ] = self : readOrZero ( source , ( offset ) + k * ( i - 1 ) + ( j - 1 ) )
end
vectors [ j ] = self : make ( lanes )
end

return vectors
end


function LuaSpecies:storeRun(destination, offset, vectors) 
local target = destination
local limit = spanCount ( destination )
local k = # vectors
for j = 1 , k do
for i = 1 , self . lanes do
local at = ( offset ) + k * ( i - 1 ) + ( j - 1 )
if at >= 1 and at <= limit then
target : set ( at , laneAt ( vectors [ j ] , i ) )
end
end
end
end

function LuaSpecies:loadPairs(source, offset) 
local run = self : loadRun ( source , offset , 2 )

return run [ 1 ] , run [ 2 ]
end

function LuaSpecies:loadTriples(source, offset) 
local run = self : loadRun ( source , offset , 3 )

return run [ 1 ] , run [ 2 ] , run [ 3 ]
end

function LuaSpecies:loadQuads(source, offset) 
local run = self : loadRun ( source , offset , 4 )

return run [ 1 ] , run [ 2 ] , run [ 3 ] , run [ 4 ]
end

function LuaSpecies:storePairs(destination, offset, first, second) 
self : storeRun ( destination , offset , { first , second } )
end

function LuaSpecies:storeTriples(destination, offset, first, second, third) 
self : storeRun ( destination , offset , { first , second , third } )
end

function LuaSpecies:storeQuads(destination, offset, first, second, third, fourth) 
self : storeRun ( destination , offset , { first , second , third , fourth } )
end


local speciesCache = { }

scalarSpecies = function ( element , lanes ) 
local name = ELEMENT_OF [ element ]
if name == nil then
error ( "simd.species takes one of the scalar witnesses in nupp.mem.array, such as array.uint32" , 3 )
end
if lanes ~= nil and ( type ( lanes ) ~= "number" or lanes < 2 or lanes > 64 or lanes % 1 ~= 0 ) then
error ( "simd.species takes a witness and, for a fixed shape, one literal lane count" , 3 )
end
local width = 1
if lanes ~= nil then
width = lanes
end
local key = ( name ) .. "/" .. tostring ( width )
local found = speciesCache [ key ]
if found == nil then
found = _G.setmetatable({ lanes =  width ,  element =  name }, LuaSpecies)
speciesCache [ key ] = found
end

return found
end
































simd . species = ( function ( element , lanes ) 
return scalarSpecies ( element , lanes )
end )
























simd . vectors = ( function ( _element , _lanes ) 
return nil
end )






























local transpose

= function ( ... ) 


local first = ...
local n = lanesOf ( first )
if n == nil then
return ...
end
local count = select ( "#" , ... )
if count ~= n then
error ( "transpose needs as many rows as the species has lanes" , 2 )
end
local rows = { ... }
local element = elementOf ( first )
local columns = { }
for j = 1 , n do
local lanes = { }
for i = 1 , count do
lanes [ i ] = laneAt ( rows [ i ] , j )
end
columns [ j ] = vectorOf ( element , n , lanes )
end

return unpack ( columns , 1 , n )
end

simd . transpose = transpose










local horizontal = { }



local function roundingOf ( element ) 
if element == "float" then
return nupp . math . f32 . narrow
end

return keep
end




local function foldLanes ( value , name ) 
local n = lanesOf ( value )
local element = elementOf ( value )
local lanes = value
if name == "pairwiseSum" then
local sum = _G.setmetatable({ partials =  { } ,  count =  0 ,  round =  roundingOf ( element ) }, simd.PairwiseSum)
for i = 1 , n do
sum : add ( lanes [ i ] )
end

return sum : value ( )
elseif name == "pairwiseProduct" then
local product = _G.setmetatable({ partials =  { } ,  count =  0 ,  round =  roundingOf ( element ) }, simd.PairwiseProduct)
for i = 1 , n do
product : add ( lanes [ i ] )
end

return product : value ( )
end
local total = lanes [ 1 ]
for i = 2 , n do
local lane = lanes [ i ]
if name == "orderedSum" or name == "algebraicSum" or name == "wrappingSum" then
total = binaryLane ( "+" , element , total , lane )
elseif name == "orderedProduct" or name == "algebraicProduct" or name == "wrappingProduct" then
total = binaryLane ( "*" , element , total , lane )
elseif name == "andBits" then
total = binaryLane ( "&" , element , total , lane )
elseif name == "orBits" then
total = binaryLane ( "|" , element , total , lane )
elseif name == "xorBits" then
total = binaryLane ( "~" , element , total , lane )
elseif name == "propagatingMin" then
total = extremum ( total , lane , true , true )
elseif name == "propagatingMax" then
total = extremum ( total , lane , false , true )
elseif name == "numberMin" then
total = extremum ( total , lane , true , false )
elseif name == "numberMax" then
total = extremum ( total , lane , false , false )
elseif name == "integerMin" then
total = ( lane < total ) and lane or total
elseif name == "integerMax" then
total = ( total < lane ) and lane or total
else
error ( "horizontal." .. name .. " is not a lane reduction" , 3 )
end
end

return total
end


local function foldDot ( left , right , name ) 
local n = lanesOf ( left )
local round = roundingOf ( elementOf ( left ) )
if name == "pairwiseDot" then
local sum = _G.setmetatable({ partials =  { } ,  count =  0 ,  round =  round }, simd.PairwiseSum)
local dot = _G.setmetatable({ sum =  sum ,  round =  round }, simd.PairwiseDot)
for i = 1 , n do
dot : add ( laneAt ( left , i ) , laneAt ( right , i ) )
end

return dot : value ( )
end


local total = 0
for i = 1 , n do
total = round ( total + round ( ( laneAt ( left , i ) ) * ( laneAt ( right , i ) ) ) )
end

return total
end



local function argLane ( value , name ) 
local n = lanesOf ( value )
local maximum = name == "propagatingArgMax" or name == "numberArgMax"
local propagate = name == "propagatingArgMin" or name == "propagatingArgMax"
local best = laneAt ( value , 1 )
local position = 1
for i = 2 , n do
local candidate = laneAt ( value , i )
if extremumWins ( candidate , best , maximum , propagate ) then
best = candidate
position = i
end
end

return position
end




function horizontal . orderedSum ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "orderedSum" )
end

return value
end




function horizontal . pairwiseSum ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "pairwiseSum" )
end

return value
end




function horizontal . algebraicSum ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "algebraicSum" )
end

return value
end




function horizontal . orderedProduct ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "orderedProduct" )
end

return value
end




function horizontal . pairwiseProduct ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "pairwiseProduct" )
end

return value
end




function horizontal . algebraicProduct ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "algebraicProduct" )
end

return value
end



function horizontal . orderedDot ( left , right ) 
if lanesOf ( left ) ~= nil then
return foldDot ( left , right , "orderedDot" )
end
return ( ( left ) * ( right ) )
end



function horizontal . pairwiseDot ( left , right ) 
if lanesOf ( left ) ~= nil then
return foldDot ( left , right , "pairwiseDot" )
end
return ( ( left ) * ( right ) )
end



function horizontal . algebraicDot ( left , right ) 
if lanesOf ( left ) ~= nil then
return foldDot ( left , right , "algebraicDot" )
end
return ( ( left ) * ( right ) )
end

















function horizontal . propagatingMin ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "propagatingMin" )
end

return value
end




function horizontal . propagatingMax ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "propagatingMax" )
end

return value
end




function horizontal . numberMin ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "numberMin" )
end

return value
end




function horizontal . numberMax ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "numberMax" )
end

return value
end
















function horizontal . propagatingArgMin ( value ) 
if lanesOf ( value ) ~= nil then
return argLane ( value , "propagatingArgMin" )
end

return 1
end




function horizontal . propagatingArgMax ( value ) 
if lanesOf ( value ) ~= nil then
return argLane ( value , "propagatingArgMax" )
end

return 1
end




function horizontal . numberArgMin ( value ) 
if lanesOf ( value ) ~= nil then
return argLane ( value , "numberArgMin" )
end

return 1
end




function horizontal . numberArgMax ( value ) 
if lanesOf ( value ) ~= nil then
return argLane ( value , "numberArgMax" )
end

return 1
end







function horizontal . wrappingSum ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "wrappingSum" )
end

return value
end





function horizontal . wrappingProduct ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "wrappingProduct" )
end

return value
end





function horizontal . andBits ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "andBits" )
end

return value
end





function horizontal . orBits ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "orBits" )
end

return value
end





function horizontal . xorBits ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "xorBits" )
end

return value
end





function horizontal . integerMin ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "integerMin" )
end

return value
end





function horizontal . integerMax ( value ) 
if lanesOf ( value ) ~= nil then
return foldLanes ( value , "integerMax" )
end

return value
end

simd . horizontal = horizontal

local __nuppExportValue= simd ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.simd"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.simd"]=__nuppExports;return __nuppExports