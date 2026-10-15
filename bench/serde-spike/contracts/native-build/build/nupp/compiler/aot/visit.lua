_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.visit\0runtime\0001") };











local scalarIR = require ( "nupp.compiler.aot.scalar" )

local visit = { }



visit.Visitor = {} visit.Visitor.__index = visit.Visitor ;_G.nupp.__reflect.link(visit.Visitor,__nuppT1[1],{ })




local scalarExpression
local scalarStatement

local function rewriteExpressions ( values , rewrite ) 
for position , value in ipairs ( values ) do
values [ position ] = rewrite ( value )
end
end

local function rewriteOptional ( value , rewrite ) 
if value ~= nil then
return rewrite ( value )
end

return nil
end

local function builderEvent ( node , rewrite ) 
node . builder = rewrite ( node . builder )
node . sourceBytes = rewriteOptional ( node . sourceBytes , rewrite )
node . start = rewriteOptional ( node . start , rewrite )
node . length = rewriteOptional ( node . length , rewrite )
node . escaped = rewriteOptional ( node . escaped , rewrite )
node . value = rewriteOptional ( node . value , rewrite )
node . negative = rewriteOptional ( node . negative , rewrite )
node . exponent = rewriteOptional ( node . exponent , rewrite )
node . exact = rewriteOptional ( node . exact , rewrite )
node . capacity = rewriteOptional ( node . capacity , rewrite )
node . scratch = rewriteOptional ( node . scratch , rewrite )
node . escapeScratch = rewriteOptional ( node . escapeScratch , rewrite )
node . escapeIndex = rewriteOptional ( node . escapeIndex , rewrite )
node . escapeCount = rewriteOptional ( node . escapeCount , rewrite )
end

local function scratchU32Set ( node , rewrite ) 
node . scratch = rewrite ( node . scratch )
node . index = rewrite ( node . index )
node . value = rewrite ( node . value )
end

local function scratchU8Set ( node , rewrite ) 
node . scratch = rewrite ( node . scratch )
node . index = rewriteOptional ( node . index , rewrite )
node . value = rewriteOptional ( node . value , rewrite )
end





function visit . expressionChildren ( node , rewrite ) 
local __nuppT8= node . op ; local __nuppT9;
if  __nuppT8== "constant"  or  __nuppT8== "constant_i32"  or  __nuppT8== "constant_i64"  or  __nuppT8== "bool"  or  __nuppT8== "lua_nil"  or  __nuppT8== "lua_string"  or  __nuppT8== "local"  or  __nuppT8== "uniform"  or  __nuppT8== "helper_param"  or  __nuppT8== "span_count"  or  __nuppT8== "loop_index"  or  __nuppT8== "workgroup_index"  or  __nuppT8== "local_index"  or  __nuppT8== "load"  or  __nuppT8== "element_ref"  then  __nuppT9= nil
elseif  __nuppT8== "shared_load"  then  local __nuppT10;do local __nuppT11,__nuppT12;repeat
local value = node
value . index = rewrite ( value . index )
do  __nuppT10= nil ;__nuppT11=true;break end
 until true; end; __nuppT9= __nuppT10
elseif  __nuppT8== "lua_string_match"  then  local __nuppT13;do local __nuppT14,__nuppT15;repeat
local value = node
value . bytes = rewrite ( value . bytes )
do  __nuppT13= nil ;__nuppT14=true;break end
 until true; end; __nuppT9= __nuppT13
elseif  __nuppT8== "lua_concat"  then  local __nuppT16;do local __nuppT17,__nuppT18;repeat
local value = node
value . left = rewrite ( value . left )
value . right = rewrite ( value . right )
do  __nuppT16= nil ;__nuppT17=true;break end
 until true; end; __nuppT9= __nuppT16
