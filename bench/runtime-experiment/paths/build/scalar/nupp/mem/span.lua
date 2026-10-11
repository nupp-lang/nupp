_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.span\0runtime\0003") };



























































































































































































local physical = require ( "nupp.runtime.storage" )
local span = { }













function span . destroyWriteSpan ( writable ) 
do
local _raw = writable
end
end __nuppCleanups["nupp.mem.span#destroyWriteSpan"]= span.destroyWriteSpan;





























local SpanImpl = {} SpanImpl.__index = SpanImpl







function SpanImpl:get(index) 
if index % 1 ~= 0 or index < 1 or index > self . count then
error ( "nupp: span index out of bounds" , 2 )
end
do
return self . pointer [ self . offset + index - 1 ]
end
end



function SpanImpl:slice(first, last) 
local finish = last or self . count
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or finish > self . count then
error ( "nupp: span slice out of bounds" , 2 )
end

return ( _G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, SpanImpl) )

end


function SpanImpl:ref() 
do
if self . offset == 0 then
return self . pointer , self . count
end
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end





span.FixedSpan = {}




local FixedSpanImpl = {} FixedSpanImpl.__index = FixedSpanImpl





function FixedSpanImpl:get(index) 
if index % 1 ~= 0 or index < 1 or index > ( self . count ) then
error ( "nupp: span index out of bounds" , 2 )
end
do
return self . pointer [ self . offset + index - 1 ]
end
end

function FixedSpanImpl:slice(first, last) 
local finish = last or ( self . count )
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or finish > ( self . count ) then
error ( "nupp: span slice out of bounds" , 2 )
end

return ( _G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, SpanImpl) )

end

function FixedSpanImpl:ref() 
do
if self . offset == 0 then
return self . pointer , self . count
end
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end






span.WriteSplit = {} span.WriteSplit.__index = span.WriteSplit ;_G.nupp.__reflect.link(span.WriteSplit,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../src/nupp/mem/span.nupp\0WriteSpan\0interface\0module\0001","nupp.mem.span") })













span.WriteSpan = {}

















































span.FixedWriteSpan = {}













local WriteSpanImpl = {} WriteSpanImpl.__index = WriteSpanImpl










function WriteSpanImpl:getMut(index) 
if index % 1 ~= 0 or index < 1 or index > self . count then
error ( "nupp: write span index out of bounds" , 2 )
end
do
local elementOffset = self . offset + index - 1
local pointer = ( self . pointer ) + elementOffset
return pointer
end
end



function WriteSpanImpl:get(index) 
if index % 1 ~= 0 or index < 1 or index > self . count then
error ( "nupp: write span index out of bounds" , 2 )
end
do
return self . pointer [ self . offset + index - 1 ]
end
end

function WriteSpanImpl:set(index, value) 
if index % 1 ~= 0 or index < 1 or index > self . count then
error ( "nupp: write span index out of bounds" , 2 )
end
do
self . pointer [ self . offset + index - 1 ] = value
end
end


function WriteSpanImpl:ref() 
do
if self . offset == 0 then
return self . pointer , self . count
end
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end


function WriteSpanImpl:shared() 
return ( _G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
self . count }, SpanImpl) )

end



function WriteSpanImpl:slice(first, last) 
local finish = last or self . count
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or finish > self . count then
error ( "nupp: write span slice out of bounds" , 2 )
end

return ( _G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, WriteSpanImpl) )

end



function WriteSpanImpl:splitAt(mid) 
if mid % 1 ~= 0 or mid < 0 or mid > self . count then
error ( "nupp: write span split point out of bounds" , 2 )
end
do
local left , right = (function() return

_G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
mid }, WriteSpanImpl) ,

_G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + mid ,  count =
self . count - mid }, WriteSpanImpl)  end)()


return ( _G.setmetatable({ anchor =  self ,  left =  left ,  right =  right }, span.WriteSplit) )
end
end




local FixedWriteSpanImpl = {} FixedWriteSpanImpl.__index = FixedWriteSpanImpl







function FixedWriteSpanImpl:getMut(index) 
if index % 1 ~= 0 or index < 1 or index > ( self . count ) then
error ( "nupp: write span index out of bounds" , 2 )
end
do
local elementOffset = self . offset + index - 1
local pointer = ( self . pointer ) + elementOffset
return pointer
end
end



