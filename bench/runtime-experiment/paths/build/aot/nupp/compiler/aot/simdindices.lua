_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local scalarIR = require ( "nupp.compiler.aot.scalar" )
local shapes = require ( "nupp.compiler.aot.simdshape" )
local indices = { }

local function indexElement ( element ) 
return element == "i32" or element == "u32" or element == "i64" or element == "u64"
end

local function speciesElement ( element ) 
return element == "f32"
or element == "f64"
or element == "i8"
or element == "u8"
or element == "i16"
or element == "u16"
or ( element == "i32" or element == "u32" or element == "i64" or element == "u64" )
end

local function logicalLanes ( element , shape ) 
local lanes = shapes . widestLanes ( element , shape )
if lanes == nil or shape : match ( "^fixed" ) ~= nil and ( ( lanes ) < 2 or ( lanes ) > 64 ) then
return nil
end

return lanes
end


const RANGES

= {
u32 = { 0 , 4294967295 } ,
i32 = { -2147483648 , 2147483647 } ,
u64 = { 0 , 9007199254740992 } ,
i64 = { - 9007199254740992 , 9007199254740992 } ,
}



local function exactIndex ( value ) 
if value . op ~= "numeric_cast" then
return scalarIR . exactInteger ( value )
end
local converted = value
local inner = converted . value
local sign = 1
if inner . op == "neg" then
inner = ( inner ) . value
sign = -1
end
local exact = scalarIR . exactInteger ( inner )
if exact == nil then
return nil
end
local answer = sign * ( exact )
local range = RANGES [ tostring ( converted . type ) ]
if range == nil then
return inner . type == converted . type and answer or nil
end

return answer >= range [ 1 ] and answer <= range [ 2 ] and answer or nil
end


function indices . matches ( indexType , speciesType ) 
local element , shape = indexType : match ( "^simd_vector_([iu]%d+)_(.+)$" )
local targetElement , targetShape = speciesType : match ( "^simd_species_([fiu]%d+)_(.+)$" )
if element == nil or targetElement == nil or shape ~= targetShape then
return false
end
if not ( element == "i32" or element == "u32" or element == "i64" or element == "u64" ) or not ( targetElement == "f32" or targetElement == "f64" or targetElement == "i8" or targetElement == "u8" or targetElement == "i16" or targetElement == "u16" or ( targetElement == "i32" or targetElement == "u32" or targetElement == "i64" or targetElement == "u64" ) ) or logicalLanes ( element , shape ) == nil then
return false
end

return shape ~= "preferred" or element : sub ( 2 ) == targetElement : sub ( 2 )
end





function indices . unique ( value ) 
if value . op ~= "simd_iota" then
return false
end
local element , shape = value . type : match ( "^simd_vector_([iu]%d+)_(.+)$" )
if not ( element == "i32" or element == "u32" or element == "i64" or element == "u64" ) then
return false
end
local args = ( value ) . args
if # args ~= 2 then
return false
end
local first , step = exactIndex ( args [ 1 ] ) , exactIndex ( args [ 2 ] )
local lanes = logicalLanes ( element , shape )
if first == nil or step == nil or step == 0 or lanes == nil then
return false
end
local bits = tonumber ( element : sub ( 2 ) ) or 0
local signed = element : sub ( 1 , 1 ) == "i"
local low = signed and - ( 2 ^ ( bits - 1 ) ) or 0
local high = 2 ^ ( signed and bits - 1 or bits ) - 1
local last = first + ( lanes - 1 ) * step

return math . abs ( first ) <= 9007199254740991
and math . abs ( last ) <= 9007199254740991
and first >= low
and first <= high
and last >= low
and last <= high
end

local __nuppExportValue= indices ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.simdindices"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.simdindices"]=__nuppExports;return __nuppExports