elseif  __nuppT8== "lua_substring"  then  local __nuppT19;do local __nuppT20,__nuppT21;repeat
local value = node
value . bytes = rewrite ( value . bytes )
value . first = rewrite ( value . first )
value . last = rewriteOptional ( value . last , rewrite )
do  __nuppT19= nil ;__nuppT20=true;break end
 until true; end; __nuppT9= __nuppT19
elseif  __nuppT8== "lua_string_byte_lua"  then  local __nuppT22;do local __nuppT23,__nuppT24;repeat
local value = node
value . bytes = rewrite ( value . bytes )
value . index = rewrite ( value . index )
do  __nuppT22= nil ;__nuppT23=true;break end
 until true; end; __nuppT9= __nuppT22
elseif  __nuppT8== "lua_table_get_index"  then  local __nuppT25;do local __nuppT26,__nuppT27;repeat
local value = node
value . table = rewrite ( value . table )
value . key = rewrite ( value . key )
do  __nuppT25= nil ;__nuppT26=true;break end
 until true; end; __nuppT9= __nuppT25
elseif  __nuppT8== "lua_string_buffer"  then  local __nuppT28;do local __nuppT29,__nuppT30;repeat
local value = node
value . initial = rewrite ( value . initial )
do  __nuppT28= nil ;__nuppT29=true;break end
 until true; end; __nuppT9= __nuppT28
elseif  __nuppT8== "lua_string_buffer_finish"  then  local __nuppT31;do local __nuppT32,__nuppT33;repeat
local value = node
value . buffer = rewrite ( value . buffer )
do  __nuppT31= nil ;__nuppT32=true;break end
 until true; end; __nuppT9= __nuppT31
elseif  __nuppT8== "lua_new_table"  then  local __nuppT34;do local __nuppT35,__nuppT36;repeat
local value = node
value . arrayCapacity = rewrite ( value . arrayCapacity )
value . hashCapacity = rewrite ( value . hashCapacity )
for _ , field in ipairs ( value . fields or { } ) do
field . key = rewrite ( field . key )
field . value = rewrite ( field . value )
end  if __nuppT35 then break end;
do  __nuppT34= nil ;__nuppT35=true;break end
 until true; end; __nuppT9= __nuppT34
elseif  __nuppT8== "lua_builder"  then  local __nuppT37;do local __nuppT38,__nuppT39;repeat
local value = node
value . nullValue = rewrite ( value . nullValue )
value . maxDepth = rewriteOptional ( value . maxDepth , rewrite )
value . stringCapacity = rewriteOptional ( value . stringCapacity , rewrite )
value . arrayMarker = rewriteOptional ( value . arrayMarker , rewrite )
value . objectMarker = rewriteOptional ( value . objectMarker , rewrite )
value . selectionShape = rewriteOptional ( value . selectionShape , rewrite )
value . arrayShapeMarker = rewriteOptional ( value . arrayShapeMarker , rewrite )
value . serdeMarkers = rewriteOptional ( value . serdeMarkers , rewrite )
do  __nuppT37= nil ;__nuppT38=true;break end
 until true; end; __nuppT9= __nuppT37
elseif  __nuppT8== "lua_scratch_u32"  then  local __nuppT40;do local __nuppT41,__nuppT42;repeat
local value = node
value . capacity = rewrite ( value . capacity )
do  __nuppT40= nil ;__nuppT41=true;break end
 until true; end; __nuppT9= __nuppT40
elseif  __nuppT8== "lua_scratch_u8"  then  local __nuppT43;do local __nuppT44,__nuppT45;repeat
local value = node
value . capacity = rewrite ( value . capacity )
do  __nuppT43= nil ;__nuppT44=true;break end
 until true; end; __nuppT9= __nuppT43
elseif  __nuppT8== "lua_scratch_u32_get"  or  __nuppT8== "lua_scratch_u32_escape_get"  then  local __nuppT46;do local __nuppT47,__nuppT48;repeat
local value = node
value . scratch = rewrite ( value . scratch )
value . index = rewrite ( value . index )
do  __nuppT46= nil ;__nuppT47=true;break end
 until true; end; __nuppT9= __nuppT46
