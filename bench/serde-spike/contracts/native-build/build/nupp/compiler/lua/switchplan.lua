_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.lua.switchplan\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.lua.switchplan\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.lua.switchplan\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.compiler.lua.switchplan\0runtime\0004") };










local cst = require ( "nupp.compiler.syntax.cst" )

local switchplan = { }

switchplan.Scalar = {} switchplan.Scalar.__index = switchplan.Scalar ;_G.nupp.__reflect.link(switchplan.Scalar,__nuppT1[1],{ })




switchplan.Entry = {} switchplan.Entry.__index = switchplan.Entry ;_G.nupp.__reflect.link(switchplan.Entry,__nuppT1[2],{ __nuppT1[1] })




switchplan.Facts = {} switchplan.Facts.__index = switchplan.Facts ;_G.nupp.__reflect.link(switchplan.Facts,__nuppT1[3],{ __nuppT1[2] , __nuppT1[1] })













switchplan.Plan = {} switchplan.Plan.__index = switchplan.Plan ;_G.nupp.__reflect.link(switchplan.Plan,__nuppT1[4],{ __nuppT1[3] })







switchplan . DENSE_MIN_CASES = 4

switchplan . STRING_MIN_CASES = 8
switchplan . SPARSE_MIN_CASES = 16
switchplan . DENSE_MIN_DENSITY = 0.5
switchplan . DENSE_MAX_SPAN = 4096
switchplan . MAX_MAP_CASES = 1024

local function scalar ( exact ) 
if not exact then
return nil
end
if exact . tag ~= "literal" then
return ( _G.setmetatable({ kind =  "nil" }, switchplan.Scalar) )
end
local kind = type ( exact . constant )
if kind ~= "boolean" and kind ~= "number" and kind ~= "string" then
return nil
end

return ( _G.setmetatable({ kind =  kind ,  value =  exact . constant }, switchplan.Scalar) )
end

local function ordered ( reason , facts ) 
return ( _G.setmetatable({ tag =  "OrderedBranches" ,  reason =  reason ,  facts =  facts }, switchplan.Plan) )
end



function switchplan . facts ( node ) 
local entries = { }
local keyKind = nil
local minimum , maximum = nil , nil
local nilResult = false
local eligible , reason = true , "static scalar result map"

for _ , arm in ipairs ( node . cases or { } ) do
local result = scalar ( arm . switchStaticResult )
if arm . patternKind ~= "static" then
eligible , reason = false , "a type case needs lexical branches"
elseif arm . guard ~= nil then


eligible , reason = false , "a guarded case needs lexical branches"
elseif arm . body ~= nil or arm . expr == nil or arm . expr . kind == "doExpr" then
eligible , reason = false , "a block arm needs lexical branches"
elseif not result then
eligible , reason = false , "an arm result is not one inert scalar"
end
if result and result . kind == "nil" then
nilResult = true
end
for _ , value in ipairs ( arm . values or { } ) do
local key = scalar ( value . switchStaticValue )
if not key or key . kind == "nil" or key . kind == "boolean" then
eligible , reason = false , "the case family has no map plan"
elseif keyKind ~= nil and key . kind ~= keyKind then
eligible , reason = false , "mixed key families need lexical branches"
else
keyKind = key . kind
end
if key and result then
entries [ # entries + 1 ] = _G.setmetatable({ key =  key ,  value =  result }, switchplan.Entry)
end
if key and key . kind == "number" then
local number = key . value
if number ~= math . floor ( number ) then
eligible , reason = false , "non-integer numeric cases need lexical branches"
end
minimum = minimum == nil and number or math . min ( minimum , number )
maximum = maximum == nil and number or math . max ( maximum , number )
end
end
end

local fallback = node . elseCase and scalar ( node . elseCase . switchStaticResult ) or nil
if node . elseCase and ( node . elseCase . body ~= nil or node . elseCase . expr == nil ) then
eligible , reason = false , "a block fallback needs lexical branches"
elseif node . elseCase and not fallback then
eligible , reason = false , "the fallback is not one inert scalar"
end
fallback = fallback or _G.setmetatable({ kind =  "nil" }, switchplan.Scalar)
if # entries > switchplan . MAX_MAP_CASES then
eligible , reason = false , "the map exceeds the generated-source case cap"
end

local span = nil
local density = nil
if keyKind == "number" and minimum ~= nil and maximum ~= nil then
local width = ( maximum ) - ( minimum ) + 1
if width == math . floor ( width ) and width > 0 and width <= 9007199254740992 then
span = width
density = # entries / width
else
eligible , reason = false , "the integer span cannot be represented exactly"
end
end

return ( _G.setmetatable({ entries =
entries ,  fallback =
fallback ,  keyKind =
keyKind ,  count =
# entries ,  minimum =
minimum ,  maximum =
maximum ,  span =
span ,  density =
density ,  nilResult =
nilResult ,  eligible =
eligible ,  reason =
reason }, switchplan.Facts) )

end


function switchplan . regular ( node , coverage ) 
local facts = switchplan . facts ( node )
if coverage then
return ordered ( "coverage needs one condition for every case" , facts )
elseif not facts . eligible then
return ordered ( facts . reason , facts )
elseif facts . keyKind == "number" then
if facts . count < switchplan . DENSE_MIN_CASES then
return ordered ( "a small integer switch is cheaper as branches" , facts )
end
if facts . span ~= nil
and facts . span <= switchplan . DENSE_MAX_SPAN
and facts . density ~= nil
and facts . density >= switchplan . DENSE_MIN_DENSITY
then
return ( _G.setmetatable({ tag =
"DenseIntegerMap" ,  reason =
"dense static integer result map" ,  facts =
facts }, switchplan.Plan) )

end
if facts . count >= switchplan . SPARSE_MIN_CASES then
return ( _G.setmetatable({ tag =
"SparseIntegerMap" ,  reason =
"sparse static integer result map" ,  facts =
facts }, switchplan.Plan) )

end
return ordered ( "a small sparse integer switch is cheaper as branches" , facts )
elseif facts . keyKind == "string" and facts . count >= switchplan . STRING_MIN_CASES then
return ( _G.setmetatable({ tag =  "StringMap" ,  reason =  "static string result map" ,  facts =  facts }, switchplan.Plan) )
elseif facts . keyKind == "string" then
return ordered ( "a small string switch is cheaper as branches" , facts )
end

return ordered ( "the case family has no map plan" , facts )
end


function switchplan . native ( selectorType ) 
if selectorType == "i32" or selectorType == "u32" then
return ( _G.setmetatable({ tag =  "NativeIntegerSwitch" ,  reason =  "an established fixed-width selector" }, switchplan.Plan) )
end

return ordered ( "the native selector is not an established 32-bit integer" )
end

local __nuppExportValue= switchplan ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lua.switchplan"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lua.switchplan"]=__nuppExports;return __nuppExports