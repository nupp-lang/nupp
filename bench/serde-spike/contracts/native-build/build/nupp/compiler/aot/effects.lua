_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.effects\0runtime\0001") };














local effects = { }

effects.Facts = {} effects.Facts.__index = effects.Facts ;_G.nupp.__reflect.link(effects.Facts,__nuppT1[1],{ })








local function facts (
observable ,
mayRaise ,
readsNative ,
writesNative ,
usesLua ,
allocatesLua
) 
return ( _G.setmetatable({ observable =
observable ,  mayRaise =
mayRaise ,  readsNative =
readsNative ,  writesNative =
writesNative ,  usesLua =
usesLua ,  allocatesLua =
allocatesLua }, effects.Facts) )

end

const PURE = ( _G.setmetatable({ observable =  false ,  mayRaise =  false ,  readsNative =  false ,  writesNative =  false ,  usesLua =  false ,  allocatesLua =  false }, effects.Facts) )
const NATIVE_READ = ( _G.setmetatable({ observable =  false ,  mayRaise =  false ,  readsNative =  true ,  writesNative =  false ,  usesLua =  false ,  allocatesLua =  false }, effects.Facts) )
const LUA_READ = ( _G.setmetatable({ observable =  false ,  mayRaise =  true ,  readsNative =  true ,  writesNative =  false ,  usesLua =  true ,  allocatesLua =  false }, effects.Facts) )
const LUA_ALLOCATE = ( _G.setmetatable({ observable =  true ,  mayRaise =  true ,  readsNative =  false ,  writesNative =  false ,  usesLua =  true ,  allocatesLua =  true }, effects.Facts) )
const LUA_MUTATE = ( _G.setmetatable({ observable =  true ,  mayRaise =  true ,  readsNative =  true ,  writesNative =  true ,  usesLua =  true ,  allocatesLua =  false }, effects.Facts) )
const NATIVE_WRITE = ( _G.setmetatable({ observable =  true ,  mayRaise =  false ,  readsNative =  false ,  writesNative =  true ,  usesLua =  false ,  allocatesLua =  false }, effects.Facts) )
const CONTROL = ( _G.setmetatable({ observable =  true ,  mayRaise =  false ,  readsNative =  false ,  writesNative =  false ,  usesLua =  false ,  allocatesLua =  false }, effects.Facts) )


local PURE_OPS