elseif  __nuppT8== "lua_scratch_u8_get"  then  local __nuppT49;do local __nuppT50,__nuppT51;repeat
local value = node
value . scratch = rewrite ( value . scratch )
value . index = rewrite ( value . index )
do  __nuppT49= nil ;__nuppT50=true;break end
 until true; end; __nuppT9= __nuppT49
elseif  __nuppT8== "lua_scratch_u32_length"  or  __nuppT8== "lua_scratch_u32_escape_length"  then  local __nuppT52;do local __nuppT53,__nuppT54;repeat
local value = node
value . scratch = rewrite ( value . scratch )
do  __nuppT52= nil ;__nuppT53=true;break end
 until true; end; __nuppT9= __nuppT52
elseif  __nuppT8== "lua_string_byte"  or  __nuppT8== "lua_string_byte_at"  or  __nuppT8== "lua_string_u32"  or  __nuppT8== "lua_string_length"  then  local __nuppT55;do local __nuppT56,__nuppT57;repeat
local value = node
value . bytes = rewrite ( value . bytes )
value . index = rewriteOptional ( value . index , rewrite )
do  __nuppT55= nil ;__nuppT56=true;break end
 until true; end; __nuppT9= __nuppT55
elseif  __nuppT8== "lua_builder_finish"  then  local __nuppT58;do local __nuppT59,__nuppT60;repeat
local value = node
value . builder = rewrite ( value . builder )
do  __nuppT58= nil ;__nuppT59=true;break end
 until true; end; __nuppT9= __nuppT58
elseif  __nuppT8== "lua_builder_depth"  or  __nuppT8== "lua_builder_kind"  or  __nuppT8== "lua_builder_count"  or  __nuppT8== "lua_builder_state"  then  local __nuppT61;do local __nuppT62,__nuppT63;repeat
local value = node
value . builder = rewrite ( value . builder )
do  __nuppT61= nil ;__nuppT62=true;break end
 until true; end; __nuppT9= __nuppT61
elseif  __nuppT8== "lua_builder_number_token"  then  local __nuppT64;do local __nuppT65,__nuppT66;repeat
local value = node
value . builder = rewrite ( value . builder )
value . sourceBytes = rewrite ( value . sourceBytes )
value . start = rewrite ( value . start )
value . limit = rewrite ( value . limit )
do  __nuppT64= nil ;__nuppT65=true;break end
 until true; end; __nuppT9= __nuppT64
elseif  __nuppT8== "lua_builder_open_array"  or  __nuppT8== "lua_builder_open_object"  or  __nuppT8== "lua_builder_key"  or  __nuppT8== "lua_builder_string"  or  __nuppT8== "lua_builder_number"  or  __nuppT8== "lua_builder_number_slice"  or  __nuppT8== "lua_builder_integer_slice"  or  __nuppT8== "lua_builder_integer64"  or  __nuppT8== "lua_builder_decimal64"  or  __nuppT8== "lua_builder_boolean"  or  __nuppT8== "lua_builder_null"  or  __nuppT8== "lua_builder_close"  or  __nuppT8== "lua_builder_key_scratch"  or  __nuppT8== "lua_builder_string_scratch"  or  __nuppT8== "lua_builder_key_escapes"  or  __nuppT8== "lua_builder_string_escapes"  then  __nuppT9= builderEvent (
node ,
rewrite
)
elseif  __nuppT8== "lua_scratch_u32_set"  then  __nuppT9= scratchU32Set ( node , rewrite )
elseif  __nuppT8== "lua_scratch_u8_set"  or  __nuppT8== "lua_scratch_u8_set4"  or  __nuppT8== "lua_scratch_u8_reset"  then  __nuppT9= scratchU8Set (
node ,
rewrite
)
elseif  __nuppT8== "field_load"  then  local __nuppT67;do local __nuppT68,__nuppT69;repeat
local value = node
value . object = rewrite ( value . object )
do  __nuppT67= nil ;__nuppT68=true;break end
 until true; end; __nuppT9= __nuppT67
