_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.verify\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.verify\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.verify\0runtime\0003") };
































local admit = require ( "nupp.compiler.aot.admit" )
local reducers = require ( "nupp.compiler.aot.reducers" )
local effects = require ( "nupp.compiler.aot.effects" )
local relations = require ( "nupp.compiler.aot.relations" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local simdbounds = require ( "nupp.compiler.aot.simdbounds" )
local simdindices = require ( "nupp.compiler.aot.simdindices" )
local simdcast = require ( "nupp.compiler.aot.simdcast" )
local shapes = require ( "nupp.compiler.aot.simdshape" )
local visit = require ( "nupp.compiler.aot.visit" )

local verify = { }









verify.Scope = {} verify.Scope.__index = verify.Scope ;_G.nupp.__reflect.link(verify.Scope,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00084","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00079","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00088","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00066","nupp.compiler.aot.scalar") , __nuppT1[2] })





























































verify.Region = {} verify.Region.__index = verify.Region ;_G.nupp.__reflect.link(verify.Region,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00050","nupp.compiler.aot.scalar") })










local function derive ( scope , overrides ) 
local nested = _G.setmetatable({ spans =
scope . spans ,  layouts =
scope . layouts ,  helpers =
scope . helpers ,  writes =
scope . writes ,  index =
scope . index ,  boundSpan =
scope . boundSpan ,  mapIndex =
scope . mapIndex ,  indexSpans =
scope . indexSpans ,  cursorBounds =
scope . cursorBounds ,  resultTypes =
scope . resultTypes ,  entryMode =
scope . entryMode ,  builderMode =
scope . builderMode ,  workgroup =
scope . workgroup ,  inPhase =
scope . inPhase ,  shared =
scope . shared ,  sharedCounts =
scope . sharedCounts ,  localReadLimit =
scope . localReadLimit ,  localReadMinimum =
scope . localReadMinimum ,  countBounds =
scope . countBounds ,  countRooms =
scope . countRooms ,  simdWidth =
scope . simdWidth ,  region =
scope . region }, verify.Scope)

for field , value in pairs ( overrides ) do
( nested ) [ field ] = value
end

return nested
end











local function refuse ( why ) 
error ( why , 0 )
end




local function holds ( condition , why ) 
if not condition then
refuse ( why )
end
end






verify . NUMERIC = { [ "f64" ] = true , [ "f32" ] = true , [ "i32" ] = true , [ "u32" ] = true , [ "i64" ] = true , [ "u64" ] = true }




local function storedVector ( valueType ) 
return valueType : match ( "^simd_vector_[fiu]%d+_fixed%d+$" ) ~= nil
end

local function storageSource ( valueType , sourceType ) 
if ( valueType : match ( "^simd_vector_[fiu]%d+_fixed%d+$" ) ~= nil ) then
return valueType
end

return sourceType or tostring ( admit . CANONICAL_SOURCE [ valueType ] )
end

local function validStorage ( valueType , sourceType ) 
return admit . STORAGE [ storageSource ( valueType , sourceType ) ] == valueType
end




local function validEntryResult ( valueType , sourceType , entryMode ) 
const results = {
[ "number" ] = "f64" ,
[ "float" ] = "f64" ,
[ "integer" ] = "f64" ,
[ "uint32" ] = "u32" ,
[ "int32" ] = "i32" ,
[ "uint64" ] = "u64" ,
[ "int64" ] = "i64" ,
[ "boolean" ] = "bool" ,
[ "string" ] = "lua_string" ,
[ "any" ] = "lua_value" ,
[ "nil" ] = "lua_nil" ,
}

return sourceType ~= nil and results [ sourceType ] == valueType
or scalarIR . nativeOnlyType ( valueType ) and sourceType ~= nil and # sourceType > 0
or valueType == "lua_table" and entryMode == "lua-builder" and sourceType ~= nil and # sourceType > 0
end



const CORRECTED_LANES = { [ "f32_min" ] = 2 , [ "f32_max" ] = 2 , [ "f32_fma" ] = 3 , }


const INTEGER_LANE_OPERATIONS = {
[ "saturating_add" ] = true ,
[ "saturating_sub" ] = true ,
[ "mul_high" ] = true ,
[ "popcount" ] = true ,
}


verify . FIXED_BINARY = {
[ "f32_add" ] = "f32" ,
[ "f32_sub" ] = "f32" ,
[ "f32_mul" ] = "f32" ,
[ "f32_div" ] = "f32" ,
[ "i32_add" ] = "i32" ,
[ "i32_sub" ] = "i32" ,
[ "i32_mul" ] = "i32" ,
[ "u32_add" ] = "u32" ,
[ "u32_sub" ] = "u32" ,
[ "u32_mul" ] = "u32" ,
[ "u32_div" ] = "u32" ,
[ "u32_mod" ] = "u32" ,
[ "u32_and" ] = "u32" ,
[ "u32_or" ] = "u32" ,
[ "u32_xor" ] = "u32" ,
[ "u32_shl" ] = "u32" ,
[ "u32_shr" ] = "u32" ,
[ "i32_rotl" ] = "i32" ,
[ "i32_rotr" ] = "i32" ,
[ "u32_rotl" ] = "u32" ,
[ "u32_rotr" ] = "u32" ,
[ "u64_add" ] = "u64" ,
[ "u64_sub" ] = "u64" ,
[ "u64_mul" ] = "u64" ,
[ "u64_and" ] = "u64" ,
[ "u64_or" ] = "u64" ,
[ "u64_xor" ] = "u64" ,
[ "u64_shl" ] = "u64" ,
[ "u64_shr" ] = "u64" ,
[ "u64_sar" ] = "u64" ,
[ "u64_rotl" ] = "u64" ,
[ "u64_rotr" ] = "u64" ,
[ "i64_add" ] = "i64" ,
[ "i64_sub" ] = "i64" ,
[ "i64_mul" ] = "i64" ,
[ "i64_div" ] = "i64" ,
[ "i64_mod" ] = "i64" ,
[ "i64_and" ] = "i64" ,
[ "i64_or" ] = "i64" ,
[ "i64_xor" ] = "i64" ,
[ "i64_shl" ] = "i64" ,
[ "i64_shr" ] = "i64" ,
[ "i64_sar" ] = "i64" ,
[ "u64_div" ] = "u64" ,
[ "u64_mod" ] = "u64" ,
[ "i64_pow" ] = "i64" ,
[ "u64_pow" ] = "u64" ,
}



verify . CONVERSIONS = {
[ "narrow_f64_f32" ] = true ,
[ "widen_f32_f64" ] = true ,
[ "int_to_f64" ] = true ,
[ "numeric_cast" ] = true ,
[ "store_cast" ] = true ,
[ "f32_from_bits" ] = true ,
[ "f32_to_bits" ] = true ,
[ "f16_to_f32" ] = true ,
[ "f32_to_f16" ] = true ,
[ "bf16_to_f32" ] = true ,
[ "f32_to_bf16" ] = true ,
}


verify . BINARY_OPCODES = {
[ "add" ] = true ,
[ "sub" ] = true ,
[ "mul" ] = true ,
[ "div" ] = true ,
[ "mod" ] = true ,
[ "pow" ] = true ,
[ "band" ] = true ,
[ "bor" ] = true ,
[ "bxor" ] = true ,
[ "lshift" ] = true ,
[ "rshift" ] = true ,
[ "arshift" ] = true ,
[ "lt" ] = true ,
[ "le" ] = true ,
[ "gt" ] = true ,
[ "ge" ] = true ,
[ "eq" ] = true ,
[ "ne" ] = true ,
[ "and" ] = true ,
[ "or" ] = true ,
}


verify . FIXED_CORRECTED = {
[ "f32_min" ] = { element = "f32" , arity = 2 } ,
[ "f32_max" ] = { element = "f32" , arity = 2 } ,
[ "f32_fma" ] = { element = "f32" , arity = 3 } ,
}








local MATH = ( function ( ) 
local names = { }
for _ , entry in pairs ( admit . MATH ) do
names [ entry . name ] = entry
end

return names
end ) ( )




local function mathArity ( intrinsic , count ) 
local rule = intrinsic ~= nil and MATH [ intrinsic ] or nil

return rule ~= nil
and count >= ( rule ) . min
and ( ( rule ) . max == nil or count <= ( ( rule ) . max ) )
end




local function integerMagnitude ( value , decimalLimit , hexLimit ) 
local decimal = value : match ( "^(%d+)$" )
local hexadecimal = value : match ( "^0[xX](%x+)$" )
local digits , limit = decimal , decimalLimit
if decimal == nil then
digits , limit = hexadecimal , hexLimit
end
if digits == nil then
return false
end
digits = ( digits ) : gsub ( "^0+" , "" )
if digits == "" then
digits = "0"
end
digits = ( digits ) : lower ( )

return # digits < # limit or # digits == # limit and digits <= limit
end

local function validInteger64 ( value , valueType ) 
local negative = value : sub ( 1 , 1 ) == "-"
local magnitude = negative and value : sub ( 2 ) or value
if valueType == "u64" then
return not negative and integerMagnitude ( magnitude , "18446744073709551615" , "ffffffffffffffff" )
end

return negative and integerMagnitude ( magnitude , "9223372036854775808" , "8000000000000000" )
or not negative and integerMagnitude ( magnitude , "9223372036854775807" , "7fffffffffffffff" )
end





local function numericSpelling ( value ) 
local sign , body = value : match ( "^(-?)(.+)$" )
if sign == nil or body == nil then
return false
end
if body == "inf" then
return true
end
if ( body ) : match ( "^0[xX]" ) ~= nil then
if ( body ) : match ( "^0[xX]%x+$" ) ~= nil then
return true
end
local mantissa , exponent = ( body ) : match ( "^(0[xX].-)[pP]([+-]?%d+)$" )
if mantissa == nil or exponent == nil then
return false
end
local digits = ( mantissa ) : sub ( 3 )

return digits : match ( "^%x+%.?%x*$" ) ~= nil or digits : match ( "^%.%x+$" ) ~= nil
end

local mantissa , exponent = ( body ) : match ( "^(.-)[eE]([+-]?%d+)$" )
if mantissa == nil then
mantissa = body
elseif exponent == nil then
return false
end

return ( mantissa ) : match ( "^%d+%.?%d*$" ) ~= nil or ( mantissa ) : match ( "^%.%d+$" ) ~= nil
end



local scalarWalk





local bitOperand = admit . bitOperand



local function boundRoom ( bounds , cursor , root ) 
local spans = cursor ~= nil and bounds [ cursor ] or nil

return spans ~= nil and root ~= nil and spans [ root ] or nil
end




local function withBound ( bounds , cursor , root , room ) 
local spans = { }
for name , held in pairs ( bounds [ cursor ] or { } ) do
spans [ name ] = held
end
spans [ root ] = simdbounds . widen ( spans [ root ] , room )
bounds [ cursor ] = spans
end




local function cursorElements ( offset ) 
if offset == nil then
return 1
end
local step = offset
if step < 0 or step % 1 ~= 0 then
return math . huge
end

return step + 1
end


local function inheritBounds ( bounds ) 
local copied = { }
for name , spans in pairs ( bounds ) do
copied [ name ] = spans
end

return copied
end







local function cursorRead (
index ,
cursor ,
cursorUniqueName ,
root ,
values ,
scope
) 
if cursor == nil or cursorUniqueName == nil or index . op ~= "local" then
return false
end
local named = index

return named . name == cursor
and named . uniqueName == cursorUniqueName
and values [ cursor ] == "u32"
and boundRoom ( scope . cursorBounds , cursor , root ) ~= nil
end




const FIXED_WIDTH = "fixed width "

const SCRATCH_LENGTH = "scratch length "







const LENGTH_OF = "length of "





const ASSIGNED = "assigned "

const DECLARED_AT = "declared at "



verify.LoopFrame = {} verify.LoopFrame.__index = verify.LoopFrame ;_G.nupp.__reflect.link(verify.LoopFrame,__nuppT1[3],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00056","nupp.compiler.aot.scalar") })







local loopFrames = { }



local function enterLoop ( carried , values ) 
holds ( carried ~= nil , "a loop without its carried list" )
local frame = _G.setmetatable({ carried =  { } ,  seen =  { } }, verify.LoopFrame)
for _ , entry in ipairs ( carried ) do
holds ( values [ entry . name ] == entry . type , "a loop carries a local it cannot see" )
holds ( values [ "assigned " .. entry . name ] ~= nil , "a loop carries a local its binding did not declare assigned" )
holds ( frame . carried [ entry . name ] == nil , "a loop carries one local twice" )
frame . carried [ entry . name ] = entry
end
loopFrames [ # loopFrames + 1 ] = frame
end


local function leaveLoop ( ) 
local frame = loopFrames [ # loopFrames ]
loopFrames [ # loopFrames ] = nil
for name in pairs ( frame . carried ) do
holds ( frame . seen [ name ] == true , "a loop carries a local its body does not assign" )
end
end


local function declareLocal ( values , name , assigned ) 
if assigned == true then
values [ "assigned " .. name ] = "true"
else
values [ "assigned " .. name ] = nil
end
values [ "declared at " .. name ] = tostring ( # loopFrames )
end



local function assignedLocal ( values , name ) 
holds ( values [ "assigned " .. name ] ~= nil , "assignment to a local its binding did not declare assigned" )
local from = tonumber ( values [ "declared at " .. name ] ) or # loopFrames
for level = ( from ) + 1 , # loopFrames do
local frame = loopFrames [ level ]
holds ( frame . carried [ name ] ~= nil , "a loop assigns a local it does not carry" )
frame . seen [ name ] = true
end
end

local function scratchLengthSource ( value , values ) 
if value . op == "lua_scratch_u32_length" or value . op == "lua_scratch_u32_escape_length" then
return ( ( value ) . scratch ) . name
elseif value . op == "local" then
return values [ "scratch length " .. ( value ) . name ]
elseif value . op == "u32_and" then
local pair = value

local function mask ( other ) 
return other . op == "constant_i32" and tonumber ( ( other ) . value ) == 2147483647
end

if mask ( pair . right ) then
return scratchLengthSource ( pair . left , values )
elseif mask ( pair . left ) then
return scratchLengthSource ( pair . right , values )
end
end

return nil
end









local function fixedWidthAgrees ( bound , values , name ) 
local declared = name ~= nil and values [ "fixed width " .. name ] or nil
if bound == nil then
return declared == nil
end

return declared == tostring ( bound )
end


local function convert ( node , values , scope ) 
local from = node . value . type
if node . op == "narrow_f64_f32" then
holds ( node . type == "f32" and from == "f64" , "invalid narrowing conversion" )
elseif node . op == "widen_f32_f64" then
holds ( node . type == "f64" and from == "f32" , "invalid widening conversion" )
elseif node . op == "int_to_f64" then
holds (
node . type == "f64" and ( from == "i32" or from == "u32" or from == "i64" or from == "u64" ) ,
"invalid integer promotion"
)
elseif node . op == "f16_to_f32" then
holds ( node . type == "f32" and from == "u32" , "invalid binary16 load conversion" )
elseif node . op == "f32_to_f16" then
holds ( node . type == "u32" and from == "f32" , "invalid binary16 store conversion" )
elseif node . op == "bf16_to_f32" then
holds ( node . type == "f32" and from == "u32" , "invalid bfloat16 load conversion" )
elseif node . op == "f32_to_bf16" then
holds ( node . type == "u32" and from == "f32" , "invalid bfloat16 store conversion" )
elseif node . op == "f32_from_bits" then
holds ( node . type == "f32" and from == "u32" , "invalid binary32 bit reinterpretation" )
elseif node . op == "f32_to_bits" then
holds ( node . type == "u32" and from == "f32" , "invalid binary32 bit reinterpretation" )
elseif node . op == "store_cast" then
holds (
( node . type == "i32" or node . type == "u32" or node . type == "i64" or node . type == "u64" ) and from == "f64" ,
"invalid store conversion"
)
else
holds (
( node . type == "i32" or node . type == "u32" or node . type == "i64" or node . type == "u64" )
and ( from == "f64" or from == "i32" or from == "u32" or from == "i64" or from == "u64" ) ,
"invalid numeric cast"
)
end
scalarWalk ( node . value , values , scope )
end


local function load ( node , values , scope ) 
local root = scope . spans [ node . span ]
holds ( root ~= nil , "invalid load root" )

local span = root
holds (
( span . kind == "read_span" or span . kind == "write_span" )
and node . type == span . type
and node . sourceType == span . sourceType
and node . type : match ( "^struct:" ) == nil ,
"invalid load root"
)
if node . cursor ~= nil then
holds (
node . index == ""
and values [ node . cursor ] == "u32"
and simdbounds . boundedThrough (
scope . cursorBounds ,
node . cursor ,
span . soa ~= nil and span . soa . view or node . span ,
scope . countBounds ,
cursorElements ( node . cursorOffset ) ,
scope . countRooms
)
and node . cursorUniqueName ~= nil ,
"unbounded cursor load"
)
else
holds (
node . index == scope . index
and values [ "assigned " .. node . index ] == nil
and (
scope . mapIndex == true and ( scope . indexSpans ) [ node . span ] == true
or node . span == scope . boundSpan
or ( ( scope . countBounds or { } ) [ tostring ( scope . boundSpan ) ] or { } ) [ node . span ] == true
or scalarIR . sameSoaView ( span , scope . spans [ tostring ( scope . boundSpan ) ] )
) ,
"unbounded load index"
)
end
end






local function elementRef ( node , values , scope ) 
local root = scope . spans [ node . span ]
local layoutName = node . type : match ( "^ref:(.+)$" )
holds ( root ~= nil and layoutName ~= nil , "invalid struct element root" )

local span = root
holds (
span . type == "struct:" .. tostring ( layoutName ) and scope . layouts [ tostring ( layoutName ) ] ~= nil ,
"invalid struct element root"
)
local bounded = node . cursor ~= nil
and node . index == ""
and values [ node . cursor ] == "u32"
and simdbounds . boundedThrough (
scope . cursorBounds ,
node . cursor ,
node . span ,
scope . countBounds ,
cursorElements ( node . cursorOffset ) ,
scope . countRooms
)
and node . cursorUniqueName ~= nil
or node . cursor == nil
and node . index == scope . index
and values [ "assigned " .. node . index ] == nil
and (
scope . mapIndex == true and ( scope . indexSpans ) [ node . span ] == true
or node . span == scope . boundSpan
or ( ( scope . countBounds or { } ) [ tostring ( scope . boundSpan ) ] or { } ) [ node . span ] == true
)
holds ( node . mutable == ( span . kind == "write_span" ) and bounded , "invalid struct element access" )
end



local function corrected ( node , values , scope ) 
local rule = verify . FIXED_CORRECTED [ tostring ( node . op ) ]
local element = rule . element
if rule . arity == 3 then
local args = node . args or { }
holds ( node . type == element and # args == 3 , "invalid fused operation" )
for _ , argument in ipairs ( args ) do
holds ( argument . type == element , "invalid fused operand" )
scalarWalk ( argument , values , scope )
end

return
end

local left , right = node . left , node . right
holds (
node . type == element and left ~= nil and left . type == element and right ~= nil and right . type == element ,
"invalid corrected binary operation"
)
scalarWalk ( left , values , scope )
scalarWalk ( right , values , scope )
end


local function widenedUint32 ( value ) 
if value . op == "numeric_cast" and value . type == "u64" then
local original = ( value ) . value
return original . type == "u32" and original or nil
elseif value . op == "constant_i64" and value . type == "u64" then
local written = ( value ) . value
local number = tonumber ( written )
if number ~= nil and number >= 0 and number <= 4294967295 and number % 1 == 0 then
return ( _G.setmetatable({ op =  "constant_i32" ,  value =  written ,  type =  "u32" }, scalarIR.IntConstant) )
end
end

return nil
end








local function laneBound (
comparison ,
values ,
scope
) 
if comparison . op ~= "le" or comparison . left . op ~= "u64_add" then
return nil , nil , nil
end
local sum = comparison . left
if sum . left . op ~= "numeric_cast" or sum . left . type ~= "u64" then
return nil , nil , nil
end
local cursorNode = ( sum . left ) . value
local lanesNode = nil
if sum . right . op == "numeric_cast"
and sum . right . type == "u64"
and ( sum . right ) . value . op == "simd_lanes_generic"
then
lanesNode = ( sum . right ) . value
elseif sum . right . op == "u64_mul" then
local product = sum . right
local left , right = widenedUint32 ( product . left ) , widenedUint32 ( product . right )
if left ~= nil and right ~= nil then
lanesNode = _G.setmetatable({ op =
"u32_mul" ,  left =
left ,  right =
right ,  type =
"u32" }, scalarIR.Fixed)

end
end
if simdbounds . cursor ( cursorNode ) == nil or lanesNode == nil then
return nil , nil , nil
end
local cursor = ( cursorNode ) . name
local species , count = simdbounds . lanes ( lanesNode )
if values [ cursor ] ~= "u32" or species == nil then
return nil , nil , nil
end





local spans = { }
local right = comparison . right
if right . op == "span_count" then
local spanName = ( right ) . span
local root = scope . spans [ spanName ]
if root == nil or ( root ) . region == nil then
return nil , nil , nil
end
spans [ 1 ] = spanName
elseif right . op == "numeric_cast" and right . type == "u64" and ( right ) . value . op == "uniform" then
local uniform = ( right ) . value
local proved = ( scope . countBounds or { } ) [ uniform . name ]
if proved == nil then
return nil , nil , nil
end
for spanName in pairs ( proved ) do
spans [ # spans + 1 ] = spanName
end
table . sort ( spans )
elseif right . op == "local" and values [ "length of " .. ( right ) . name ] ~= nil then



local bytesName = values [ "length of " .. ( right ) . name ]
local root = scope . spans [ bytesName ]
if root == nil
or ( root ) . type ~= "lua_string" and ( root ) . type ~= "lua_bytes"
then
return nil , nil , nil
end
spans [ 1 ] = bytesName
else
return nil , nil , nil
end

return cursor , spans , simdbounds . room ( tostring ( ( species ) . type ) , count )
end






local function cursorSum ( value , values ) 
if value . op ~= "u64_add" then
return nil , nil
end
local sum = value
if sum . left . op ~= "numeric_cast" or sum . left . type ~= "u64" then
return nil , nil
end
if sum . right . op ~= "numeric_cast" or sum . right . type ~= "u64" then
return nil , nil
end
local cursorNode = ( sum . left ) . value
local literal = ( sum . right ) . value
if simdbounds . cursor ( cursorNode ) == nil or literal . op ~= "constant_i32" or literal . type ~= "u32" then
return nil , nil
end
local cursor = ( cursorNode ) . name
local step = tonumber ( ( literal ) . value )
if values [ cursor ] ~= "u32" or step == nil or step < 1 or step % 1 ~= 0 then
return nil , nil
end

return cursor , step
end



local function countedSpan ( right , scope ) 
if right . op ~= "span_count" then
return nil
end
local spanName = ( right ) . span
local root = scope . spans [ spanName ]
if root == nil or ( root ) . region == nil then
return nil
end

return spanName
end



local function sumBound (
comparison ,
values ,
scope
) 
if comparison . op ~= "lt" and comparison . op ~= "le" then
return nil , nil , nil
end
local cursor , step = cursorSum ( comparison . left , values )
local spanName = countedSpan ( comparison . right , scope )
if cursor == nil or spanName == nil then
return nil , nil , nil
end

return cursor , spanName , tostring ( comparison . op == "lt" and ( step ) + 1 or step )
end







local function vectorCursor ( access , values , scope ) 
local cursor = access . cursor
local named , species , count = simdbounds . offset ( access . args [ 2 ] )
local wanted = tostring ( access . args [ 1 ] . type )
local param = access . span ~= nil and scope . spans [ access . span ] or nil
local counted = param ~= nil and param . soa ~= nil and param . soa . view or access . span

return named ~= nil
and ( named ) . name == cursor
and ( named ) . uniqueName == access . cursorUniqueName
and access . cursorUniqueName ~= nil
and values [ cursor ] == "u32"
and ( species == nil or simdbounds . covers ( species , wanted ) )
and simdbounds . coveredThrough (
scope . cursorBounds ,
cursor ,
counted ,
scope . countBounds ,
wanted ,
( count or 0 ) + simdbounds . ways ( access . intrinsic )
)
end


local function binary ( node , values , scope ) 
local op = node . op
if op == "add" or op == "sub" or op == "mul" or op == "div" or op == "mod" or op == "pow" then
holds ( node . type == "f64" and node . left . type == "f64" and node . right . type == "f64" , "invalid arithmetic" )
elseif op == "band" or op == "bor" or op == "bxor" or op == "lshift" or op == "rshift" or op == "arshift" then
holds ( node . type == "i32" and bitOperand ( node . left ) and bitOperand ( node . right ) , "invalid bitwise operation" )
elseif op == "lt" or op == "le" or op == "gt" or op == "ge" or op == "eq" or op == "ne" then
local mixed = verify . NUMERIC [ node . left . type ] == true and verify . NUMERIC [ node . right . type ] == true
holds ( node . type == "bool" and ( node . left . type == node . right . type or mixed ) , "invalid comparison" )
else
holds (
node . type == "bool" and node . left . type == "bool" and node . right . type == "bool" ,
"invalid boolean operation"
)
end
scalarWalk ( node . left , values , scope )
local rightScope = scope
if ( op == "and" or op == "or" ) and ( node . left . op == "lt" or node . left . op == "ge" ) then



local comparison = node . left
local cursor = comparison . left . op == "local" and ( comparison . left ) . name or nil
local room = scalarIR . ONE_ELEMENT
local bound = nil
if cursor == nil then


local sumCursor , step = cursorSum ( comparison . left , values )
if sumCursor ~= nil and countedSpan ( comparison . right , scope ) ~= nil then
cursor , room = sumCursor , tostring ( ( step ) + 1 )
end
end
if comparison . right . op == "span_count" then
local spanName = ( comparison . right ) . span
local root = scope . spans [ spanName ]
if root ~= nil and ( root ) . region ~= nil then
bound = spanName
end
elseif comparison . right . op == "local" then
bound = scratchLengthSource ( comparison . right , values )
end
if cursor ~= nil
and values [ cursor ] == "u32"
and bound ~= nil
and ( op == "and" and node . left . op == "lt" or op == "or" and node . left . op == "ge" )
then
local cursorBounds = inheritBounds ( scope . cursorBounds )
withBound ( cursorBounds , cursor , bound , room )
rightScope = derive ( scope , { cursorBounds = cursorBounds } )
end
elseif op == "and" and node . left . op == "le" then


local cursor , spans , speciesType = laneBound ( node . left , values , scope )
if cursor ~= nil then
local cursorBounds = inheritBounds ( scope . cursorBounds )
for _ , spanName in ipairs ( spans ) do
withBound ( cursorBounds , cursor , spanName , speciesType )
end
rightScope = derive ( scope , { cursorBounds = cursorBounds } )
else
local sumCursor , sumSpan , sumRoom = sumBound ( node . left , values , scope )
if sumCursor ~= nil then
local cursorBounds = inheritBounds ( scope . cursorBounds )
withBound ( cursorBounds , sumCursor , sumSpan , sumRoom )
rightScope = derive ( scope , { cursorBounds = cursorBounds } )
end
end
end
scalarWalk ( node . right , values , rightScope )
end

local GENERIC_SIMD

= {
simd_species = true ,
simd_lanes_generic = true ,
simd_splat = true ,
simd_iota = true ,
simd_tail = true ,
simd_load = true ,
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
simd_field_load = true ,
simd_call = true ,
simd_math = true ,
}

local function genericSimdType ( typeName ) 
return typeName : match ( "^simd_(%a+)_([fiu]%d+)_(.+)$" )
end


local function genericSimdScalar ( element ) 
if element == "u8" or element == "u16" then
return "u32"
elseif element == "i8" or element == "i16" then
return "i32"
end

return element
end



local function lanesAt ( width ) 
return function ( speciesType ) 
local _ , element , shape = genericSimdType ( speciesType )
if element == nil or shape == nil then
return nil
end
if width == nil then
return tostring ( shape ) : match ( "^fixed" ) ~= nil
and shapes . lanes ( 16 , element , shape )
or nil
end

return shapes . lanes ( width , element , shape )
end
end





local function laneIndex ( operation , width ) 
local index = operation . args [ 2 ]
holds ( shapes . laneExpression ( index ) , "invalid SIMD lane index" )
local _ , element , shape = genericSimdType ( operation . args [ 1 ] . type )
local value = shapes . laneValue ( index , lanesAt ( width ) )
if value == nil then
holds (
index . op ~= "constant" and width == nil and tostring ( shape ) : match ( "^fixed" ) == nil ,
"invalid SIMD lane index"
)

return
end
holds ( ( value ) >= 1 and ( value ) % 1 == 0 , "invalid SIMD lane index" )
local lanes = lanesAt ( width ) ( operation . args [ 1 ] . type )
if lanes == nil and width == nil then
lanes = shapes . widestLanes ( tostring ( element ) , tostring ( shape ) )
end
holds ( lanes == nil or ( value ) <= ( lanes ) , "invalid SIMD lane index" )
end


local function genericSimdSpanElement ( param ) 
local physical

= {
int8 = "i8" ,
uint8 = "u8" ,
int16 = "i16" ,
uint16 = "u16" ,
float = "f32" ,
int32 = "i32" ,
uint32 = "u32" ,
int64 = "i64" ,
uint64 = "u64" ,
number = "f64" ,
}

return physical [ param . sourceType or "" ] or param . type
end



local function genericSimdFieldElement ( scope , layoutName , field ) 
local layout = layoutName ~= nil and scope . layouts [ layoutName ] or nil
if layout == nil or field == nil then
return nil
end
local stored = ( layout ) . fieldTypes or { }
local sources = ( layout ) . fieldSourceTypes or { }
local storedType = stored [ field ]
if storedType == nil then
return nil
end

return genericSimdSpanElement (
_G.setmetatable({ kind =
"read_span" ,  name =
field ,  type =
storedType ,  sourceType =
sources [ field ] }, scalarIR.Param)

)
end



local function sameLaneCount ( left , right ) 
local leftFamily = genericSimdType ( left )
local rightFamily = genericSimdType ( right )

return leftFamily == "mask" and rightFamily == "mask" and shapes . sameLanes ( left , right )
end




local function genericFieldAccess (
access ,
vectorType ,
valueCount ,
rootKind ,
values ,
scope
) 
local args = access . args
local family , element , shape = genericSimdType ( vectorType )
local maskPosition = 3 + valueCount
holds (
family == "vector"
and ( # args == maskPosition - 1 or # args == maskPosition )
and access . intrinsic == "field"
and args [ 1 ] . type == "simd_species_" .. tostring ( element ) .. "_" .. tostring ( shape )
and args [ 2 ] . type == "f64"
and (
args [ maskPosition ] == nil
or args [ maskPosition ] . type == "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape )
) ,
"generic SIMD field access operands do not match"
)
local span = access . span ~= nil and scope . spans [ access . span ] or nil
holds (
span ~= nil
and (
( span ) . kind == rootKind
or rootKind == "read_span" and ( span ) . kind == "write_span"
)
and ( span ) . type == "struct:" .. tostring ( access . layout )
and genericSimdFieldElement ( scope , access . layout , access . field ) == element ,
"invalid generic SIMD field access root"
)
if access . cursor ~= nil then
holds ( args [ maskPosition ] == nil and vectorCursor ( access , values , scope ) , "unbounded SIMD cursor field access" )
end
for _ , argument in ipairs ( args ) do
scalarWalk ( argument , values , scope )
end
end

scalarWalk = function ( node , values , scope ) 
holds ( node ~= nil and node . type ~= nil , "untyped IR expression" )




local op = node . op
if verify . CONVERSIONS [ tostring ( op ) ] == true then
convert ( node , values , scope )
elseif op == "load" then
load ( node , values , scope )
elseif op == "element_ref" then
elementRef ( node , values , scope )
elseif op == "field_load" then
local layout = scope . layouts [ node . layout ]
holds (
layout ~= nil
and layout . nativeOnly ~= true
and ( layout . fieldTypes or { } ) [ node . field ] == node . type
and ( layout . fieldSourceTypes or { } ) [ node . field ] == storageSource ( node . type , node . sourceType ) ,
"invalid struct field load"
)
scalarWalk ( node . object , values , scope )
elseif op == "aggregate_new" then
local built = node
local layout = scope . layouts [ built . layout ]
holds (
layout ~= nil
and layout . nativeOnly == true
and node . type == "aggregate:" .. built . layout
and # built . values == # layout . fields ,
"invalid native-only aggregate construction"
)
for position , value in ipairs ( built . values ) do
holds (
value . type == ( layout ) . fields [ position ] . type ,
"native-only aggregate field value type"
)
scalarWalk ( value , values , scope )
end
elseif op == "aggregate_field" then
local field = node
local layout = scope . layouts [ field . layout ]
holds (
layout ~= nil
and layout . nativeOnly == true
and ( layout . fieldTypes or { } ) [ field . field ] == node . type
and field . object . type == "aggregate:" .. field . layout ,
"invalid native-only aggregate field"
)
scalarWalk ( field . object , values , scope )
elseif op == "uniform" then
local param = scope . spans [ node . name ]
holds ( param ~= nil , "invalid uniform" )
holds (
( param ) . kind == "uniform" and node . type == ( param ) . type ,
"invalid uniform"
)
elseif op == "span_count" then
local span = scope . spans [ node . span ]
holds ( span ~= nil and ( span ) . region ~= nil and node . type == "f64" , "invalid span count" )
elseif op == "loop_index" then
holds ( scope . mapIndex == true and node . type == "f64" , "loop index outside a map body" )
elseif op == "workgroup_index" or op == "local_index" then
holds (
scope . workgroup == true and node . type == "u32" and ( op ~= "local_index" or scope . inPhase == true ) ,
"workgroup coordinate outside its structural body"
)
elseif op == "shared_load" then
local load = node
local shared = scope . shared or { }
local counts = scope . sharedCounts or { }
holds (
scope . workgroup == true and scope . inPhase == true and shared [ load . shared ] == load . type ,
"invalid workgroup scratch read"
)
holds ( load . index . type == "u32" , "workgroup scratch index is not uint32" )

local function indexRange ( value ) 
local operation = value . op
if operation == "constant" or operation == "constant_i32" then
local constant = tonumber ( ( value ) . value )
if constant ~= nil and constant == math . floor ( constant ) and constant >= 0 then
return constant , constant
end
elseif operation == "local_index" then
local count = counts [ load . shared ]
if count ~= nil then
return 0 , count - 1
end
elseif operation == "numeric_cast" or operation == "int_to_f64" then
return indexRange ( ( value ) . value )
elseif operation == "u32_add" or operation == "u32_mul" then
local pair = value
local leftMin , leftMax = indexRange ( pair . left )
local rightMin , rightMax = indexRange ( pair . right )
if leftMin ~= nil and leftMax ~= nil and rightMin ~= nil and rightMax ~= nil then
local low = operation == "u32_add" and ( leftMin ) + ( rightMin )
or ( leftMin ) * ( rightMin )
local high = operation == "u32_add" and ( leftMax ) + ( rightMax )
or ( leftMax ) * ( rightMax )
if high <= 4294967295 then
return low , high
end
end
elseif operation == "u32_div" or operation == "u32_mod" then
local pair = value
local leftMin , leftMax = indexRange ( pair . left )
local rightMin , rightMax = indexRange ( pair . right )
if leftMin ~= nil and leftMax ~= nil and rightMin ~= nil and rightMin == rightMax and rightMin > 0 then
if operation == "u32_div" then
return math . floor (
( leftMin ) / ( rightMin )
) , math . floor ( ( leftMax ) / ( rightMin ) )
end
return 0 , math . min ( leftMax , ( rightMin ) - 1 )
end
end

return nil , nil
end

local minimum , maximum = indexRange ( load . index )
local constant = load . index . op == "constant_i32" and tonumber ( ( load . index ) . value ) or nil
local offset = nil
local back = nil
if load . index . op == "u32_add" then
local added = load . index
if added . left . op == "local_index" and added . right . op == "constant_i32" then
offset = tonumber ( ( added . right ) . value )
end
elseif load . index . op == "u32_sub" then
local subtracted = load . index
if subtracted . left . op == "local_index" and subtracted . right . op == "constant_i32" then
back = tonumber ( ( subtracted . right ) . value )
end
end
holds (
load . index . op == "local_index"
or constant ~= nil and constant >= 0 and constant < counts [ load . shared ]
or minimum ~= nil and maximum ~= nil and minimum >= 0 and maximum < counts [ load . shared ]
or offset ~= nil
and scope . localReadLimit ~= nil
and offset >= 0
and ( scope . localReadLimit ) + offset <= counts [ load . shared ]
or back ~= nil
and scope . localReadMinimum ~= nil
and back >= 0
and ( scope . localReadMinimum ) >= back ,
"workgroup scratch read is not proved in bounds"
)
scalarWalk ( load . index , values , scope )
elseif op == "local" or op == "helper_param" then
local named = node
holds (
values [ named . name ] == node . type ,
"invalid local value " .. named . name .. " of type " .. tostring ( node . type )
)
if named . lengthOf ~= nil then
local bytes = scope . spans [ named . lengthOf ]
holds (
bytes ~= nil
and ( ( bytes ) . type == "lua_string" or ( bytes ) . type == "lua_bytes" )
and values [ "length of " .. named . name ] == named . lengthOf ,
"invalid rooted length alias"
)
end
elseif GENERIC_SIMD [ tostring ( op ) ] == true then
local simd = node
local args = simd . args
holds ( simd . rooted == nil or op == "simd_load" , "unexpected rooted SIMD root" )
local family , element , shape = genericSimdType ( node . type )
if op == "simd_species" then
holds ( family == "species" and # args == 0 , "invalid generic SIMD species" )
elseif op == "simd_lanes_generic" then
local argFamily = args [ 1 ] ~= nil and genericSimdType ( args [ 1 ] . type ) or nil
holds ( node . type == "u32" and # args == 1 and argFamily == "species" , "invalid generic SIMD lane count" )
elseif op == "simd_splat" or op == "simd_iota" then
holds ( family == "vector" and # args == ( op == "simd_splat" and 1 or 2 ) , "invalid generic SIMD construction" )
for _ , argument in ipairs ( args ) do
holds ( argument . type == genericSimdScalar ( element ) , "generic SIMD construction has the wrong element" )
end
elseif op == "simd_convert" or op == "simd_reinterpret" then
holds (
# args == 1
and simd . intrinsic == ( op == "simd_convert" and "convert" or "reinterpret" )
and simdcast . matches ( args [ 1 ] . type , node . type , op == "simd_reinterpret" ) ,
"invalid generic SIMD conversion"
)
elseif op == "simd_tail" then
holds ( family == "mask" and # args == 1 and args [ 1 ] . type == "u32" , "invalid generic SIMD tail" )
elseif op == "simd_mask_splat" then
holds ( family == "mask" and # args == 1 and args [ 1 ] . type == "bool" , "invalid generic SIMD mask splat" )
elseif op == "simd_mask_convert" then
holds (
family == "mask" and # args == 1 and sameLaneCount ( args [ 1 ] . type , node . type ) ,
"generic SIMD mask conversion changes the lane count"
)
elseif op == "simd_field_load" then
genericFieldAccess ( simd , node . type , 0 , "read_span" , values , scope )

return
elseif op == "simd_call" or op == "simd_math" then
holds ( family == "vector" and # args >= 1 , "invalid generic SIMD lane-wise call" )
local scalar = genericSimdScalar ( element )
local corrected = op == "simd_call" and CORRECTED_LANES [ tostring ( simd . intrinsic ) ] or nil
if corrected ~= nil then



holds (
simd . helper == nil and element == "f32" and # args == corrected ,
"invalid generic SIMD lane-wise correction"
)
elseif op == "simd_call" then
local found = simd . helper ~= nil and scope . helpers [ simd . helper ] or nil
holds ( found ~= nil , "invalid generic SIMD lane-wise helper" )
local helper = found


local carrier = scalar == "f32" and "f64" or scalar
holds (
# helper . params == # args and # helper . resultTypes == 1 and helper . resultTypes [ 1 ] == carrier ,
"generic SIMD lane-wise helper does not take the element"
)
for _ , param in ipairs ( helper . params ) do
holds ( param . type == carrier , "generic SIMD lane-wise helper does not take the element" )
end
else
holds (
( element == "f32" or element == "f64" ) and mathArity ( simd . intrinsic , # args ) ,
"invalid generic SIMD lane-wise math"
)
end


for _ , argument in ipairs ( args ) do
holds (
argument . op == "local" and argument . type == node . type ,
"generic SIMD lane-wise operand is not a local of the result's species"
)
end
elseif op == "simd_load" then
local interleaved = simdbounds . interleaved ( simd . intrinsic )
holds ( family == "vector" and ( # args == 2 or # args == 3 and not interleaved ) , "invalid generic SIMD load" )
holds (
simd . intrinsic == "load" or simd . intrinsic == "gather" or interleaved and simd . rooted == nil ,
"invalid SIMD load addressing"
)

holds (
interleaved
and simd . part ~= nil
and ( simd . part ) >= 0
and ( simd . part ) < simdbounds . ways ( simd . intrinsic )
and ( simd . part ) % 1 == 0
or not interleaved and simd . part == nil ,
"invalid interleaved SIMD load part"
)
holds (
args [ 1 ] . type == "simd_species_" .. tostring ( element ) .. "_" .. tostring ( shape )
and (
simd . intrinsic == "gather" and simdindices . matches ( args [ 2 ] . type , args [ 1 ] . type )
or simd . intrinsic ~= "gather" and args [ 2 ] . type == "f64"
)
and ( args [ 3 ] == nil or args [ 3 ] . type == "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape ) ) ,
"generic SIMD load operands do not match"
)
local span = simd . span ~= nil and scope . spans [ simd . span ] or nil
if simd . rooted ~= nil then






local rooted = simd . rooted
holds (
scope . entryMode == "lua-builder"
and element == "u8"
and span ~= nil
and ( span ) . kind == "scalar"
and ( ( span ) . type == "lua_string" or ( span ) . type == "lua_bytes" )
and rooted . op == "local"
and rooted . name == simd . span
and rooted . type == ( span ) . type
and rooted . uniqueName ~= nil
and rooted . uniqueName == ( span ) . uniqueName ,
"invalid rooted SIMD load root"
)
scalarWalk ( rooted , values , scope )
else
holds (
span ~= nil
and ( ( span ) . kind == "read_span" or ( span ) . kind == "write_span" )
and genericSimdSpanElement ( span ) == element ,
"invalid generic SIMD load root"
)
end
if simd . cursor ~= nil then
holds (
simd . intrinsic ~= "gather" and args [ 3 ] == nil and vectorCursor ( simd , values , scope ) ,
"unbounded SIMD cursor load"
)
end
elseif op == "simd_binary" or op == "simd_unary" then
local intrinsic = tostring ( simd . intrinsic )

local arity = op == "simd_unary" and 1 or intrinsic == "fma" and 3 or 2
holds (
( family == "vector" or family == "mask" )
and # args == arity
and args [ 1 ] . type == node . type
and ( args [ 2 ] == nil or args [ 2 ] . type == node . type )
and ( args [ 3 ] == nil or args [ 3 ] . type == node . type ) ,
"invalid generic SIMD operator"
)
local floating = element == "f32" or element == "f64"
if INTEGER_LANE_OPERATIONS [ intrinsic ] == true then
holds ( family == "vector" and not floating , "invalid generic SIMD integer lane operation" )
elseif intrinsic == "fma" then
holds ( family == "vector" and floating , "invalid generic SIMD fused multiply-add" )
end
elseif op == "simd_compare" then
local operandFamily , operandElement , operandShape = nil , nil , nil
if args [ 1 ] ~= nil then
operandFamily , operandElement , operandShape = genericSimdType ( args [ 1 ] . type )
end
holds (
family == "mask"
and # args == 2
and args [ 1 ] . type == args [ 2 ] . type
and ( operandFamily == "vector" or operandFamily == "mask" )
and element == operandElement
and shape == operandShape ,
"invalid generic SIMD comparison"
)
elseif op == "simd_select" then
holds (
family == "vector"
and # args == 3
and args [ 1 ] . type == "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape )
and args [ 2 ] . type == node . type
and args [ 3 ] . type == node . type ,
"invalid generic SIMD select"
)
elseif op == "simd_extract" then
local vectorFamily , vectorElement = nil , nil
if args [ 1 ] ~= nil then
vectorFamily , vectorElement = genericSimdType ( args [ 1 ] . type )
end
holds (
# args == 2
and vectorFamily == "vector"
and node . type == genericSimdScalar ( vectorElement )
and args [ 2 ] . type == "f64" ,
"invalid generic SIMD extract"
)
laneIndex ( simd , scope . simdWidth )
elseif op == "simd_insert" then
holds (
family == "vector"
and # args == 3
and args [ 1 ] . type == node . type
and args [ 2 ] . type == "f64"
and args [ 3 ] . type == genericSimdScalar ( element ) ,
"invalid generic SIMD insert"
)
laneIndex ( simd , scope . simdWidth )
elseif op == "simd_permute" then
local intrinsic = tostring ( simd . intrinsic )
holds ( family == "vector" , "invalid generic SIMD permutation result" )
if intrinsic == "reverse" then
holds ( # args == 1 and args [ 1 ] . type == node . type , "invalid generic SIMD reverse" )
elseif intrinsic == "rotate_left" or intrinsic == "rotate_right" then
holds (
# args == 2 and args [ 1 ] . type == node . type and args [ 2 ] . op == "constant" ,
"invalid generic SIMD rotation"
)
elseif intrinsic == "interleave" or intrinsic == "deinterleave" or intrinsic == "transpose" then
local rows = # args - 1
local part = args [ # args ]
local index = part ~= nil and part . op == "constant" and tonumber ( ( part ) . value )
or nil
local valid = family == "vector"
and index ~= nil
and index >= 0
and index % 1 == 0
and index < rows
and part . type == "f64"
if intrinsic == "transpose" then
valid = valid and rows >= 2 and rows <= 64 and shape == "fixed" .. tostring ( rows )
else
valid = valid and rows == 2
end
for i = 1 , rows do
valid = valid and args [ i ] . type == node . type
end
holds ( valid , "invalid generic SIMD rearrangement" )
elseif intrinsic == "swizzle"
or intrinsic == "swizzle_pair"
or intrinsic == "swizzle_triple"
or intrinsic == "swizzle_quad"
then
local operands = intrinsic == "swizzle_quad" and 5
or intrinsic == "swizzle_triple" and 4
or intrinsic == "swizzle_pair" and 3
or 2
local sameShape = # args == operands
for position = 1 , operands do
sameShape = sameShape and args [ position ] ~= nil and args [ position ] . type == node . type
end
holds ( sameShape and tostring ( element ) : sub ( 1 , 1 ) ~= "f" , "invalid generic SIMD swizzle" )
elseif intrinsic == "align" then
holds (
# args == 3
and args [ 1 ] . type == node . type
and args [ 2 ] . type == node . type
and shapes . laneExpression ( args [ 3 ] ) ,
"invalid generic SIMD alignment"
)
local offset = shapes . laneValue ( args [ 3 ] , lanesAt ( scope . simdWidth ) )
holds (
offset == nil and args [ 3 ] . op ~= "constant"
or offset ~= nil and ( offset ) >= 0 and ( offset ) % 1 == 0 ,
"invalid generic SIMD alignment"
)
else
holds ( false , "unknown generic SIMD permutation" )
end
elseif op == "simd_compress" or op == "simd_expand" then
holds (
family == "vector"
and # args == 2
and args [ 1 ] . type == node . type
and args [ 2 ] . type == "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape ) ,
"invalid generic SIMD packing operation"
)
elseif op == "simd_prefix" then
holds (
family == "vector"
and # args == 1
and args [ 1 ] . type == node . type
and ( simd . intrinsic == "prefix_sum_ordered" or simd . intrinsic == "prefix_xor" )
and not ( simd . intrinsic == "prefix_xor" and tostring ( element ) : sub ( 1 , 1 ) == "f" ) ,
"invalid generic SIMD prefix operation"
)
elseif op == "simd_horizontal" then
local vectorFamily , vectorElement = nil , nil
if args [ 1 ] ~= nil then
vectorFamily , vectorElement = genericSimdType ( args [ 1 ] . type )
end
local intrinsic = tostring ( simd . intrinsic )
local dot = intrinsic : match ( "_dot$" ) ~= nil
local admittedHorizontal = {
ordered_sum = true ,
pairwise_sum = true ,
algebraic_sum = true ,
ordered_product = true ,
pairwise_product = true ,
algebraic_product = true ,
ordered_dot = true ,
pairwise_dot = true ,
algebraic_dot = true ,
propagating_min = true ,
propagating_max = true ,
number_min = true ,
number_max = true ,
propagating_arg_min = true ,
propagating_arg_max = true ,
number_arg_min = true ,
number_arg_max = true ,
exact_sum = true ,
exact_product = true ,
exact_and = true ,
exact_or = true ,
exact_xor = true ,
integer_min = true ,
integer_max = true ,
}






local indexed = intrinsic : match ( "_arg_m[ai][xn]$" ) ~= nil
local extremum = indexed or intrinsic : match ( "^propagating_m" ) ~= nil or intrinsic : match ( "^number_m" ) ~= nil
local integerContract = intrinsic : match ( "^exact_" ) ~= nil or intrinsic : match ( "^integer_" ) ~= nil
local floating = vectorElement == "f32" or vectorElement == "f64"
holds (
vectorFamily == "vector"
and # args == ( dot and 2 or 1 )
and ( args [ 2 ] == nil or args [ 2 ] . type == args [ 1 ] . type )
and node . type == ( indexed and "f64" or genericSimdScalar ( vectorElement ) )
and admittedHorizontal [ intrinsic ] == true
and ( integerContract and not floating or not integerContract and ( extremum or floating ) ) ,
"invalid generic SIMD horizontal operation"
)
else
local maskFamily = args [ 1 ] ~= nil and genericSimdType ( args [ 1 ] . type ) or nil
local result = ( op == "simd_mask_any" or op == "simd_mask_all" ) and "bool"
or op == "simd_mask_count" and "u32"
or op == "simd_mask_first" and "u32"
or nil
holds (
# args == 1
and maskFamily == "mask"
and ( node . type == result or op == "simd_mask_bits" and node . type == "u64" ) ,
"invalid generic SIMD mask query"
)
end
for _ , argument in ipairs ( args ) do
scalarWalk ( argument , values , scope )
end
elseif verify . FIXED_BINARY [ tostring ( op ) ] ~= nil then
local element = verify . FIXED_BINARY [ tostring ( op ) ]
local pair = node
local rotate = op == "u64_rotl" or op == "u64_rotr"
holds (
node . type == element
and pair . left . type == element
and ( pair . right . type == element or rotate and pair . right . type == "i64" ) ,
"invalid fixed-width binary operation"
)
scalarWalk ( pair . left , values , scope )
scalarWalk ( pair . right , values , scope )
elseif op == "f32_sqrt" or op == "f32_exp" then
local unary = node
holds ( node . type == "f32" and unary . value . type == "f32" , "invalid binary32 unary operation" )
scalarWalk ( unary . value , values , scope )
elseif op == "u32_not" or op == "u32_popcount" or op == "u32_ctz" or op == "u32_clz" then
local counted = node
holds ( node . type == "u32" and counted . value . type == "u32" , "invalid uint32 bit count" )
scalarWalk ( counted . value , values , scope )
elseif op == "u64_not" or op == "i64_not" then
local complemented = node
local width = op == "u64_not" and "u64" or "i64"
holds ( node . type == width and complemented . value . type == width , "invalid 64-bit complement" )
scalarWalk ( complemented . value , values , scope )
elseif op == "u64_popcount" or op == "u64_ctz" or op == "u64_clz" then


local counted = node
holds ( node . type == "u32" and counted . value . type == "u64" , "invalid uint64 bit count" )
scalarWalk ( counted . value , values , scope )
elseif op == "u64_prefix_xor" then
local prefixed = node
holds ( node . type == "u64" and prefixed . value . type == "u64" , "invalid uint64 prefix xor" )
scalarWalk ( prefixed . value , values , scope )
elseif verify . FIXED_CORRECTED [ tostring ( op ) ] ~= nil then
corrected ( node , values , scope )
elseif op == "constant_i32" then
local number = tonumber ( node . value )
holds (
( node . type == "i32" or node . type == "u32" )
and numericSpelling ( node . value )
and number ~= nil
and number % 1 == 0
and number >= ( node . type == "u32" and 0 or -2147483648 )
and number <= ( node . type == "u32" and 4294967295 or 2147483647 ) ,
"invalid 32-bit integer constant"
)
elseif op == "constant_i64" then
holds (
( node . type == "i64" or node . type == "u64" ) and validInteger64 ( node . value , node . type ) ,
"invalid 64-bit integer constant"
)
elseif op == "constant" then



local number = tonumber ( node . value )
holds (
node . type == "f64" and numericSpelling ( node . value ) and number ~= nil and number == number ,
"invalid constant"
)
elseif op == "bool" then
holds ( node . type == "bool" and type ( node . value ) == "boolean" , "invalid boolean" )
elseif op == "lua_nil" then
holds ( scope . entryMode == "lua-builder" and node . type == "lua_nil" , "Lua nil outside a builder" )
elseif op == "lua_string" then
holds (
scope . entryMode == "lua-builder" and node . type == "lua_string" and type ( node . value ) == "string" ,
"Lua string outside a builder"
)
elseif op == "lua_string_match" then
local matched = node
holds ( scope . entryMode == "lua-builder" and node . type == "bool" , "string match outside a builder" )
holds ( matched . bytes . type == "lua_string" and matched . bytes . op == "local" , "string match input is not rooted" )
holds ( type ( matched . value ) == "string" , "string match literal is not bytes" )
scalarWalk ( matched . bytes , values , scope )
elseif op == "lua_concat" then
local joined = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_string" , "Lua concat outside a builder" )
holds ( joined . left . type == "lua_string" and joined . right . type == "lua_string" , "non-string Lua concat" )
scalarWalk ( joined . left , values , scope )
scalarWalk ( joined . right , values , scope )
elseif op == "lua_substring" then
local sliced = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_string" , "Lua substring outside a builder" )
holds ( sliced . bytes . type == "lua_string" and sliced . bytes . op == "local" , "substring input is not rooted" )
holds (
sliced . first . type == "f64" and ( sliced . last == nil or ( sliced . last ) . type == "f64" ) ,
"substring bounds are not numeric"
)
scalarWalk ( sliced . bytes , values , scope )
scalarWalk ( sliced . first , values , scope )
if sliced . last ~= nil then
scalarWalk ( sliced . last , values , scope )
end
elseif op == "lua_string_byte_lua" then
local loaded = node
holds ( scope . entryMode == "lua-builder" and node . type == "f64" , "Lua string byte outside a builder" )
holds ( loaded . bytes . type == "lua_string" and loaded . bytes . op == "local" , "string.byte input is not rooted" )
holds ( loaded . index . type == "f64" , "string.byte index is not numeric" )
scalarWalk ( loaded . bytes , values , scope )
scalarWalk ( loaded . index , values , scope )
elseif op == "lua_table_get_index" then
local loaded = node
holds ( scope . entryMode == "lua-builder" and node . type == "f64" , "Lua table read outside a builder" )
holds ( loaded . table . type == "lua_table" and loaded . table . op == "local" , "Lua table read is not rooted" )
holds ( verify . NUMERIC [ loaded . key . type ] == true , "Lua table index is not numeric" )
scalarWalk ( loaded . table , values , scope )
scalarWalk ( loaded . key , values , scope )
elseif op == "lua_string_buffer" then
local buffer = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_string_buffer" , "string buffer outside a builder" )
holds ( buffer . initial . type == "lua_string" , "string buffer initial value is not a string" )
scalarWalk ( buffer . initial , values , scope )
elseif op == "lua_string_buffer_finish" then
local finished = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_string" , "string buffer finish outside a builder" )
holds (
finished . buffer . type == "lua_string_buffer" and finished . buffer . op == "local" ,
"string buffer finish has no local buffer"
)
scalarWalk ( finished . buffer , values , scope )
elseif op == "lua_new_table" then
local created = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_table" , "Lua allocation outside a builder" )
for _ , capacity in ipairs ( { created . arrayCapacity , created . hashCapacity } ) do
holds ( verify . NUMERIC [ capacity . type ] == true , "non-numeric Lua table capacity" )
scalarWalk ( capacity , values , scope )
end
for _ , field in ipairs ( created . fields or { } ) do
scalarWalk ( field . key , values , scope )
scalarWalk ( field . value , values , scope )
holds (
verify . NUMERIC [ field . key . type ] == true or field . key . type == "lua_string" ,
"unsupported fresh-table literal key"
)
holds (
verify . NUMERIC [ field . value . type ] == true
or field . value . type == "bool"
or field . value . type == "lua_nil"
or field . value . type == "lua_string"
or field . value . type == "lua_table" ,
"unsupported fresh-table literal value"
)
end
elseif op == "lua_builder" then
local builder = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_builder" , "value stream outside a builder" )
holds (
( builder . mode == "eager" or builder . mode == "pull" or builder . mode == "serde" )
and scope . builderMode == builder . mode ,
"unknown or inconsistent value stream mode"
)
holds (
builder . nullValue . type == "lua_value" and builder . nullValue . op == "local" ,
"value stream null is not rooted"
)
scalarWalk ( builder . nullValue , values , scope )
if builder . maxDepth ~= nil or builder . stringCapacity ~= nil then
holds (
builder . maxDepth ~= nil
and ( builder . maxDepth ) . type == "u32"
and builder . stringCapacity ~= nil
and ( builder . stringCapacity ) . type == "u32" ,
"sized value stream has invalid bounds"
)
scalarWalk ( builder . maxDepth , values , scope )
scalarWalk ( builder . stringCapacity , values , scope )
end
if builder . arrayMarker ~= nil or builder . objectMarker ~= nil then
holds (
builder . arrayMarker ~= nil
and builder . objectMarker ~= nil
and ( builder . arrayMarker ) . type == "lua_value"
and ( builder . objectMarker ) . type == "lua_value" ,
"value stream container markers are not rooted"
)
scalarWalk ( builder . arrayMarker , values , scope )
scalarWalk ( builder . objectMarker , values , scope )
end
if builder . selectionShape ~= nil or builder . arrayShapeMarker ~= nil or builder . serdeMarkers ~= nil then
holds (
builder . selectionShape ~= nil
and builder . arrayShapeMarker ~= nil
and ( builder . selectionShape ) . type == "lua_value"
and ( builder . selectionShape ) . op == "local"
and ( builder . arrayShapeMarker ) . type == "lua_value"
and ( builder . arrayShapeMarker ) . op == "local"
and builder . serdeMarkers ~= nil
and ( builder . serdeMarkers ) . type == "lua_value"
and ( builder . serdeMarkers ) . op == "local" ,
"pull value stream selection is not rooted"
)
scalarWalk ( builder . selectionShape , values , scope )
scalarWalk ( builder . arrayShapeMarker , values , scope )
scalarWalk ( builder . serdeMarkers , values , scope )
end
elseif op == "lua_scratch_u32" then
local scratch = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_scratch_u32" , "scratch outside a builder" )
holds ( scratch . capacity . type == "u32" , "scratch capacity is not uint32" )
scalarWalk ( scratch . capacity , values , scope )
elseif op == "lua_scratch_u32_get" or op == "lua_scratch_u32_escape_get" then
local loaded = node
holds ( scope . entryMode == "lua-builder" and node . type == "u32" , "scratch read outside a builder" )
holds (
loaded . scratch . type == "lua_scratch_u32" and loaded . scratch . op == "local" ,
"scratch read has no local buffer"
)
holds ( loaded . index . type == "u32" , "scratch read index is not uint32" )
holds (
loaded . cursor == nil and loaded . cursorUniqueName == nil
or cursorRead (
loaded . index ,
loaded . cursor ,
loaded . cursorUniqueName ,
( loaded . scratch ) . name ,
values ,
scope
) ,
"direct scratch read lacks a dominating length proof"
)
holds (
fixedWidthAgrees ( loaded . fixedBound , values , ( loaded . scratch ) . name ) ,
"scratch read bound is not the width of the buffer it reads"
)
scalarWalk ( loaded . scratch , values , scope )
scalarWalk ( loaded . index , values , scope )
elseif op == "lua_scratch_u32_length" or op == "lua_scratch_u32_escape_length" then
local loaded = node
holds ( scope . entryMode == "lua-builder" and node . type == "u32" , "scratch length outside a builder" )
holds (
loaded . scratch . type == "lua_scratch_u32" and loaded . scratch . op == "local" ,
"scratch length has no local buffer"
)
scalarWalk ( loaded . scratch , values , scope )
elseif op == "lua_scratch_u8" then
local scratch = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_scratch_u8" , "byte scratch outside a builder" )
holds ( scratch . capacity . type == "u32" , "byte scratch capacity is not uint32" )
scalarWalk ( scratch . capacity , values , scope )
elseif op == "lua_scratch_u8_get" then
local loaded = node
holds ( scope . entryMode == "lua-builder" and node . type == "u32" , "byte scratch read outside a builder" )
holds (
loaded . scratch . type == "lua_scratch_u8" and loaded . scratch . op == "local" ,
"byte scratch read has no local buffer"
)
holds ( loaded . index . type == "u32" , "byte scratch read index is not uint32" )
holds (
fixedWidthAgrees ( loaded . fixedBound , values , ( loaded . scratch ) . name ) ,
"byte scratch read bound is not the width of the buffer it reads"
)
scalarWalk ( loaded . scratch , values , scope )
scalarWalk ( loaded . index , values , scope )
elseif op == "lua_string_byte"
or op == "lua_string_byte_at"
or op == "lua_string_u32"
or op == "lua_string_length"
then
local bytes = node
holds ( scope . entryMode == "lua-builder" and node . type == "u32" , "rooted byte read outside a builder" )
holds (
( bytes . bytes . type == "lua_string" or bytes . bytes . type == "lua_bytes" ) and bytes . bytes . op == "local" ,
"byte input is not a rooted string or buffer"
)
scalarWalk ( bytes . bytes , values , scope )
if op == "lua_string_length" then
holds ( bytes . index == nil , "string length carried an index" )
else
holds ( bytes . index ~= nil and ( bytes . index ) . type == "u32" , "byte read index is not uint32" )
scalarWalk ( bytes . index , values , scope )
if op == "lua_string_byte_at" then
local rooted = bytes . bytes
holds (
cursorRead (
bytes . index ,
bytes . cursor ,
bytes . cursorUniqueName ,
rooted . name ,
values ,
scope
) ,
"direct rooted byte read lacks a bounds proof"
)
end
end
elseif op == "lua_builder_finish" then
local finished = node
holds ( scope . entryMode == "lua-builder" and node . type == "lua_value" , "value stream finish outside a builder" )
holds (
finished . builder . type == "lua_builder" and finished . builder . op == "local" ,
"finished value stream is not local"
)
scalarWalk ( finished . builder , values , scope )
holds (
( finished . mode == "eager" or finished . mode == "pull" or finished . mode == "serde" )
and scope . builderMode == finished . mode ,
"unknown or inconsistent finished value stream mode"
)
elseif op == "lua_builder_depth"
or op == "lua_builder_kind"
or op == "lua_builder_count"
or op == "lua_builder_state"
then
local query = node
holds ( scope . entryMode == "lua-builder" and node . type == "u32" , "value stream query outside a builder" )
holds (
query . builder . type == "lua_builder" and query . builder . op == "local" ,
"value stream query has no local builder"
)
scalarWalk ( query . builder , values , scope )
holds (
( query . mode == "eager" or query . mode == "pull" or query . mode == "serde" )
and scope . builderMode == query . mode ,
"unknown or inconsistent queried value stream mode"
)
elseif op == "lua_builder_number_token" then
local number = node
holds ( scope . entryMode == "lua-builder" and node . type == "u32" , "number token outside a builder" )
holds (
number . builder . type == "lua_builder" and number . builder . op == "local" ,
"number token has no local builder"
)
holds (
( number . sourceBytes . type == "lua_string" or number . sourceBytes . type == "lua_bytes" )
and number . sourceBytes . op == "local" ,
"number token input is not rooted bytes"
)
holds ( number . start . type == "u32" and number . limit . type == "u32" , "number token bounds are not uint32" )
holds (
( number . mode == "eager" or number . mode == "pull" or number . mode == "serde" )
and scope . builderMode == number . mode ,
"unknown or inconsistent number token mode"
)
scalarWalk ( number . builder , values , scope )
scalarWalk ( number . sourceBytes , values , scope )
scalarWalk ( number . start , values , scope )
scalarWalk ( number . limit , values , scope )
elseif op == "neg" or op == "not" or op == "bnot" then
local operand = ( node ) . value
scalarWalk ( operand , values , scope )
local expected = op == "neg" and "f64" or op == "not" and "bool" or "i32"
holds ( node . type == expected , "invalid unary operation" )
if op == "bnot" then
holds ( bitOperand ( operand ) , "invalid bitwise operand" )
else
holds ( operand . type == expected , "invalid unary operation" )
end
elseif op == "math" then
holds ( node . type == "f64" , "invalid math result" )
holds ( mathArity ( node . intrinsic , # node . args ) , "unknown math intrinsic or arity" )
for _ , argument in ipairs ( node . args ) do
holds ( argument . type == "f64" , "invalid math argument" )
scalarWalk ( argument , values , scope )
end
elseif op == "helper_call" then
local found = scope . helpers [ node . helper ]
holds ( found ~= nil , "invalid helper call" )

local helper = found
local resultTypes = node . resultTypes or { }
holds (
# node . args == # helper . params
and # resultTypes == # helper . resultTypes
and node . type == ( # helper . resultTypes == 1 and helper . resultTypes [ 1 ] or "multi" ) ,
"invalid helper call"
)
for position , resultType in ipairs ( resultTypes ) do
holds ( resultType == helper . resultTypes [ position ] , "invalid helper call result" )
end
for position , argument in ipairs ( node . args ) do
holds ( argument . type == helper . params [ position ] . type , "invalid helper argument" )
scalarWalk ( argument , values , scope )
end
elseif op == "reducer_init" then
local reducer = node
holds (
reducers . input ( reducer . type , reducer . order , reducer . operation ) == reducer . initial . type ,
"invalid reducer construction"
)
scalarWalk ( reducer . initial , values , scope )
elseif op == "reducer_add" then
local reducer = node
local element = reducers . input ( reducer . reducer . type , reducer . order , reducer . operation )
holds (
reducer . reducer . op == "local"
and reducer . value . type == element
and ( reducer . operation == "dot" ) == ( reducer . right ~= nil )
and ( reducer . right == nil or ( reducer . right ) . type == element ) ,
"invalid reducer contribution"
)
local named = reducer . reducer
holds ( values [ named . name ] == reducer . reducer . type , "reducer contribution does not match its scoped binding" )
scalarWalk ( reducer . reducer , values , scope )
scalarWalk ( reducer . value , values , scope )
if reducer . right ~= nil then
scalarWalk ( reducer . right , values , scope )
end
elseif op == "reducer_value" then
local reducer = node
local element = reducers . input ( reducer . reducer . type , reducer . order , reducer . operation )
holds (
reducer . reducer . op == "local"
and element ~= nil
and reducer . type == reducers . result ( reducer . operation , element ) ,
"invalid reducer finalization"
)
local named = reducer . reducer
holds ( values [ named . name ] == reducer . reducer . type , "reducer finalization does not match its scoped binding" )
holds (
scope . region == nil or ( scope . region ) . reducers [ named . name ] == nil ,
"reducer finalized inside the region accumulating it"
)
scalarWalk ( reducer . reducer , values , scope )
elseif verify . BINARY_OPCODES [ tostring ( op ) ] == true then
binary ( node , values , scope )
else
refuse ( "unknown expression opcode " .. tostring ( op ) )
end
end







local function inherit ( values ) 
local copied = { }
for name , entry in pairs ( values ) do
copied [ name ] = entry
end

return copied
end


local function assignment (
entry ,
values ,
scope ,
stored
) 
local target = entry . target
if target . kind == "local" then
holds ( values [ tostring ( target . name ) ] == target . type , "invalid local assignment target" )
elseif target . kind == "field" then
local layout = scope . layouts [ tostring ( target . layout ) ]
local object = target . object
holds (
object ~= nil
and ( object ) . mutable == true
and layout ~= nil
and ( layout ) . fieldTypes ~= nil
and ( ( layout ) . fieldTypes or { } ) [ tostring ( target . field ) ] == target . type
and (
( layout ) . fieldSourceTypes or { }
) [ tostring ( target . field ) ] == storageSource ( tostring ( target . type ) , target . sourceType ) ,
"invalid field assignment target"
)
scalarWalk ( object , values , scope )
else
refuse ( "invalid scalar assignment target" )
end
holds ( entry . value . type == target . type , "assignment type mismatch" )
scalarWalk ( entry . value , values , scope )
end




local function provesCursorBound (
condition ,
cursor ,
spanName ,
room ,
values ,
scope
) 
if condition . op == "and" then
local binary = condition
return provesCursorBound ( binary . left , cursor , spanName , room , values , scope )
or provesCursorBound ( binary . right , cursor , spanName , room , values , scope )
end


local sumCursor , sumSpan , sumRoom = sumBound ( condition , values , scope )
if sumCursor ~= nil then
return sumCursor == cursor
and sumSpan == spanName
and simdbounds . elementRoom ( room )
and simdbounds . elements ( sumRoom ) >= simdbounds . elements ( room )
end
if condition . op == "le" then
local boundCursor , boundSpans , speciesType = laneBound ( condition , values , scope )
if boundCursor ~= cursor or speciesType ~= room then
return false
end
for _ , boundSpan in ipairs ( boundSpans ) do
if boundSpan == spanName then
return true
end
end

return false
elseif room ~= scalarIR . ONE_ELEMENT then
return false
elseif condition . op == "lt" then
local comparison = condition
local right = comparison . right
return ( comparison . left . op == "local" or comparison . left . op == "uniform" )
and ( comparison . left ) . name == cursor
and (
right . op == "span_count" and ( right ) . span == spanName
or right . op == "local"
and (
values [ "length of " .. ( right ) . name ] == spanName
or values [ "scratch length " .. ( right ) . name ] == spanName
)
)
else
return false
end
end













local function proveCursorBounds (
condition ,
declared ,
values ,
scope ,
carried ,
why
) 
local cursorBounds = { }
for name , spans in pairs ( scope . cursorBounds ) do
cursorBounds [ name ] = spans
end
for _ , entry in ipairs ( carried or { } ) do
cursorBounds [ entry . name ] = nil
end
for name , spans in pairs ( declared or { } ) do
for spanName , room in pairs ( spans ) do
local root = scope . spans [ spanName ]
holds (
values [ name ] == "u32"
and (
root ~= nil
and (
( root ) . region ~= nil
or ( root ) . type == "lua_string"
or ( root ) . type == "lua_bytes"
)
or values [ spanName ] == "lua_scratch_u32"
)
and provesCursorBound ( condition , name , spanName , room , values , scope ) ,
why .. " for " .. name .. " against " .. spanName
)
withBound ( cursorBounds , name , spanName , room )
end
end

return cursorBounds
end


local function invalidateCursors ( scope , nested ) 
local invalidated = { }
for name in pairs ( scope . cursorBounds ) do
if nested . cursorBounds [ name ] == nil then
invalidated [ # invalidated + 1 ] = name
end
end
for _ , name in ipairs ( invalidated ) do
scope . cursorBounds [ name ] = nil
end
end











local VECTOR_CONTRIBUTIONS

= {
sum = true ,
product = true ,
dot = true ,
[ "and" ] = true ,
[ "or" ] = true ,
xor = true ,
min = true ,
max = true ,
argmin = true ,
argmax = true ,
any = true ,
all = true ,
count = true ,
}








local function contributions ( statements , region ) 
local counts = { }

local function merge ( into , from , largest ) 
for name , count in pairs ( from ) do
local current = into [ name ] or 0
into [ name ] = largest and math . max ( current , count ) or current + count
end
end

for _ , statement in ipairs ( statements ) do
if statement . op == "simd_reducer_add" then
local named = ( statement ) . reducer
holds ( region [ named . name ] == true , "a SIMD region contribution names a reducer outside it" )
counts [ named . name ] = ( counts [ named . name ] or 0 ) + 1
elseif statement . op == "if" then
local arms = { }
for _ , clause in ipairs ( ( statement ) . clauses ) do
merge ( arms , contributions ( clause . body , region ) , true )
end
merge ( arms , contributions ( ( statement ) . elseBody or { } , region ) , true )
merge ( counts , arms , false )
elseif statement . op == "block" then
merge ( counts , contributions ( ( statement ) . body , region ) , false )
elseif statement . op == "while" or statement . op == "repeat" or statement . op == "fornum" then
contributions ( ( statement ) . body , region )
end
end
for _ , count in pairs ( counts ) do
holds ( count <= 1 , "a reducer contributed twice in one region iteration" )
end

return counts
end

local function block (
statements ,
inherited ,
scope ,
stored ,
sameScope
) 
local values = sameScope == true and inherited or inherit ( inherited )
for _ , statement in ipairs ( statements ) do
effects . statement ( tostring ( statement . op ) )
if statement . op == "let" then
holds ( values [ statement . name ] == nil and statement . type == statement . value . type , "invalid local declaration" )
scalarWalk ( statement . value , values , scope )
values [ statement . name ] = statement . type
declareLocal ( values , statement . name , statement . assigned )
if statement . value . op == "lua_string_length" then
values [
"length of " .. statement . name
] = ( ( statement . value ) . bytes ) . name
else
values [ "length of " .. statement . name ] = nil
end
local scratchLength = scratchLengthSource ( statement . value , values )
if scratchLength ~= nil then
values [ "scratch length " .. statement . name ] = scratchLength
else
values [ "scratch length " .. statement . name ] = nil
end








if statement . type == "lua_scratch_u32" then
local allocated = statement . value
if allocated . fixed ~= nil then
values [ "fixed width " .. statement . name ] = tostring ( allocated . fixed )
end
elseif statement . type == "lua_scratch_u8" then
local allocatedBytes = statement . value
if allocatedBytes . fixed ~= nil then
values [ "fixed width " .. statement . name ] = tostring ( allocatedBytes . fixed )
end
end
elseif statement . op == "multi_let" then
scalarWalk ( statement . call , values , scope )

local resultTypes = statement . call . resultTypes or { }
holds (
statement . call . type == "multi" and # statement . bindings > 0 and # statement . bindings <= # resultTypes ,
"invalid multiple-result declaration"
)
for position , bound in ipairs ( statement . bindings ) do
holds (
values [ bound . name ] == nil and bound . type == resultTypes [ position ] ,
"invalid multiple-result binding"
)
values [ bound . name ] = bound . type
declareLocal ( values , bound . name , bound . assigned )
end
elseif statement . op == "store" then
local param = scope . spans [ statement . span ]
local bounded = statement . cursor ~= nil
and statement . index == ""
and values [ statement . cursor ] == "u32"
and simdbounds . boundedThrough (
scope . cursorBounds ,
statement . cursor ,
param ~= nil and param . soa ~= nil and param . soa . view or statement . span ,
scope . countBounds ,
cursorElements ( statement . cursorOffset ) ,
scope . countRooms
)
and statement . cursorUniqueName ~= nil
or statement . cursor == nil
and statement . index == scope . index
and values [ "assigned " .. statement . index ] == nil
and (
scope . mapIndex == true and ( scope . indexSpans ) [ statement . span ] == true
or statement . span == scope . boundSpan
or ( ( scope . countBounds or { } ) [ tostring ( scope . boundSpan ) ] or { } ) [ statement . span ] == true
or scalarIR . sameSoaView ( param , scope . spans [ tostring ( scope . boundSpan ) ] )
)
holds ( scope . writes [ statement . span ] == true and bounded , "invalid store root" )
scalarWalk ( statement . value , values , scope )
holds ( statement . value . type == ( scope . spans [ statement . span ] ) . type , "store type mismatch" )
stored [ statement . span ] = true
elseif statement . op == "shared_store" then
local write = statement
local shared = scope . shared or { }
holds (
scope . workgroup == true
and scope . inPhase == true
and shared [ write . shared ] == write . value . type
and write . index . op == "local_index"
and write . index . type == "u32" ,
"invalid structurally disjoint workgroup scratch write"
)
scalarWalk ( write . index , values , scope )
scalarWalk ( write . value , values , scope )
elseif statement . op == "phase" then
holds ( scope . workgroup == true and scope . inPhase ~= true , "nested workgroup phase" )
local phase = statement
local written = { }
local crossRead = { }
local inspectExpression
inspectExpression = function ( value ) 
if value . op == "shared_load" then
local load = value
if load . index . op ~= "local_index" then
crossRead [ load . shared ] = true
end
end
visit . expressionChildren ( value , function ( child ) 
inspectExpression ( child )
return child
end )
end
local inspectBlock
inspectBlock = function ( body ) 
for _ , nested in ipairs ( body ) do
if nested . op == "shared_store" then
written [ ( nested ) . shared ] = true
end
if ( nested ) . conditionBody ~= nil then
inspectBlock ( ( nested ) . conditionBody )
end
visit . statementExpressions ( nested , function ( value ) 
inspectExpression ( value )
return value
end )
if nested . op == "if" then
for _ , clause in ipairs ( ( nested ) . clauses ) do
inspectBlock ( clause . body )
end
inspectBlock ( ( nested ) . elseBody or { } )
elseif nested . op == "while"
or nested . op == "repeat"
or nested . op == "fornum"
or nested . op == "block"
then
inspectBlock ( ( nested ) . body )
end
end
end
inspectBlock ( phase . body )

local function fixedTreeShared ( ) 
if # phase . body ~= 1 or phase . body [ 1 ] . op ~= "if" then
return nil
end
local branch = phase . body [ 1 ]
if # branch . clauses ~= 1 or branch . elseBody ~= nil or # branch . clauses [ 1 ] . body ~= 1 then
return nil
end
local condition = branch . clauses [ 1 ] . condition
local write = branch . clauses [ 1 ] . body [ 1 ]
if condition . op ~= "lt" or write . op ~= "shared_store" then
return nil
end
local compared = condition
local storedValue = write
if compared . left . op ~= "local_index"
or compared . right . op ~= "constant_i32"
or storedValue . index . op ~= "local_index"
or storedValue . value . op ~= "f32_add"
then
return nil
end
local stride = ( compared . right ) . value
local sum = storedValue . value
if sum . left . op ~= "shared_load" or sum . right . op ~= "shared_load" then
return nil
end
local left = sum . left
local right = sum . right
if left . shared ~= storedValue . shared
or right . shared ~= storedValue . shared
or left . index . op ~= "local_index"
or right . index . op ~= "u32_add"
then
return nil
end
local added = right . index
if added . left . op ~= "local_index"
or added . right . op ~= "constant_i32"
or ( added . right ) . value ~= stride
then
return nil
end

return storedValue . shared
end

local collective = fixedTreeShared ( )
for name in pairs ( written ) do
holds (
crossRead [ name ] ~= true or collective == name ,
"ordinary workgroup phase has a cross-lane scratch race"
)
end
block ( phase . body , values , derive ( scope , { cursorBounds = { } , workgroup = true , inPhase = true } ) , stored )
elseif statement . op == "lua_set_index" or statement . op == "lua_set_key" then
local write = statement
holds ( scope . entryMode == "lua-builder" , "Lua write outside a builder" )
holds ( write . table . type == "lua_table" , "Lua write target is not a fresh table handle" )
scalarWalk ( write . table , values , scope )
scalarWalk ( write . key , values , scope )
scalarWalk ( write . value , values , scope )
holds ( verify . NUMERIC [ write . key . type ] == true or write . key . type == "lua_string" , "unsupported Lua table key" )
holds (
verify . NUMERIC [ write . value . type ] == true
or write . value . type == "bool"
or write . value . type == "lua_table"
or write . value . type == "lua_string"
or write . value . type == "lua_nil" ,
"unsupported Lua table value"
)
elseif statement . op == "lua_string_buffer_append" then
local appended = statement
holds ( scope . entryMode == "lua-builder" , "string buffer append outside a builder" )
holds (
appended . buffer . type == "lua_string_buffer" and appended . buffer . op == "local" ,
"string append has no local buffer"
)
holds ( appended . value . type == "lua_string" , "string buffer appended a non-string" )
scalarWalk ( appended . buffer , values , scope )
scalarWalk ( appended . value , values , scope )
elseif statement . op == "simd_store" then
local store = statement
local vectorFamily , element , shape = genericSimdType ( store . args [ 3 ] . type )
local interleaved = simdbounds . interleaved ( store . intrinsic )
holds (
store . type == "lua_effect"
and (
interleaved and # store . args == 2 + simdbounds . ways ( store . intrinsic )
or not interleaved and ( # store . args == 3 or # store . args == 4 )
) ,
"invalid generic SIMD store"
)
holds (
store . intrinsic == "store"
or store . intrinsic == "scatter"
or store . intrinsic == "scatterUnchecked"
or interleaved ,
"invalid SIMD store addressing"
)
if interleaved then

for position = 4 , # store . args do
holds ( store . args [ position ] . type == store . args [ 3 ] . type , "generic SIMD store operands do not match" )
end
end
if store . intrinsic == "scatter" then
holds ( simdindices . unique ( store . args [ 2 ] ) , "SIMD scatter lost its index uniqueness proof" )
end
holds (
vectorFamily == "vector"
and store . args [ 1 ] . type == "simd_species_" .. tostring ( element ) .. "_" .. tostring ( shape )
and (
( store . intrinsic == "scatter" or store . intrinsic == "scatterUnchecked" )
and simdindices . matches ( store . args [ 2 ] . type , store . args [ 1 ] . type )
or ( store . intrinsic == "store" or interleaved ) and store . args [ 2 ] . type == "f64"
)
and (
interleaved
or store . args [ 4 ] == nil
or store . args [ 4 ] . type == "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape )
) ,
"generic SIMD store operands do not match"
)
local span = store . span ~= nil and scope . spans [ store . span ] or nil
holds (
span ~= nil
and ( span ) . kind == "write_span"
and genericSimdSpanElement ( span ) == element ,
"invalid generic SIMD store root"
)
if store . cursor ~= nil then
holds (
( store . intrinsic == "store" and store . args [ 4 ] == nil or interleaved )
and vectorCursor ( store , values , scope ) ,
"unbounded SIMD cursor store"
)
end
for _ , argument in ipairs ( store . args ) do
scalarWalk ( argument , values , scope )
end
elseif statement . op == "simd_field_store" then
local store = statement
holds ( store . type == "lua_effect" and store . args [ 3 ] ~= nil , "invalid generic SIMD field store" )
genericFieldAccess ( store , store . args [ 3 ] . type , 1 , "write_span" , values , scope )
elseif statement . op == "simd_reducer_add" then
local contribution = statement
holds ( contribution . reducer . op == "local" , "invalid SIMD reducer contribution" )
local named = contribution . reducer
local region = scope . region
local accumulated = region ~= nil and ( region ) . reducers [ named . name ] or nil
holds ( accumulated ~= nil , "a SIMD reducer contribution outside a region accumulating its reducer" )
local entry = accumulated
holds (
values [ named . name ] == contribution . reducer . type
and entry . order == contribution . order
and entry . operation == contribution . operation
and entry . element == contribution . element ,
"SIMD reducer contribution does not match its region's reducer"
)
local family , element , shape = genericSimdType ( entry . vectorType )
holds (
family == ( entry . element == "bool" and "mask" or "vector" )
and contribution . value . type == entry . vectorType
and contribution . mask . type == "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape )
and ( contribution . operation == "dot" ) == ( contribution . right ~= nil )
and ( contribution . right == nil or ( contribution . right ) . type == entry . vectorType ) ,
"SIMD reducer contribution operands do not match"
)
scalarWalk ( contribution . reducer , values , scope )
scalarWalk ( contribution . value , values , scope )
scalarWalk ( contribution . mask , values , scope )
if contribution . right ~= nil then
scalarWalk ( contribution . right , values , scope )
end
elseif statement . op == "reducer_region" then
local region = statement
holds ( scope . region == nil , "a SIMD region inside another" )
local accumulated = { }
for _ , entry in ipairs ( region . reducers ) do
local reducerType = values [ entry . name ]
holds (
reducerType ~= nil and accumulated [ entry . name ] == nil ,
"a SIMD region names a reducer twice or not in scope"
)
local _ , _ , parsedElement = reducers . parse ( reducerType )
local input = reducers . input ( reducerType , entry . order , entry . operation )
holds (
input ~= nil and parsedElement == entry . element ,
"a SIMD region's reducer does not match its binding"
)
local family , element = genericSimdType ( entry . vectorType )


holds (
( input == "bool" and family == "mask" or family == "vector" and genericSimdScalar ( element ) == input )
and VECTOR_CONTRIBUTIONS [ entry . operation ] == true ,
"a SIMD region's reducer takes no vector contribution"
)
accumulated [ entry . name ] = entry
end
block ( region . body , values , derive ( scope , { region = _G.setmetatable({ reducers =  accumulated }, verify.Region) } ) , stored )
local named = { }
for name in pairs ( accumulated ) do
named [ name ] = true
end
contributions ( region . body , named )
elseif statement . op == "lua_scratch_u32_set" then
local write = statement
holds ( scope . entryMode == "lua-builder" and write . type == "lua_effect" , "scratch write outside a builder" )
holds (
fixedWidthAgrees ( write . fixedBound , values , ( write . scratch ) . name ) ,
"scratch write bound is not the width of the buffer it writes"
)
holds (
write . scratch . type == "lua_scratch_u32" and write . scratch . op == "local" ,
"scratch write has no local buffer"
)
holds ( write . index . type == "u32" and write . value . type == "u32" , "invalid scratch write" )
scalarWalk ( write . scratch , values , scope )
scalarWalk ( write . index , values , scope )
scalarWalk ( write . value , values , scope )
elseif statement . op == "lua_scratch_u8_set"
or statement . op == "lua_scratch_u8_set4"
or statement . op == "lua_scratch_u8_reset"
then
local write = statement
holds (
scope . entryMode == "lua-builder" and write . type == "lua_effect" ,
"byte scratch write outside a builder"
)
holds (
write . scratch . type == "lua_scratch_u8" and write . scratch . op == "local" ,
"byte scratch write has no local buffer"
)
scalarWalk ( write . scratch , values , scope )
holds (
statement . op ~= "lua_scratch_u8_reset"
or values [ "fixed width " .. tostring ( ( write . scratch ) . name ) ] == nil ,
"a fixed byte scratch cannot be reset"
)
if statement . op == "lua_scratch_u8_set" or statement . op == "lua_scratch_u8_set4" then
holds (
write . index ~= nil
and ( write . index ) . type == "u32"
and write . value ~= nil
and ( write . value ) . type == "u32" ,
"invalid byte scratch write"
)
holds (
fixedWidthAgrees ( write . fixedBound , values , ( write . scratch ) . name ) ,
"byte scratch write bound is not the width of the buffer it writes"
)
scalarWalk ( write . index , values , scope )
scalarWalk ( write . value , values , scope )
else
holds ( write . index == nil and write . value == nil , "byte scratch reset carried operands" )
end
elseif tostring ( statement . op ) : match ( "^lua_builder_" ) ~= nil then
local event = statement
holds (
scope . entryMode == "lua-builder" and event . type == "lua_effect" ,
"value stream event outside a builder"
)
holds (
event . builder . type == "lua_builder" and event . builder . op == "local" ,
"value stream event has no local builder"
)
scalarWalk ( event . builder , values , scope )
holds (
( event . mode == "eager" or event . mode == "pull" or event . mode == "serde" )
and scope . builderMode == event . mode ,
"unknown or inconsistent value stream event mode"
)
if event . op == "lua_builder_open_array" or event . op == "lua_builder_open_object" then
holds (
event . capacity ~= nil and ( event . capacity ) . type == "u32" ,
"invalid value stream capacity"
)
scalarWalk ( event . capacity , values , scope )
elseif event . op == "lua_builder_key" or event . op == "lua_builder_string" then
holds (
event . sourceBytes ~= nil
and (
( event . sourceBytes ) . type == "lua_string"
or ( event . sourceBytes ) . type == "lua_bytes"
)
and event . start ~= nil
and ( event . start ) . type == "u32"
and event . length ~= nil
and ( event . length ) . type == "u32"
and event . escaped ~= nil
and ( event . escaped ) . type == "bool" ,
"invalid value stream string event"
)
for _ , value in ipairs ( { event . sourceBytes , event . start , event . length , event . escaped } ) do
scalarWalk ( value , values , scope )
end
elseif event . op == "lua_builder_number_slice" or event . op == "lua_builder_integer_slice" then
holds (
event . sourceBytes ~= nil
and (
( event . sourceBytes ) . type == "lua_string"
or ( event . sourceBytes ) . type == "lua_bytes"
)
and event . start ~= nil
and ( event . start ) . type == "u32"
and event . length ~= nil
and ( event . length ) . type == "u32" ,
"invalid value stream number slice"
)
for _ , value in ipairs ( { event . sourceBytes , event . start , event . length } ) do
scalarWalk ( value , values , scope )
end
elseif event . op == "lua_builder_key_scratch" or event . op == "lua_builder_string_scratch" then
holds (
event . scratch ~= nil
and ( event . scratch ) . type == "lua_scratch_u8"
and event . start ~= nil
and ( event . start ) . type == "u32"
and event . length ~= nil
and ( event . length ) . type == "u32" ,
"invalid value stream scratch string event"
)
scalarWalk ( event . scratch , values , scope )
scalarWalk ( event . start , values , scope )
scalarWalk ( event . length , values , scope )
elseif event . op == "lua_builder_key_escapes" or event . op == "lua_builder_string_escapes" then
holds (
event . sourceBytes ~= nil
and (
( event . sourceBytes ) . type == "lua_string"
or ( event . sourceBytes ) . type == "lua_bytes"
)
and event . start ~= nil
and ( event . start ) . type == "u32"
and event . length ~= nil
and ( event . length ) . type == "u32"
and event . escapeScratch ~= nil
and ( event . escapeScratch ) . type == "lua_scratch_u32"
and event . escapeIndex ~= nil
and ( event . escapeIndex ) . type == "u32"
and event . escapeCount ~= nil
and ( event . escapeCount ) . type == "u32" ,
"invalid value stream indexed escape event"
)
for _ , value in ipairs ( {
event . sourceBytes ,
event . start ,
event . length ,
event . escapeScratch ,
event . escapeIndex ,
event . escapeCount ,
} ) do
scalarWalk ( value , values , scope )
end
elseif event . op == "lua_builder_number" then
holds ( event . value ~= nil and ( event . value ) . type == "f64" , "invalid streamed number" )
scalarWalk ( event . value , values , scope )
elseif event . op == "lua_builder_integer64" then
holds (
event . value ~= nil
and ( event . value ) . type == "u64"
and event . negative ~= nil
and ( event . negative ) . type == "bool" ,
"invalid streamed uint64 integer"
)
scalarWalk ( event . value , values , scope )
scalarWalk ( event . negative , values , scope )
elseif event . op == "lua_builder_decimal64" then
holds (
event . sourceBytes ~= nil
and (
( event . sourceBytes ) . type == "lua_string"
or ( event . sourceBytes ) . type == "lua_bytes"
)
and event . start ~= nil
and ( event . start ) . type == "u32"
and event . length ~= nil
and ( event . length ) . type == "u32"
and event . value ~= nil
and ( event . value ) . type == "u64"
and event . exponent ~= nil
and ( event . exponent ) . type == "i32"
and event . negative ~= nil
and ( event . negative ) . type == "bool"
and event . exact ~= nil
and ( event . exact ) . type == "bool" ,
"invalid streamed decimal64"
)
for _ , value in ipairs ( {
event . sourceBytes ,
event . start ,
event . length ,
event . value ,
event . exponent ,
event . negative ,
event . exact ,
} ) do
scalarWalk ( value , values , scope )
end
elseif event . op == "lua_builder_boolean" then
holds ( event . value ~= nil and ( event . value ) . type == "bool" , "invalid streamed boolean" )
scalarWalk ( event . value , values , scope )
else
holds ( event . op == "lua_builder_null" or event . op == "lua_builder_close" , "unknown value stream event" )
end
elseif statement . op == "assign" then
for _ , entry in ipairs ( statement . values ) do
assignment ( entry , values , scope , stored )
end
for _ , entry in ipairs ( statement . values ) do
local target = entry . target
if target . kind == "local" and target . name ~= nil then
assignedLocal ( values , target . name )
scope . cursorBounds [ target . name ] = nil
values [ "length of " .. ( target . name ) ] = nil
local scratchLength = scratchLengthSource ( entry . value , values )
if scratchLength ~= nil then
values [ "scratch length " .. ( target . name ) ] = scratchLength
else
values [ "scratch length " .. ( target . name ) ] = nil
end
end
end
elseif statement . op == "reducer_add" then
scalarWalk ( statement , values , scope )
elseif statement . op == "if" then
local invalidated = { }
for _ , clause in ipairs ( statement . clauses ) do
holds ( clause . condition . type == "bool" , "non-boolean branch" )
scalarWalk ( clause . condition , values , scope )
local nestedScope = derive ( scope , {
cursorBounds = proveCursorBounds (
clause . condition ,
clause . cursorBounds ,
values ,
scope ,
nil ,
"invalid cursor bounds proof"
) ,
localReadLimit = ( function ( ) 
local condition = clause . condition
if condition . op == "lt" then
local comparison = condition
if comparison . left . op == "local_index" and comparison . right . op == "constant_i32" then
return tonumber ( ( comparison . right ) . value )
end
end

return scope . localReadLimit
end ) ( ) ,
localReadMinimum = ( function ( ) 
local condition = clause . condition
if condition . op == "ge" then
local comparison = condition
if comparison . left . op == "local_index" and comparison . right . op == "constant_i32" then
return tonumber ( ( comparison . right ) . value )
end
end

return scope . localReadMinimum
end ) ( ) ,
} )
block ( clause . body , values , nestedScope , stored )
for name in pairs ( scope . cursorBounds ) do
if nestedScope . cursorBounds [ name ] == nil then
invalidated [ name ] = true
end
end
end
if statement . elseBody ~= nil then
block ( statement . elseBody or { } , values , scope , stored )
end
for name in pairs ( invalidated ) do
scope . cursorBounds [ name ] = nil
end
elseif statement . op == "fornum" then
for _ , bound in ipairs ( { statement . from , statement . to } ) do
holds ( bound . type == "i32" or bound . type == "u32" or bound . type == "f64" , "non-numeric for bound" )
scalarWalk ( bound , values , scope )
end
holds ( statement . binding . type == "i32" or statement . binding . type == "f64" , "for induction variable type" )

local inner = inherit ( values )
enterLoop ( statement . carried , inner )
inner [ statement . binding . name ] = statement . binding . type
declareLocal ( inner , statement . binding . name , statement . binding . assigned )


local nestedScope = derive ( scope , {
index = statement . binding . name ,
boundSpan = statement . boundSpan ,
mapIndex = false ,
cursorBounds = proveCursorBounds (
statement . from ,
nil ,
values ,
scope ,
statement . carried ,
"invalid loop cursor bounds proof"
) ,
} )
nestedScope . indexSpans = nil
if statement . boundSpan ~= nil then
holds (
statement . from . op == "constant_i32"
and ( tonumber ( ( statement . from ) . value ) or 0 ) >= 1
and statement . to . op == "span_count"
and ( statement . to ) . span == statement . boundSpan ,
"invalid counted span loop proof"
)
end
block ( statement . body , inner , nestedScope , stored )
leaveLoop ( )
invalidateCursors ( scope , nestedScope )
elseif statement . op == "while" then
local values = inherit ( values )
enterLoop ( statement . carried , values )
if statement . conditionBody ~= nil then
block ( statement . conditionBody , values , scope , stored , true )
end
holds ( statement . condition . type == "bool" , "non-boolean loop condition" )
scalarWalk ( statement . condition , values , scope )
local nestedScope = derive ( scope , {
cursorBounds = proveCursorBounds (
statement . condition ,
statement . cursorBounds ,
values ,
scope ,
statement . carried ,
"invalid loop cursor bounds proof"
) ,
} )
block ( statement . body , values , nestedScope , stored )
leaveLoop ( )
invalidateCursors ( scope , nestedScope )
elseif statement . op == "repeat" then
local inner = inherit ( values )
local nestedScope = derive ( scope , { cursorBounds = inheritBounds ( scope . cursorBounds ) } )
enterLoop ( statement . carried , inner )
block ( statement . body , inner , nestedScope , stored , true )
if statement . conditionBody ~= nil then
block ( statement . conditionBody , inner , nestedScope , stored , true )
end
holds ( statement . condition . type == "bool" , "non-boolean repeat condition" )
scalarWalk ( statement . condition , inner , nestedScope )
leaveLoop ( )
invalidateCursors ( scope , nestedScope )
elseif statement . op == "block" then
block ( statement . body , values , scope , stored )
elseif statement . op == "return" then
holds ( # statement . values == # scope . resultTypes , "invalid AOT return count" )
for position , value in ipairs ( statement . values ) do
holds ( value . type == scope . resultTypes [ position ] , "invalid AOT return type" )
scalarWalk ( value , values , scope )
end
else
holds ( statement . op == "break" or statement . op == "continue" , "unknown statement opcode" )
end
end
end






local function layoutsByName ( program ) 
local layouts = { }
for _ , layout in ipairs ( program . layouts or { } ) do
holds ( layouts [ layout . name ] == nil and layout . uniqueName ~= nil and # layout . fields > 0 , "invalid native layout" )

local fields = { }
local sources = { }
for _ , field in ipairs ( layout . fields ) do


local valueField = layout . nativeOnly == true
and ( scalarIR . nativeOnlyType ( field . type ) or verify . NUMERIC [ field . type ] == true or field . type == "bool" )
local vectorField = layout . nativeOnly ~= true and storedVector ( tostring ( field . type ) )
holds (
fields [ field . name ] == nil and ( valueField or vectorField or validStorage ( field . type , field . sourceType ) ) ,
"invalid native layout field"
)
fields [ field . name ] = field . type
sources [ field . name ] = ( valueField or vectorField ) and tostring ( field . sourceType or field . type )
or storageSource ( field . type , field . sourceType )
end
layout . fieldTypes = fields
layout . fieldSourceTypes = sources
layouts [ layout . name ] = layout
end

return layouts
end





local function signature (
program ,
layouts
) 
local byName = { }
local byRegion = { }
local writes = { }
local primary = nil
local views = { }
local previousView = nil
for _ , param in ipairs ( program . params ) do
holds ( byName [ param . name ] == nil , "duplicate IR parameter" )
holds (
param . kind == "write_span"
or param . kind == "read_span"
or param . kind == "uniform"
or param . kind == "scalar" ,
"unknown IR parameter kind"
)
if param . kind == "uniform" then
holds (
(
verify . NUMERIC [ param . type ] == true
or param . type == "bool"
or scalarIR . nativeOnlyType ( param . type ) and program . nativeOnly == true
)
and param . region == nil ,
"invalid IR uniform"
)
elseif param . kind == "scalar" then
holds (
program . entryMode == "lua-builder"
and ( param . type == "lua_string" or param . type == "lua_bytes" or param . type == "lua_value" )
and param . region == nil ,
"invalid Lua builder scalar"
)
else
local structName = param . type : match ( "^struct:(.+)$" )
local element = structName == nil and validStorage ( param . type , param . sourceType )
or structName ~= nil and param . sourceType == nil and layouts [ tostring ( structName ) ] ~= nil
holds ( element and param . region ~= nil and byRegion [ tostring ( param . region ) ] == nil , "invalid IR span" )
holds ( param . access == ( param . kind == "write_span" and "readwrite" or "read" ) , "invalid IR region access" )
byRegion [ tostring ( param . region ) ] = param
if param . kind == "write_span" then
writes [ param . name ] = true
primary = primary or param
end
end
byName [ param . name ] = param
if param . soa ~= nil then
local column = param . soa
local layout = layouts [ column . layout ]
holds ( program . executionTarget == "cpu" and program . entryMode == "kernel" , "invalid SoA execution target" )
holds ( param . spanModule == "nupp.mem.soa" and param . region ~= nil and layout ~= nil , "invalid SoA column" )
holds ( column . ordinal >= 1 and column . ordinal % 1 == 0 , "invalid SoA column ordinal" )
local field = ( layout ) . fields [ column . ordinal ]
holds (
field ~= nil
and field . name == column . field
and field . type == param . type
and field . sourceType == param . sourceType ,
"invalid SoA field identity"
)
holds ( param . ownership == ( param . kind == "write_span" and "exclusive" or "shared" ) , "invalid SoA ownership" )
local prior = views [ column . view ]
if prior == nil then
holds (
column . ordinal == 1 and param . name == column . view and # column . sourceType > 0 ,
"invalid SoA source parameter"
)
prior = { }
views [ column . view ] = prior
else
local first = prior [ 1 ]
holds (
previousView == column . view
and column . ordinal == # prior + 1
and column . layout == ( first . soa ) . layout
and column . sourceType == ( first . soa ) . sourceType
and param . kind == first . kind
and param . ownership == first . ownership ,
"inconsistent SoA column mapping"
)
end
prior [ # prior + 1 ] = param
previousView = column . view
else
holds ( param . spanModule ~= "nupp.mem.soa" , "SoA span lacks its source mapping" )
previousView = nil
end
end
for _ , columns in pairs ( views ) do
local layout = layouts [ ( columns [ 1 ] . soa ) . layout ]
holds ( # columns == # layout . fields , "incomplete SoA column mapping" )
end
if program . loop ~= nil then
holds (
primary ~= nil and ( program . loop ) . count == ( primary ) . name ,
"loop is not bounded by its primary output"
)
end

return byName , byRegion , writes , primary
end






local function regions ( program , byRegion ) 
local declared = { }
for _ , region in ipairs ( program . regions ) do
local param = byRegion [ region . id ]
holds ( param ~= nil and declared [ region . id ] == nil , "invalid or duplicate region declaration" )

local span = param
holds ( region . param == span . name and region . access == span . access , "region declaration mismatch" )
holds ( region . proof == tostring ( span . ownership ) .. "_borrow" , "invalid region proof" )
declared [ region . id ] = true
end

local count = 0
for id in pairs ( byRegion ) do
holds ( declared [ id ] == true , "undeclared parameter region" )
count = count + 1
end

local seen = { }
for _ , fact in ipairs ( program . aliasFacts ) do
holds (
byRegion [ fact . left ] ~= nil and byRegion [ fact . right ] ~= nil and fact . left ~= fact . right ,
"alias fact references an invalid region"
)

local key = fact . left < fact . right and fact . left .. ":" .. fact . right or fact . right .. ":" .. fact . left
holds ( seen [ key ] == nil , "duplicate alias fact" )

local hasWrite = ( byRegion [ fact . left ] ) . kind == "write_span"
or ( byRegion [ fact . right ] ) . kind == "write_span"
local siblings = scalarIR . sameSoaView ( byRegion [ fact . left ] , byRegion [ fact . right ] )
holds ( fact . relation == ( ( hasWrite or siblings ) and "disjoint" or "may_alias" ) , "invalid alias relationship" )
holds (
fact . proof == ( siblings and "soa_columns" or hasWrite and "exclusive_borrow" or "shared_borrows" ) ,
"invalid alias proof"
)
seen [ key ] = true
end
holds ( # program . aliasFacts == count * ( count - 1 ) / 2 , "incomplete alias matrix" )
end



local function termUniverse ( params ) 
local terms = { relations . zero ( ) }
local spans = { }
for _ , param in ipairs ( params ) do
if param . region ~= nil then
terms [ # terms + 1 ] = relations . count ( param . name )
spans [ # spans + 1 ] = param . name
elseif param . kind == "uniform" then
terms [ # terms + 1 ] = relations . uniform ( param . name )
end
end

return terms , spans
end


local function namedTerm ( term , byName ) 
local isOrigin = term . kind == "zero"
local isCount = term . kind == "count"
local factor = term . factor
if factor ~= nil
and (
not isCount
or ( factor ) < 2
or ( factor ) > relations . MAX_OFFSET
or ( factor ) % 1 ~= 0
)
then
return false
end
if isOrigin then
return term . name == nil
end
local param = term . name ~= nil and byName [ term . name ] or nil
if param == nil then
return false
elseif isCount then
return ( param ) . region ~= nil
else
return ( param ) . kind == "uniform"
end
end









local function bounds (
program ,
byName ,
primary
) 
local pool = program . relations or { }
if program . loop == nil then
holds ( program . rangeGuard == nil and # program . guards == 0 , "a block kernel carried map-loop bounds" )
end

holds ( # pool <= relations . BUDGET , "more guard relations than the budget admits" )
for _ , relation in ipairs ( pool ) do
holds ( namedTerm ( relation . left , byName ) , "a guard relation names an undeclared term" )
holds ( namedTerm ( relation . right , byName ) , "a guard relation names an undeclared term" )
if program . executionTarget == "gpu" then
holds (
relation . left . kind == "count"
and relation . right . kind == "count"
and relation . left . factor == nil
and relation . right . factor == nil ,
"a GPU guard relation is not over span lengths"
)
end
holds (
relation . offset >= - relations . MAX_OFFSET and relation . offset <= relations . MAX_OFFSET ,
"a guard relation offsets further than the budget admits"
)
end
local terms , spans = termUniverse ( program . params )
local closure = relations . solve ( relations . withSoaCounts ( pool , program . params ) , spans , terms )
holds ( closure . contradiction == nil , "guard relations that cannot all hold" )




local countBounds = { }
for _ , param in ipairs ( program . params ) do
if param . kind == "uniform" and param . sourceType == "integer" then
local uniform = relations . uniform ( param . name )
if relations . proves ( closure , relations . zero ( ) , uniform , 0 ) ~= nil then
local proved = { }
for _ , spanName in ipairs ( spans ) do
if relations . proves ( closure , uniform , relations . count ( spanName ) , 0 ) ~= nil then
proved [ spanName ] = true
end
end
if next ( proved ) ~= nil then
countBounds [ param . name ] = proved
end
end
end
end

for _ , from in ipairs ( spans ) do
local proved = { }
for _ , to in ipairs ( spans ) do
if relations . proves ( closure , relations . count ( from ) , relations . count ( to ) , 0 ) ~= nil then
proved [ to ] = true
end
end
countBounds [ from ] = proved
end
local countRooms = relations . transfers ( closure , spans )

if program . loop == nil then
return countBounds , countRooms
end
local loop = program . loop
holds ( primary ~= nil , "a map loop has no primary output" )
local primary_ = primary

local count = relations . count ( primary_ . name )
local rangeGuard = program . rangeGuard
if rangeGuard ~= nil then
local guard = rangeGuard
holds (
loop . first == guard . first and loop . last == guard . last and guard . count == primary_ . name ,
"loop range proof mismatch"
)
holds (
byName [ guard . first ] ~= nil
and ( byName [ guard . first ] ) . sourceType == "integer"
and byName [ guard . last ] ~= nil
and ( byName [ guard . last ] ) . sourceType == "integer" ,
"range proof does not use integer uniforms"
)
local first , last = relations . uniform ( guard . first ) , relations . uniform ( guard . last )
holds ( relations . proves ( closure , relations . zero ( ) , first , -1 ) ~= nil , "unproved loop lower bound" )
holds ( relations . proves ( closure , last , count , 0 ) ~= nil , "unproved loop upper bound" )
holds ( relations . proves ( closure , first , last , 1 ) ~= nil , "unproved empty loop range" )
else
holds ( loop . first == 1 and loop . last == primary_ . name , "invalid full-span loop" )
end

local guarded = { }
for _ , guard in ipairs ( program . guards ) do
holds ( guard . op == "equal_count" and guard . left == primary_ . name , "invalid IR guard" )
holds ( byName [ guard . right ] ~= nil and ( byName [ guard . right ] ) . region ~= nil , "guarded non-span" )
holds ( guarded [ guard . right ] == nil , "duplicate IR guard" )
holds ( relations . equalCounts ( closure , guard . left , guard . right ) , "an IR guard the relations do not prove" )
guarded [ guard . right ] = true
end





return countBounds , countRooms
end


local function helperBodies ( program , scope ) 
for _ , helper in ipairs ( program . helpers or { } ) do


if helper . native == true then
holds ( # helper . values == 0 , "a native call carries a body" )
holds ( # helper . resultTypes == 1 , "a native call returns one value" )
end
local values = { }
for _ , param in ipairs ( helper . params ) do
holds ( values [ param . name ] == nil , "duplicate helper parameter" )
values [ param . name ] = param . type
end





for _ , constant in ipairs ( program . constants or { } ) do
holds ( values [ constant . uniqueName ] == nil , "an IR constant table shadows a helper parameter" )
values [ constant . uniqueName ] = "lua_string"
end
holds ( # helper . resultTypes > 0 , "helper result mismatch" )
holds ( helper . native == true or # helper . values == # helper . resultTypes , "helper result mismatch" )
for position , value in ipairs ( helper . values ) do
holds ( value . type == helper . resultTypes [ position ] , "helper result type mismatch" )
scalarWalk ( value , values , scope )
end
end
end


local function constructionExpression ( node ) 
if node . op == "lua_concat" then
local joined = node
local left = constructionExpression ( joined . left )
local right = constructionExpression ( joined . right )
return math . max ( left , 1 + right ) , false
elseif node . op == "lua_substring" or node . op == "lua_table_get_index" then
return 1 , false
elseif node . op ~= "lua_new_table" then
return 0 , false
end
local depth = 1
for _ , field in ipairs ( ( node ) . fields or { } ) do
for _ , value in ipairs ( { field . key , field . value } ) do
local nested = constructionExpression ( value )
depth = math . max ( depth , 1 + nested )
end
end

return depth , true
end







local function constructionStack ( statements , inLoop ) 
local roots , depth = 0 , 0
for _ , statement in ipairs ( statements ) do
if statement . op == "let" then
local nested , allocates = constructionExpression ( statement . value )
holds ( not ( inLoop and allocates ) , "fresh Lua table allocation inside a loop is not stack bounded" )
holds (
not ( inLoop and statement . type == "lua_builder" ) ,
"value stream creation inside a loop is not stack bounded"
)
holds (
not ( inLoop and statement . type == "lua_scratch_u32" ) ,
"scratch allocation inside a loop is not stack bounded"
)
holds (
not ( inLoop and statement . type == "lua_scratch_u8" ) ,
"byte scratch allocation inside a loop is not stack bounded"
)
holds (
not ( inLoop and statement . type == "lua_string_buffer" ) ,
"string accumulation inside a loop is not stack bounded"
)
depth = math . max ( depth , nested )
if statement . type == "lua_table"
or statement . type == "lua_string"
or statement . type == "lua_nil"
or statement . type == "lua_value"
or statement . type == "lua_scratch_u32"
or statement . type == "lua_scratch_u8"
then
roots = roots + 1
elseif statement . type == "lua_builder" then


roots = roots + 2
end
elseif statement . op == "lua_set_index" or statement . op == "lua_set_key" then
local write = statement
local keyDepth = constructionExpression ( write . key )
local valueDepth , allocates = constructionExpression ( write . value )
holds ( not ( inLoop and allocates ) , "fresh Lua table allocation inside a loop is not stack bounded" )
depth = math . max ( depth , keyDepth , valueDepth )
elseif statement . op == "if" then
for _ , clause in ipairs ( statement . clauses ) do
local nestedRoots , nestedDepth = constructionStack ( clause . body , inLoop )
roots = roots + nestedRoots
depth = math . max ( depth , nestedDepth )
end
local nestedRoots , nestedDepth = constructionStack ( statement . elseBody or { } , inLoop )
roots = roots + nestedRoots
depth = math . max ( depth , nestedDepth )
elseif statement . op == "fornum" or statement . op == "while" or statement . op == "repeat" then
local nestedRoots , nestedDepth = constructionStack ( statement . body , true )
local headerRoots , headerDepth = constructionStack ( ( statement ) . conditionBody or { } , true )
roots = roots + headerRoots
depth = math . max ( depth , headerDepth )
roots = roots + nestedRoots
depth = math . max ( depth , nestedDepth )
elseif statement . op == "block" then
local nestedRoots , nestedDepth = constructionStack ( statement . body , inLoop )
roots = roots + nestedRoots
depth = math . max ( depth , nestedDepth )
end
end

return roots , depth
end






local function streamBuilders ( statements ) 
local count = 0
for _ , statement in ipairs ( statements ) do
if statement . op == "let" and statement . type == "lua_builder" then
count = count + 1
elseif statement . op == "if" then
for _ , clause in ipairs ( statement . clauses ) do
count = count + streamBuilders ( clause . body )
end
count = count + streamBuilders ( statement . elseBody or { } )
elseif statement . op == "fornum"
or statement . op == "while"
or statement . op == "repeat"
or statement . op == "block"
then
count = count + streamBuilders ( statement . body ) + streamBuilders ( ( statement ) . conditionBody or { } )
end
end

return count
end

local BUFFER_BLOCKING_ROOTS

= {
lua_table = true ,
lua_string = true ,
lua_nil = true ,
lua_value = true ,
lua_builder = true ,
lua_scratch_u32 = true ,
lua_scratch_u8 = true ,
}







local function stringBufferOrder ( statements , seen ) 
local count = 0
for _ , statement in ipairs ( statements ) do
if statement . op == "let" and statement . type == "lua_string_buffer" then
seen = true
count = count + 1
elseif statement . op == "let" and seen and BUFFER_BLOCKING_ROOTS [ tostring ( statement . type ) ] then
holds ( false , "a persistent Lua root follows a string accumulator" )
elseif statement . op == "if" then
for _ , clause in ipairs ( statement . clauses ) do
local nestedSeen , nestedCount = stringBufferOrder ( clause . body , seen )
seen = seen or nestedSeen
count = ( count + nestedCount )
end
local nestedSeen , nestedCount = stringBufferOrder ( statement . elseBody or { } , seen )
seen = seen or nestedSeen
count = ( count + nestedCount )
elseif statement . op == "fornum"
or statement . op == "while"
or statement . op == "repeat"
or statement . op == "block"
then
if statement . op == "while" then
local headerSeen , headerCount = stringBufferOrder ( statement . conditionBody or { } , seen )
seen = seen or headerSeen
count = ( count + headerCount )
end
local nestedSeen , nestedCount = stringBufferOrder ( statement . body , seen )
seen = seen or nestedSeen
count = ( count + nestedCount )
if statement . op == "repeat" then
local headerSeen , headerCount = stringBufferOrder ( statement . conditionBody or { } , seen )
seen = seen or headerSeen
count = ( count + headerCount )
end
end
end

return seen , count
end








function verify . builderStack ( program ) 
local roots , depth = constructionStack ( program . body or { } , false )

return roots + depth + 4
end






function verify . program ( program ) 
loopFrames = { }
holds ( program . version == scalarIR . VERSION , "unknown native IR version" )
holds (
program . numericForRuntime == nil
or program . numericForRuntime == "luajit-single"
or program . numericForRuntime == "luajit-dual" ,
"unknown numeric-for runtime"
)
holds (
program . numericForRuntimeRequired ~= true or program . numericForRuntime ~= nil ,
"numeric-for runtime dependency has no model"
)
holds ( program . symbol == scalarIR . privateSymbol ( program . name ) , "private symbol does not match function identity" )
holds ( program . entryMode == "kernel" or program . entryMode == "lua-builder" , "invalid AOT entry mode" )
if program . entryMode == "lua-builder" then
holds (
program . runtimeAbi == "lua-5.1"
and program . registrar ~= nil
and ( program . registrar ) : match ( "^ks_register_[0-9a-f]+$" ) ~= nil ,
"invalid Lua builder registration ABI"
)
for _ , param in ipairs ( program . params ) do
holds ( param . kind == "uniform" or param . kind == "scalar" , "Lua builder parameter needs a VM-stack ABI" )
end
local roots , depth = constructionStack ( program . body or { } , false )
holds (
program . builderMode == nil
or program . builderMode == "eager"
or program . builderMode == "pull"
or program . builderMode == "serde" ,
"invalid program value stream mode"
)
holds ( streamBuilders ( program . body or { } ) <= 1 , "a Lua builder entry has more than one value stream" )
local _ , stringBufferCount = stringBufferOrder ( program . body or { } , false )
holds ( stringBufferCount <= 1 , "a Lua builder entry has more than one string accumulator" )
holds ( roots + depth + 4 <= 256 , "Lua builder exceeds the 256-slot construction limit" )
else
holds (
program . runtimeAbi == nil and program . registrar == nil and program . builderMode == nil ,
"kernel carried a Lua runtime ABI"
)
end

local layouts = layoutsByName ( program )
local byName , byRegion , writes , primary = signature ( program , layouts )
local countBounds , countRooms = bounds ( program , byName , primary )
regions ( program , byRegion )

local helpers = { }
for _ , helper in ipairs ( program . helpers or { } ) do
holds ( helpers [ helper . name ] == nil , "duplicate IR helper" )
helpers [ helper . name ] = helper
end

local loop = program . loop
local body = program . body
local workgroup = program . workgroup
local forms = ( loop ~= nil and 1 or 0 ) + ( body ~= nil and 1 or 0 ) + ( workgroup ~= nil and 1 or 0 )
holds (
forms == 1 ,
"an AOT program needs exactly one body form: " .. tostring (
loop ~= nil
) .. "/" .. tostring ( body ~= nil ) .. "/" .. tostring ( workgroup ~= nil )
)
local sharedTypes = nil
local sharedCounts = nil
if workgroup ~= nil then
local phased = workgroup
holds (
program . executionTarget == "gpu"
and program . entryMode == "kernel"
and phased . size >= 1
and phased . size <= 256
and phased . groups . type == "u32"
and byName [ phased . dispatchSpan ] ~= nil ,
"invalid GPU workgroup contract"
)
local scratchTypes = { }
local scratchCounts = { }
sharedTypes = scratchTypes
sharedCounts = scratchCounts
local scratchBytes = 0
for _ , scratch in ipairs ( phased . shared ) do
local unique = scratchTypes [ scratch . name ] == nil
local physical = scratch . element == "f32" or scratch . element == "i32" or scratch . element == "u32"
local initialized = scratch . initial . type == scratch . element
holds (
unique and physical and initialized and scratch . count == phased . size ,
"invalid workgroup scratch declaration"
)
scratchTypes [ scratch . name ] = scratch . element
scratchCounts [ scratch . name ] = scratch . count
scratchBytes = scratchBytes + scratch . count * 4
end
holds ( scratchBytes <= 16384 , "workgroup scratch exceeds the portable limit" )
end
local resultTypes = program . resultTypes or { }
local sourceResults = program . resultSourceTypes or { }
holds ( # resultTypes == # sourceResults , "invalid AOT entry results" )
for position , resultType in ipairs ( resultTypes ) do
holds (
verify . NUMERIC [ resultType ] == true
or resultType == "bool"
or scalarIR . nativeOnlyType ( resultType ) and program . nativeOnly == true
or program . entryMode == "lua-builder"
and (
resultType == "lua_table"
or resultType == "lua_string"
or resultType == "lua_nil"
or resultType == "lua_value"
) ,
"invalid AOT entry result type"
)
holds (
validEntryResult ( resultType , sourceResults [ position ] , program . entryMode ) ,
"invalid AOT entry result storage"
)
end
if program . usesSimd == true then
holds ( body ~= nil and loop == nil and workgroup == nil , "explicit SIMD requires a block kernel" )
end
if program . usesSimd == true then
holds (
program . simdWidth == nil or program . simdWidth == 16 or program . simdWidth == 32 or program . simdWidth == 64 ,
"invalid SIMD width"
)
else
holds ( program . simdWidth == nil , "a scalar program carries a SIMD width" )
end

local indexSpans = nil
if loop ~= nil then
local provable = { [ ( loop ) . count ] = true }
for _ , guard in ipairs ( program . guards ) do
provable [ guard . left ] = true
provable [ guard . right ] = true
end
indexSpans = provable
end
local scope = _G.setmetatable({ spans =
byName ,  layouts =
layouts ,  helpers =
helpers ,  writes =
writes ,  index =
loop ~= nil and ( loop ) . index or nil ,  boundSpan =
loop ~= nil and ( loop ) . count or nil ,  mapIndex =
loop ~= nil ,  indexSpans =
indexSpans ,  cursorBounds =
{ } ,  resultTypes =
resultTypes ,  entryMode =
program . entryMode ,  builderMode =
program . builderMode ,  workgroup =
workgroup ~= nil ,  inPhase =
false ,  shared =
sharedTypes ,  sharedCounts =
sharedCounts ,  countBounds =
countBounds ,  countRooms =
countRooms ,  simdWidth =
program . simdWidth }, verify.Scope)

helperBodies ( program , scope )

local uniforms = { }
for _ , param in ipairs ( program . params ) do
if param . kind == "uniform" or param . kind == "scalar" then
uniforms [ param . name ] = param . type
end
end




local constantNames = { }
for _ , constant in ipairs ( program . constants or { } ) do
holds ( constantNames [ constant . uniqueName ] == nil , "duplicate IR constant table" )
holds ( uniforms [ constant . uniqueName ] == nil , "an IR constant table shadows a parameter" )
constantNames [ constant . uniqueName ] = true
uniforms [ constant . uniqueName ] = "lua_string"
end





holds (
program . reusableScratch == visit . reusableScratch ( program ) ,
"the recorded reusable byte scratch is not the one this program proves"
)

local stored = { }
if workgroup ~= nil then
local phased = workgroup
block ( phased . prelude , uniforms , scope , stored , true )
scalarWalk ( phased . groups , uniforms , scope )
for _ , scratch in ipairs ( phased . shared ) do
scalarWalk ( scratch . initial , uniforms , scope )
end
block ( phased . statements , uniforms , scope , stored , true )
else
block ( loop ~= nil and ( loop ) . statements or body or { } , uniforms , scope , stored )
end
if loop ~= nil or workgroup ~= nil then
for output in pairs ( writes ) do
if ( byName [ output ] ) . type : match ( "^struct:" ) == nil then
holds ( stored [ output ] == true , "scalar IR output is never stored" )
end
end
end

return program
end

local __nuppExportValue= verify ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.verify"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.verify"]=__nuppExports;return __nuppExports