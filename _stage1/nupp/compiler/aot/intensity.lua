_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);























local lane = require ( "nupp.compiler.aot.lane" )

local intensity = { }


intensity.Estimate = {} intensity.Estimate.__index = intensity.Estimate




















intensity . ARITHMETIC = {
[ "add" ] = true ,
[ "sub" ] = true ,
[ "mul" ] = true ,
[ "div" ] = true ,
[ "neg" ] = true ,
[ "mod" ] = true ,
[ "pow" ] = true ,
[ "math" ] = true ,
[ "band" ] = true ,
[ "bor" ] = true ,
[ "bxor" ] = true ,
[ "bnot" ] = true ,
[ "lshift" ] = true ,
[ "rshift" ] = true ,
[ "arshift" ] = true ,
[ "f32_add" ] = true ,
[ "f32_sub" ] = true ,
[ "f32_mul" ] = true ,
[ "f32_div" ] = true ,
[ "f32_sqrt" ] = true ,
[ "f32_min" ] = true ,
[ "f32_max" ] = true ,
[ "f32_fma" ] = true ,
[ "i32_add" ] = true ,
[ "i32_sub" ] = true ,
[ "i32_mul" ] = true ,
}




intensity . ELEMENT_BYTES = { [ "f32" ] = 4 , [ "i32" ] = 4 , [ "u32" ] = 4 , [ "f64" ] = 8 , }











function intensity . estimate ( statements )
local operations = 0
local touched = { }

local countExpr
countExpr = function ( node , weight )
if type ( node ) ~= "table" or not node . op then
return
end
if intensity . ARITHMETIC [ node . op ] then
operations = operations + weight
end
if node . op == "field_load" then
touched [ "r:" .. tostring ( node . layout ) .. "." .. tostring ( node . field ) ] = node . type
elseif node . op == "load" then
touched [ "r:" .. tostring ( node . span ) ] = node . type
end
countExpr ( node . left , weight )
countExpr ( node . right , weight )
countExpr ( node . value , weight )
countExpr ( node . object , weight )
for _ , argument in ipairs ( node . args or { } ) do
countExpr ( argument , weight )
end
end

local countBlock
countBlock = function ( block , weight )
for _ , statement in ipairs ( block or { } ) do
countExpr ( statement . value , weight )
countExpr ( statement . call , weight )
countExpr ( statement . condition , weight )
countExpr ( statement . from , weight )
countExpr ( statement . to , weight )
for _ , assignment in ipairs ( statement . values or { } ) do
countExpr ( assignment . value , weight )
local target = assignment . target
if target and target . kind == "field" then
touched [ "w:" .. tostring ( target . layout ) .. "." .. tostring ( target . field ) ] = target . type
end
end
for _ , clause in ipairs ( statement . clauses or { } ) do
countExpr ( clause . condition , weight )
countBlock ( clause . body , weight )
end
countBlock ( statement . elseBody , weight )
local inner = statement . op == "while" or statement . op == "fornum"
countBlock ( statement . body , inner and weight * lane . INNER_LOOP_WEIGHT or weight )
end
end

countBlock ( statements , 1 )

local bytes = 0
for _ , elementType in pairs ( touched ) do
bytes = bytes + ( intensity . ELEMENT_BYTES [ elementType ] or 8 )
end
local perByte = bytes == 0 and operations or operations / bytes

return setmetatable({ perByte =
perByte ,  operations =
operations ,  bytes =
bytes ,  worthwhile =
perByte >= lane . INTENSITY_THRESHOLD }, intensity.Estimate)

end

return intensity