elseif  __nuppT8== "aggregate_new"  then  local __nuppT70;do local __nuppT71,__nuppT72;repeat
local value = node
for position , field in ipairs ( value . values ) do
value . values [ position ] = rewrite ( field )
end  if __nuppT71 then break end;
do  __nuppT70= nil ;__nuppT71=true;break end
 until true; end; __nuppT9= __nuppT70
elseif  __nuppT8== "aggregate_field"  then  local __nuppT73;do local __nuppT74,__nuppT75;repeat
local value = node
value . object = rewrite ( value . object )
do  __nuppT73= nil ;__nuppT74=true;break end
 until true; end; __nuppT9= __nuppT73
elseif  __nuppT8== "add"  or  __nuppT8== "sub"  or  __nuppT8== "mul"  or  __nuppT8== "div"  or  __nuppT8== "mod"  or  __nuppT8== "pow"  or  __nuppT8== "lt"  or  __nuppT8== "le"  or  __nuppT8== "gt"  or  __nuppT8== "ge"  or  __nuppT8== "eq"  or  __nuppT8== "ne"  or  __nuppT8== "and"  or  __nuppT8== "or"  or  __nuppT8== "band"  or  __nuppT8== "bor"  or  __nuppT8== "bxor"  or  __nuppT8== "lshift"  or  __nuppT8== "rshift"  or  __nuppT8== "arshift"  then  local __nuppT76;do local __nuppT77,__nuppT78;repeat
local value = node
value . left = rewrite ( value . left )
value . right = rewrite ( value . right )
do  __nuppT76= nil ;__nuppT77=true;break end
 until true; end; __nuppT9= __nuppT76
elseif  __nuppT8== "f32_add"  or  __nuppT8== "f32_sub"  or  __nuppT8== "f32_mul"  or  __nuppT8== "f32_div"  or  __nuppT8== "i32_add"  or  __nuppT8== "i32_sub"  or  __nuppT8== "i32_mul"  or  __nuppT8== "u32_add"  or  __nuppT8== "u32_sub"  or  __nuppT8== "u32_mul"  or  __nuppT8== "u32_div"  or  __nuppT8== "u32_mod"  or  __nuppT8== "u32_and"  or  __nuppT8== "u32_or"  or  __nuppT8== "u32_xor"  or  __nuppT8== "u32_shl"  or  __nuppT8== "u32_shr"  or  __nuppT8== "i32_rotl"  or  __nuppT8== "i32_rotr"  or  __nuppT8== "u32_rotl"  or  __nuppT8== "u32_rotr"  or  __nuppT8== "i64_add"  or  __nuppT8== "i64_sub"  or  __nuppT8== "i64_mul"  or  __nuppT8== "i64_div"  or  __nuppT8== "i64_mod"  or  __nuppT8== "i64_pow"  or  __nuppT8== "i64_and"  or  __nuppT8== "i64_or"  or  __nuppT8== "i64_xor"  or  __nuppT8== "i64_shl"  or  __nuppT8== "i64_shr"  or  __nuppT8== "i64_sar"  or  __nuppT8== "u64_add"  or  __nuppT8== "u64_sub"  or  __nuppT8== "u64_mul"  or  __nuppT8== "u64_div"  or  __nuppT8== "u64_mod"  or  __nuppT8== "u64_pow"  or  __nuppT8== "u64_and"  or  __nuppT8== "u64_or"  or  __nuppT8== "u64_xor"  or  __nuppT8== "u64_shl"  or  __nuppT8== "u64_shr"  or  __nuppT8== "u64_sar"  or  __nuppT8== "u64_rotl"  or  __nuppT8== "u64_rotr"  then  local __nuppT79;do local __nuppT80,__nuppT81;repeat
local value = node
value . left = rewrite ( value . left )
value . right = rewrite ( value . right )
do  __nuppT79= nil ;__nuppT80=true;break end
 until true; end; __nuppT9= __nuppT79
