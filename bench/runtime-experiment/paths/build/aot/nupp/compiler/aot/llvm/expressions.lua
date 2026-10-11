_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.expressions\0runtime\0001") };


























local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local prelude = require ( "nupp.compiler.aot.llvm.prelude" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local targetLayout = require ( "nupp.compiler.targetlayout" )
local text = require ( "nupp.compiler.aot.llvm.text" )
local types = require ( "nupp.compiler.aot.llvm.types" )

local expressions = { }


expressions . UNSUPPORTED = "llvm backend does not yet emit "



function expressions . unsupported ( what ) 
error ( expressions . UNSUPPORTED .. what , 0 )
end

local exactNarrowing
local integralOperand
local integerValue








function expressions . convert ( ctx , value , from , to ) 
if from == to then
return value
end
local target = types . require ( to )
local source = types . require ( from )
if source == target and types . isInteger ( from ) and types . isInteger ( to ) then

return value
end
if to == "bool" then
if types . isFloat ( from ) then
return context . value ( ctx , ("fcmp une %s %s, 0.0") : format ( source , value ) )
end

return context . value ( ctx , ("icmp ne %s %s, 0") : format ( source , value ) )
end
if from == "bool" then
if types . isFloat ( to ) then
return context . value ( ctx , ("uitofp i1 %s to %s") : format ( value , target ) )
end

return context . value ( ctx , ("zext i1 %s to %s") : format ( value , target ) )
end
if types . isFloat ( from ) and types . isFloat ( to ) then
local op = types . bits ( from ) < types . bits ( to ) and "fpext" or "fptrunc"

return context . value ( ctx , ("%s %s %s to %s") : format ( op , source , value , target ) )
end
if types . isInteger ( from ) and types . isFloat ( to ) then
local op = types . signed ( from ) and "sitofp" or "uitofp"

return context . value ( ctx , ("%s %s %s to %s") : format ( op , source , value , target ) )
end
if types . isFloat ( from ) and types . isInteger ( to ) then
local sat = types . signed ( to ) and "fptosi" or "fptoui"
local name = ("llvm.%s.sat.%s.%s") : format ( sat , target , source == "double" and "f64" or "f32" )
local callee = prelude . intrinsic ( ctx . module , name , ("%s @NAME(%s)") : format ( target , source ) )

return context . value ( ctx , ("call %s %s(%s %s)") : format ( target , callee , source , value ) )
end

local fromBits , toBits = types . bits ( from ) , types . bits ( to )
if fromBits > toBits then
return context . value ( ctx , ("trunc %s %s to %s") : format ( source , value , target ) )
end
local op = types . signed ( from ) and "sext" or "zext"

return context . value ( ctx , ("%s %s %s to %s") : format ( op , source , value , target ) )
end


local function toDouble ( ctx , value , from ) 
return expressions . convert ( ctx , value , from , "f64" )
end



local function u32Bits ( ctx , value , from ) 
if from == "i32" or from == "u32" then
return value
elseif from == "i64" or from == "u64" then
return context . value ( ctx , ("trunc i64 %s to i32") : format ( value ) )
elseif from == "bool" then
return context . value ( ctx , ("zext i1 %s to i32") : format ( value ) )
elseif from == "f32" then
value = context . value ( ctx , ("fpext float %s to double") : format ( value ) )
end
local wrap = prelude . use ( ctx . module , "nupp.wrap.u32" )

return context . value ( ctx , ("call i32 %s(double %s)") : format ( wrap , value ) )
end


local function u64Bits ( ctx , value , from ) 
return expressions . convert ( ctx , value , from , "u64" )
end







function expressions . luaInteger ( ctx , value , from , to ) 
if from == "f32" then
value = context . value ( ctx , ("fpext float %s to double") : format ( value ) )
end
local signed = expressions . convert ( ctx , value , "f64" , "i64" )
if to == "i64" then
return signed
elseif to == "u64" then
local unsigned = expressions . convert ( ctx , value , "f64" , "u64" )
local negative = context . value ( ctx , ("fcmp olt double %s, 0.0") : format ( value ) )

return context . value ( ctx , ("select i1 %s, i64 %s, i64 %s") : format ( negative , signed , unsigned ) )
end

return context . value ( ctx , ("trunc i64 %s to %s") : format ( signed , types . require ( to ) ) )
end





const FLOAT_PREDICATE

= { [ "lt" ] = "olt" , [ "le" ] = "ole" , [ "gt" ] = "ogt" , [ "ge" ] = "oge" , [ "eq" ] = "oeq" , [ "ne" ] = "une" , }

const SIGNED_PREDICATE

= { [ "lt" ] = "slt" , [ "le" ] = "sle" , [ "gt" ] = "sgt" , [ "ge" ] = "sge" , [ "eq" ] = "eq" , [ "ne" ] = "ne" , }

const UNSIGNED_PREDICATE

= { [ "lt" ] = "ult" , [ "le" ] = "ule" , [ "gt" ] = "ugt" , [ "ge" ] = "uge" , [ "eq" ] = "eq" , [ "ne" ] = "ne" , }






function expressions . compare (
ctx ,
operation ,
left ,
leftType ,
right ,
rightType ,
byValue
) 
if leftType == "bool" and rightType == "bool" then
return context . value ( ctx , ("icmp %s i1 %s, %s") : format ( SIGNED_PREDICATE [ operation ] , left , right ) )
end
local wide = ( leftType == "u64" or rightType == "u64" ) and "u64"
or ( leftType == "i64" or rightType == "i64" ) and "i64"
or nil
if wide ~= nil and leftType ~= rightType and not byValue then





local function operand ( value , typeName ) 
if types . isFloat ( typeName ) then
return expressions . luaInteger ( ctx , value , typeName , wide )
end

return expressions . convert ( ctx , value , typeName , wide )
end

local predicate = wide == "u64" and UNSIGNED_PREDICATE [ operation ] or SIGNED_PREDICATE [ operation ]

return context . value (
ctx ,
("icmp %s i64 %s, %s") : format ( predicate , operand ( left , leftType ) , operand ( right , rightType ) )
)
end
if types . isFloat ( leftType ) or types . isFloat ( rightType ) then


local a , b = ( expressions . convert ( ctx , left , leftType , "f64" ) ) , ( expressions . convert ( ctx , right , rightType , "f64" ) )

return context . value ( ctx , ("fcmp %s double %s, %s") : format ( FLOAT_PREDICATE [ operation ] , a , b ) )
end
if leftType == rightType then
local t = types . require ( leftType )
local predicate = types . signed ( leftType ) and SIGNED_PREDICATE [ operation ] or UNSIGNED_PREDICATE [ operation ]

return context . value ( ctx , ("icmp %s %s %s, %s") : format ( predicate , t , left , right ) )
end




local function widen ( value , typeName ) 
return context . value (
ctx ,
("%s %s %s to i65") : format ( types . signed ( typeName ) and "sext" or "zext" , types . require ( typeName ) , value )
)
end

return context . value (
ctx ,
("icmp %s i65 %s, %s")

: format ( SIGNED_PREDICATE [ operation ] , widen ( left , leftType ) , widen ( right , rightType ) )
)
end





const LIBM

= {
[ "cos" ] = 1 ,
[ "tan" ] = 1 ,
[ "asin" ] = 1 ,
[ "acos" ] = 1 ,
[ "atan" ] = 1 ,
[ "atan2" ] = 2 ,
[ "sinh" ] = 1 ,
[ "cosh" ] = 1 ,
[ "tanh" ] = 1 ,
[ "exp" ] = 1 ,
[ "log" ] = 1 ,
[ "pow" ] = 2 ,
[ "fmod" ] = 2 ,
}

const EXACT_INTRINSIC

= { [ "sqrt" ] = "llvm.sqrt.f64" , [ "abs" ] = "llvm.fabs.f64" , [ "floor" ] = "llvm.floor.f64" , [ "ceil" ] = "llvm.ceil.f64" , }



function expressions . math ( ctx , intrinsic , args ) 
if intrinsic == "min" or intrinsic == "max" then
local helper = prelude . use ( ctx . module , "nupp." .. intrinsic .. "2" )
local current = args [ 1 ]
for position = 2 , # args do
current = context . value (
ctx ,
("call double %s(double %s, double %s)") : format ( helper , current , args [ position ] )
)
end

return current
end
if intrinsic == "log" and # args == 2 then



local log2 = prelude . libm ( ctx . module , "log2" , 1 )
local a = context . value ( ctx , ("call double %s(double %s)") : format ( log2 , args [ 1 ] ) )
local b = context . value ( ctx , ("call double %s(double %s)") : format ( log2 , args [ 2 ] ) )
local reciprocal = context . value ( ctx , ("fdiv double 1.0, %s") : format ( b ) )

return context . value ( ctx , ("fmul double %s, %s") : format ( a , reciprocal ) )
end
if intrinsic == "deg" then
return context . value ( ctx , ("fmul double %s, %s") : format ( args [ 1 ] , text . double ( 180 / math . pi ) ) )
elseif intrinsic == "rad" then
return context . value ( ctx , ("fmul double %s, %s") : format ( args [ 1 ] , text . double ( math . pi / 180 ) ) )
elseif intrinsic == "sin" then
return context . value ( ctx , ("call double %s(double %s)") : format ( prelude . use ( ctx . module , "nupp.sin" ) , args [ 1 ] ) )
end
local exact = EXACT_INTRINSIC [ intrinsic ]
if exact ~= nil then
local callee = prelude . intrinsic ( ctx . module , exact , "double @NAME(double)" )

return context . value ( ctx , ("call double %s(double %s)") : format ( callee , args [ 1 ] ) )
end
local arity = LIBM [ intrinsic ]
if arity == nil then
expressions . unsupported ( "math operation " .. intrinsic )
end
local callee = prelude . libm ( ctx . module , intrinsic , arity )
local rendered = { }
for position , value in ipairs ( args ) do
rendered [ position ] = "double " .. value
end

return context . value ( ctx , ("call double %s(%s)") : format ( callee , table . concat ( rendered , ", " ) ) )
end











function expressions . index (
ctx ,
indexUniqueName ,
cursorUniqueName ,
cursorOffset
) 
if cursorUniqueName ~= nil then
local slot = ctx . locals [ cursorUniqueName ]
if slot == nil then
error ( "no local " .. tostring ( cursorUniqueName ) , 0 )
end
local cursor = context . value ( ctx , ("load %s, ptr %s") : format ( types . require ( slot . type ) , slot . pointer ) )
local index = expressions . convert ( ctx , cursor , slot . type , "u64" )
if cursorOffset ~= nil and ( cursorOffset ) > 0 then
index = context . value ( ctx , ("add nuw nsw i64 %s, %d") : format ( index , cursorOffset ) )
end

return index
end
if indexUniqueName == "i" then
if ctx . mapIndex == nil then
error ( "map index read outside the map loop" , 0 )
end

return ctx . mapIndex
end
local counter = ctx . spanCounters [ tostring ( indexUniqueName ) ]
if counter ~= nil then

local current = context . value ( ctx , ("load i64, ptr %s") : format ( counter ) )
return context . value ( ctx , ("sub %si64 %s, 1") : format ( ctx . facts . bounds and "nuw " or "" , current ) )
end
local slot = ctx . locals [ tostring ( indexUniqueName ) ]
if slot == nil then
error ( "no local " .. tostring ( indexUniqueName ) , 0 )
end
local loaded = context . value ( ctx , ("load %s, ptr %s") : format ( types . require ( slot . type ) , slot . pointer ) )
if types . isFloat ( slot . type ) then

local less = context . value ( ctx , ("fsub double %s, 1.0") : format ( toDouble ( ctx , loaded , slot . type ) ) )

return expressions . convert ( ctx , less , "f64" , "u64" )
end
local wide = expressions . convert ( ctx , loaded , slot . type , "u64" )



return context . value ( ctx , ("sub %si64 %s, 1") : format ( ctx . facts . bounds and "nuw " or "" , wide ) )
end



function expressions . inbounds ( ctx ) 
return ctx . facts . bounds and "inbounds nuw " or ""
end



function expressions . element ( ctx , name , index , storage ) 
local span = ctx . spans [ name ]
if span == nil then
error ( "no span " .. name , 0 )
end




return context . value (
ctx ,
("getelementptr %s%s, ptr %s, i64 %s") : format ( expressions . inbounds ( ctx ) , storage , span . pointer , index )
)
end



function expressions . widen (
ctx ,
value ,
storage ,
valueType ,
sourceType
) 
local target = types . require ( valueType )
if storage == target then
return value
end
if storage == "i8" or storage == "i16" then
local op = types . storageSigned ( sourceType ) and "sext" or "zext"
local widened = context . value ( ctx , ("%s %s %s to i32") : format ( op , storage , value ) )

return expressions . convert ( ctx , widened , types . storageSigned ( sourceType ) and "i32" or "u32" , valueType )
end
if storage == "float" and target == "double" then
return context . value ( ctx , ("fpext float %s to double") : format ( value ) )
end
error ( ("cannot widen %s to %s") : format ( storage , valueType ) , 0 )
end



function expressions . narrow ( ctx , value , valueType , storage ) 
local source = types . require ( valueType )
if storage == source then
return value
end
if storage == "float" and source == "double" then
return context . value ( ctx , ("fptrunc double %s to float") : format ( value ) )
end
if storage == "i8" or storage == "i16" then
local bits = types . isInteger ( valueType ) and value or u32Bits ( ctx , value , valueType )

return context . value (
ctx ,
("trunc %s %s to %s") : format ( types . isInteger ( valueType ) and source or "i32" , bits , storage )
)
end
if storage == "i1" or storage == "i8" and valueType == "bool" then
return context . value ( ctx , ("zext i1 %s to i8") : format ( value ) )
end
error ( ("cannot narrow %s to %s") : format ( valueType , storage ) , 0 )
end








function expressions . vectorField ( field ) 
return scalarIR . storedVectorField ( field )
end



expressions.LayoutModel = {} expressions.LayoutModel.__index = expressions.LayoutModel ;_G.nupp.__reflect.link(expressions.LayoutModel,__nuppT1[1],{ })


















local function roundUp ( value , alignment ) 
return math . floor ( ( value + alignment - 1 ) / alignment ) * alignment
end











function expressions . layoutModel ( ctx , layoutName ) 
local known = ctx . layoutModels [ layoutName ]
if known ~= nil then
return known
end
local layout = ctx . layouts [ layoutName ]
if layout == nil then
error ( "no layout " .. layoutName , 0 )
end
local model = _G.setmetatable({ members =
{ } ,  index =
{ } ,  storage =
{ } ,  fieldAlignment =
{ } ,  size =
0 ,  alignment =
1 }, expressions.LayoutModel)

local cursor = 0
local natural = 1
for _ , field in ipairs ( ( layout ) . fields ) do
if expressions . vectorField ( field ) then
local found = context . species ( ctx , tostring ( field . type ) )
if found == nil then
error ( "no species for stored vector field " .. field . name , 0 )
end
local lanes = ( found ) . lanes
local elementBytes = math . floor ( ( found ) . bits / 8 )
local laid , why = targetLayout . vector ( tostring ( ctx . triple ) , elementBytes , lanes )
if laid == nil then
error ( "stored vector field " .. field . name .. ": " .. tostring ( why ) , 0 )
end
local vector = laid
local before = roundUp ( cursor , vector . alignment ) - cursor
if before > 0 then
model . members [ # model . members + 1 ] = ("[%d x i8]") : format ( before )
cursor = cursor + before
end
local storage = ("[%d x %s]") : format ( lanes , ( found ) . scalar )
model . index [ field . name ] = # model . members
model . storage [ field . name ] = storage
model . fieldAlignment [ field . name ] = vector . alignment
model . members [ # model . members + 1 ] = storage
cursor = cursor + vector . payload
if vector . padding > 0 then
model . members [ # model . members + 1 ] = ("[%d x i8]") : format ( vector . padding )
cursor = cursor + vector . padding
end
if vector . alignment > model . alignment then
model . alignment = vector . alignment
end
if elementBytes > natural then
natural = elementBytes
end
else
local storage = types . storage ( field . type , field . sourceType )
local bytes = types . storageBytes ( field . type , field . sourceType )
cursor = roundUp ( cursor , bytes )
model . index [ field . name ] = # model . members
model . storage [ field . name ] = storage
model . fieldAlignment [ field . name ] = bytes
model . members [ # model . members + 1 ] = storage
cursor = cursor + bytes
if bytes > model . alignment then
model . alignment = bytes
end
if bytes > natural then
natural = bytes
end
end
end
model . size = roundUp ( cursor , model . alignment )
local tail = model . size - roundUp ( cursor , natural )
if tail > 0 then
model . members [ # model . members + 1 ] = ("[%d x i8]") : format ( tail )
end
ctx . layoutModels [ layoutName ] = model

return model
end



function expressions . layoutType ( ctx , layoutName ) 
local layout = ctx . layouts [ layoutName ]
if layout == nil then
error ( "no layout " .. layoutName , 0 )
end
local name = "%struct." .. layout . uniqueName
local model = expressions . layoutModel ( ctx , layoutName )
builder . once ( ctx . module , "type " .. name , name .. " = type { " .. table . concat ( model . members , ", " ) .. " }" )

return name
end

local function fieldIndex ( ctx , layoutName , field ) 
local layout = ctx . layouts [ layoutName ]


local model = layout . nativeOnly ~= true and expressions . layoutModel ( ctx , layoutName ) or nil
for position , candidate in ipairs ( layout . fields ) do
if candidate . name == field then
if model == nil then
return position - 1 , candidate
end

return ( model ) . index [ field ] , candidate
end
end
error ( "layout " .. layoutName .. " has no field " .. field , 0 )
end



function expressions . fieldAddress (
ctx ,
object ,
layoutName ,
field
) 
local structType = expressions . layoutType ( ctx , layoutName )
local index , found = fieldIndex ( ctx , layoutName , field )
local alignment = expressions . layoutModel ( ctx , layoutName ) . fieldAlignment [ field ]

return context . value (
ctx ,
("getelementptr %s%s, ptr %s, i32 0, i32 %d") : format ( expressions . inbounds ( ctx ) , structType , object , index )
) , found , alignment
end

local function binaryFloat ( ctx , instruction , t , a , b ) 
local flags = ctx . contract and " contract" or ""

return context . value ( ctx , ("%s%s %s %s, %s") : format ( instruction , flags , t , a , b ) )
end

const F64_BINARY = { [ "add" ] = "fadd" , [ "sub" ] = "fsub" , [ "mul" ] = "fmul" , [ "div" ] = "fdiv" , }
const F32_BINARY

= { [ "f32_add" ] = "fadd" , [ "f32_sub" ] = "fsub" , [ "f32_mul" ] = "fmul" , [ "f32_div" ] = "fdiv" , }
const I32_WRAPPING = { [ "i32_add" ] = "add" , [ "i32_sub" ] = "sub" , [ "i32_mul" ] = "mul" , }
const U32_BINARY

= {
[ "u32_add" ] = "add" ,
[ "u32_sub" ] = "sub" ,
[ "u32_mul" ] = "mul" ,
[ "u32_and" ] = "and" ,
[ "u32_or" ] = "or" ,
[ "u32_xor" ] = "xor" ,
}
const WIDE_BINARY

= {
[ "u64_add" ] = "add" ,
[ "u64_sub" ] = "sub" ,
[ "u64_mul" ] = "mul" ,
[ "u64_and" ] = "and" ,
[ "u64_or" ] = "or" ,
[ "u64_xor" ] = "xor" ,
[ "i64_add" ] = "add" ,
[ "i64_sub" ] = "sub" ,
[ "i64_mul" ] = "mul" ,
[ "i64_and" ] = "and" ,
[ "i64_or" ] = "or" ,
[ "i64_xor" ] = "xor" ,
}
const BITWISE = { [ "band" ] = "and" , [ "bor" ] = "or" , [ "bxor" ] = "xor" , }



const F32_CANONICAL_NAN = "0x7FF8000000000000"



const WIDE_HELPER

= {
[ "i64_div" ] = true ,
[ "i64_mod" ] = true ,
[ "i64_pow" ] = true ,
[ "u64_div" ] = true ,
[ "u64_mod" ] = true ,
[ "u64_pow" ] = true ,
}


local function operands (
ctx ,
left ,
right
) 
local a , at = expressions . value ( ctx , left )
local b , bt = expressions . value ( ctx , right )

return a , at , b , bt
end


local function logical ( ctx , operation , left , right ) 
local a , at = expressions . value ( ctx , left )
a = expressions . convert ( ctx , a , at , "bool" )
local from = ctx . f . current
local rhs = builder . label ( ctx . f , operation .. ".rhs" )
local done = builder . label ( ctx . f , operation .. ".end" )
if operation == "and" then
builder . terminate ( ctx . f , ("br i1 %s, label %%%s, label %%%s") : format ( a , rhs , done ) )
else
builder . terminate ( ctx . f , ("br i1 %s, label %%%s, label %%%s") : format ( a , done , rhs ) )
end
builder . start ( ctx . f , rhs )
local b , bt = expressions . value ( ctx , right )
b = expressions . convert ( ctx , b , bt , "bool" )
local last = ctx . f . current
builder . start ( ctx . f , done )
local short = operation == "and" and "false" or "true"

return context . value ( ctx , ("phi i1 [ %s, %%%s ], [ %s, %%%s ]") : format ( short , from , b , last ) )
end



function expressions . helperResult ( ctx , resultTypes ) 
if # resultTypes == 1 then
return context . llvmType ( ctx , tostring ( resultTypes [ 1 ] ) )
end
local fields = { }
for position , resultType in ipairs ( resultTypes ) do
fields [ position ] = context . llvmType ( ctx , tostring ( resultType ) )
end

return "{ " .. table . concat ( fields , ", " ) .. " }"
end




function expressions . helperCall ( ctx , call ) 
local callee = ctx . helpers [ call . helper ]
if callee == nil then
error ( "no LLVM helper for " .. call . helper , 0 )
end
local rendered = { }
for _ , argument in ipairs ( call . args ) do
local named = context . species ( ctx , tostring ( argument . type ) )

if named == nil or ( named ) . family ~= "species" then
local value , t = expressions . value ( ctx , argument )
rendered [ # rendered + 1 ] = context . llvmType ( ctx , t ) .. " " .. value
end
end
local results = call . resultTypes or { call . type }

return context . value (
ctx ,
("call %s %s(%s)")

: format (
expressions . helperResult ( ctx , results ) ,
callee ,
table . concat ( rendered , ", " )
)
)
end



integralOperand = function ( node ) 
if node . op == "span_count" then
return true
elseif node . op == "int_to_f64" then
return types . isInteger ( tostring ( ( node ) . value . type ) )
end

return types . isInteger ( tostring ( node . type ) )
end


integerValue = function ( ctx , node ) 
if node . op == "span_count" then
return context . count ( ctx , ( node ) . span ) , "u64"
elseif node . op == "int_to_f64" then
return expressions . value ( ctx , ( node ) . value )
end

return expressions . value ( ctx , node )
end



local function exactInteger ( ctx , value ) 
if value . op == "int_to_f64" then
local widened = ( value ) . value
if widened . type == "u32" or widened . type == "i32" then
local inner , t = expressions . value ( ctx , widened )
return expressions . convert ( ctx , inner , t , t == "i32" and "i64" or "u64" ) , false
end
elseif value . op == "span_count" then
return context . count ( ctx , ( value ) . span ) , true
end

return nil , false
end




exactNarrowing = function ( ctx , converted , target ) 
if converted . op == "int_to_f64" then
local widened = ( converted ) . value
if widened . type == "i32" or widened . type == "u32" then
local value = expressions . value ( ctx , widened )
return value
end
return nil
end
if converted . op ~= "sub" then
return nil
end
local difference = converted
local left , leftCount = exactInteger ( ctx , difference . left )
local right , rightCount = exactInteger ( ctx , difference . right )
if left == nil or right == nil then
return nil
end
local wide = context . value ( ctx , ("sub i64 %s, %s") : format ( left , right ) )
local integer = context . value ( ctx , ("trunc i64 %s to i32") : format ( wide ) )
if not leftCount and not rightCount then
return integer
end



local exact = "true"
if leftCount then
exact = context . value ( ctx , ("icmp ule i64 %s, %s") : format ( left , "9007199254740992" ) )
end
if rightCount then
local within = context . value ( ctx , ("icmp ule i64 %s, %s") : format ( right , "9007199254740992" ) )
exact = exact == "true" and within or context . value ( ctx , ("and i1 %s, %s") : format ( exact , within ) )
end
local value , t = expressions . value ( ctx , converted )
local wrapped = u32Bits ( ctx , value , t )

return context . value ( ctx , ("select i1 %s, i32 %s, i32 %s") : format ( exact , integer , wrapped ) )
end



expressions . handlers = { }




function expressions . operand ( ctx , node ) 
local value = expressions . value ( ctx , node )

return value
end



function expressions . value ( ctx , node ) 
local operation = node . op
local nodeType = tostring ( node . type )
local handler = expressions . handlers [ operation ]
if handler ~= nil then
return handler ( ctx , node )
end

if operation == "constant" then
local constant = node
if nodeType == "f32" then
return text . float ( text . roundToFloat ( tonumber ( constant . value ) or 0 ) ) , "f32"
elseif types . isInteger ( nodeType ) then
return text . integer ( tonumber ( constant . value ) or 0 ) , nodeType
end

return text . decimal ( constant . value ) , "f64"
elseif operation == "constant_i32" then
return text . integer ( tonumber ( ( node ) . value ) or 0 ) , nodeType
elseif operation == "constant_i64" then
local spelled = ( node ) . value
local hex = spelled : match ( "^0[xX](%x+)$" )

return hex ~= nil and "u0x" .. ( hex ) or spelled , nodeType
elseif operation == "bool" then
return ( node ) . value and "true" or "false" , "bool"
elseif operation == "uniform" then
local name = ( node ) . name

local slot = ctx . locals [ "p_" .. name ]
if slot ~= nil then
return context . loadSlot ( ctx , slot ) , slot . type
end
local value = ctx . uniforms [ name ]
if value == nil then
error ( "no uniform " .. name , 0 )
end

return value , nodeType
elseif operation == "local" or operation == "helper_param" then
local named = node
local found = context . species ( ctx , nodeType )
if found ~= nil and ( found ) . family == "species" then

return tostring ( ( found ) . lanes ) , nodeType
end
local param = ctx . helperParams [ tostring ( named . uniqueName ) ]
if param ~= nil then
return param , nodeType
end
local slot = ctx . locals [ tostring ( named . uniqueName ) ]
if slot == nil then
error ( "no local " .. tostring ( named . uniqueName ) , 0 )
end

return context . loadSlot ( ctx , slot ) , slot . type
elseif operation == "span_count" then
local count = context . count ( ctx , ( node ) . span )

return context . value ( ctx , ("uitofp i64 %s to double") : format ( count ) ) , "f64"
elseif operation == "loop_index" then
if ctx . mapIndex == nil then
error ( "loop index outside the map loop" , 0 )
end
local next = context . value ( ctx , ("add nuw i64 %s, 1") : format ( ctx . mapIndex ) )

return context . value ( ctx , ("uitofp i64 %s to double") : format ( next ) ) , "f64"
elseif operation == "load" then
local loaded = node
local storage = types . storage ( nodeType , loaded . sourceType )
local index = expressions . index ( ctx , loaded . indexUniqueName , loaded . cursorUniqueName , loaded . cursorOffset )
local address = expressions . element ( ctx , loaded . span , index , storage )
local raw = context . value (
ctx ,
("load %s, ptr %s, align %d") : format ( storage , address , types . storageBytes ( nodeType , loaded . sourceType ) )
)

return expressions . widen ( ctx , raw , storage , nodeType , loaded . sourceType ) , nodeType
elseif operation == "element_ref" then
local referenced = node
local structType = expressions . layoutType ( ctx , referenced . layout )
local index = expressions . index (
ctx ,
referenced . indexUniqueName ,
referenced . cursorUniqueName ,
referenced . cursorOffset
)

return expressions . element ( ctx , referenced . span , index , structType ) , "ptr"
elseif operation == "aggregate_new" then


local aggregate = node
local aggregateType = context . llvmType ( ctx , nodeType )
local built = "undef"
for position , value in ipairs ( aggregate . values ) do
local inserted , t = expressions . value ( ctx , value )
built = context . value (
ctx ,
("insertvalue %s %s, %s %s, %d")

: format ( aggregateType , built , context . llvmType ( ctx , t ) , inserted , position - 1 )
)
end

return built , nodeType
elseif operation == "aggregate_field" then
local field = node
local object , objectType = expressions . value ( ctx , field . object )
local index = fieldIndex ( ctx , field . layout , field . field )

return context . value (
ctx ,
("extractvalue %s %s, %d") : format ( context . llvmType ( ctx , objectType ) , object , index )
) , nodeType
elseif operation == "field_load" then
local field = node
local object = expressions . value ( ctx , field . object )
local address , declared , alignment = expressions . fieldAddress ( ctx , object , field . layout , field . field )
if expressions . vectorField ( declared ) then


local vectorType = context . llvmType ( ctx , nodeType )

return context . value ( ctx , ("load %s, ptr %s, align %d") : format ( vectorType , address , alignment ) ) , nodeType
end
local storage = types . storage ( nodeType , declared . sourceType )
local raw = context . value ( ctx , ("load %s, ptr %s") : format ( storage , address ) )

return expressions . widen ( ctx , raw , storage , nodeType , declared . sourceType ) , nodeType
elseif operation == "neg" then
local value , t = expressions . value ( ctx , ( node ) . value )
if types . isFloat ( t ) then
return context . value ( ctx , ("fneg %s %s") : format ( types . require ( t ) , value ) ) , t
end

return context . value ( ctx , ("sub %s 0, %s") : format ( types . require ( t ) , value ) ) , t
elseif operation == "not" then
local value , t = expressions . value ( ctx , ( node ) . value )

return context . value ( ctx , ("xor i1 %s, true") : format ( expressions . convert ( ctx , value , t , "bool" ) ) ) , "bool"
elseif operation == "bnot" then
local value , t = expressions . value ( ctx , ( node ) . value )

return context . value ( ctx , ("xor i32 %s, -1") : format ( u32Bits ( ctx , value , t ) ) ) , "i32"
elseif operation == "and" or operation == "or" then
local binary = node

return logical ( ctx , operation , binary . left , binary . right ) , "bool"
elseif FLOAT_PREDICATE [ operation ] ~= nil then
local binary = node
local counted = binary . left . op == "span_count" or binary . right . op == "span_count"
if counted and integralOperand ( binary . left ) and integralOperand ( binary . right ) then


local a , at = integerValue ( ctx , binary . left )
local b , bt = integerValue ( ctx , binary . right )
return expressions . compare ( ctx , operation , a , at , b , bt , true ) , "bool"
end
local a , at , b , bt = operands ( ctx , binary . left , binary . right )

return expressions . compare ( ctx , operation , a , at , b , bt ) , "bool"
elseif F64_BINARY [ operation ] ~= nil then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
if types . isInteger ( nodeType ) then
expressions . unsupported ( "integer-typed " .. operation )
end

return binaryFloat (
ctx ,
F64_BINARY [ operation ] ,
"double" ,
( expressions . convert ( ctx , a , at , "f64" ) ) ,
( expressions . convert ( ctx , b , bt , "f64" ) )
) , "f64"
elseif operation == "mod" then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local helper = prelude . use ( ctx . module , "nupp.mod" )

return context . value (
ctx ,
("call double %s(double %s, double %s)") : format ( helper , ( expressions . convert ( ctx , a , at , "f64" ) ) , ( expressions . convert ( ctx , b , bt , "f64" ) ) )
) , "f64"
elseif operation == "pow" then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )

return expressions . math ( ctx , "pow" , { ( expressions . convert ( ctx , a , at , "f64" ) ) , ( expressions . convert ( ctx , b , bt , "f64" ) ) } ) , "f64"
elseif BITWISE [ operation ] ~= nil then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )

return context . value (
ctx ,
("%s i32 %s, %s") : format ( BITWISE [ operation ] , u32Bits ( ctx , a , at ) , u32Bits ( ctx , b , bt ) )
) , "i32"
elseif operation == "lshift" or operation == "rshift" or operation == "arshift" then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local shift = context . value ( ctx , ("and i32 %s, 31") : format ( u32Bits ( ctx , b , bt ) ) )
local op = operation == "lshift" and "shl" or operation == "rshift" and "lshr" or "ashr"

return context . value ( ctx , ("%s i32 %s, %s") : format ( op , u32Bits ( ctx , a , at ) , shift ) ) , "i32"
elseif F32_BINARY [ operation ] ~= nil then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )

return binaryFloat (
ctx ,
F32_BINARY [ operation ] ,
"float" ,
expressions . convert ( ctx , a , at , "f32" ) ,
expressions . convert ( ctx , b , bt , "f32" )
) , "f32"
elseif I32_WRAPPING [ operation ] ~= nil then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )

return context . value (
ctx ,
("%s i32 %s, %s") : format ( I32_WRAPPING [ operation ] , u32Bits ( ctx , a , at ) , u32Bits ( ctx , b , bt ) )
) , "i32"
elseif U32_BINARY [ operation ] ~= nil then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local flags = ctx . noWrap [ node ] and " nuw" or ""

return context . value (
ctx ,
("%s%s i32 %s, %s") : format ( U32_BINARY [ operation ] , flags , u32Bits ( ctx , a , at ) , u32Bits ( ctx , b , bt ) )
) , "u32"
elseif operation == "u32_div" or operation == "u32_mod" then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local helper = prelude . use ( ctx . module , operation == "u32_div" and "nupp.u32.div" or "nupp.u32.mod" )

return context . value (
ctx ,
("call i32 %s(i32 %s, i32 %s)") : format ( helper , u32Bits ( ctx , a , at ) , u32Bits ( ctx , b , bt ) )
) , "u32"
elseif operation == "u32_shl" or operation == "u32_shr" then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local shift = context . value ( ctx , ("and i32 %s, 31") : format ( u32Bits ( ctx , b , bt ) ) )

return context . value (
ctx ,
("%s i32 %s, %s") : format ( operation == "u32_shl" and "shl" or "lshr" , u32Bits ( ctx , a , at ) , shift )
) , "u32"
elseif operation == "i32_rotl" or operation == "i32_rotr" or operation == "u32_rotl" or operation == "u32_rotr" then


local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local value = u32Bits ( ctx , a , at )
local funnel = operation : sub ( -1 ) == "l" and "llvm.fshl.i32" or "llvm.fshr.i32"
local callee = prelude . intrinsic ( ctx . module , funnel , "i32 @NAME(i32, i32, i32)" )

return context . value (
ctx ,
("call i32 %s(i32 %s, i32 %s, i32 %s)") : format ( callee , value , value , u32Bits ( ctx , b , bt ) )
) , operation : sub ( 1 , 1 ) == "u"
and "u32"
or "i32"
elseif operation == "f32_to_bits" then

local value , t = expressions . value ( ctx , ( node ) . value )
local operand = expressions . convert ( ctx , value , t , "f32" )
local bits = context . value ( ctx , ("bitcast float %s to i32") : format ( operand ) )
local nan = context . value ( ctx , ("fcmp uno float %s, %s") : format ( operand , operand ) )

return context . value ( ctx , ("select i1 %s, i32 2143289344, i32 %s") : format ( nan , bits ) ) , "u32"
elseif operation == "f32_from_bits" then
local value , t = expressions . value ( ctx , ( node ) . value )
local bits = u32Bits ( ctx , value , t )
local decoded = context . value ( ctx , ("bitcast i32 %s to float") : format ( bits ) )
local nan = context . value ( ctx , ("fcmp uno float %s, %s") : format ( decoded , decoded ) )

return context . value ( ctx , ("select i1 %s, float %s, float %s") : format ( nan , "0x7FF8000000000000" , decoded ) ) , "f32"
elseif operation == "u64_shl"
or operation == "u64_shr"
or operation == "u64_sar"
or operation == "i64_shl"
or operation == "i64_shr"
or operation == "i64_sar"
then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local shift = context . value ( ctx , ("and i64 %s, 63") : format ( ( expressions . convert ( ctx , b , bt , "u64" ) ) ) )
local instruction = operation : sub ( -3 ) == "shl" and "shl" or operation : sub ( -3 ) == "shr" and "lshr" or "ashr"

return context . value (
ctx ,
("%s i64 %s, %s") : format ( instruction , ( expressions . convert ( ctx , a , at , "u64" ) ) , shift )
) , operation : sub ( 1 , 1 ) == "u"
and "u64"
or "i64"
elseif operation == "u64_rotl" or operation == "u64_rotr" then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local value = ( expressions . convert ( ctx , a , at , "u64" ) )
local funnel = operation == "u64_rotl" and "llvm.fshl.i64" or "llvm.fshr.i64"
local callee = prelude . intrinsic ( ctx . module , funnel , "i64 @NAME(i64, i64, i64)" )

return context . value (
ctx ,
("call i64 %s(i64 %s, i64 %s, i64 %s)") : format ( callee , value , value , ( expressions . convert ( ctx , b , bt , "u64" ) ) )
) , "u64"
elseif WIDE_HELPER [ operation ] then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local helper = prelude . use ( ctx . module , "nupp." .. operation : gsub ( "_" , "." ) )

return context . value (
ctx ,
("call i64 %s(i64 %s, i64 %s)") : format ( helper , ( expressions . convert ( ctx , a , at , "u64" ) ) , ( expressions . convert ( ctx , b , bt , "u64" ) ) )
) , operation : sub ( 1 , 1 ) == "u"
and "u64"
or "i64"
elseif WIDE_BINARY [ operation ] ~= nil then
local binary = node
local a , at , b , bt = operands ( ctx , binary . left , binary . right )
local result = context . value (
ctx ,
("%s i64 %s, %s") : format ( WIDE_BINARY [ operation ] , ( expressions . convert ( ctx , a , at , "u64" ) ) , ( expressions . convert ( ctx , b , bt , "u64" ) ) )
)

return result , operation : sub ( 1 , 1 ) == "u" and "u64" or "i64"
elseif operation == "f32_sqrt" then
local value , t = expressions . value ( ctx , ( node ) . value )
local sqrt = prelude . intrinsic ( ctx . module , "llvm.sqrt.f32" , "float @NAME(float)" )

return context . value (
ctx ,
("call float %s(float %s)") : format ( sqrt , expressions . convert ( ctx , value , t , "f32" ) )
) , "f32"
elseif operation == "f32_exp" then
local value , t = expressions . value ( ctx , ( node ) . value )
local operand = expressions . convert ( ctx , value , t , "f32" )
if ctx . program . fpTranscendentals == true then
return context . value (
ctx ,
("call float %s(float %s)") : format ( prelude . libm ( ctx . module , "expf" , 1 , true ) , operand )
) , "f32"
end

return context . value (
ctx ,
("call float %s(float %s)") : format ( prelude . use ( ctx . module , "nupp.f32.exp" ) , operand )
) , "f32"
elseif operation == "f16_to_f32" or operation == "bf16_to_f32" then
local value , t = expressions . value ( ctx , ( node ) . value )
local bits = expressions . convert ( ctx , value , t , "u32" )
local helper = prelude . use ( ctx . module , operation == "f16_to_f32" and "nupp.f16.to.f32" or "nupp.bf16.to.f32" )

return context . value ( ctx , ("call float %s(i32 %s)") : format ( helper , bits ) ) , "f32"
elseif operation == "f32_to_f16" or operation == "f32_to_bf16" then
local value , t = expressions . value ( ctx , ( node ) . value )
local operand = expressions . convert ( ctx , value , t , "f32" )
local helper = prelude . use ( ctx . module , operation == "f32_to_f16" and "nupp.f32.to.f16" or "nupp.f32.to.bf16" )

return context . value ( ctx , ("call i32 %s(float %s)") : format ( helper , operand ) ) , "u32"
elseif operation == "u32_not" or operation == "u64_not" or operation == "i64_not" then
local value , t = expressions . value ( ctx , ( node ) . value )
if operation == "u32_not" then
return context . value ( ctx , ("xor i32 %s, -1") : format ( u32Bits ( ctx , value , t ) ) ) , "u32"
end

return context . value ( ctx , ("xor i64 %s, -1") : format ( ( expressions . convert ( ctx , value , t , "u64" ) ) ) ) , operation == "u64_not" and "u64"
or "i64"
elseif operation == "u32_popcount" or operation == "u32_ctz" or operation == "u32_clz" then
local value , t = expressions . value ( ctx , ( node ) . value )
local bits = u32Bits ( ctx , value , t )
if operation == "u32_popcount" then
local callee = prelude . intrinsic ( ctx . module , "llvm.ctpop.i32" , "i32 @NAME(i32)" )

return context . value ( ctx , ("call i32 %s(i32 %s)") : format ( callee , bits ) ) , "u32"
end

local counter = operation == "u32_ctz" and "llvm.cttz.i32" or "llvm.ctlz.i32"
local callee = prelude . intrinsic ( ctx . module , counter , "i32 @NAME(i32, i1)" )

return context . value ( ctx , ("call i32 %s(i32 %s, i1 false)") : format ( callee , bits ) ) , "u32"
elseif operation == "u64_popcount" or operation == "u64_ctz" or operation == "u64_clz" then
local value , t = expressions . value ( ctx , ( node ) . value )
local bits = ( expressions . convert ( ctx , value , t , "u64" ) )
local counted
if operation == "u64_popcount" then
local callee = prelude . intrinsic ( ctx . module , "llvm.ctpop.i64" , "i64 @NAME(i64)" )
counted = context . value ( ctx , ("call i64 %s(i64 %s)") : format ( callee , bits ) )
else
local counter = operation == "u64_ctz" and "llvm.cttz.i64" or "llvm.ctlz.i64"
local callee = prelude . intrinsic ( ctx . module , counter , "i64 @NAME(i64, i1)" )
counted = context . value ( ctx , ("call i64 %s(i64 %s, i1 false)") : format ( callee , bits ) )
end

return context . value ( ctx , ("trunc i64 %s to i32") : format ( counted ) ) , "u32"
elseif operation == "u64_prefix_xor" then
local value , t = expressions . value ( ctx , ( node ) . value )
local bits = ( expressions . convert ( ctx , value , t , "u64" ) )
for _ , shift in ipairs ( { 1 , 2 , 4 , 8 , 16 , 32 } ) do
local shifted = context . value ( ctx , ("shl i64 %s, %d") : format ( bits , shift ) )
bits = context . value ( ctx , ("xor i64 %s, %s") : format ( bits , shifted ) )
end

return bits , "u64"
elseif operation == "f32_min" or operation == "f32_max" or operation == "f32_fma" then
local corrected = node
local parts = corrected . args ~= nil and corrected . args
or { corrected . left , corrected . right }
local rendered = { }
for position , part in ipairs ( parts ) do
local value , t = expressions . value ( ctx , part )
rendered [ position ] = "float " .. expressions . convert ( ctx , value , t , "f32" )
end
local helper = prelude . use ( ctx . module , "nupp." .. operation : gsub ( "_" , "." ) )

return context . value ( ctx , ("call float %s(%s)") : format ( helper , table . concat ( rendered , ", " ) ) ) , "f32"
elseif operation == "narrow_f64_f32" or operation == "widen_f32_f64" or operation == "int_to_f64" then
local value , t = expressions . value ( ctx , ( node ) . value )

return expressions . convert ( ctx , value , t , nodeType ) , nodeType
elseif operation == "numeric_cast" then
local converted = ( node ) . value
if ( nodeType == "u32" or nodeType == "i32" ) and converted . type == "f64" then
local exact = exactNarrowing ( ctx , converted , nodeType )
if exact ~= nil then
return exact , nodeType
end
end
local value , t = expressions . value ( ctx , converted )
if ( nodeType == "u32" or nodeType == "i32" ) and types . isFloat ( t ) then

return u32Bits ( ctx , value , t ) , nodeType
elseif nodeType == "u64" and types . isFloat ( t ) then

return expressions . luaInteger ( ctx , value , t , "u64" ) , nodeType
end

return expressions . convert ( ctx , value , t , nodeType ) , nodeType
elseif operation == "store_cast" then
local value , t = expressions . value ( ctx , ( node ) . value )

return expressions . luaInteger ( ctx , value , t , nodeType ) , nodeType
elseif operation == "helper_call" then
return expressions . helperCall ( ctx , node ) , nodeType
elseif operation == "math" then
local math = node
local rendered = { }
for position , argument in ipairs ( math . args ) do
local value , t = expressions . value ( ctx , argument )
rendered [ position ] = ( expressions . convert ( ctx , value , t , "f64" ) )
end

return expressions . math ( ctx , math . intrinsic , rendered ) , "f64"
end

if tostring ( operation ) : match ( "^simd_" ) ~= nil then
expressions . unsupported ( "explicit SIMD operation " .. operation )
elseif tostring ( operation ) : match ( "^lua_" ) ~= nil then
expressions . unsupported ( "Lua value operation " .. operation )
elseif tostring ( operation ) : match ( "^reducer_" ) ~= nil then
expressions . unsupported ( "reducer " .. operation )
end
expressions . unsupported ( "operation " .. tostring ( operation ) )
end

local __nuppExportValue= expressions ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.expressions"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.expressions"]=__nuppExports;return __nuppExports