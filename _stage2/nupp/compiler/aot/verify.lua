_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);























local lane = require ( "nupp.compiler.aot.lane" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local verify = { }





verify.Context = {} verify.Context.__index = verify.Context





















local function invalid ( why )
error ( "invalid lane IR: " .. why , 0 )
end




local function holds ( condition , why )
if not condition then
invalid ( why )
end
end



local function laneTypes ( shape )
local admitted = { }
admitted [ shape . mask ] = true
admitted [ shape . bits ] = true
for _ , vector in pairs ( shape . vectorFor ) do
admitted [ vector ] = true
end

return admitted
end


verify . BITWISE_ARITY = { [ "and" ] = 2 , [ "or" ] = 2 , [ "xor" ] = 2 , [ "shl" ] = 2 , [ "shr" ] = 2 , [ "sar" ] = 2 , [ "not" ] = 1 , }


verify . CORRECTED_ARITY = { [ "nupp_f32_min" ] = 2 , [ "nupp_f32_max" ] = 2 , [ "nupp_f32_fma" ] = 3 , }


verify . LANE_MATH = {
[ "sqrt" ] = true ,
[ "abs" ] = true ,
[ "floor" ] = true ,
[ "ceil" ] = true ,
[ "min" ] = true ,
[ "max" ] = true ,
[ "sin" ] = true ,
[ "cos" ] = true ,
[ "tan" ] = true ,
[ "asin" ] = true ,
[ "acos" ] = true ,
[ "atan" ] = true ,
[ "atan2" ] = true ,
[ "sinh" ] = true ,
[ "cosh" ] = true ,
[ "tanh" ] = true ,
[ "exp" ] = true ,
[ "log" ] = true ,
[ "pow" ] = true ,
[ "fmod" ] = true ,
[ "deg" ] = true ,
[ "rad" ] = true ,
}



verify . FIXED_OPCODES = {
[ "local" ] = true ,
[ "vsplat" ] = true ,
[ "vbool_splat" ] = true ,
[ "vfield_load" ] = true ,
[ "vmask" ] = true ,
[ "vshort" ] = true ,
[ "vselect" ] = true ,
[ "vmath" ] = true ,
[ "vcorrected" ] = true ,
[ "vbinary" ] = true ,
[ "vunary" ] = true ,
[ "vbitwise" ] = true ,
[ "vbits" ] = true ,
}



verify . FIELD_STORAGE = { [ "f32" ] = true , [ "i32" ] = true , [ "u32" ] = true }





local function laneSignatures ( shape )
local binary = { }
local unary = { }
for element , vector in pairs ( shape . vectorFor ) do
if vector ~= shape . mask then
for _ , verb in ipairs ( { "add" , "sub" , "mul" , "div" } ) do
binary [ verb .. "." .. element ] = { result = vector , operand = vector }
end
for _ , verb in ipairs ( { "lt" , "le" , "gt" , "ge" , "eq" , "ne" } ) do
binary [ verb .. "." .. element ] = { result = shape . mask , operand = vector }
end
unary [ "neg." .. element ] = { result = vector , operand = vector }
unary [ "sqrt." .. element ] = { result = vector , operand = vector }
end
end

return binary , unary
end





local walk





local function shortCircuit ( node , values , context )


holds ( node . effect == "pure_total" , "a short-circuit mask without its effect proof" )
holds (
# node . args == 2 and node . args [
1
] . type == context . shape . mask and node . args [ 2 ] . type == context . shape . mask and node . type == context . shape . mask ,
"a short-circuit mask over something that is not a mask"
)
walk ( node . args [ 1 ] , values , context )
walk ( node . args [ 2 ] , values , context )
end


