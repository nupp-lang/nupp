_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local context = require ( "nupp.compiler.aot.llvm.context" )
local expressions = require ( "nupp.compiler.aot.llvm.expressions" )
local lanes = require ( "nupp.compiler.aot.llvm.simd.lanes" )
local prelude = require ( "nupp.compiler.aot.llvm.prelude" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local species = require ( "nupp.compiler.aot.llvm.simd.species" )

local reduce = { }


local registerTest









function reduce . bits ( ctx , found , mask ) 
local packed = context . value ( ctx , ("bitcast %s %s to i%d") : format ( found . mask , mask , found . lanes ) )
if found . lanes == 64 then
return packed
end

return context . value ( ctx , ("zext i%d %s to i64") : format ( found . lanes , packed ) )
end





registerTest = function (
ctx ,
widened ,
count ,
element ,
total ,
any
) 
local vector = "<" .. tostring ( count ) .. " x " .. element .. ">"
local registers = math . floor ( total / 128 )
local x86 = ctx . vectorRegister == "x"
local piece = x86 and "<16 x i8>" or "<4 x i32>"
local pieces = x86 and 16 or 4
local whole = "<" .. tostring ( registers * pieces ) .. " x " .. ( x86 and "i8" or "i32" ) .. ">"
local cast = context . value ( ctx , ("bitcast %s %s to %s") : format ( vector , widened , whole ) )
local combined = nil
for register = 0 , registers - 1 do
local picks = { }
for lane = 0 , pieces - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( register * pieces + lane )
end
local one = context . value (
ctx ,
("shufflevector %s %s, %s poison, <%d x i32> <%s>")

: format ( whole , cast , whole , pieces , table . concat ( picks , ", " ) )
)
combined = combined == nil and one
or context . value ( ctx , ("%s %s %s, %s") : format ( any and "or" or "and" , piece , combined , one ) )
end
if x86 then
local movemask = prelude . intrinsic ( ctx . module , "llvm.x86.sse2.pmovmskb.128" , "i32 @NAME(<16 x i8>)" )
local bits = context . value ( ctx , ("call i32 %s(<16 x i8> %s)") : format ( movemask , tostring ( combined ) ) )
return context . value ( ctx , ("icmp %s i32 %s, %s") : format ( any and "ne" or "eq" , bits , any and "0" or "65535" ) )
end


local name = any and "llvm.aarch64.neon.umaxp.v4i32" or "llvm.aarch64.neon.uminp.v4i32"
local pairwise = prelude . intrinsic ( ctx . module , name , "<4 x i32> @NAME(<4 x i32>, <4 x i32>)" )
local folded = context . value (
ctx ,
("call <4 x i32> %s(<4 x i32> %s, <4 x i32> %s)") : format ( pairwise , tostring ( combined ) , tostring ( combined ) )
)
local halves = context . value ( ctx , ("bitcast <4 x i32> %s to <2 x i64>") : format ( folded ) )
local low = context . value ( ctx , ("extractelement <2 x i64> %s, i32 0") : format ( halves ) )

return context . value ( ctx , ("icmp %s i64 %s, %s") : format ( any and "ne" or "eq" , low , any and "0" or "-1" ) )
end

const SWAPPED = { [ "ge" ] = "le" , [ "le" ] = "ge" , [ "gt" ] = "lt" , [ "lt" ] = "gt" , [ "ne" ] = "ne" , [ "eq" ] = "eq" , }





local function anyCompare ( ctx , mask ) 
if ctx . vectorRegister ~= "w" or mask . op ~= "simd_compare" then
return nil
end
local compare = mask
local found = context . species ( ctx , tostring ( compare . args [ 1 ] . type ) )
if found == nil
or ( found ) . float
or ( found ) . lanes * ( found ) . bits ~= 128
then
return nil
end
local lanesOf = found
local named = tostring ( compare . intrinsic )
local value , bound = compare . args [ 1 ] , compare . args [ 2 ]
if value . op == "simd_splat" and bound . op ~= "simd_splat" then
value , bound = bound , value
named = SWAPPED [ named ]
end
if bound . op ~= "simd_splat" or named == "eq" then
return nil
end
local vector = expressions . operand ( ctx , value )
local scalar , scalarType = expressions . value ( ctx , ( bound ) . args [ 1 ] )
local lane = lanes . toLane ( ctx , lanesOf , scalar , scalarType )
local wideLane = lanesOf . bits < 32
and context . value ( ctx , ("%s %s %s to i32") : format ( lanesOf . signed and "sext" or "zext" , lanesOf . scalar , lane ) )
or lane
local suffix = lanes . suffix ( lanesOf . lanes , lanesOf . scalar )

local function reduced ( kind ) 
local name = ("llvm.aarch64.neon.%s%sv.i32.%s") : format ( lanesOf . signed and "s" or "u" , kind , suffix )
local callee = prelude . intrinsic ( ctx . module , name , ("i32 @NAME(%s)") : format ( lanesOf . vector ) )
local result = context . value ( ctx , ("call i32 %s(%s %s)") : format ( callee , lanesOf . vector , vector ) )
if lanesOf . bits == 32 then
return result
end

local narrow = context . value ( ctx , ("trunc i32 %s to %s") : format ( result , lanesOf . scalar ) )

return context . value (
ctx ,
("%s %s %s to i32") : format ( lanesOf . signed and "sext" or "zext" , lanesOf . scalar , narrow )
)
end

if lanesOf . bits > 32 then
return nil
end
local zero = ( bound ) . args [ 1 ]
while zero . op == "numeric_cast" do
zero = ( zero ) . value
end
local isZero = ( zero . op == "constant" or zero . op == "constant_i32" or zero . op == "constant_i64" )
and tonumber ( tostring ( ( zero ) . value ) ) == 0
if named == "ne" and not lanesOf . signed and isZero then


return context . value ( ctx , ("icmp ne i32 %s, 0") : format ( reduced ( "max" ) ) )
elseif named == "ne" then

local largest , smallest = reduced ( "max" ) , reduced ( "min" )
local high = context . value ( ctx , ("icmp ne i32 %s, %s") : format ( largest , wideLane ) )
local low = context . value ( ctx , ("icmp ne i32 %s, %s") : format ( smallest , wideLane ) )
return context . value ( ctx , ("or i1 %s, %s") : format ( high , low ) )
end
local greater = named == "ge" or named == "gt"
local extreme = reduced ( greater and "max" or "min" )
local predicate = ( lanesOf . signed and "s" or "u" ) .. named

return context . value ( ctx , ("icmp %s i32 %s, %s") : format ( predicate , extreme , wideLane ) )
end

local function maskQuery ( ctx , node ) 
local simd = node
local found = lanes . of ( ctx , tostring ( simd . args [ 1 ] . type ) )
local query = tostring ( simd . op )
if query == "simd_mask_any" then
local shortcut = anyCompare ( ctx , simd . args [ 1 ] )
if shortcut ~= nil then
return shortcut , "bool"
end
end
local wide = "<" .. tostring ( found . lanes ) .. " x i" .. tostring ( found . bits ) .. ">"



local laneWide = ( query == "simd_mask_any" or query == "simd_mask_all" )
and ctx . tier ~= "avx512f"
and ctx . vectorRegister ~= ""


local carried = nil
if laneWide and simd . args [ 1 ] . op == "local" then
local slot = ctx . locals [ tostring ( ( simd . args [ 1 ] ) . uniqueName ) ]
if slot ~= nil and ( slot ) . carried then
carried = context . value ( ctx , ("load %s, ptr %s") : format ( wide , ( slot ) . pointer ) )
end
end
local mask = carried == nil and expressions . operand ( ctx , simd . args [ 1 ] ) or ""
local suffix = lanes . suffix ( found . lanes , "i1" )
if laneWide then



local widened = carried
or context . opaque ( ctx , context . value ( ctx , ("sext %s %s to %s") : format ( found . mask , mask , wide ) ) , wide )
local any = query == "simd_mask_any"
local total = found . lanes * found . bits
local element = "i" .. tostring ( found . bits )
local reduced = widened
local verb = any and "or" or "and"
if total % 128 == 0 and ctx . vectorRegister ~= "" then
return registerTest ( ctx , widened , found . lanes , element , total , any ) , "bool"
end
local callee = prelude . intrinsic (
ctx . module ,
"llvm.vector.reduce." .. verb .. "." .. lanes . suffix ( found . lanes , element ) ,
("%s @NAME(%s)") : format ( element , wide )
)
local folded = context . value ( ctx , ("call %s %s(%s %s)") : format ( element , callee , wide , reduced ) )
return context . value (
ctx ,
("icmp %s %s %s, %s") : format ( any and "ne" or "eq" , element , folded , any and "0" or "-1" )
) , "bool"
end
if query == "simd_mask_any" or query == "simd_mask_all" then
local verb = query == "simd_mask_any" and "or" or "and"
local callee = prelude . intrinsic (
ctx . module ,
"llvm.vector.reduce." .. verb .. "." .. suffix ,
("i1 @NAME(%s)") : format ( found . mask )
)
return context . value ( ctx , ("call i1 %s(%s %s)") : format ( callee , found . mask , mask ) ) , "bool"
end
local bits = reduce . bits ( ctx , found , mask )
if query == "simd_mask_bits" then
return bits , "u64"
elseif query == "simd_mask_count" then
local ctpop = prelude . intrinsic ( ctx . module , "llvm.ctpop.i64" , "i64 @NAME(i64)" )
local count = context . value ( ctx , ("call i64 %s(i64 %s)") : format ( ctpop , bits ) )
return context . value ( ctx , ("trunc i64 %s to i32") : format ( count ) ) , "u32"
end

local cttz = prelude . intrinsic ( ctx . module , "llvm.cttz.i64" , "i64 @NAME(i64, i1)" )
local zeros = context . value ( ctx , ("call i64 %s(i64 %s, i1 false)") : format ( cttz , bits ) )
local lane = context . value ( ctx , ("add i64 %s, 1") : format ( zeros ) )
local none = context . value ( ctx , ("icmp eq i64 %s, 0") : format ( bits ) )
local picked = context . value ( ctx , ("select i1 %s, i64 0, i64 %s") : format ( none , lane ) )

return context . value ( ctx , ("trunc i64 %s to i32") : format ( picked ) ) , "u32"
end


local function unpack ( ctx , found , vector ) 
local values = { }
for index = 0 , found . lanes - 1 do
values [ # values + 1 ] = lanes . extract ( ctx , found , vector , index )
end

return values
end


local function prefix ( ctx , node ) 
local simd = node
local typeName = tostring ( simd . type )
local found = lanes . of ( ctx , typeName )
local vector = expressions . operand ( ctx , simd . args [ 1 ] )
local instruction = simd . intrinsic == "prefix_xor" and "xor" or found . float and "fadd" or "add"
if not found . float then


local running = vector
local distance = 1
while distance < found . lanes do
local picks = { }
for lane = 0 , found . lanes - 1 do


picks [ # picks + 1 ] = "i32 " .. tostring ( lane < distance and 0 or found . lanes + lane - distance )
end
local shifted = context . value (
ctx ,
("shufflevector %s zeroinitializer, %s %s, <%d x i32> <%s>")

: format ( found . vector , found . vector , running , found . lanes , table . concat ( picks , ", " ) )
)
running = context . value ( ctx , ("%s %s %s, %s") : format ( instruction , found . vector , running , shifted ) )
distance = distance * 2
end
return running , typeName
end
local values = unpack ( ctx , found , vector )
local out = lanes . insert ( ctx , found , "poison" , values [ 1 ] , 0 )
local running = values [ 1 ]
for index = 2 , # values do
running = context . value ( ctx , ("%s %s %s, %s") : format ( instruction , found . scalar , running , values [ index ] ) )
out = lanes . insert ( ctx , found , out , running , index - 1 )
end

return out , typeName
end



local function combine ( ctx , found , operation , a , b ) 
local instruction = operation == "product" and ( found . float and "fmul" or "mul" )
or operation == "sum" and ( found . float and "fadd" or "add" )
or operation

return context . value ( ctx , ("%s %s %s, %s") : format ( instruction , found . scalar , a , b ) )
end



local function pairwise ( ctx , found , operation , values ) 
local level = values
while # level > 1 do
local next = { }
local index = 1
while index + 1 <= # level do
next [ # next + 1 ] = combine ( ctx , found , operation , level [ index ] , level [ index + 1 ] )
index = index + 2
end
if index <= # level then
next [ # next + 1 ] = level [ index ]
end
level = next
end

return level [ 1 ]
end


local function products ( ctx , found , a , b ) 
local out = { }
for index = 1 , # a do
out [ index ] = combine ( ctx , found , "product" , a [ index ] , b [ index ] )
end

return out
end


local function fused ( ctx , found , a , b , c ) 
local t = found . scalar
local fma = prelude . intrinsic (
ctx . module ,
"llvm.fma." .. ( t == "double" and "f64" or "f32" ) ,
("%s @NAME(%s, %s, %s)") : format ( t , t , t , t )
)

return context . value ( ctx , ("call %s %s(%s %s, %s %s, %s %s)") : format ( t , fma , t , a , t , b , t , c ) )
end


local function argBetter (
ctx ,
found ,
v ,
best ,
minimum ,
propagating
) 
local t = found . scalar
if not found . float then
local predicate = ( found . signed and "s" or "u" ) .. ( minimum and "lt" or "gt" )
return context . value ( ctx , ("icmp %s %s %s, %s") : format ( predicate , t , v , best ) )
end
local bitsType = lanes . bitsType ( found )
local vNan = context . value ( ctx , ("fcmp uno %s %s, %s") : format ( t , v , v ) )
local bestNan = context . value ( ctx , ("fcmp uno %s %s, %s") : format ( t , best , best ) )
local strict = context . value ( ctx , ("fcmp %s %s %s, %s") : format ( minimum and "olt" or "ogt" , t , v , best ) )
local equal = context . value ( ctx , ("fcmp oeq %s %s, %s") : format ( t , v , best ) )
local vBits = context . value ( ctx , ("bitcast %s %s to %s") : format ( t , v , bitsType ) )
local bestBits = context . value ( ctx , ("bitcast %s %s to %s") : format ( t , best , bitsType ) )
local vSign = context . value ( ctx , ("icmp slt %s %s, 0") : format ( bitsType , vBits ) )
local bestSign = context . value ( ctx , ("icmp slt %s %s, 0") : format ( bitsType , bestBits ) )

local winner = minimum and vSign or bestSign
local loser = minimum and bestSign or vSign
local loserClear = context . value ( ctx , ("xor i1 %s, true") : format ( loser ) )
local signs = context . value ( ctx , ("and i1 %s, %s") : format ( winner , loserClear ) )
local tie = context . value ( ctx , ("and i1 %s, %s") : format ( equal , signs ) )
local ordered = context . value ( ctx , ("or i1 %s, %s") : format ( strict , tie ) )
if propagating then
local either = context . value ( ctx , ("or i1 %s, %s") : format ( vNan , ordered ) )
local bestNumber = context . value ( ctx , ("xor i1 %s, true") : format ( bestNan ) )
return context . value ( ctx , ("and i1 %s, %s") : format ( bestNumber , either ) )
end
local either = context . value ( ctx , ("or i1 %s, %s") : format ( bestNan , ordered ) )
local vNumber = context . value ( ctx , ("xor i1 %s, true") : format ( vNan ) )

return context . value ( ctx , ("and i1 %s, %s") : format ( vNumber , either ) )
end

local function horizontal ( ctx , node ) 
local simd = node
local found = lanes . of ( ctx , tostring ( simd . args [ 1 ] . type ) )
local intrinsic = tostring ( simd . intrinsic )
local order , kind = intrinsic : match ( "^(%a+)_(.+)$" )
local values = unpack ( ctx , found , expressions . operand ( ctx , simd . args [ 1 ] ) )
local t = found . scalar
local zero = found . float and "0.0" or "0"
local one = found . float and "1.0" or "1"

if order == "exact" then



local result = values [ 1 ]
for index = 2 , # values do
result = combine ( ctx , found , kind , result , values [ index ] )
end
return lanes . fromLane ( ctx , found , result )
end

if kind == "sum" or kind == "product" or kind == "dot" then
local operation = kind == "product" and "product" or "sum"
local identity = kind == "product" and one or zero
local leaves = values
if kind == "dot" then
local right = unpack ( ctx , found , expressions . operand ( ctx , simd . args [ 2 ] ) )
if order == "algebraic" then

local even , odd = zero , zero
local index = 1
while index + 1 <= # values do
even = fused ( ctx , found , values [ index ] , right [ index ] , even )
odd = fused ( ctx , found , values [ index + 1 ] , right [ index + 1 ] , odd )
index = index + 2
end
if index <= # values then
even = fused ( ctx , found , values [ index ] , right [ index ] , even )
end
return lanes . fromLane ( ctx , found , combine ( ctx , found , "sum" , even , odd ) )
end
leaves = products ( ctx , found , values , right )
end
local result
if order == "ordered" then
result = identity
for _ , value in ipairs ( leaves ) do
result = combine ( ctx , found , operation , result , value )
end
elseif order == "pairwise" then
result = pairwise ( ctx , found , operation , leaves )
elseif order == "algebraic" then
local even , odd = identity , identity
local index = 1
while index + 1 <= # leaves do
even = combine ( ctx , found , operation , even , leaves [ index ] )
odd = combine ( ctx , found , operation , odd , leaves [ index + 1 ] )
index = index + 2
end
if index <= # leaves then
even = combine ( ctx , found , operation , even , leaves [ index ] )
end
result = combine ( ctx , found , operation , even , odd )
else
expressions . unsupported ( "horizontal order " .. tostring ( order ) )
end
return lanes . fromLane ( ctx , found , result )
end

local propagating = order == "propagating"
if kind == "min" or kind == "max" then
local shape = lanes . scalarShape ( found )
local result = values [ 1 ]
for index = 2 , # values do
result = found . float and lanes . floatExtreme ( ctx , shape , result , values [ index ] , kind == "min" , propagating )
or lanes . integerExtreme ( ctx , shape , result , values [ index ] , kind == "min" , found . signed )
end
return lanes . fromLane ( ctx , found , result )
elseif kind == "arg_min" or kind == "arg_max" then
local minimum = kind == "arg_min"
local best = values [ 1 ]
local at = "0"
for index = 2 , # values do
local take = argBetter ( ctx , found , values [ index ] , best , minimum , propagating )
best = context . value ( ctx , ("select i1 %s, %s %s, %s %s") : format ( take , t , values [ index ] , t , best ) )
at = context . value ( ctx , ("select i1 %s, i32 %d, i32 %s") : format ( take , index - 1 , at ) )
end
local lane = context . value ( ctx , ("add i32 %s, 1") : format ( at ) )
return context . value ( ctx , ("uitofp i32 %s to double") : format ( lane ) ) , "f64"
end

expressions . unsupported ( "horizontal operation " .. intrinsic )
end

reduce . EXPRESSIONS = {
[ "simd_mask_any" ] = maskQuery ,
[ "simd_mask_all" ] = maskQuery ,
[ "simd_mask_count" ] = maskQuery ,
[ "simd_mask_first" ] = maskQuery ,
[ "simd_mask_bits" ] = maskQuery ,
[ "simd_prefix" ] = prefix ,
[ "simd_horizontal" ] = horizontal ,
}

local __nuppExportValue= reduce ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.simd.reduce"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.simd.reduce"]=__nuppExports;return __nuppExports