= {
aggregate_new = true ,
aggregate_field = true ,
constant = true ,
constant_i32 = true ,
constant_i64 = true ,
bool = true ,
lua_nil = true ,
[ "local" ] = true ,
uniform = true ,
helper_param = true ,
span_count = true ,
loop_index = true ,
workgroup_index = true ,
local_index = true ,
add = true ,
sub = true ,
mul = true ,
div = true ,
mod = true ,
pow = true ,
lt = true ,
le = true ,
gt = true ,
ge = true ,
eq = true ,
ne = true ,
[ "and" ] = true ,
[ "or" ] = true ,
band = true ,
bor = true ,
bxor = true ,
lshift = true ,
rshift = true ,
arshift = true ,
neg = true ,
[ "not" ] = true ,
bnot = true ,
reducer_init = true ,
reducer_add = true ,
simd_reducer_add = true ,
reducer_value = true ,
math = true ,
f32_add = true ,
f32_sub = true ,
f32_mul = true ,
f32_div = true ,
i32_add = true ,
i32_sub = true ,
i32_mul = true ,
u32_add = true ,
u32_sub = true ,
u32_mul = true ,
u32_div = true ,
u32_mod = true ,
u32_and = true ,
u32_or = true ,
u32_xor = true ,
u32_shl = true ,
u32_shr = true ,
i32_rotl = true ,
i32_rotr = true ,
u32_rotl = true ,
u32_rotr = true ,
u64_add = true ,
u64_sub = true ,
u64_mul = true ,
u64_and = true ,
u64_or = true ,
u64_xor = true ,
u64_shl = true ,
u64_shr = true ,
u64_sar = true ,
u64_rotl = true ,
u64_rotr = true ,
i64_add = true ,
i64_sub = true ,
i64_mul = true ,
i64_div = true ,
i64_mod = true ,
i64_and = true ,
i64_or = true ,
i64_xor = true ,
i64_shl = true ,
i64_shr = true ,
i64_sar = true ,
u64_div = true ,
u64_mod = true ,
i64_pow = true ,
u64_pow = true ,
f32_sqrt = true ,
f32_exp = true ,
u32_not = true ,
u32_popcount = true ,
u32_ctz = true ,
u32_clz = true ,
i64_not = true ,
u64_not = true ,
u64_popcount = true ,
u64_ctz = true ,
u64_clz = true ,
u64_prefix_xor = true ,
f32_min = true ,
f32_max = true ,
f32_fma = true ,
narrow_f64_f32 = true ,
widen_f32_f64 = true ,
int_to_f64 = true ,
numeric_cast = true ,
store_cast = true ,
f32_from_bits = true ,
f32_to_bits = true ,
f16_to_f32 = true ,
f32_to_f16 = true ,
bf16_to_f32 = true ,
f32_to_bf16 = true ,
helper_call = true ,
simd_species = true ,
simd_lanes_generic = true ,
simd_splat = true ,
simd_iota = true ,
simd_tail = true ,
simd_binary = true ,
simd_unary = true ,
simd_compare = true ,
simd_select = true ,
simd_mask_any = true ,
simd_mask_all = true ,
simd_mask_count = true ,
simd_mask_first = true ,
simd_mask_bits = true ,
simd_extract = true ,
simd_insert = true ,
simd_permute = true ,
simd_convert = true ,
simd_reinterpret = true ,
simd_compress = true ,
simd_expand = true ,
simd_prefix = true ,
simd_horizontal = true ,
simd_mask_splat = true ,
simd_mask_convert = true ,
simd_call = true ,
simd_math = true ,
}

local NATIVE_READ_OPS

= { load = true , element_ref = true , field_load = true , shared_load = true , simd_load = true , simd_field_load = true , }

local LUA_READ_OPS

= {
lua_scratch_u32_get = true ,
lua_scratch_u32_escape_get = true ,
lua_scratch_u32_length = true ,
lua_scratch_u32_escape_length = true ,
lua_scratch_u8_get = true ,
lua_string_byte = true ,
lua_string_byte_at = true ,
lua_string_u32 = true ,
lua_string_length = true ,
lua_string_match = true ,
lua_string_byte_lua = true ,
lua_table_get_index = true ,
lua_builder_depth = true ,
lua_builder_kind = true ,
lua_builder_count = true ,
lua_builder_state = true ,
}

local LUA_ALLOCATE_OPS

= {
lua_string = true ,
lua_new_table = true ,
lua_builder = true ,
lua_scratch_u32 = true ,
lua_scratch_u8 = true ,
lua_concat = true ,
lua_substring = true ,
lua_string_buffer = true ,
}

local LUA_MUTATE_OPS

= {
lua_builder_finish = true ,
lua_builder_number_token = true ,
lua_string_buffer_finish = true ,
lua_builder_open_array = true ,
lua_builder_open_object = true ,
lua_builder_key = true ,
lua_builder_string = true ,
lua_builder_number = true ,
lua_builder_number_slice = true ,
lua_builder_integer_slice = true ,
lua_builder_integer64 = true ,
lua_builder_decimal64 = true ,
lua_builder_boolean = true ,
lua_builder_null = true ,
lua_builder_close = true ,
lua_builder_key_scratch = true ,
lua_builder_string_scratch = true ,
lua_builder_key_escapes = true ,
lua_builder_string_escapes = true ,
lua_scratch_u32_set = true ,
lua_scratch_u8_set = true ,
lua_scratch_u8_set4 = true ,
lua_scratch_u8_reset = true ,
}

