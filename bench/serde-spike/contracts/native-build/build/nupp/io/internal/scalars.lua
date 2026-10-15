_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math"));local __nuppExports={};package.loaded["nupp.io.internal.scalars"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local storage = require ( "nupp.io.internal.bytes" )





local newBuffer = storage . newBuffer
local integer_ = storage . validateInteger
local physical = require ( "nupp.runtime.storage" )



local ScalarReader = {}
































































































local fill
local taken






local Scalars = {} Scalars.__index = Scalars






function Scalars:remaining() 
if self . _closed then
error ( "nupp: io.ScalarReader is closed" , 2 )
end
if self . _reader then
return nil
end
if self . _queue then
return # self . _pending + storage . queueLength ( self . _queue )
end

return # self . _pending
end

function Scalars:atEnd() 
if self . _closed then
error ( "nupp: io.ScalarReader is closed" , 2 )
end
local have , failure = fill ( self , 1 )
if failure then
error ( "nupp: io.ScalarReader source failed: " .. tostring ( failure ) , 2 )
end

return have < 1
end

function Scalars:skip(count) 
taken ( self , integer_ ( count , "io.ScalarReader count" , 2 ) )

return self
end

function Scalars:readBytes(count) 
return taken ( self , integer_ ( count , "io.ScalarReader count" , 2 ) )
end

function Scalars:readUint8() 
local raw = taken ( self , 1 )
local value = physical . decodeUint8 ( raw )

return (__nuppBitTobit( value )%4294967296)
end

function Scalars:readInt8() 
local raw = taken ( self , 1 )
local value = physical . decodeInt8 ( raw )

return __nuppBitTobit( value )
end

function Scalars:readUint16() 
local raw = taken ( self , 2 )
local value = physical . decodeUint16 ( raw )

return (__nuppBitTobit( value )%4294967296)
end

function Scalars:readInt16() 
local raw = taken ( self , 2 )
local value = physical . decodeInt16 ( raw )

return __nuppBitTobit( value )
end

function Scalars:readUint32() 
local raw = taken ( self , 4 )
local value = physical . decodeUint32 ( raw )

return (__nuppBitTobit( value )%4294967296)
end

function Scalars:readInt32() 
local raw = taken ( self , 4 )
local value = physical . decodeInt32 ( raw )

return __nuppBitTobit( value )
end

function Scalars:readUint64() 
local raw = taken ( self , 8 )
local value = physical . decodeUint64 ( raw )

return value
end

function Scalars:readInt64() 
local raw = taken ( self , 8 )
local value = physical . decodeInt64 ( raw )

return value
end

function Scalars:readFloat32() 
local raw = taken ( self , 4 )
local value = physical . decodeFloat32 ( raw )

return nupp . math . f32 . narrow ( value )
end

function Scalars:readFloat64() 
local raw = taken ( self , 8 )
local value = physical . decodeFloat64 ( raw )

return value
end





local ScalarWriter = {}


























































































local put


local ScalarSink = {} ScalarSink.__index = ScalarSink






function ScalarSink:writeBytes(bytes) 
if type ( bytes ) ~= "string" then
error ( "nupp: io.ScalarWriter bytes must be a string" , 2 )
end

put ( self , bytes )

return self
end

function ScalarSink:writeUint8(value) 
put ( self , physical . encodeUint8 ( value ) )

return self
end

function ScalarSink:writeInt8(value) 
put ( self , physical . encodeInt8 ( value ) )

return self
end

function ScalarSink:writeUint16(value) 
put ( self , physical . encodeUint16 ( value ) )

return self
end

function ScalarSink:writeInt16(value) 
put ( self , physical . encodeInt16 ( value ) )

return self
end

function ScalarSink:writeUint32(value) 
put ( self , physical . encodeUint32 ( value ) )

return self
end

function ScalarSink:writeInt32(value) 
put ( self , physical . encodeInt32 ( value ) )

return self
end

function ScalarSink:writeUint64(value) 
put ( self , physical . encodeUint64 ( value ) )

return self
end

function ScalarSink:writeInt64(value) 
put ( self , physical . encodeInt64 ( value ) )

return self
end

function ScalarSink:writeFloat32(value) 
put ( self , physical . encodeFloat32 ( value ) )

return self
end

function ScalarSink:writeFloat64(value) 
put ( self , physical . encodeFloat64 ( value ) )

return self
end

function ScalarSink:buffer() 
return self . _buffer
end

function ScalarSink:flush() 
if self . _closed then
return false , "the writer is closed"
end
if self . _writer then
return self . _writer : flush ( )
end

