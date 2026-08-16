_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);


local scalar = { }



local PATHS = { }
for _ , family in ipairs ( { "i32" , "u32" } ) do
for _ , operation in ipairs ( {
"add" ,
"sub" ,
"mul" ,
"andBits" ,
"orBits" ,
"xorBits" ,
"notBits" ,
"shiftLeft" ,
"rotateLeft" ,
"rotateRight" ,
"lessThan" ,
"lessOrEqual" ,
} ) do
PATHS [ "nupp.math." .. family .. "." .. operation ] = family .. "." .. operation
end
end
PATHS [ "nupp.math.i32.shiftRightArithmetic" ] = "i32.shiftRightArithmetic"
PATHS [ "nupp.math.i32.wrap" ] = "i32.wrap"
PATHS [ "nupp.math.i32.fromU32" ] = "i32.fromU32"
PATHS [ "nupp.math.i32.toU32" ] = "i32.toU32"
PATHS [ "nupp.math.u32.shiftRightLogical" ] = "u32.shiftRightLogical"
PATHS [ "nupp.math.u32.wrap" ] = "u32.wrap"
PATHS [ "nupp.math.u32.fromI32" ] = "u32.fromI32"
PATHS [ "nupp.math.u32.toI32" ] = "u32.toI32"
for _ , operation in ipairs ( {
"narrow" ,
"round" ,
"add" ,
"sub" ,
"mul" ,
"div" ,
"sqrt" ,
"min" ,
"max" ,
"fma" ,
"fromBits" ,
"toBits" ,
} ) do
PATHS [ "nupp.math.f32." .. operation ] = "f32." .. operation
end

function scalar . forPath ( path )
return PATHS [ path ]
end

local function u32 ( value )
value = bit . tobit ( value )
return value < 0 and value + 4294967296 or value
end

local function mul32 ( a , b )
a , b = u32 ( a ) , u32 ( b )
local al , bl = a % 65536 , b % 65536
local ah , bh = math . floor ( a / 65536 ) , math . floor ( b / 65536 )
return bit . tobit ( al * bl + ( ( ah * bl + al * bh ) % 65536 ) * 65536 )
end




function scalar . fold ( identity , args )
local family , operation = identity : match ( "^(i32)%.(.+)$" )
if not family then
family , operation = identity : match ( "^(u32)%.(.+)$" )
end
if not family then
return nil
end
local a , b = args [ 1 ] , args [ 2 ]
if operation == "wrap" then
local out = bit . tobit ( a )
return family == "u32" and u32 ( out ) or out
elseif operation == "add" then
local out = bit . tobit ( a + b )
return family == "u32" and u32 ( out ) or out
elseif operation == "sub" then
local out = bit . tobit ( a - b )
return family == "u32" and u32 ( out ) or out
elseif operation == "mul" then
local out = mul32 ( a , b )
return family == "u32" and u32 ( out ) or out
elseif operation == "andBits" then
local out = bit . band ( a , b )
return family == "u32" and u32 ( out ) or out
elseif operation == "orBits" then
local out = bit . bor ( a , b )
return family == "u32" and u32 ( out ) or out
elseif operation == "xorBits" then
local out = bit . bxor ( a , b )
return family == "u32" and u32 ( out ) or out
elseif operation == "notBits" then
local out = bit . bnot ( a )
return family == "u32" and u32 ( out ) or out
elseif operation == "shiftLeft" then
local out = bit . lshift ( a , bit . band ( b , 31 ) )
return family == "u32" and u32 ( out ) or out
elseif operation == "shiftRightArithmetic" then
return bit . arshift ( a , bit . band ( b , 31 ) )
elseif operation == "shiftRightLogical" then
return u32 ( bit . rshift ( a , bit . band ( b , 31 ) ) )
elseif operation == "rotateLeft" then
local out = bit . rol ( a , bit . band ( b , 31 ) )
return family == "u32" and u32 ( out ) or out
elseif operation == "rotateRight" then
local out = bit . ror ( a , bit . band ( b , 31 ) )
return family == "u32" and u32 ( out ) or out
elseif operation == "lessThan" then
return family == "u32" and u32 ( a ) < u32 ( b ) or bit . tobit ( a ) < bit . tobit ( b )
elseif operation == "lessOrEqual" then
return family == "u32" and u32 ( a ) <= u32 ( b ) or bit . tobit ( a ) <= bit . tobit ( b )
elseif operation == "fromU32" or operation == "toI32" then
return bit . tobit ( a )
elseif operation == "toU32" or operation == "fromI32" then
return u32 ( a )
end

return nil
end

return scalar