local NATIVE_WRITE_OPS

= {
store = true ,
assign = true ,
shared_store = true ,
reducer_add = true ,
simd_reducer_add = true ,
simd_store = true ,
simd_field_store = true ,
}





local NATIVE_WRITE_EXPRESSION_OPS = { simd_store = true , simd_field_store = true , }

local STATEMENT_LUA_MUTATE_OPS

= {
lua_set_index = true ,
lua_set_key = true ,
lua_string_buffer_append = true ,
lua_builder_open_array = true ,
lua_builder_open_object = true ,
lua_builder_key = true ,
lua_builder_string = true ,
lua_builder_number = true ,
lua_builder_number_slice = true ,
lua_builder_integer_slice = true ,
lua_builder_integer64 = true ,
lua_builder_decimal64 = true ,
lua_builder_boolean = true ,
lua_builder_null = true ,
lua_builder_close = true ,
lua_builder_key_scratch = true ,
lua_builder_string_scratch = true ,
lua_builder_key_escapes = true ,
lua_builder_string_escapes = true ,
lua_scratch_u32_set = true ,
lua_scratch_u8_set = true ,
lua_scratch_u8_set4 = true ,
lua_scratch_u8_reset = true ,
}

local CONTROL_OPS

= {
let = true ,
multi_let = true ,
[ "if" ] = true ,
[ "while" ] = true ,
[ "repeat" ] = true ,
fornum = true ,
block = true ,
[ "break" ] = true ,
[ "continue" ] = true ,
[ "return" ] = true ,
phase = true ,
reducer_region = true ,
}



function effects . expression ( op ) 
if PURE_OPS [ op ] == true then
return PURE
elseif NATIVE_READ_OPS [ op ] == true then
return NATIVE_READ
elseif LUA_READ_OPS [ op ] == true then
return LUA_READ
elseif LUA_ALLOCATE_OPS [ op ] == true then
return LUA_ALLOCATE
elseif LUA_MUTATE_OPS [ op ] == true then
return LUA_MUTATE
elseif NATIVE_WRITE_EXPRESSION_OPS [ op ] == true then
return NATIVE_WRITE
end

error ( "unclassified AOT expression opcode " .. op , 2 )
end



function effects . statement ( op ) 
if STATEMENT_LUA_MUTATE_OPS [ op ] == true then
return LUA_MUTATE
elseif NATIVE_WRITE_OPS [ op ] == true then
return NATIVE_WRITE
elseif CONTROL_OPS [ op ] == true then
return CONTROL
elseif op : match ( "^simd_" ) ~= nil then
return effects . expression ( op )
end

error ( "unclassified AOT statement opcode " .. op , 2 )
end

local function merge ( into , from ) 
for op in pairs ( from ) do
into [ op ] = true
end
end


function effects . expressionOpcodes ( ) 
local opcodes = { }
merge ( opcodes , PURE_OPS )
merge ( opcodes , NATIVE_READ_OPS )
merge ( opcodes , LUA_READ_OPS )
merge ( opcodes , LUA_ALLOCATE_OPS )
merge ( opcodes , LUA_MUTATE_OPS )
merge ( opcodes , NATIVE_WRITE_EXPRESSION_OPS )

return opcodes
end


function effects . statementOpcodes ( ) 
local opcodes = { }
merge ( opcodes , STATEMENT_LUA_MUTATE_OPS )
merge ( opcodes , NATIVE_WRITE_OPS )
merge ( opcodes , CONTROL_OPS )
for op in pairs ( effects . expressionOpcodes ( ) ) do
if op : match ( "^simd_" ) ~= nil then
opcodes [ op ] = true
end
end

return opcodes
end

local __nuppExportValue= effects ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.effects"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.effects"]=__nuppExports;return __nuppExports