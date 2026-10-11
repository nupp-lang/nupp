_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT38={}; local function __nuppT35(...) return {n=select("#",...),...} end; local __nuppT39,__nuppT40,__nuppT41,__nuppT42,__nuppT43,__nuppT44,__nuppT45,__nuppT46=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT36(value) return value end; local function __nuppT37(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT44({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT45(v.primary) for _,reason in __nuppT46(v.suppressed) do text=text.."\ncleanup: "..__nuppT45(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppDrop2 = function(__nuppV) if __nuppV == nil then return end __nuppV:close();  end;local __nuppExports={};package.loaded["nupp.io.internal.bytes"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local newBuffer;__nuppExports["newBuffer"]=function(...) return newBuffer(...) end;local newQueueReader;__nuppExports["newQueueReader"]=function(...) return newQueueReader(...) end;local newStringReader;__nuppExports["newStringReader"]=function(...) return newStringReader(...) end;local readAll;__nuppExports["readAll"]=function(...) return readAll(...) end;



local physical = require ( "nupp.runtime.storage" )
local span = require ( "nupp.mem.span" )

local SMALLEST = 32
local DEFAULT_READ = 65536
local MAX_EXACT_INTEGER = 9007199254740991


local function integer_ ( value , what , level ) 
if type ( value ) ~= "number"
or value ~= math . floor ( value )
or ( value ) < 0
or ( value ) > 9007199254740991
then
error ( "nupp: " .. what .. " must be a non-negative integer" , level )
end

return value
end


local function whole ( value , what , level ) 
if type ( value ) ~= "number"
or value ~= math . floor ( value )
or math . abs ( value ) > 9007199254740991
then
error ( "nupp: " .. what .. " must be an integer" , level )
end

return value
end


local function sizeSum ( left , right , what , level ) 
if left > 9007199254740991 - right then
error ( "nupp: " .. what .. " is too large" , level )
end

return left + right
end


local function positive ( value , what , level ) 
local answer = whole ( value , what , level + 1 )
if answer < 1 then
error ( "nupp: " .. what .. " must be a positive integer" , level )
end

return answer
end


local function opened ( closed , what , level ) 
if closed then
error ( "nupp: " .. what .. " is closed" , level )
end
end





local function range ( length , offset , count , what , level ) 
local from = integer_ ( offset == nil and 0 or offset , what .. " offset" , level )
if from > length then
error ( "nupp: " .. what .. " offset is past the end" , level )
end
local taking = integer_ ( count == nil and length - from or count , what .. " count" , level )
if taking > length - from then
error ( "nupp: " .. what .. " range is past the end" , level )
end

return from , taking
end











local Writer = {}































local Reader = {}




















































local function destroyLease ( self ) 
self : drop ( )
end __nuppCleanups["nupp.io.internal.bytes#destroyLease"]=destroyLease;



local reserve
local bytesAt
local newReaderOver
local newWriterOver



















const queueLength = function ( source ) 
local answer
local custom = false
if type ( source ) == "table" then
local meta = getmetatable ( source )
if type ( meta ) == "table" and type ( meta . __len ) == "function" then
answer = meta . __len ( source )
custom = true
end
end
if not custom then
answer = # source
end

return integer_ ( answer , "io.ByteQueue length" , 2 )
end ;__nuppExports["queueLength"]=queueLength

local function takeQueue ( source , count ) 
local chunk = source : get ( count )
if type ( chunk ) ~= "string" or # chunk ~= count then
error ( "nupp: io.ByteQueue returned the wrong byte count" , 2 )
end

return chunk
end

local function takeAllQueue ( source , count ) 
local chunk = source : get ( )
if type ( chunk ) ~= "string" or # chunk ~= count then
error ( "nupp: io.ByteQueue returned the wrong byte count" , 2 )
end

return chunk
end



local ByteView = {}











local newView





local Snapshot = {} Snapshot.__index = Snapshot





function Snapshot:length() 
opened ( self . _closed , "io.ByteView" , 2 )
return # self . _bytes
end

function Snapshot:getString() 
opened ( self . _closed , "io.ByteView" , 2 )
return self . _bytes
end

function Snapshot:readSpan() 
opened ( self . _closed , "io.ByteView" , 2 )
return span . fromString ( self . _bytes )
end

function Snapshot:newReader() 
opened ( self . _closed , "io.ByteView" , 2 )
return newReaderOver ( self . _bytes )
end

function Snapshot:view(offset, count) 
opened ( self . _closed , "io.ByteView" , 2 )
local from , taking = range ( # self . _bytes , offset , count , "io.ByteView" , 2 )
return newView ( self . _bytes : sub ( from + 1 , from + taking ) )
end

function Snapshot:isReleased() 
return self . _closed
end














local Buffer = {}




















local newWriteLease





local HeapBuffer = {} HeapBuffer.__index = HeapBuffer







function HeapBuffer:length() 
opened ( self . _closed , "io.Buffer" , 2 )
return self . _length
end

function HeapBuffer:capacity() 
opened ( self . _closed , "io.Buffer" , 2 )
return self . _capacity
end

function HeapBuffer:clear() 
opened ( self . _closed , "io.Buffer" , 2 )
self . _length = 0
end

function HeapBuffer:ensureCapacity(minimum) 
opened ( self . _closed , "io.Buffer" , 2 )
reserve ( self , integer_ ( minimum , "io.Buffer capacity" , 2 ) )
end

function HeapBuffer:resize(length) 
opened ( self . _closed , "io.Buffer" , 2 )
local wanted = integer_ ( length , "io.Buffer length" , 2 )
if wanted > self . _length then
reserve ( self , wanted )
do
local root = self . _data
physical . fill ( ( root ) + self . _length , wanted - self . _length , 0 )
end
end
self . _length = wanted
end

function HeapBuffer:getString(offset, count) 
opened ( self . _closed , "io.Buffer" , 2 )
local from , taking = range ( self . _length , offset , count , "io.Buffer" , 2 )
return bytesAt ( self , from , taking )
end

function HeapBuffer:setString(bytes, offset) 
opened ( self . _closed , "io.Buffer" , 2 )
if type ( bytes ) ~= "string" then
error ( "nupp: io.Buffer bytes must be a string" , 2 )
end
local from = integer_ ( offset == nil and 0 or offset , "io.Buffer offset" , 2 )
local ending = sizeSum ( from , # bytes , "io.Buffer range" , 2 )
reserve ( self , ending )
if from > self . _length then
do
local root = self . _data
physical . fill ( ( root ) + self . _length , from - self . _length , 0 )
end
end
if # bytes > 0 then
do
local root = self . _data
physical . copy ( ( root ) + from , bytes , # bytes )
end
end
if ending > self . _length then
self . _length = ending
end
end

function HeapBuffer:readSpan() 
opened ( self . _closed , "io.Buffer" , 2 )
return span . fromCarray ( self . _data , self . _length )
end

function HeapBuffer:reserveWrite(offset, count) 




opened ( self . _closed , "io.Buffer" , 2 )
local from = integer_ ( offset , "io.Buffer write offset" , 2 )
local available = integer_ ( count , "io.Buffer write count" , 2 )
reserve ( self , sizeSum ( from , available , "io.Buffer write range" , 2 ) )

return newWriteLease ( self , from , available )
end

function HeapBuffer:view(offset, count) 
opened ( self . _closed , "io.Buffer" , 2 )
local from , taking = range ( self . _length , offset , count , "io.Buffer" , 2 )
return newView ( bytesAt ( self , from , taking ) )
end

function HeapBuffer:newReader() 
opened ( self . _closed , "io.Buffer" , 2 )
return newReaderOver ( bytesAt ( self , 0 , self . _length ) )
end

function HeapBuffer:newWriter() 
opened ( self . _closed , "io.Buffer" , 2 )
self : clear ( )
return newWriterOver ( self )
end

function HeapBuffer:isReleased() 
return self . _closed
end


local WriteLease = {} WriteLease.__index = WriteLease








function WriteLease:span() 
return span . writeCarray ( self . pointer , self . count )
end

function WriteLease:commit(written) 
local used = integer_ ( written , "io.Buffer committed byte count" , 2 )
if used > self . count then
error ( "nupp: io.Buffer committed byte count exceeds its lease" , 2 )
end
local raw = self
local target = raw . state
opened ( target . _closed , "io.Buffer" , 2 )
if used > 0 then
if raw . offset > target . _length then
do
local root = target . _data
physical . fill (
( root ) + ( target . _length ) ,
( raw . offset ) - ( target . _length ) ,
0
)
end
end
local ending = raw . offset + used
if ending > target . _length then
target . _length = ending
end
end
end


newWriteLease = function (
buffer ,
offset ,
count
) 
local state = buffer
return ( _G.setmetatable({ anchor =
buffer ,  state =
state ,  pointer =
( state . _data + offset ) ,  offset =
offset ,  count =
count }, WriteLease) )

end


local BufferWriter = {} BufferWriter.__index = BufferWriter














function BufferWriter:write(bytes) 
if self . _closed then
return false , "the writer is closed"
end
if type ( bytes ) ~= "string" then
error ( "nupp: Writer:write bytes must be a string" , 2 )
end
local state = self . _buffer
if state . _closed then
return false , "the destination buffer is closed"
end


( state ) : setString ( bytes , self . _at )
self . _at = sizeSum ( self . _at , # bytes , "Writer position" , 2 )

return true , nil
end

function BufferWriter:writeSpan(source) 
if self . _closed then
return nil , "the writer is closed"
end
local state = self . _buffer
if state . _closed then
return nil , "the destination buffer is closed"
end
local count = source .count
if count == 0 then
return 0 , nil
end
local at = self . _at
reserve ( state , at + count )
do local __nuppT47=0; local  __nuppT53 ; local __nuppT54=false ; local __nuppT48,__nuppT49,__nuppT50=__nuppT40(function() do local __nuppT55= newWriteLease ( state , at , count ) ; __nuppT53= __nuppT55 ; __nuppT47=1;  __nuppT54=true;  local lease=__nuppT53;
do
do local __nuppT56=0; local  __nuppT62 ; local __nuppT63=false ; local __nuppT57,__nuppT58,__nuppT59=__nuppT40(function() do local __nuppT64= lease : span ( ) ; __nuppT62= __nuppT64 ; __nuppT56=1;  __nuppT63=true;  local output=__nuppT62;
if count == 1 then
output :set( 1 , source :get( 1 ) )
else
local destinationPointer = output : ref ( )
local sourcePointer = source : ref ( )


require ( "nupp.runtime.storage" ) . copy ( destinationPointer , sourcePointer , count )
end
do __nuppT63=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT36); local __nuppT60={}; local __nuppT61=0; if __nuppT56>=1 and __nuppT63 then  local __nuppT65,__nuppT66=__nuppT39(__nuppCleanup1,__nuppT62);  if not __nuppT65 then __nuppT61=__nuppT61+1; __nuppT60[__nuppT61]=__nuppT66 end; end; if not __nuppT57 then if __nuppT61>0 then __nuppT41(__nuppT37(__nuppT58,__nuppT60,1),0) else __nuppT41(__nuppT58,0) end end; if __nuppT61>0 then if __nuppT61>1 then __nuppT41(__nuppT37(__nuppT60[1],__nuppT60,2),0) else __nuppT41(__nuppT60[1],0) end end; if __nuppT58=="return" then  return "return",__nuppT59  end; end
end
do (function(__nuppT67,...)  __nuppT54=false; return __nuppT67:commit(...)  end)( lease , count ) end
self . _at = sizeSum ( at , count , "Writer position" , 2 )

return "return",__nuppT35( count , nil ) end; return "normal" end,__nuppT36); local __nuppT51={}; local __nuppT52=0; if __nuppT47>=1 and __nuppT54 then  local __nuppT68,__nuppT69=__nuppT39(__nuppCleanup2,__nuppT53);  if not __nuppT68 then __nuppT52=__nuppT52+1; __nuppT51[__nuppT52]=__nuppT69 end; end; if not __nuppT48 then if __nuppT52>0 then __nuppT41(__nuppT37(__nuppT49,__nuppT51,1),0) else __nuppT41(__nuppT49,0) end end; if __nuppT52>0 then if __nuppT52>1 then __nuppT41(__nuppT37(__nuppT51[1],__nuppT51,2),0) else __nuppT41(__nuppT51[1],0) end end; if __nuppT49=="return" then  return __nuppT42(__nuppT50,1,__nuppT50.n)  end; end
end





function BufferWriter:flush() 
if self . _closed then
return false , "the writer is closed"
end

return true , nil
end












local function copyString (
destination ,
bytes ,
offset ,
count
) 
local pointer = destination : ref ( )
do
local source = physical . borrowString ( bytes )
physical . copy ( pointer , ( source ) + offset , count )
end
end

local StringReader = {} StringReader.__index = StringReader















function StringReader:read(count) 
if self . _closed then
return nil , "the reader is closed"
end
local wanted = positive ( count , "Reader:read count" , 2 )
local bytes = self . _bytes
local at = self . _at
if at > # bytes then
return "" , nil
end
local taking = math . min ( wanted , # bytes - at + 1 )
local out = bytes : sub ( at , at + ( taking ) - 1 )
self . _at = at + ( taking )

return out , nil
end

function StringReader:readSpan(destination) 
if self . _closed then
return nil , "the reader is closed"
end
local wanted
do
local output = destination
wanted = positive ( output .count , "Reader:readSpan destination length" , 2 )
end
local bytes = self . _bytes
local at = self . _at
if at > # bytes then
return 0 , nil
end
local taking = math . min ( wanted , # bytes - at + 1 )
copyString ( destination , bytes , at - 1 , taking )
self . _at = at + taking

return taking , nil
end

function StringReader:readInto(destination, offset, count) 





if self . _closed then
return nil , "the reader is closed"
end
local from = integer_ ( offset == nil and 0 or offset , "Reader:readInto offset" , 2 )
local wanted = positive ( count == nil and DEFAULT_READ or count , "Reader:readInto count" , 2 )
local bytes = self . _bytes
local at = self . _at
if at > # bytes then
return 0 , nil
end
local taking = math . min ( wanted , # bytes - at + 1 )
do local __nuppT75=0; local  __nuppT81 ; local __nuppT82=false ; local __nuppT76,__nuppT77,__nuppT78=__nuppT40(function() do local __nuppT83= destination : reserveWrite ( from , wanted ) ; __nuppT81= __nuppT83 ; __nuppT75=1;  __nuppT82=true;  local lease=__nuppT81;
do
do local __nuppT84=0; local  __nuppT90 ; local __nuppT91=false ; local __nuppT85,__nuppT86,__nuppT87=__nuppT40(function() do local __nuppT92= lease : span ( ) ; __nuppT90= __nuppT92 ; __nuppT84=1;  __nuppT91=true;  local output=__nuppT90;
copyString ( output , bytes , at - 1 , taking )
do __nuppT91=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT36); local __nuppT88={}; local __nuppT89=0; if __nuppT84>=1 and __nuppT91 then  local __nuppT93,__nuppT94=__nuppT39(__nuppCleanup1,__nuppT90);  if not __nuppT93 then __nuppT89=__nuppT89+1; __nuppT88[__nuppT89]=__nuppT94 end; end; if not __nuppT85 then if __nuppT89>0 then __nuppT41(__nuppT37(__nuppT86,__nuppT88,1),0) else __nuppT41(__nuppT86,0) end end; if __nuppT89>0 then if __nuppT89>1 then __nuppT41(__nuppT37(__nuppT88[1],__nuppT88,2),0) else __nuppT41(__nuppT88[1],0) end end; if __nuppT86=="return" then  return "return",__nuppT87  end; end
end
do (function(__nuppT95,...)  __nuppT82=false; return __nuppT95:commit(...)  end)( lease , taking ) end
self . _at = at + taking

return "return",__nuppT35( taking , nil ) end; return "normal" end,__nuppT36); local __nuppT79={}; local __nuppT80=0; if __nuppT75>=1 and __nuppT82 then  local __nuppT96,__nuppT97=__nuppT39(__nuppCleanup2,__nuppT81);  if not __nuppT96 then __nuppT80=__nuppT80+1; __nuppT79[__nuppT80]=__nuppT97 end; end; if not __nuppT76 then if __nuppT80>0 then __nuppT41(__nuppT37(__nuppT77,__nuppT79,1),0) else __nuppT41(__nuppT77,0) end end; if __nuppT80>0 then if __nuppT80>1 then __nuppT41(__nuppT37(__nuppT79[1],__nuppT79,2),0) else __nuppT41(__nuppT79[1],0) end end; if __nuppT77=="return" then  return __nuppT42(__nuppT78,1,__nuppT78.n)  end; end
end






function StringReader:transferTo(destination) 
if self . _closed then
return nil , "the reader is closed"
end
local remaining = self . _bytes : sub ( self . _at )
local ok , reason = destination : write ( remaining )
if not ok then
return nil , reason
end
self . _at = # self . _bytes + 1

return # remaining , nil
end










local QueueReader = {} QueueReader.__index = QueueReader









function QueueReader:read(count) 
if self . _closed then
return nil , "the reader is closed"
end
local wanted = positive ( count , "Reader:read count" , 2 )
local source = self . _source
local have = queueLength ( source )
if have == 0 then
return "" , nil
end

return takeQueue ( source , math . min ( wanted , have ) ) , nil
end

function QueueReader:readSpan(destination) 
if self . _closed then
return nil , "the reader is closed"
end
local wanted
do
local output = destination
wanted = positive ( output .count , "Reader:readSpan destination length" , 2 )
end
local source = self . _source
local have = queueLength ( source )
if have == 0 then
return 0 , nil
end
local taking = math . min ( wanted , have )
local chunk = takeQueue ( source , taking )
copyString ( destination , chunk , 0 , taking )

return taking , nil
end

function QueueReader:readInto(destination, offset, count) 





if self . _closed then
return nil , "the reader is closed"
end
local from = integer_ ( offset == nil and 0 or offset , "Reader:readInto offset" , 2 )
local wanted = positive ( count == nil and DEFAULT_READ or count , "Reader:readInto count" , 2 )
local source = self . _source
local have = queueLength ( source )
if have == 0 then
return 0 , nil
end
local taking = math . min ( wanted , have )
local chunk = takeQueue ( source , taking )
do local __nuppT102=0; local  __nuppT108 ; local __nuppT109=false ; local __nuppT103,__nuppT104,__nuppT105=__nuppT40(function() do local __nuppT110= destination : reserveWrite ( from , wanted ) ; __nuppT108= __nuppT110 ; __nuppT102=1;  __nuppT109=true;  local lease=__nuppT108;
do
do local __nuppT111=0; local  __nuppT117 ; local __nuppT118=false ; local __nuppT112,__nuppT113,__nuppT114=__nuppT40(function() do local __nuppT119= lease : span ( ) ; __nuppT117= __nuppT119 ; __nuppT111=1;  __nuppT118=true;  local output=__nuppT117;
copyString ( output , chunk , 0 , taking )
do __nuppT118=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT36); local __nuppT115={}; local __nuppT116=0; if __nuppT111>=1 and __nuppT118 then  local __nuppT120,__nuppT121=__nuppT39(__nuppCleanup1,__nuppT117);  if not __nuppT120 then __nuppT116=__nuppT116+1; __nuppT115[__nuppT116]=__nuppT121 end; end; if not __nuppT112 then if __nuppT116>0 then __nuppT41(__nuppT37(__nuppT113,__nuppT115,1),0) else __nuppT41(__nuppT113,0) end end; if __nuppT116>0 then if __nuppT116>1 then __nuppT41(__nuppT37(__nuppT115[1],__nuppT115,2),0) else __nuppT41(__nuppT115[1],0) end end; if __nuppT113=="return" then  return "return",__nuppT114  end; end
end
do (function(__nuppT122,...)  __nuppT109=false; return __nuppT122:commit(...)  end)( lease , taking ) end

return "return",__nuppT35( taking , nil ) end; return "normal" end,__nuppT36); local __nuppT106={}; local __nuppT107=0; if __nuppT102>=1 and __nuppT109 then  local __nuppT123,__nuppT124=__nuppT39(__nuppCleanup2,__nuppT108);  if not __nuppT123 then __nuppT107=__nuppT107+1; __nuppT106[__nuppT107]=__nuppT124 end; end; if not __nuppT103 then if __nuppT107>0 then __nuppT41(__nuppT37(__nuppT104,__nuppT106,1),0) else __nuppT41(__nuppT104,0) end end; if __nuppT107>0 then if __nuppT107>1 then __nuppT41(__nuppT37(__nuppT106[1],__nuppT106,2),0) else __nuppT41(__nuppT106[1],0) end end; if __nuppT104=="return" then  return __nuppT42(__nuppT105,1,__nuppT105.n)  end; end
end






function QueueReader:transferTo(destination) 
if self . _closed then
return nil , "the reader is closed"
end
local source = self . _source
local count = queueLength ( source )
local rest = takeAllQueue ( source , count )
local ok , reason = destination : write ( rest )
if not ok then
return nil , reason
end

return # rest , nil
end













function Snapshot . close ( self ) 
local state = self
state . _closed = true
state . _bytes = ""
end

function HeapBuffer . close ( self ) 
local state = self
state . _closed = true
state . _length = 0
state . _capacity = 0

( state ) . _data = nil
end

function WriteLease . drop ( self ) 
do
local _raw = self
end
end

function BufferWriter . close ( self ) 
local state = self
state . _closed = true
end

function StringReader . close ( self ) 
local state = self
state . _closed = true
state . _bytes = ""
end

function QueueReader . close ( self ) 
local state = self
state . _closed = true
state . _source = nil
end






reserve = function ( self , minimum ) 
local state = self
if minimum <= state . _capacity then
return
end
local capacity = state . _capacity > 9007199254740991 / 2 and minimum or state . _capacity * 2
if capacity < minimum then
capacity = minimum
end
if capacity < 32 then
capacity = 32
end
local data = physical . allocateBytes ( capacity )
if state . _length > 0 then
physical . copy ( data , state . _data , state . _length )
end
state . _data = data
state . _capacity = capacity
end

bytesAt = function ( self , offset , count ) 
if count == 0 then
return ""
end

return physical . string ( ( self ) . _data + offset , count )
end

newView = function ( bytes ) 
return ( _G.setmetatable({ _bytes =  bytes ,  _closed =  false }, Snapshot) )
end

newReaderOver = function ( bytes ) 
return ( _G.setmetatable({ _bytes =  bytes ,  _at =  1 ,  _closed =  false }, StringReader) )
end

newWriterOver = function ( buffer ) 
return ( _G.setmetatable({ anchor =  buffer ,  _buffer =  buffer ,  _at =  0 ,  _closed =  false }, BufferWriter) )
end





local function queueLike ( value ) 
local kind = type ( value )
if kind == "table" then
return value . get ~= nil
elseif kind == "userdata" or kind == "cdata" then

local ok , getter = pcall ( function ( ) 
return value . get
end )

return ok and getter ~= nil
else
return false
end
end























newBuffer=function ( initial ) 
if initial ~= nil and type ( initial ) ~= "number" and type ( initial ) ~= "string" then
error ( "nupp: io.newBuffer initial value must be bytes or a capacity" , 2 )
end
local bytes = type ( initial ) == "string" and initial or ""
local capacity = type ( initial ) == "number" and integer_ ( initial , "io.newBuffer capacity" , 2 ) or # bytes
local data = physical . allocateBytes ( math . max ( capacity , 1 ) )
if # bytes > 0 then
physical . copy ( data , bytes , # bytes )
end

return ( _G.setmetatable({ _data =  data ,  _length =  # bytes ,  _capacity =  capacity ,  _closed =  false }, HeapBuffer) )
end ;__nuppExports["newBuffer"]=newBuffer



















newStringReader=function ( text ) 
if type ( text ) ~= "string" then
error ( "nupp: io.newStringReader needs a string" , 2 )
end

return newReaderOver ( text )
end ;__nuppExports["newStringReader"]=newStringReader











newQueueReader=function ( source ) 
if not queueLike ( source ) then
error ( "nupp: io.newQueueReader needs a byte queue" , 2 )
end

return ( _G.setmetatable({ _source =  source ,  _closed =  false }, QueueReader) )
end ;__nuppExports["newQueueReader"]=newQueueReader












readAll=function ( reader , maxBytes ) 
local limit = nil
if maxBytes ~= nil then
limit = positive ( maxBytes , "io.readAll maxBytes" , 2 )
end
local parts = { }
local total = 0
local failure = nil
while true do
local wanted = 65536
if limit ~= nil and limit - total + 1 < wanted then

wanted = limit - total + 1
end
local chunk , reason = reader : read ( wanted )
if chunk == nil then
failure = reason ?? "the reader is closed"
do break end
elseif chunk == "" then
do break end
end
total = total + # chunk
if limit ~= nil and total > limit then
failure = "the reader holds more than " .. tostring ( limit ) .. " bytes"
do break end
end
parts [ # parts + 1 ] = chunk
end
do __nuppDrop2( reader ) end
if failure ~= nil then
return nil , failure
end

return table . concat ( parts ) , nil
end ;__nuppExports["readAll"]=readAll

const validatePositive = positive ;__nuppExports["validatePositive"]=validatePositive
const validateInteger = integer_ ;__nuppExports["validateInteger"]=validateInteger
 end);if not __nuppOk then package.loaded["nupp.io.internal.bytes"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.internal.bytes"]=__nuppExports;return __nuppExports