return true , nil
end



function Scalars . close ( self ) 
local state = self
local reader = state . _reader
state . _closed = true
state . _pending = ""
state . _queue = nil
state . _reader = nil
if reader then
reader : close ( )
end
end

function ScalarSink . close ( self ) 
local state = self
local writer = state . _writer
local buffer = state . _buffer
local ownsBuffer = state . _ownsBuffer
state . _closed = true
state . _writer = nil
state . _buffer = nil
if writer then
writer : close ( )
elseif ownsBuffer and buffer then
buffer : close ( )
end
end




fill = function ( self , need ) 
local state = self
local failure = nil
if state . _reader then
while # ( state . _pending ) < need do
local wanted = need - # ( state . _pending )
local chunk , reason = state . _reader : read ( wanted )
if chunk == nil then
failure = reason
do break end
elseif chunk == "" then
do break end
end
if # chunk > wanted then
error ( "nupp: io.Reader returned more bytes than requested" , 3 )
end
state . _pending = ( state . _pending ) .. ( chunk )
end
elseif state . _queue then
local want = need - # ( state . _pending )
local queue = state . _queue
local have = want > 0 and storage . queueLength ( queue ) or 0
if have > 0 then
local taking = math . min ( want , have )
local chunk = queue : get ( taking )
if type ( chunk ) ~= "string" or # chunk ~= taking then
error ( "nupp: io.ByteQueue returned the wrong byte count" , 3 )
end
state . _pending = ( state . _pending ) .. ( chunk )
end
end

return # ( state . _pending ) , failure
end


taken = function ( self , need ) 
local state = self
if state . _closed then
error ( "nupp: io.ScalarReader is closed" , 3 )
end
local have , failure = fill ( self , need )
if failure then
error ( "nupp: io.ScalarReader source failed: " .. tostring ( failure ) , 3 )
end
if have < need then
error ( ("nupp: io.ScalarReader needs %d bytes, has %d") : format ( need , have ) , 3 )
end
local out = ( state . _pending ) : sub ( 1 , need )
state . _pending = ( state . _pending ) : sub ( need + 1 )

return out
end


put = function ( self , bytes ) 
local state = self
if state . _closed then
error ( "nupp: io.ScalarWriter is closed" , 3 )
end
if state . _buffer then


local buffer = state . _buffer
buffer : setString ( bytes , buffer : length ( ) )

return
end
local ok , reason = state . _writer : write ( bytes )
if not ok then
error ( "nupp: io.ScalarWriter destination failed: " .. tostring ( reason ) , 3 )
end
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

local function readerLike ( value ) 
local kind = type ( value )
if kind ~= "table" and kind ~= "userdata" and kind ~= "cdata" then
return false
end
local ok , answer = pcall ( function ( ) 
return type ( value . read ) == "function"
and type ( value . readSpan ) == "function"
and type ( value . readInto ) == "function"
and type ( value . transferTo ) == "function"
and type ( value . close ) == "function"
end )

return ok and answer
end






local function openScalarReader ( source ) 
local pending = ""
local reader = nil
local queue = nil
local kind = type ( source )
if kind == "string" then
pending = source
elseif readerLike ( source ) then
reader = source
elseif kind == "table" and source . getString ~= nil then
pending = source : getString ( )
elseif queueLike ( source ) then
queue = source
else
error ( "nupp: io.newScalarReader needs bytes, a snapshot, a buffer, a reader or a byte queue" , 2 )
end

return ( _G.setmetatable({ _pending =  pending ,  _reader =  reader ,  _queue =  queue ,  _closed =  false }, Scalars) )
end

local function openScalarWriter ( destination ) 
local buffer = nil
local writer = nil
local ownsBuffer = false
if destination == nil then


buffer = newBuffer ( nil )
ownsBuffer = true
elseif type ( destination ) == "table" and destination . write ~= nil then
writer = destination
elseif type ( destination ) == "table" and destination . setString ~= nil then
buffer = destination
else
error ( "nupp: io.newScalarWriter needs a buffer, a writer, or nothing" , 2 )
end

return ( _G.setmetatable({ _buffer =  buffer ,  _writer =  writer ,  _ownsBuffer =  ownsBuffer ,  _closed =  false }, ScalarSink) )
end























const newScalarReader

= openScalarReader ;__nuppExports["newScalarReader"]=newScalarReader






















const newScalarWriter

= openScalarWriter ;__nuppExports["newScalarWriter"]=newScalarWriter
 end);if not __nuppOk then package.loaded["nupp.io.internal.scalars"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.internal.scalars"]=__nuppExports;return __nuppExports