elseif  __nuppT8== "neg"  or  __nuppT8== "not"  or  __nuppT8== "bnot"  then  local __nuppT82;do local __nuppT83,__nuppT84;repeat
local value = node
value . value = rewrite ( value . value )
do  __nuppT82= nil ;__nuppT83=true;break end
 until true; end; __nuppT9= __nuppT82
elseif  __nuppT8== "f32_sqrt"  or  __nuppT8== "f32_exp"  or  __nuppT8== "u32_not"  or  __nuppT8== "u32_popcount"  or  __nuppT8== "u32_ctz"  or  __nuppT8== "u32_clz"  or  __nuppT8== "i64_not"  or  __nuppT8== "u64_not"  or  __nuppT8== "u64_popcount"  or  __nuppT8== "u64_ctz"  or  __nuppT8== "u64_clz"  or  __nuppT8== "u64_prefix_xor"  then  local __nuppT85;do local __nuppT86,__nuppT87;repeat
local value = node
value . value = rewrite ( value . value )
do  __nuppT85= nil ;__nuppT86=true;break end
 until true; end; __nuppT9= __nuppT85
elseif  __nuppT8== "narrow_f64_f32"  or  __nuppT8== "widen_f32_f64"  or  __nuppT8== "int_to_f64"  or  __nuppT8== "numeric_cast"  or  __nuppT8== "store_cast"  or  __nuppT8== "f32_from_bits"  or  __nuppT8== "f32_to_bits"  or  __nuppT8== "f16_to_f32"  or  __nuppT8== "f32_to_f16"  or  __nuppT8== "bf16_to_f32"  or  __nuppT8== "f32_to_bf16"  then  local __nuppT88;do local __nuppT89,__nuppT90;repeat
local value = node
value . value = rewrite ( value . value )
do  __nuppT88= nil ;__nuppT89=true;break end
 until true; end; __nuppT9= __nuppT88
elseif  __nuppT8== "math"  then  __nuppT9= rewriteExpressions ( ( node ) . args , rewrite )
elseif  __nuppT8== "helper_call"  then  __nuppT9= rewriteExpressions ( ( node ) . args , rewrite )
elseif  __nuppT8== "reducer_init"  then  local __nuppT91;do local __nuppT92,__nuppT93;repeat
local value = node
value . initial = rewrite ( value . initial )
do  __nuppT91= nil ;__nuppT92=true;break end
 until true; end; __nuppT9= __nuppT91
elseif  __nuppT8== "reducer_add"  then  local __nuppT94;do local __nuppT95,__nuppT96;repeat
local value = node
value . reducer = rewrite ( value . reducer )
value . value = rewrite ( value . value )
value . right = rewriteOptional ( value . right , rewrite )
do  __nuppT94= nil ;__nuppT95=true;break end
 until true; end; __nuppT9= __nuppT94
elseif  __nuppT8== "reducer_value"  then  local __nuppT97;do local __nuppT98,__nuppT99;repeat
local value = node
value . reducer = rewrite ( value . reducer )
do  __nuppT97= nil ;__nuppT98=true;break end
 until true; end; __nuppT9= __nuppT97
elseif  __nuppT8== "f32_min"  or  __nuppT8== "f32_max"  or  __nuppT8== "f32_fma"  then  local __nuppT100;do local __nuppT101,__nuppT102;repeat
local value = node
value . left = rewriteOptional ( value . left , rewrite )
value . right = rewriteOptional ( value . right , rewrite )
rewriteExpressions ( value . args or { } , rewrite )
do  __nuppT100= nil ;__nuppT101=true;break end
 until true; end; __nuppT9= __nuppT100
