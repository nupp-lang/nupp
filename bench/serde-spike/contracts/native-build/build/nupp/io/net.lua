_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppModule = require("nupp.mem.indexed"); local __nuppT29={}; local function __nuppT26(...) return {n=select("#",...),...} end; local __nuppT30,__nuppT31,__nuppT32,__nuppT33,__nuppT34,__nuppT35,__nuppT36,__nuppT37=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT27(value) return value end; local function __nuppT28(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT35({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT36(v.primary) for _,reason in __nuppT37(v.suppressed) do text=text.."\ncleanup: "..__nuppT36(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.net\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.io.net\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.io.net\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.io.net\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.io.net\0runtime\0005") };























local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

const io = require ( "nupp.io" )





local suspension = require ( "nupp.suspension" )
local span = require ( "nupp.mem.span" )
local physical = require ( "nupp.runtime.storage" )
local spanStringValue = physical . string


local function spanString ( source ) 
const pointer = source : ref ( )

return spanStringValue ( pointer , source .count )
end

const contract = require ( "nupp.io.net.spi" )
local __nuppT3;do local __nuppT4,__nuppT5;repeat
const chosen = spi . select ( spi . load ("nupp.io.net.spi.Provider") )
if chosen ~= nil then
do  __nuppT3= chosen ;__nuppT4=true;break end
end
assert ( target . host == "native" , "nupp.io.net: no implementation is available" )
do  __nuppT3= _G . require ( "nupp.runtime.provider.nativenet" ) ;__nuppT4=true;break end
 until true; end; local provider = __nuppT3
local net = { }
const shared = require ( "nupp.io.net.types" )
local layering = require ( "nupp.io.net.internal" )

























































































net.Message = {} net.Message.__index = net.Message ;_G.nupp.__reflect.link(net.Message,__nuppT1[1],{ })



















const DEFAULT_HIGH_WATER = 1048576
const DEFAULT_CONNECT_MS = 30000
const READ_SIZE = 65536
const MAX_BACKLOG = 2147483647
const MAX_UINT32 = 4294967295



local function positive ( value , what , level ) 
if value < 1 or math . floor ( value ) ~= value then
error ( "nupp: " .. what .. " must be a positive integer" , level + 1 )
end

return value
end


local function answered ( value , why ) 
return value , io . toError ( why )
end



local function pathText ( value , what , level ) 
local given = value
if type ( given ) == "string" then
return given
end
if type ( given ) == "table" and type ( given . toString ) == "function" then
return given : toString ( )
end
error ( "nupp: " .. what .. " must be a string or a path" , level + 1 )
end


local function checkedPort ( value , what , level ) 
if value < 0 or value > 65535 or math . floor ( value ) ~= value then
error ( "nupp: " .. what .. " must be 0 through 65535" , level + 1 )
end

return value
end







local function await ( operation , ready , abandon ) 
if ready ( ) then
return
end
const chosen = provider
suspension . suspend ( operation , function ( resume , context ) 


local resumed = false
const source = context : source (
"nupp.io.net" ,
50 ,
function ( ) 
chosen : run ( 0 )
if not resumed and ready ( ) then
resumed = true
resume ( true )

return 1
end

return 0
end ,
function ( waitMs ) 
chosen : run ( waitMs )

return 0
end
)

return function ( ) 
source : release ( )
if abandon ~= nil then
abandon ( )
end
end
end )
end






local function readOnce ( chosen , handle , wanted ) 
local chunk = nil
local failure = nil
await ( "nupp.io.net read" , function ( ) 
const got , why = chosen : read ( handle , wanted )
if got == nil then
failure = why or "the connection failed"

return true
end
if # got > wanted then
failure = "the network provider returned more bytes than requested"

return true
end
if # got > 0 then
chunk = got

return true
end

return chosen : ended ( handle )
end )
if failure ~= nil then
return nil , failure
end

return chunk or ""
end






local function writeAll ( chosen , handle , highWater , bytes ) 


local waitingBelow = highWater
const hasRoom = function ( ) 
return chosen : pending ( handle ) < waitingBelow
end
local at = 1
while at <= # bytes do
local room = highWater - chosen : pending ( handle )
if room < 1 then
waitingBelow = highWater
await ( "nupp.io.net write" , hasRoom )
room = highWater - chosen : pending ( handle )
if room < 1 then
room = 1
end
end
const taking = math . min ( room , # bytes - at + 1 )
const took , why = chosen : write ( handle , bytes : sub ( at , at + taking - 1 ) )
if took == nil then
return false , why
end
if took < 0 or took > taking or math . floor ( took ) ~= took then
return false , "the network provider returned an invalid write count"
end
if took < 1 then



waitingBelow = chosen : pending ( handle )
if waitingBelow < 1 then
return false , "the network writer accepted no bytes without applying backpressure"
end
await ( "nupp.io.net write" , hasRoom )
else
at = at + took
end
end

return true
end






local function drain ( chosen , handle ) 
await ( "nupp.io.net flush" , function ( ) 
return ( chosen : pending ( handle ) == 0 and not chosen : shuttingDown ( handle ) ) or chosen : writeFailed ( handle )
end )
if chosen : writeFailed ( handle ) then
return false , "a write did not reach the platform"
end

return true
end










net.DirectionView = {} net.DirectionView.__index = net.DirectionView











function net.DirectionView:read(count) 
if self . _ended then
return nil , "the reader is closed"
end
if self . _writing then
return nil , "the view is write-only"
end

return readOnce ( self . _provider , self . _handle , positive ( count , "net.DirectionView read count" , 2 ) )
end


function net.DirectionView:readSpan(destination) 
const wanted = positive ( # destination , "net.DirectionView readSpan destination length" , 2 )
const chunk , why = self : read ( wanted )
if chunk == nil then
return nil , why
end
const __nuppT23= chunk ; const input = #__nuppT23
for index = 1 , # chunk do
destination :set( index , __nuppFfi.cast("const uint8_t *", __nuppT23 )[ 0 + __nuppModule._checkedIndex( input , index ,"span index out of bounds") -1] )
end

return # chunk
end


function net.DirectionView:readInto(destination, offset, count) 





const wanted = positive ( count or READ_SIZE , "net.DirectionView readInto count" , 2 )
const chunk , why = self : read ( wanted )
if chunk == nil then
return nil , why
end
const landed = # chunk
if landed > 0 then
const __nuppT25= chunk ; const input = #__nuppT25
do local __nuppT38=0; local  __nuppT44 ; local __nuppT45=false ; local __nuppT39,__nuppT40,__nuppT41=__nuppT31(function() do local __nuppT46= destination : reserveWrite ( offset or 0 , landed ) ; __nuppT44= __nuppT46 ; __nuppT38=1;  __nuppT45=true;  const lease=__nuppT44;
do
do local __nuppT47=0; local  __nuppT53 ; local __nuppT54=false ; local __nuppT48,__nuppT49,__nuppT50=__nuppT31(function() do local __nuppT55= lease : span ( ) ; __nuppT53= __nuppT55 ; __nuppT47=1;  __nuppT54=true;  const output=__nuppT53;
for index = 1 , landed do
output :set( index , __nuppFfi.cast("const uint8_t *", __nuppT25 )[ 0 + __nuppModule._checkedIndex( input , index ,"span index out of bounds") -1] )
end
do __nuppT54=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT27); local __nuppT51={}; local __nuppT52=0; if __nuppT47>=1 and __nuppT54 then  local __nuppT56,__nuppT57=__nuppT30(__nuppCleanup1,__nuppT53);  if not __nuppT56 then __nuppT52=__nuppT52+1; __nuppT51[__nuppT52]=__nuppT57 end; end; if not __nuppT48 then if __nuppT52>0 then __nuppT32(__nuppT28(__nuppT49,__nuppT51,1),0) else __nuppT32(__nuppT49,0) end end; if __nuppT52>0 then if __nuppT52>1 then __nuppT32(__nuppT28(__nuppT51[1],__nuppT51,2),0) else __nuppT32(__nuppT51[1],0) end end; if __nuppT49=="return" then  return "return",__nuppT50  end; end
end
do (function(__nuppT58,...)  __nuppT45=false; return __nuppT58:commit(...)  end)( lease , landed ) end end; return "normal" end,__nuppT27); local __nuppT42={}; local __nuppT43=0; if __nuppT38>=1 and __nuppT45 then  local __nuppT59,__nuppT60=__nuppT30(__nuppCleanup2,__nuppT44);  if not __nuppT59 then __nuppT43=__nuppT43+1; __nuppT42[__nuppT43]=__nuppT60 end; end; if not __nuppT39 then if __nuppT43>0 then __nuppT32(__nuppT28(__nuppT40,__nuppT42,1),0) else __nuppT32(__nuppT40,0) end end; if __nuppT43>0 then if __nuppT43>1 then __nuppT32(__nuppT28(__nuppT42[1],__nuppT42,2),0) else __nuppT32(__nuppT42[1],0) end end; if __nuppT40=="return" then  return __nuppT33(__nuppT41,1,__nuppT41.n)  end; end
end

return landed
end

function net.DirectionView:transferTo(destination) 
local moved = 0
while true do
const chunk , why = self : read ( READ_SIZE )
if chunk == nil then
return nil , why
end
if # chunk == 0 then
return moved
end
const wrote , wroteWhy = destination : write ( chunk )
if not wrote then
return nil , wroteWhy
end
moved = moved + ( # chunk )
end
end

function net.DirectionView:write(bytes) 
if self . _ended then
return false , "the writer is closed"
end
if not self . _writing then
return false , "the view is read-only"
end

return writeAll ( self . _provider , self . _handle , self . _highWater , bytes )
end

function net.DirectionView:writeSpan(source) 
const bytes = spanString ( source )
const wrote , why = self : write ( bytes )
if not wrote then
return nil , why
end

return # bytes
end




function net.DirectionView:flush() 
if self . _ended then
return false , "the writer is closed"
end
if not self . _writing then
return false , "the view is read-only"
end

return drain ( self . _provider , self . _handle )
end







function net.DirectionView:close() 
if self . _ended then
return
end
self . _ended = true
if self . _writing then









local _ , _drained = drain ( self . _provider , self . _handle )
local _ , _why = self . _provider : shutdownWrite ( self . _handle )
local _ , _sent = drain ( self . _provider , self . _handle )
end
end ;_G.nupp.__reflect.link(net.DirectionView,__nuppT1[2],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/net/spi.nupp\0Provider\0interface\0module\0001","nupp.io.net.spi") })







net.Stream = {} net.Stream.__index = net.Stream







function net.Stream:isReleased() 
return self . _closed
end





function net.Stream:isEnded() 
if self . _closed then
return true
end

return self . _provider : ended ( self . _handle )
end





function net.Stream:pending() 
if self . _closed then
return 0
end

return self . _provider : pending ( self . _handle )
end






function net.Stream:peerAddress() 
if self . _closed then
return nil
end

return self . _provider : address ( self . _handle , true )
end



function net.Stream:localAddress() 
if self . _closed then
return nil
end

return self . _provider : address ( self . _handle , false )
end











function net.Stream:setNoDelay(enable) 
if self . _closed then
return false , io . toError ( "the connection is closed" )
end

return answered ( self . _provider : noDelay ( self . _handle , enable ) )
end














function net.Stream:setKeepAlive(enable, delayMs) 
if self . _closed then
return false , io . toError ( "the connection is closed" )
end
const delay = positive ( delayMs , "net.Stream setKeepAlive delayMs" , 2 )
if delay > MAX_UINT32 then
error ( "nupp: net.Stream setKeepAlive delayMs is too large" , 2 )
end

return answered ( self . _provider : keepAlive ( self . _handle , enable , delay ) )
end










function net.Stream:read(count) 
if self . _closed then
return nil , "the connection is closed"
end

return readOnce ( self . _provider , self . _handle , positive ( count , "net.Stream read count" , 2 ) )
end







function net.Stream:readSpan(destination) 
const wanted = positive ( # destination , "net.Stream readSpan destination length" , 2 )
const chunk , why = self : read ( wanted )
if chunk == nil then
return nil , why
end
const __nuppT75= chunk ; const input = #__nuppT75
for index = 1 , # chunk do
destination :set( index , __nuppFfi.cast("const uint8_t *", __nuppT75 )[ 0 + __nuppModule._checkedIndex( input , index ,"span index out of bounds") -1] )
end

return # chunk
end









function net.Stream:readInto(destination, offset, count) 





const wanted = positive ( count or READ_SIZE , "net.Stream readInto count" , 2 )
const chunk , why = self : read ( wanted )
if chunk == nil then
return nil , why
end
const landed = # chunk
if landed > 0 then
const __nuppT77= chunk ; const input = #__nuppT77
do local __nuppT78=0; local  __nuppT84 ; local __nuppT85=false ; local __nuppT79,__nuppT80,__nuppT81=__nuppT31(function() do local __nuppT86= destination : reserveWrite ( offset or 0 , landed ) ; __nuppT84= __nuppT86 ; __nuppT78=1;  __nuppT85=true;  const lease=__nuppT84;
do
do local __nuppT87=0; local  __nuppT93 ; local __nuppT94=false ; local __nuppT88,__nuppT89,__nuppT90=__nuppT31(function() do local __nuppT95= lease : span ( ) ; __nuppT93= __nuppT95 ; __nuppT87=1;  __nuppT94=true;  const output=__nuppT93;
for index = 1 , landed do
output :set( index , __nuppFfi.cast("const uint8_t *", __nuppT77 )[ 0 + __nuppModule._checkedIndex( input , index ,"span index out of bounds") -1] )
end
do __nuppT94=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT27); local __nuppT91={}; local __nuppT92=0; if __nuppT87>=1 and __nuppT94 then  local __nuppT96,__nuppT97=__nuppT30(__nuppCleanup1,__nuppT93);  if not __nuppT96 then __nuppT92=__nuppT92+1; __nuppT91[__nuppT92]=__nuppT97 end; end; if not __nuppT88 then if __nuppT92>0 then __nuppT32(__nuppT28(__nuppT89,__nuppT91,1),0) else __nuppT32(__nuppT89,0) end end; if __nuppT92>0 then if __nuppT92>1 then __nuppT32(__nuppT28(__nuppT91[1],__nuppT91,2),0) else __nuppT32(__nuppT91[1],0) end end; if __nuppT89=="return" then  return "return",__nuppT90  end; end
end
do (function(__nuppT98,...)  __nuppT85=false; return __nuppT98:commit(...)  end)( lease , landed ) end end; return "normal" end,__nuppT27); local __nuppT82={}; local __nuppT83=0; if __nuppT78>=1 and __nuppT85 then  local __nuppT99,__nuppT100=__nuppT30(__nuppCleanup2,__nuppT84);  if not __nuppT99 then __nuppT83=__nuppT83+1; __nuppT82[__nuppT83]=__nuppT100 end; end; if not __nuppT79 then if __nuppT83>0 then __nuppT32(__nuppT28(__nuppT80,__nuppT82,1),0) else __nuppT32(__nuppT80,0) end end; if __nuppT83>0 then if __nuppT83>1 then __nuppT32(__nuppT28(__nuppT82[1],__nuppT82,2),0) else __nuppT32(__nuppT82[1],0) end end; if __nuppT80=="return" then  return __nuppT33(__nuppT81,1,__nuppT81.n)  end; end
end

return landed
end






function net.Stream:transferTo(destination) 
local moved = 0
while true do
const chunk , why = self : read ( READ_SIZE )
if chunk == nil then
return nil , why
end
if # chunk == 0 then
return moved
end
const wrote , wroteWhy = destination : write ( chunk )
if not wrote then
return nil , wroteWhy
end
moved = moved + ( # chunk )
end
end










function net.Stream:write(bytes) 
if self . _closed then
return false , "the connection is closed"
end
if self . _shutdown then
return false , "the sending half is closed"
end

return writeAll ( self . _provider , self . _handle , self . _highWater , bytes )
end






function net.Stream:writeSpan(source) 
const bytes = spanString ( source )
const wrote , why = self : write ( bytes )
if not wrote then
return nil , why
end

return # bytes
end













function net.Stream:flush() 
if self . _closed then
return false , "the connection is closed"
end
return drain ( self . _provider , self . _handle )
end










function net.Stream:shutdownWrite() 
if self . _closed then
return false , io . toError ( "the connection is closed" )
end
if self . _shutdown then
return true
end




const drained , drainWhy = drain ( self . _provider , self . _handle )
if not drained then
return false , io . toError ( drainWhy )
end
const done , why = self . _provider : shutdownWrite ( self . _handle )
if not done then
return false , io . toError ( why )
end
self . _shutdown = true

return answered ( drain ( self . _provider , self . _handle ) )
end






function net.Stream:asReader() 
return ( _G.setmetatable({ _provider =
self . _provider ,  _handle =
self . _handle ,  _writing =
false ,  _ended =
false ,  _highWater =
self . _highWater }, net.DirectionView) )

end







function net.Stream:asWriter() 
return ( _G.setmetatable({ _provider =
self . _provider ,  _handle =
self . _handle ,  _writing =
true ,  _ended =
false ,  _highWater =
self . _highWater }, net.DirectionView) )

end




function net.Stream:close() 
if self . _closed then
return
end
self . _closed = true
self . _provider : closeStream ( self . _handle )
end ;_G.nupp.__reflect.link(net.Stream,__nuppT1[3],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/net/spi.nupp\0Provider\0interface\0module\0001","nupp.io.net.spi") })








net.Listener = {} net.Listener.__index = net.Listener







function net.Listener:port() 
if self . _closed then
return - 1
end

return self . _provider : listenerPort ( self . _handle )
end


function net.Listener:isReleased() 
return self . _closed
end





function net.Listener:accept() 
if self . _closed then
return nil , io . toError ( "the listener is closed" )
end
local handle = nil
local failure = nil
await ( "nupp.io.net accept" , function ( ) 
if self . _closed then
failure = "the listener is closed"

return true
end
const taken , why = self . _provider : accept ( self . _handle )
if taken ~= nil then
handle = taken

return true
end
if why ~= nil then
failure = why

return true
end

return false
end )
if failure ~= nil then
return nil , io . toError ( failure )
end

return ( _G.setmetatable({ _provider =
self . _provider ,  _handle =
handle ,  _closed =
false ,  _shutdown =
false ,  _highWater =
self . _highWater }, net.Stream) )

end




function net.Listener:close() 
if self . _closed then
return
end
self . _closed = true
self . _provider : closeListener ( self . _handle )
end ;_G.nupp.__reflect.link(net.Listener,__nuppT1[4],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/net/spi.nupp\0Provider\0interface\0module\0001","nupp.io.net.spi") })







net.Datagram = {} net.Datagram.__index = net.Datagram





function net.Datagram:port() 
if self . _closed then
return - 1
end

return self . _provider : datagramPort ( self . _handle )
end


function net.Datagram:isReleased() 
return self . _closed
end













function net.Datagram:receiveFrom(destination, maximum) 
if self . _closed then
return nil , io . toError ( "the datagram socket is closed" )
end
const wanted = positive ( maximum , "net.Datagram receiveFrom maximum" , 2 )
local bytes = nil
local host = nil
local peerPort = nil
local cut = nil
local failure = nil
await ( "nupp.io.net receive" , function ( ) 
const got , from , at , truncated , why = self . _provider : receive ( self . _handle , wanted )
if why ~= nil then
failure = why

return true
end
if got == nil then
return false
end
local rawHost = from
local rawPort = at
local rawTruncated = truncated
if type ( rawHost ) ~= "string"
or rawHost == ""
or type ( rawPort ) ~= "number"
or rawPort < 0
or rawPort > 65535
or math . floor ( rawPort ) ~= rawPort
or type ( rawTruncated ) ~= "boolean"
or # got > wanted
then
failure = "the network provider returned an invalid datagram"

return true
end
bytes = got
host = from
peerPort = at
cut = truncated

return true
end )
if failure ~= nil then
return nil , io . toError ( failure )
end
const landed = # ( bytes or "" )
if landed > 0 then
const input = span . fromString ( bytes or "" )
do local __nuppT118=0; local  __nuppT124 ; local __nuppT125=false ; local __nuppT119,__nuppT120,__nuppT121=__nuppT31(function() do local __nuppT126= destination : reserveWrite ( 0 , landed ) ; __nuppT124= __nuppT126 ; __nuppT118=1;  __nuppT125=true;  const lease=__nuppT124;
do
do local __nuppT127=0; local  __nuppT133 ; local __nuppT134=false ; local __nuppT128,__nuppT129,__nuppT130=__nuppT31(function() do local __nuppT135= lease : span ( ) ; __nuppT133= __nuppT135 ; __nuppT127=1;  __nuppT134=true;  const output=__nuppT133;
for index = 1 , landed do
output :set( index , input :get( index ) )
end
do __nuppT134=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT27); local __nuppT131={}; local __nuppT132=0; if __nuppT127>=1 and __nuppT134 then  local __nuppT136,__nuppT137=__nuppT30(__nuppCleanup1,__nuppT133);  if not __nuppT136 then __nuppT132=__nuppT132+1; __nuppT131[__nuppT132]=__nuppT137 end; end; if not __nuppT128 then if __nuppT132>0 then __nuppT32(__nuppT28(__nuppT129,__nuppT131,1),0) else __nuppT32(__nuppT129,0) end end; if __nuppT132>0 then if __nuppT132>1 then __nuppT32(__nuppT28(__nuppT131[1],__nuppT131,2),0) else __nuppT32(__nuppT131[1],0) end end; if __nuppT129=="return" then  return "return",__nuppT130  end; end
end
do (function(__nuppT138,...)  __nuppT125=false; return __nuppT138:commit(...)  end)( lease , landed ) end end; return "normal" end,__nuppT27); local __nuppT122={}; local __nuppT123=0; if __nuppT118>=1 and __nuppT125 then  local __nuppT139,__nuppT140=__nuppT30(__nuppCleanup2,__nuppT124);  if not __nuppT139 then __nuppT123=__nuppT123+1; __nuppT122[__nuppT123]=__nuppT140 end; end; if not __nuppT119 then if __nuppT123>0 then __nuppT32(__nuppT28(__nuppT120,__nuppT122,1),0) else __nuppT32(__nuppT120,0) end end; if __nuppT123>0 then if __nuppT123>1 then __nuppT32(__nuppT28(__nuppT122[1],__nuppT122,2),0) else __nuppT32(__nuppT122[1],0) end end; if __nuppT120=="return" then  return __nuppT33(__nuppT121,1,__nuppT121.n)  end; end
end

return ( _G.setmetatable({ length =
landed ,  address =
{ host = host or "" , port = peerPort or 0 } ,  truncated =
cut or false }, net.Message) )

end











function net.Datagram:sendTo(address, bytes) 
if self . _closed then
return false , io . toError ( "the datagram socket is closed" )
end

return answered (
self . _provider : sendTo (
self . _handle ,
address . host ,
checkedPort ( address . port , "net.Datagram sendTo port" , 2 ) ,
bytes
)
)
end





function net.Datagram:setBroadcast(enable) 
if self . _closed then
return false , io . toError ( "the datagram socket is closed" )
end

return answered ( self . _provider : broadcast ( self . _handle , enable ) )
end






function net.Datagram:setMulticastTTL(ttl) 
if self . _closed then
return false , io . toError ( "the datagram socket is closed" )
end
if ttl < 1 or ttl > 255 or math . floor ( ttl ) ~= ttl then
error ( "nupp: a multicast hop limit must be 1 through 255" , 2 )
end

return answered ( self . _provider : multicastTtl ( self . _handle , ttl ) )
end





function net.Datagram:setMulticastLoop(enable) 
if self . _closed then
return false , io . toError ( "the datagram socket is closed" )
end

return answered ( self . _provider : multicastLoop ( self . _handle , enable ) )
end






function net.Datagram:joinMulticast(group, interfaceAddress) 
if self . _closed then
return false , io . toError ( "the datagram socket is closed" )
end

return answered ( self . _provider : membership ( self . _handle , group , interfaceAddress or "" , true ) )
end


function net.Datagram:leaveMulticast(group, interfaceAddress) 
if self . _closed then
return false , io . toError ( "the datagram socket is closed" )
end

return answered ( self . _provider : membership ( self . _handle , group , interfaceAddress or "" , false ) )
end


function net.Datagram:close() 
if self . _closed then
return
end
self . _closed = true
self . _provider : closeDatagram ( self . _handle )
end ;_G.nupp.__reflect.link(net.Datagram,__nuppT1[5],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/net/spi.nupp\0Provider\0interface\0module\0001","nupp.io.net.spi") })












function net . bind ( options ) 
const chosen = provider
const bound = checkedPort ( options . port , "net.bind port" , 2 )
const handle , why = chosen : bindDatagram ( options . host , bound , options . reusePort or false )
if handle == nil then
return nil , io . toError ( why )
end

return ( _G.setmetatable({ _provider =  chosen ,  _handle =  handle ,  _closed =  false }, net.Datagram) )
end







function net . listen ( options ) 
const chosen = provider
const backlog = positive ( options . backlog or 128 , "net.listen backlog" , 2 )
if backlog > 2147483647 then
error ( "nupp: net.listen backlog is too large" , 2 )
end
local handle = nil
local why = nil
if options . path ~= nil then
if options . host ~= nil or options . port ~= nil then
error ( "nupp: net.listen takes a path or a host and port, not both" , 2 )
end
handle , why = chosen : listenPath ( pathText ( options . path or "" , "net.listen path" , 2 ) , backlog )
else
if options . host == nil or options . port == nil then
error ( "nupp: net.listen needs a path, or a host and a port" , 2 )
end
handle , why = chosen : listen (
options . host or "" ,
checkedPort ( options . port or 0 , "net.listen port" , 2 ) ,
backlog ,
options . reusePort or false
)
end
if handle == nil then
return nil , io . toError ( why )
end

return ( _G.setmetatable({ _provider =  chosen ,  _handle =  handle ,  _closed =  false ,  _highWater =  DEFAULT_HIGH_WATER }, net.Listener) )
end







function net . connect ( options ) 
const chosen = provider
const deadline = positive ( options . timeoutMs or 30000 , "net.connect timeoutMs" , 2 )



const highWater = positive ( options . sendHighWater or 1048576 , "net.connect sendHighWater" , 2 )
local request = nil
local why = nil
if options . path ~= nil then
if options . host ~= nil or options . port ~= nil then
error ( "nupp: net.connect takes a path or a host and port, not both" , 2 )
end
request , why = chosen : connectPath ( pathText ( options . path or "" , "net.connect path" , 2 ) , deadline )
else
if options . host == nil or options . port == nil then
error ( "nupp: net.connect needs a path, or a host and a port" , 2 )
end
request , why = chosen : connect (
options . host or "" ,
checkedPort ( options . port or 0 , "net.connect port" , 2 ) ,
deadline
)
end
if request == nil then
return nil , io . toError ( why )
end
local requestOpen = true

local function closeRequest ( ) 
if requestOpen then
requestOpen = false
chosen : closeConnect ( request )
end
end

local handle = nil
local failure = nil
local completed , problem = pcall ( function ( ) 
await (
"nupp.io.net connect" ,
function ( ) 
const ready , reason = chosen : connectPoll ( request )
if ready ~= nil then
handle = ready

return true
end
if reason ~= nil then
failure = reason

return true
end

return false
end ,
closeRequest
)
end )
closeRequest ( )
if not completed then
error ( problem , 0 )
end
if failure ~= nil then
return nil , io . toError ( failure )
end

return ( _G.setmetatable({ _provider =
chosen ,  _handle =
handle ,  _closed =
false ,  _shutdown =
false ,  _highWater =
highWater }, net.Stream) )

end














local function takeStreamHandle ( source ) 


local stream = source
if stream . _closed then
error ( "nupp: the connection is closed" , 2 )
end
stream . _closed = true

return stream . _handle
end

layering . takeStreamHandle = takeStreamHandle



function net . pump ( timeoutMs ) 
if timeoutMs < 0 or math . floor ( timeoutMs ) ~= timeoutMs then
error ( "nupp: net.pump timeoutMs must be a non-negative integer" , 2 )
end
provider : run ( timeoutMs )
end

local __nuppExportValue= net ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.net"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.net"]=__nuppExports;return __nuppExports