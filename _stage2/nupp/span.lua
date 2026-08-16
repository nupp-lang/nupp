_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;








local span = { }










span.WriteToken = {}




function span . destroyWriteSpan ( writable )
writable : commit ( )
end ;__nuppCleanups["nupp.span#span.destroyWriteSpan"]=span.destroyWriteSpan




span.Span = {}







const SpanImpl = {} SpanImpl.__index = SpanImpl







function SpanImpl:get(index)
if index < 1 or index > self . count then
error ( "span index out of bounds" , 2 )
end
do
return self . pointer [ self . offset + index - 1 ]
end
end



function SpanImpl:slice(first, last)
local finish = last or self . count
if first < 1 or finish < first - 1 or finish > self . count then
error ( "span slice out of bounds" , 2 )
end

return setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, SpanImpl)

end


function SpanImpl:ref()
do
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end





span.FixedSpan = {}




const FixedSpanImpl = {} FixedSpanImpl.__index = FixedSpanImpl





function FixedSpanImpl:get(index)
if index < 1 or index > ( self . count ) then
error ( "span index out of bounds" , 2 )
end
do
return self . pointer [ self . offset + index - 1 ]
end
end

function FixedSpanImpl:slice(first, last)
local finish = last or ( self . count )
if first < 1 or finish < first - 1 or finish > ( self . count ) then
error ( "span slice out of bounds" , 2 )
end

return setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, SpanImpl)

end

function FixedSpanImpl:ref()
do
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end






span.WriteSplit = {} span.WriteSplit.__index = span.WriteSplit









span.WriteSpan = {}


















span.FixedWriteSpan = {}













const WriteSpanImpl = {} WriteSpanImpl.__index = WriteSpanImpl












function WriteSpanImpl:getMut(index)
if index < 1 or index > self . count then
error ( "write span index out of bounds" , 2 )
end
do
local elementOffset = self . offset + index - 1
local pointer = ( self . pointer ) + elementOffset
return pointer
end
end

function WriteSpanImpl:set(index, value)
if index < 1 or index > self . count then
error ( "write span index out of bounds" , 2 )
end
do
self . pointer [ self . offset + index - 1 ] = value
end
end


function WriteSpanImpl:ref()
do
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end


function WriteSpanImpl:shared()
return setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
self . count }, SpanImpl)

end



function WriteSpanImpl:slice(first, last)
local finish = last or self . count
if first < 1 or finish < first - 1 or finish > self . count then
error ( "write span slice out of bounds" , 2 )
end

return setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, WriteSpanImpl)

end



function WriteSpanImpl:splitAt(mid)
if mid < 0 or mid > self . count then
error ( "write span split point out of bounds" , 2 )
end
do
local left , right = (function() return  setmetatable({ anchor =


self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
mid }, WriteSpanImpl) , setmetatable({ anchor =


self ,  pointer =
self . pointer ,  offset =
self . offset + mid ,  count =
self . count - mid }, WriteSpanImpl)  end)()


return setmetatable({ anchor =  self ,  left =  left ,  right =  right }, span.WriteSplit)
end
end




const FixedWriteSpanImpl = {} FixedWriteSpanImpl.__index = FixedWriteSpanImpl








function FixedWriteSpanImpl:getMut(index)
if index < 1 or index > ( self . count ) then
error ( "write span index out of bounds" , 2 )
end
do
local elementOffset = self . offset + index - 1
local pointer = ( self . pointer ) + elementOffset
return pointer
end
end

function FixedWriteSpanImpl:set(index, value)
if index < 1 or index > ( self . count ) then
error ( "write span index out of bounds" , 2 )
end
do
self . pointer [ self . offset + index - 1 ] = value
end
end

function FixedWriteSpanImpl:ref()
do
local pointer = ( self . pointer ) + self . offset
return pointer , self . count
end
end

function FixedWriteSpanImpl:shared()
return setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
self . count }, FixedSpanImpl)

end

function FixedWriteSpanImpl:slice(first, last)




local finish = last or ( self . count )
if first < 1 or finish < first - 1 or finish > ( self . count ) then
error ( "write span slice out of bounds" , 2 )
end

return setmetatable({ anchor =
self ,  pointer =
self . pointer ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, WriteSpanImpl)

end

function FixedWriteSpanImpl:splitAt(mid)
if mid < 0 or mid > ( self . count ) then
error ( "write span split point out of bounds" , 2 )
end
do
local left , right = (function() return  setmetatable({ anchor =


self ,  pointer =
self . pointer ,  offset =
self . offset ,  count =
mid }, WriteSpanImpl) , setmetatable({ anchor =


self ,  pointer =
self . pointer ,  offset =
self . offset + mid ,  count =
( self . count ) - mid }, WriteSpanImpl)  end)()


return setmetatable({ anchor =  self ,  left =  left ,  right =  right }, span.WriteSplit)
end
end


function WriteSpanImpl . commit ( self )
do
local _raw = self
end
end

function FixedWriteSpanImpl . commit ( self )
do
local _raw = self
end
end

function WriteSpanImpl . drop ( self )
self : commit ( )
end

function FixedWriteSpanImpl . drop ( self )
self : commit ( )
end



function span . commit ( writable )
writable : commit ( )
end










function span . fromString ( source )
local pointer = __nuppFfi.cast("const uint8_t *" , source )
return ( setmetatable({ anchor =  source ,  pointer =  pointer ,  offset =  0 ,  count =  # source }, SpanImpl) )
end




function span . fromCarray ( source , count )
if count < 0 then
error ( "span count cannot be negative" , 2 )
end
return ( setmetatable({ anchor =  source ,  pointer =  source ,  offset =  0 ,  count =  count }, SpanImpl) )
end




function span . fromFixedCarray (
source ,
count
)
return ( setmetatable({ anchor =
source ,  pointer =  source ,  offset =  0 ,  count =  count }, FixedSpanImpl)
)
end






function span . writeCarray ( source , count )
if count < 0 then
error ( "write span count cannot be negative" , 2 )
end
return ( setmetatable({ anchor =  source ,  pointer =  source ,  offset =  0 ,  count =  count }, WriteSpanImpl) )
end




function span . writeFixedCarray (
source ,
count
)
return ( setmetatable({ anchor =
source ,  pointer =  source ,  offset =  0 ,  count =  count }, FixedWriteSpanImpl)
)
end



span.Range = {} span.Range.__index = span.Range









function span . range ( first , last , ... )
local count = select ( "#" , ... )
if count < 1 or first < 1 or last < first - 1 then
error ( "span range out of bounds" , 2 )
end
for index = 1 , count do
local candidate = select ( index , ... )
if last > candidate . count then
error ( "span range out of bounds" , 2 )
end
end

return setmetatable({ first =  first ,  last =  last }, span.Range)
end

return span