local function operands (
args ,
want ,
count ,
values ,
context ,
why
)
holds ( # args == count , why )
for _ , argument in ipairs ( args ) do
holds ( argument . type == want , why )
walk ( argument , values , context )
end
end

walk = function ( node , values , context )
local shape = context . shape
local admitted = laneTypes ( shape )
local binary , unary = laneSignatures ( shape )
local mask = shape . mask

holds ( node ~= nil and node . type ~= nil , "an expression with no type" )







if not admitted [ node . type ] then

context . verifyScalar ( node , values )

return
end

holds (
verify . FIXED_OPCODES [ tostring ( node . op ) ] == true ,
"an operation this vocabulary has no rule for: " .. tostring ( node . op )
)





if node . op == "local" then
holds ( values [ node . name ] == node . type , "a lane local of the wrong type" )
elseif node . op == "vsplat" then
holds (
# node . args == 1 and node . type ~= mask and shape . vectorFor [ node . element ] == node . type ,
"a splat that does not carry its element"
)
context . verifyScalar ( node . args [ 1 ] , values )
elseif node . op == "vbool_splat" then
holds ( node . type == mask and # node . args == 1 , "a boolean splat that is not a mask" )
context . verifyScalar ( node . args [ 1 ] , values )
elseif node . op == "vfield_load" then
local root = context . spans [ node . span ]
local layout = context . layouts [ node . layout ]
holds (
root ~= nil and root . type == "struct:" .. tostring (
node . layout
) and layout ~= nil and layout . fieldTypes [
node . field
] == node . scalarType and verify . FIELD_STORAGE [
node . scalarType
] == true and node . lanes == shape . lanes and node . type == shape . vectorFor [ node . scalarType ] ,
"a lane load that does not match its span, field, or width"
)
elseif node . op == "vbinary" then
local signature = binary [ node . verb .. "." .. tostring ( node . element ) ]
holds ( signature ~= nil and node . type == signature . result , "a binary operation this gang does not admit" )
operands (
node . args ,
signature . operand ,
2 ,
values ,
context ,
"a binary operation whose operands are not its own width"
)
elseif node . op == "vunary" then
local signature = unary [ node . verb .. "." .. tostring ( node . element ) ]
holds ( signature ~= nil and node . type == signature . result , "a unary operation this gang does not admit" )
operands (
node . args ,
signature . operand ,
1 ,
values ,
context ,
"a unary operation whose operand is not its own width"
)
elseif node . op == "vmask" then
local count = node . verb == "not" and 1 or 2
operands ( node . args , mask , count , values , context , "a mask operation over something that is not a mask" )
holds ( node . type == mask , "a mask operation that does not produce a mask" )
elseif node . op == "vshort" then
shortCircuit ( node , values , context )
elseif node . op == "vselect" then
holds (
# node . args == 3 and node . args [
1
] . type == mask and node . args [ 2 ] . type == node . type and node . args [ 3 ] . type == node . type ,
"a select whose arms disagree, or whose condition is not a mask"
)
walk ( node . args [ 1 ] , values , context )
walk ( node . args [ 2 ] , values , context )
walk ( node . args [ 3 ] , values , context )
elseif node . op == "vmath" then
holds (
node . type == shape . vectorFor [ "f64" ] and verify . LANE_MATH [ node . intrinsic ] == true ,
"a math operation outside the closed set, or not in binary64 lanes"
)
operands ( node . args , node . type , # node . args , values , context , "a math argument of the wrong width" )
elseif node . op == "vcorrected" then
holds (
node . type == "f32x8" and verify . CORRECTED_ARITY [ node . helper ] == # node . args ,
"a corrected operation with the wrong helper or arity"
)
operands ( node . args , node . type , # node . args , values , context , "a corrected operand of the wrong width" )
elseif node . op == "vbitwise" then
local verb = node . verb
holds (
node . type == shape . bits and verify . BITWISE_ARITY [ verb ] ~= nil ,
"a bitwise operation outside the gang's bit vector"
)
operands (
node . args ,
shape . bits ,
verify . BITWISE_ARITY [ verb ] ,
values ,
context ,
"a bitwise operand outside the bit vector"
)
elseif node . op == "vbits" then
holds (
admitted [
node . type
] == true and # node . args == 1 and admitted [ node . args [ 1 ] . type ] == true and node . args [ 1 ] . type ~= node . type ,
"a bit conversion that does not change vector"
)
walk ( node . args [ 1 ] , values , context )
else
invalid ( "an operation this vocabulary has no rule for" )
end
end







function verify . expression ( node , values , context )
walk ( node , values , context )
end

return verify