elseif  __nuppT8== "simd_species"  or  __nuppT8== "simd_lanes_generic"  or  __nuppT8== "simd_splat"  or  __nuppT8== "simd_iota"  or  __nuppT8== "simd_tail"  or  __nuppT8== "simd_load"  or  __nuppT8== "simd_store"  or  __nuppT8== "simd_binary"  or  __nuppT8== "simd_unary"  or  __nuppT8== "simd_compare"  or  __nuppT8== "simd_select"  or  __nuppT8== "simd_mask_any"  or  __nuppT8== "simd_mask_all"  or  __nuppT8== "simd_mask_count"  or  __nuppT8== "simd_mask_first"  or  __nuppT8== "simd_mask_bits"  or  __nuppT8== "simd_extract"  or  __nuppT8== "simd_insert"  or  __nuppT8== "simd_permute"  or  __nuppT8== "simd_convert"  or  __nuppT8== "simd_reinterpret"  or  __nuppT8== "simd_compress"  or  __nuppT8== "simd_expand"  or  __nuppT8== "simd_prefix"  or  __nuppT8== "simd_horizontal"  or  __nuppT8== "simd_mask_splat"  or  __nuppT8== "simd_mask_convert"  or  __nuppT8== "simd_field_load"  or  __nuppT8== "simd_field_store"  or  __nuppT8== "simd_call"  or  __nuppT8== "simd_math"  then  local __nuppT103;do local __nuppT104,__nuppT105;repeat
local value = node
rewriteExpressions ( value . args , rewrite )
value . rooted = rewriteOptional ( value . rooted , rewrite )
do  __nuppT103= nil ;__nuppT104=true;break end
 until true; end; __nuppT9= __nuppT103
elseif  __nuppT8== "simd_reducer_add"  then  local __nuppT106;do local __nuppT107,__nuppT108;repeat
local value = node
value . reducer = rewrite ( value . reducer )
value . value = rewrite ( value . value )
value . mask = rewrite ( value . mask )
value . right = rewriteOptional ( value . right , rewrite )
do  __nuppT106= nil ;__nuppT107=true;break end
 until true; end; __nuppT9= __nuppT106
end; return __nuppT9
end

scalarExpression = function ( node , visitor ) 
local callback = visitor . scalarExpression
if callback ~= nil then
callback ( node )
end
visit . expressionChildren ( node , function ( child ) 
scalarExpression ( child , visitor )
return child
end )
end

local function scalarExpressions ( values , visitor ) 
for _ , value in ipairs ( values ) do
scalarExpression ( value , visitor )
end
end

local function scalarBlock ( block , visitor ) 
for _ , statement in ipairs ( block ) do
scalarStatement ( statement , visitor )
end
end


function visit . statementExpressions ( node , rewrite ) 
local __nuppT114= node . op ; local __nuppT115;
if  __nuppT114== "reducer_add"  then  local __nuppT116;do local __nuppT117,__nuppT118;repeat
local value = node
value . reducer = rewrite ( value . reducer )
value . value = rewrite ( value . value )
value . right = rewriteOptional ( value . right , rewrite )
do  __nuppT116= nil ;__nuppT117=true;break end
 until true; end; __nuppT115= __nuppT116
elseif  __nuppT114== "simd_reducer_add"  then  local __nuppT119;do local __nuppT120,__nuppT121;repeat
local value = node
value . reducer = rewrite ( value . reducer )
value . value = rewrite ( value . value )
value . mask = rewrite ( value . mask )
value . right = rewriteOptional ( value . right , rewrite )
do  __nuppT119= nil ;__nuppT120=true;break end
 until true; end; __nuppT115= __nuppT119
elseif  __nuppT114== "let"  then  local __nuppT122;do local __nuppT123,__nuppT124;repeat
local value = node
value . value = rewrite ( value . value )
do  __nuppT122= nil ;__nuppT123=true;break end
 until true; end; __nuppT115= __nuppT122
