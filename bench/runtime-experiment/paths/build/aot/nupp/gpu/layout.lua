_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.gpu.layout\0runtime\0001") };
























local layout = { }

local function copied ( values ) 
local out = { }
for index , value in ipairs ( values ) do
out [ index ] = value
end

return out
end

layout.Layout = {} layout.Layout.__index = layout.Layout










function layout.Layout:offset() 
return self . _offset
end



function layout.Layout:extent() 
return self . _extent
end


function layout.Layout:dimensions() 
return copied ( self . _shape )
end


function layout.Layout:strides() 
return copied ( self . _strides )
end


function layout.Layout:isDense() 
return self . _dense
end





function layout.Layout:isInjective() 
return self . _injective
end ;_G.nupp.__reflect.link(layout.Layout,__nuppT1[1],{ })


local facts = require ( "nupp.gpu.layoutfacts" ) . layoutFacts




function layout . new ( shape , strides , offset ) 
offset = offset ?? 0
if type ( offset ) ~= "number" or offset % 1 ~= 0 or offset < 0 or offset > 4294967295 then
error ( "nupp: GPU tensor layout offset exceeds uint32" , 2 )
end
local count , extent , dense , injective = facts ( shape , strides , 2 )

return ( _G.setmetatable({ _offset =
offset ,  _shape =
copied ( shape ) ,  _strides =
copied ( strides ) ,  _extent =
extent ,  _dense =
dense ,  _injective =
injective ,  count =
count }, layout.Layout) )

end

function layout . subview ( value , origin , shape ) 
if # origin ~= # value . _shape or # shape ~= # value . _shape then
error ( "nupp: GPU tensor subview rank does not match" , 2 )
end
local offset = value . _offset
for index = # shape , 1 , -1 do
local first = origin [ index ]
local dimension = shape [ index ]
if type ( first ) ~= "number"
or first % 1 ~= 0
or first < 0
or first > value . _shape [ index ]
or dimension > value . _shape [ index ] - first
then
error ( "nupp: GPU tensor subview is outside its layout" , 2 )
end
offset = offset + first * value . _strides [ index ]
end

return layout . new ( shape , value . _strides , offset )
end

function layout . transpose ( value , order ) 
if # order ~= # value . _shape then
error ( "nupp: GPU tensor transpose rank does not match" , 2 )
end
local shape = { }
local strides = { }
local seen = { }
for index , axis in ipairs ( order ) do
if type ( axis ) ~= "number" or axis % 1 ~= 0 or axis < 1 or axis > # order or seen [ axis ] then
error ( "nupp: GPU tensor transpose must name every axis exactly once" , 2 )
end
seen [ axis ] = true
shape [ index ] = value . _shape [ axis ]
strides [ index ] = value . _strides [ axis ]
end

return layout . new ( shape , strides , value . _offset )
end

function layout . broadcast ( value , shape ) 
if # shape < # value . _shape or # shape > 4 then
error ( "nupp: GPU tensor broadcast rank must contain the source rank" , 2 )
end
local strides = { }
local shift = # shape - # value . _shape
for index , dimension in ipairs ( shape ) do
if index <= shift then
strides [ index ] = 0
else
local source = value . _shape [ index - shift ]
if source ~= dimension and source ~= 1 then
error ( "nupp: GPU tensor broadcast dimensions are incompatible" , 2 )
end
strides [ index ] = source == 1 and dimension > 1 and 0 or value . _strides [ index - shift ]
end
end
local result = layout . new ( shape , strides , value . _offset )
if result . _extent > value . _extent then
error ( "nupp: GPU tensor broadcast exceeds its source" , 2 )
end

return result
end

function layout . asStrided (
value ,
shape ,
strides ,
relativeOffset
) 
if type ( relativeOffset ) ~= "number"
or relativeOffset % 1 ~= 0
or relativeOffset < 0
or value . _offset > 4294967295 - relativeOffset
then
error ( "nupp: GPU strided layout offset exceeds uint32" , 2 )
end
local result = layout . new ( shape , strides , value . _offset + relativeOffset )
if result . _extent > value . _extent or relativeOffset > value . _extent - result . _extent then
error ( "nupp: GPU strided layout exceeds its source" , 2 )
end

return result
end

local __nuppExportValue= layout ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.gpu.layout"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.gpu.layout"]=__nuppExports;return __nuppExports