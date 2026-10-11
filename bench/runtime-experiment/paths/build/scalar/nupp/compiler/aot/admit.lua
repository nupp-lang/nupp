_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.admit\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.admit\0runtime\0002") };
















local scalar = require ( "nupp.compiler.scalarintrinsics" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local admit = __nuppNew(0,5)






admit . STORAGE = {
[ "number" ] = "f64" ,
[ "float" ] = "f32" ,
[ "int8" ] = "i32" ,
[ "int16" ] = "i32" ,
[ "int32" ] = "i32" ,
[ "uint8" ] = "u32" ,
[ "uint16" ] = "u32" ,
[ "uint32" ] = "u32" ,
[ "int64" ] = "i64" ,
[ "uint64" ] = "u64" ,
}



admit . CANONICAL_SOURCE = {
[ "f64" ] = "number" ,
[ "f32" ] = "float" ,
[ "i32" ] = "int32" ,
[ "u32" ] = "uint32" ,
[ "i64" ] = "int64" ,
[ "u64" ] = "uint64" ,
}



admit . UINT32_MAX = 4294967295


admit . INT32_MIN = -2147483648

admit . INT32_MAX = 2147483647







function admit . bitOperand ( value ) 
if value . type == "i32" or value . type == "u32" then
return true
end
local raw = value
if raw . op ~= "constant" then
return false
end

local number = tonumber ( raw . value )

return number ~= nil and number >= 0 and number <= admit . UINT32_MAX and number % 1 == 0
end


local ARITHMETIC

= { [ "+" ] = "add" , [ "-" ] = "sub" , [ "*" ] = "mul" , [ "/" ] = "div" , [ "%" ] = "mod" , [ "^" ] = "pow" , }

admit . ARITHMETIC = ARITHMETIC


local BITWISE

= { [ "&" ] = "band" , [ "|" ] = "bor" , [ "~" ] = "bxor" , [ "<<" ] = "lshift" , [ ">>" ] = "rshift" , [ "~>>" ] = "arshift" , }

admit . BITWISE = BITWISE


local COMPARISON

= { [ "<" ] = "lt" , [ "<=" ] = "le" , [ ">" ] = "gt" , [ ">=" ] = "ge" , [ "==" ] = "eq" , [ "~=" ] = "ne" , }

admit . COMPARISON = COMPARISON


admit.Fixed = {} admit.Fixed.__index = admit.Fixed ;_G.nupp.__reflect.link(admit.Fixed,__nuppT1[1],{ })



















































admit . FIXED = ( function ( ) 
local byIdentity = { }
for _ , entry in ipairs ( {
_G.setmetatable({ identity =  "f32.narrow" ,  op =  "narrow_f64_f32" ,  arity =  1 ,  operand =  "f64" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.add" ,  op =  "f32_add" ,  arity =  2 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.sub" ,  op =  "f32_sub" ,  arity =  2 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.mul" ,  op =  "f32_mul" ,  arity =  2 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.div" ,  op =  "f32_div" ,  arity =  2 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.sqrt" ,  op =  "f32_sqrt" ,  arity =  1 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.min" ,  op =  "f32_min" ,  arity =  2 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.max" ,  op =  "f32_max" ,  arity =  2 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.fma" ,  op =  "f32_fma" ,  arity =  3 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.exp" ,  op =  "f32_exp" ,  arity =  1 ,  operand =  "f32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.fromF16Bits" ,  op =  "f16_to_f32" ,  arity =  1 ,  operand =  "u32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.toF16Bits" ,  op =  "f32_to_f16" ,  arity =  1 ,  operand =  "f32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.fromBF16Bits" ,  op =  "bf16_to_f32" ,  arity =  1 ,  operand =  "u32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.toBF16Bits" ,  op =  "f32_to_bf16" ,  arity =  1 ,  operand =  "f32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "i32.wrap" ,  op =  "numeric_cast" ,  arity =  1 ,  operand =  "f64" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "i32.add" ,  op =  "i32_add" ,  arity =  2 ,  operand =  "i32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "i32.sub" ,  op =  "i32_sub" ,  arity =  2 ,  operand =  "i32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "i32.mul" ,  op =  "i32_mul" ,  arity =  2 ,  operand =  "i32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =
"i32.andBits" ,  op =
"band" ,  arity =
2 ,  operand =
"i32" ,  result =
"i32" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"i32.orBits" ,  op =
"bor" ,  arity =
2 ,  operand =
"i32" ,  result =
"i32" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"i32.xorBits" ,  op =
"bxor" ,  arity =
2 ,  operand =
"i32" ,  result =
"i32" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"i32.notBits" ,  op =
"bnot" ,  arity =
1 ,  operand =
"i32" ,  result =
"i32" ,  form =
"unary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"i32.shiftLeft" ,  op =
"lshift" ,  arity =
2 ,  operand =
"i32" ,  result =
"i32" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"i32.shiftRightArithmetic" ,  op =
"arshift" ,  arity =
2 ,  operand =
"i32" ,  result =
"i32" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =  "i32.rotateLeft" ,  op =  "i32_rotl" ,  arity =  2 ,  operand =  "i32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "i32.rotateRight" ,  op =  "i32_rotr" ,  arity =  2 ,  operand =  "i32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =
"i32.lessThan" ,  op =
"lt" ,  arity =
2 ,  operand =
"i32" ,  result =
"bool" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"i32.lessOrEqual" ,  op =
"le" ,  arity =
2 ,  operand =
"i32" ,  result =
"bool" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =  "i32.toU32" ,  op =  "numeric_cast" ,  arity =  1 ,  operand =  "i32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.wrap" ,  op =  "numeric_cast" ,  arity =  1 ,  operand =  "f64" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.fromI32" ,  op =  "numeric_cast" ,  arity =  1 ,  operand =  "i32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "i32.fromU32" ,  op =  "numeric_cast" ,  arity =  1 ,  operand =  "u32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.toI32" ,  op =  "numeric_cast" ,  arity =  1 ,  operand =  "u32" ,  result =  "i32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.add" ,  op =  "u32_add" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.sub" ,  op =  "u32_sub" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.mul" ,  op =  "u32_mul" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.div" ,  op =  "u32_div" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.mod" ,  op =  "u32_mod" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.andBits" ,  op =  "u32_and" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.orBits" ,  op =  "u32_or" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.xorBits" ,  op =  "u32_xor" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.notBits" ,  op =  "u32_not" ,  arity =  1 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.shiftLeft" ,  op =  "u32_shl" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.shiftRightLogical" ,  op =  "u32_shr" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.popcount" ,  op =  "u32_popcount" ,  arity =  1 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.trailingZeros" ,  op =  "u32_ctz" ,  arity =  1 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.leadingZeros" ,  op =  "u32_clz" ,  arity =  1 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.rotateLeft" ,  op =  "u32_rotl" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u32.rotateRight" ,  op =  "u32_rotr" ,  arity =  2 ,  operand =  "u32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =
"u32.lessThan" ,  op =
"lt" ,  arity =
2 ,  operand =
"u32" ,  result =
"bool" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =
"u32.lessOrEqual" ,  op =
"le" ,  arity =
2 ,  operand =
"u32" ,  result =
"bool" ,  form =
"binary" }, admit.Fixed)
,
_G.setmetatable({ identity =  "f32.fromBits" ,  op =  "f32_from_bits" ,  arity =  1 ,  operand =  "u32" ,  result =  "f32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "f32.toBits" ,  op =  "f32_to_bits" ,  arity =  1 ,  operand =  "f32" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u64.andBits" ,  op =  "u64_and" ,  arity =  2 ,  operand =  "u64" ,  result =  "u64" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u64.sub" ,  op =  "u64_sub" ,  arity =  2 ,  operand =  "u64" ,  result =  "u64" }, admit.Fixed) ,
_G.setmetatable({ identity =
"u64.rotateLeft" ,  op =
"u64_rotl" ,  arity =
2 ,  operand =
"u64" ,  operands =
{ "u64" , "f64" } ,  result =
"u64" }, admit.Fixed)
,
_G.setmetatable({ identity =
"u64.rotateRight" ,  op =
"u64_rotr" ,  arity =
2 ,  operand =
"u64" ,  operands =
{ "u64" , "f64" } ,  result =
"u64" }, admit.Fixed)
,
_G.setmetatable({ identity =  "u64.popcount" ,  op =  "u64_popcount" ,  arity =  1 ,  operand =  "u64" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u64.trailingZeros" ,  op =  "u64_ctz" ,  arity =  1 ,  operand =  "u64" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u64.leadingZeros" ,  op =  "u64_clz" ,  arity =  1 ,  operand =  "u64" ,  result =  "u32" }, admit.Fixed) ,
_G.setmetatable({ identity =  "u64.prefixXor" ,  op =  "u64_prefix_xor" ,  arity =  1 ,  operand =  "u64" ,  result =  "u64" }, admit.Fixed) ,
} ) do
byIdentity [ entry . identity ] = entry
end

return byIdentity
end ) ( )


admit.Math = {} admit.Math.__index = admit.Math ;_G.nupp.__reflect.link(admit.Math,__nuppT1[2],{ })














admit . MATH = ( function ( ) 
local byPath = { }
for _ , entry in ipairs ( {
_G.setmetatable({ path =  "math.sqrt" ,  name =  "sqrt" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.abs" ,  name =  "abs" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.floor" ,  name =  "floor" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.ceil" ,  name =  "ceil" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.min" ,  name =  "min" ,  min =  2 }, admit.Math) ,
_G.setmetatable({ path =  "math.max" ,  name =  "max" ,  min =  2 }, admit.Math) ,
_G.setmetatable({ path =  "math.sin" ,  name =  "sin" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.cos" ,  name =  "cos" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.tan" ,  name =  "tan" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.asin" ,  name =  "asin" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.acos" ,  name =  "acos" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.atan" ,  name =  "atan" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.atan2" ,  name =  "atan2" ,  min =  2 ,  max =  2 }, admit.Math) ,
_G.setmetatable({ path =  "math.sinh" ,  name =  "sinh" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.cosh" ,  name =  "cosh" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.tanh" ,  name =  "tanh" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.exp" ,  name =  "exp" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.log" ,  name =  "log" ,  min =  1 ,  max =  2 }, admit.Math) ,
_G.setmetatable({ path =  "math.pow" ,  name =  "pow" ,  min =  2 ,  max =  2 }, admit.Math) ,
_G.setmetatable({ path =  "math.fmod" ,  name =  "fmod" ,  min =  2 ,  max =  2 }, admit.Math) ,
_G.setmetatable({ path =  "math.deg" ,  name =  "deg" ,  min =  1 ,  max =  1 }, admit.Math) ,
_G.setmetatable({ path =  "math.rad" ,  name =  "rad" ,  min =  1 ,  max =  1 }, admit.Math) ,
} ) do
byPath [ entry . path ] = entry
end

return byPath
end ) ( )





function admit . fixed ( path ) 
local identity = scalar . forPath ( path )
if identity == nil then
return nil
end

return admit . FIXED [ identity ]
end


function admit . math ( path ) 
return admit . MATH [ path ]
end

local __nuppExportValue= admit ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.admit"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.admit"]=__nuppExports;return __nuppExports