elseif  __nuppT114== "multi_let"  then  local __nuppT125;do local __nuppT126,__nuppT127;repeat
local value = node
value . call = rewrite ( value . call )
do  __nuppT125= nil ;__nuppT126=true;break end
 until true; end; __nuppT115= __nuppT125
elseif  __nuppT114== "assign"  then  local __nuppT128;do local __nuppT129,__nuppT130;repeat
for _ , assignment in ipairs ( ( node ) . values ) do
assignment . target . object = rewriteOptional ( assignment . target . object , rewrite )
assignment . value = rewrite ( assignment . value )
end  if __nuppT129 then break end;
do  __nuppT128= nil ;__nuppT129=true;break end
 until true; end; __nuppT115= __nuppT128
elseif  __nuppT114== "store"  then  local __nuppT131;do local __nuppT132,__nuppT133;repeat
local value = node
value . value = rewrite ( value . value )
do  __nuppT131= nil ;__nuppT132=true;break end
 until true; end; __nuppT115= __nuppT131
elseif  __nuppT114== "shared_store"  then  local __nuppT134;do local __nuppT135,__nuppT136;repeat
local value = node
value . index = rewrite ( value . index )
value . value = rewrite ( value . value )
do  __nuppT134= nil ;__nuppT135=true;break end
 until true; end; __nuppT115= __nuppT134
elseif  __nuppT114== "lua_set_index"  or  __nuppT114== "lua_set_key"  then  local __nuppT137;do local __nuppT138,__nuppT139;repeat
local value = node
value . table = rewrite ( value . table )
value . key = rewrite ( value . key )
value . value = rewrite ( value . value )
do  __nuppT137= nil ;__nuppT138=true;break end
 until true; end; __nuppT115= __nuppT137
elseif  __nuppT114== "lua_string_buffer_append"  then  local __nuppT140;do local __nuppT141,__nuppT142;repeat
local value = node
value . buffer = rewrite ( value . buffer )
value . value = rewrite ( value . value )
do  __nuppT140= nil ;__nuppT141=true;break end
 until true; end; __nuppT115= __nuppT140
elseif  __nuppT114== "lua_builder_open_array"  or  __nuppT114== "lua_builder_open_object"  or  __nuppT114== "lua_builder_key"  or  __nuppT114== "lua_builder_string"  or  __nuppT114== "lua_builder_number"  or  __nuppT114== "lua_builder_number_slice"  or  __nuppT114== "lua_builder_integer_slice"  or  __nuppT114== "lua_builder_integer64"  or  __nuppT114== "lua_builder_decimal64"  or  __nuppT114== "lua_builder_boolean"  or  __nuppT114== "lua_builder_null"  or  __nuppT114== "lua_builder_close"  or  __nuppT114== "lua_builder_key_scratch"  or  __nuppT114== "lua_builder_string_scratch"  or  __nuppT114== "lua_builder_key_escapes"  or  __nuppT114== "lua_builder_string_escapes"  then  __nuppT115= builderEvent (
node ,
rewrite
)
elseif  __nuppT114== "lua_scratch_u32_set"  then  __nuppT115= scratchU32Set ( node , rewrite )
elseif  __nuppT114== "lua_scratch_u8_set"  or  __nuppT114== "lua_scratch_u8_set4"  or  __nuppT114== "lua_scratch_u8_reset"  then  __nuppT115= scratchU8Set (
node ,
rewrite
)
elseif  __nuppT114== "if"  then  local __nuppT143;do local __nuppT144,__nuppT145;repeat
local value = node
for _ , clause in ipairs ( value . clauses ) do
clause . condition = rewrite ( clause . condition )
end  if __nuppT144 then break end;
do  __nuppT143= nil ;__nuppT144=true;break end
 until true; end; __nuppT115= __nuppT143
