_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.gpu.layoutfacts"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local layoutFacts;__nuppExports["layoutFacts"]=function(...) return layoutFacts(...) end;


layoutFacts=function ( shape , strides , level ) 
if # shape < 1 or # shape > 4 or # strides ~= # shape then
error ( "nupp: GPU tensor layouts take one through four matched dimensions and strides" , level )
end
local count = 1
local extent = 1
local expected = 1
local dense = true
for index = # shape , 1 , - 1 do
local dimension = shape [ index ]
local stride = strides [ index ]
if type ( dimension ) ~= "number"
or dimension % 1 ~= 0
or type ( stride ) ~= "number"
or stride % 1 ~= 0
or dimension < 1
or stride < 0
or count > _G.math.floor(( 4294967295 ) / ( dimension ))
then
error ( "nupp: GPU tensor dimensions and strides must fit uint32" , level )
end
if dimension > 1 and stride ~= expected then
dense = false
end
count = count * dimension
if dimension > 1 and stride > 0 then
local distance = dimension - 1
if distance > _G.math.floor(( ( 4294967295 - extent ) ) / ( stride )) then
error ( "nupp: GPU tensor layout extent exceeds uint32" , level )
end
extent = extent + distance * stride
end
expected = expected * dimension
end

local used = { }
local occupied = 1
local injective = true
for _ = 1 , # shape do
local chosen = 0
local smallest = nil
for axis = 1 , # shape do
if not used [ axis ] and shape [ axis ] > 1 and ( smallest == nil or strides [ axis ] < ( smallest ) ) then
chosen = axis
smallest = strides [ axis ]
end
end
if chosen == 0 then
do break end
end
used [ chosen ] = true
local stride = smallest
if stride < occupied then
injective = false
end
occupied = occupied + ( shape [ chosen ] - 1 ) * stride
end

return count , extent , dense , injective
end ;__nuppExports["layoutFacts"]=layoutFacts
 end);if not __nuppOk then package.loaded["nupp.gpu.layoutfacts"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.gpu.layoutfacts"]=__nuppExports;return __nuppExports