function FixedWriteSpanImpl:get(index) 
if index % 1 ~= 0 or index < 1 or index > ( self . count ) then
error ( "nupp: write span index out of bounds" , 2 )
end
do
return self . pointer [ self . offset + index - 1 ]
end
end

function FixedWriteSpanImpl:set(index, value) 
if index % 1 ~= 0 or index < 1 or index > ( self . count ) then
error ( "nupp: write span index out of bounds" , 2 )
end
do
self . pointer [ self . offset + index - 1 ] = value
end
end

function FixedWriteSpanImpl:ref() 
do
if self . offset == 0 then
return self . pointer , self . count
end
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end

function FixedWriteSpanImpl:shared() 
return ( _G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
self . count }, FixedSpanImpl) )

end

function FixedWriteSpanImpl:slice(first, last) 




local finish = last or ( self . count )
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or finish > ( self . count ) then
error ( "nupp: write span slice out of bounds" , 2 )
end

return ( _G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, WriteSpanImpl) )

end

function FixedWriteSpanImpl:splitAt(mid) 
if mid % 1 ~= 0 or mid < 0 or mid > ( self . count ) then
error ( "nupp: write span split point out of bounds" , 2 )
end
do
local left , right = (function() return

_G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
mid }, WriteSpanImpl) ,

_G.setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + mid ,  count =
( self . count ) - mid }, WriteSpanImpl)  end)()


return ( _G.setmetatable({ anchor =  self ,  left =  left ,  right =  right }, span.WriteSplit) )
end
end


function WriteSpanImpl . drop ( self ) 
do
local _raw = self
end
end

function FixedWriteSpanImpl . drop ( self ) 
do
local _raw = self
end
end




















function span . fromString ( source ) 
local pointer = physical . borrowString ( source )
return ( ( _G.setmetatable({ anchor =  source ,  pointer =  pointer ,  offset =  0 ,  count =  # source }, SpanImpl) ) )
end





local function foreignByteSpan ( anchor , pointer , offset , count ) 
local typed = physical . castBytes ( pointer )
return ( ( _G.setmetatable({ anchor =  anchor ,  pointer =  typed ,  offset =  offset ,  count =  count }, SpanImpl) ) )
end

rawset ( span , "__foreignByteSpan" , foreignByteSpan )



local function foreignSpan (
anchor ,
pointer ,
offset ,
count ,
element
) 
do
local typed = physical . castElements ( element , pointer )
return ( ( _G.setmetatable({ anchor =  anchor ,  pointer =  typed ,  offset =  offset ,  count =  count }, SpanImpl) ) )
end
end

rawset ( span , "__foreignSpan" , foreignSpan )





















function span . fromCarray ( source , count ) 
if count % 1 ~= 0 or count < 0 then
error ( "nupp: span count cannot be negative" , 2 )
end
return ( (
_G.setmetatable({ anchor =  source ,  pointer =  source ,  offset =  0 ,  count =  physical . boundedCount ( source , count ) }, SpanImpl)
) )
end










function span . fromFixedCarray (
source ,
count
) 
return ( (
_G.setmetatable({ anchor =  source ,  pointer =  source ,  offset =  0 ,  count =  count }, FixedSpanImpl)
) )
end




























function span . writeCarray ( source , count ) 
if count % 1 ~= 0 or count < 0 then
error ( "nupp: write span count cannot be negative" , 2 )
end
return ( (
_G.setmetatable({ anchor =
source ,  pointer =
source ,  offset =
0 ,  count =
physical . boundedCount ( source , count ) }, WriteSpanImpl)

) )
end










function span . writeFixedCarray (
source ,
count
) 
return ( (
_G.setmetatable({ anchor =  source ,  pointer =  source ,  offset =  0 ,  count =  count }, FixedWriteSpanImpl)
) )
end





local function sharedRef ( value ) 
local implementation = getmetatable ( value )
if implementation == ( SpanImpl ) or implementation == ( FixedSpanImpl ) then
return value : ref ( )
end

return nil , nil
end

rawset ( span , "__sharedRef" , sharedRef )

local __nuppExportValue= span ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.mem.span"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.span"]=__nuppExports;return __nuppExports