elseif  __nuppT114== "while"  then  local __nuppT146;do local __nuppT147,__nuppT148;repeat
local value = node
value . condition = rewrite ( value . condition )
do  __nuppT146= nil ;__nuppT147=true;break end
 until true; end; __nuppT115= __nuppT146
elseif  __nuppT114== "repeat"  then  local __nuppT149;do local __nuppT150,__nuppT151;repeat
local value = node
value . condition = rewrite ( value . condition )
do  __nuppT149= nil ;__nuppT150=true;break end
 until true; end; __nuppT115= __nuppT149
elseif  __nuppT114== "fornum"  then  local __nuppT152;do local __nuppT153,__nuppT154;repeat
local value = node
value . from = rewrite ( value . from )
value . to = rewrite ( value . to )
do  __nuppT152= nil ;__nuppT153=true;break end
 until true; end; __nuppT115= __nuppT152
elseif  __nuppT114== "phase"  or  __nuppT114== "block"  or  __nuppT114== "reducer_region"  or  __nuppT114== "break"  or  __nuppT114== "continue"  then  __nuppT115= nil
elseif  __nuppT114== "return"  then  __nuppT115= rewriteExpressions ( ( node ) . values , rewrite )




else  __nuppT115= visit . expressionChildren ( node , rewrite )
end; return __nuppT115
end

scalarStatement = function ( node , visitor ) 
local callback = visitor . scalarStatement
if callback ~= nil then
callback ( node )
end
if node . op == "while" or node . op == "repeat" then
local setup = ( node ) . conditionBody
if setup ~= nil then
scalarBlock ( setup , visitor )
end
end
visit . statementExpressions ( node , function ( child ) 
scalarExpression ( child , visitor )
return child
end )

if node . op == "if" then
local value = node
for _ , clause in ipairs ( value . clauses ) do
scalarBlock ( clause . body , visitor )
end
if value . elseBody ~= nil then
scalarBlock ( value . elseBody , visitor )
end
elseif node . op == "while"
or node . op == "repeat"
or node . op == "fornum"
or node . op == "block"
or node . op == "reducer_region"
or node . op == "phase"
then
scalarBlock ( ( node ) . body , visitor )
end
end


function visit . block ( block , visitor ) 
scalarBlock ( block , visitor )
end

function visit . program ( program , visitor ) 
if program . loop ~= nil then
scalarBlock ( ( program . loop ) . statements , visitor )
end
if program . body ~= nil then
scalarBlock ( program . body , visitor )
end
if program . workgroup ~= nil then
local workgroup = program . workgroup
scalarBlock ( workgroup . prelude , visitor )
scalarExpression ( workgroup . groups , visitor )
for _ , shared in ipairs ( workgroup . shared ) do
scalarExpression ( shared . initial , visitor )
end
scalarBlock ( workgroup . statements , visitor )
end
for _ , helper in ipairs ( program . helpers or { } ) do
scalarExpressions ( helper . values , visitor )
end
end















function visit . reusableScratch ( program ) 
if program . entryMode ~= "lua-builder" or program . body == nil then
return nil
end

local statements = program . body
local candidate = nil
for index , statement in ipairs ( statements ) do
local op = statement . op
if op == "lua_builder_string_scratch" or op == "lua_builder_key_scratch" then
local published = ( statement ) . scratch
if published == nil or ( published ) . op ~= "local" then
return nil
end
for after = index + 1 , # statements do
if statements [ after ] . op ~= "return" then
return nil
end
end
candidate = published
do break end
end
end
if candidate == nil then
return nil
end

local publishes = 0
visit . program (
program ,
_G.setmetatable({ scalarStatement =  function ( statement ) 
local op = statement . op
if op == "lua_builder_string_scratch" or op == "lua_builder_key_scratch" then
publishes = publishes + 1
end
end }, visit.Visitor)
)
if publishes ~= 1 then
return nil
end

return ( candidate ) . uniqueName
end

local __nuppExportValue= visit ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.visit"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.visit"]=__nuppExports;return __nuppExports