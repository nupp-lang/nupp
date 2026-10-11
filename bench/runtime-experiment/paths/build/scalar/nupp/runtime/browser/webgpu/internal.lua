_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT24={}; local function __nuppT21(...) return {n=select("#",...),...} end; local __nuppT25,__nuppT26,__nuppT27,__nuppT28,__nuppT29,__nuppT30,__nuppT31,__nuppT32=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT22(value) return value end; local function __nuppT23(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT30({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT31(v.primary) for _,reason in __nuppT32(v.suppressed) do text=text.."\ncleanup: "..__nuppT31(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppExports={};package.loaded["nupp.runtime.browser.webgpu.internal"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()






















local response = require ( "nupp.runtime.browser.response" )
local cancellation = require ( "nupp.suspension.cancellation" )
local effects = require ( "nupp.runtime.browser.effects" )
local requestNosuspend = effects . request
local memory = require ( "nupp.runtime.browser.memory" )
local storage = require ( "nupp.runtime.storage" )
local array = require ( "nupp.mem.array" )
local span = require ( "nupp.mem.span" )

local shared = require ( "nupp.gpu.types" )
local api = require ( "nupp.gpu.api" )
local operations = require ( "nupp.gpu.operations" )

local layoutFacts = require ( "nupp.gpu.layoutfacts" ) . layoutFacts
local gpu = { }

gpu . Buffer = shared . Buffer

gpu . Kernel = shared . Kernel

gpu . ArtifactSet = shared . ArtifactSet


gpu . Shared = shared . Shared

gpu . Phases = shared . Phases












gpu.Binding = {} gpu.Binding.__index = gpu.Binding




















































gpu.Context = {} gpu.Context.__index = gpu.Context

























































































local function live ( context ) 
if context . _closed then
error ( "nupp: GPU context is closed" , 3 )
end
end

local function answerHandle ( answer , field ) 
if type ( answer ) ~= "table" then
error ( "nupp: browser GPU returned an invalid " .. field .. " handle" , 3 )
end
local handle = answer [ field ]
if type ( handle ) ~= "number" or handle < 1 or handle > 4294967295 or handle % 1 ~= 0 then
error ( "nupp: browser GPU returned an invalid " .. field .. " handle" , 3 )
end

return handle
end

local function isHandle ( value ) 
return type ( value ) == "number" and value >= 1 and value <= 4294967295 and value % 1 == 0
end

local function rememberHandle ( handles , handle , field ) 
for _ , value in ipairs ( handles ) do
if value == handle then
error ( "nupp: browser GPU returned a duplicate " .. field .. " handle" , 3 )
end
end
handles [ # handles + 1 ] = handle
end

local function orphanDestroy ( field , operation ) 
return function ( answer ) 
local value = type ( answer ) == "table" and answer . ok == true and answer . value or nil
local handle = type ( value ) == "table" and value [ field ] or nil
if not ( type ( handle ) == "number" and handle >= 1 and handle <= 4294967295 and handle % 1 == 0 ) then
return
end
requestNosuspend ( "gpu" , { operation = operation , [ field ] = handle , } , function ( _answer ) 
end )
end
end

local destroyOrphanBuffer = orphanDestroy ( "buffer" , "runtime-destroy-buffer" )
local destroyOrphanKernel = orphanDestroy ( "kernel" , "runtime-destroy-kernel" )

local function awaitLease ( lease , request ) 
local completed , problem = pcall ( response . await , "gpu" , request )
memory . releaseLease ( lease )
if not completed then
error ( problem , 0 )
end
end

local function forgetHandle ( handles , handle ) 
for index , value in ipairs ( handles ) do
if value == handle then
handles [ index ] = handles [ # handles ]
handles [ # handles ] = nil
return
end
end
end

local function contextdestroy ( state ) 
if state . _closed then
return
end
shared . markClosed ( state )
requestNosuspend (
"gpu" ,
{ operation = "runtime-close" , buffers = state . _buffers , kernels = state . _kernels , } ,
function ( _answer ) 
end
)
end

local contextdestroyNosuspend = contextdestroy

function gpu . Context . driver ( self ) 
live ( self )
return "webgpu"
end

function gpu . Context . buffer (
self ,
element ,
count
) 
return self : _allocate ( nil , operations . elementType ( element ) , count )
end

function gpu . Context . tensor (
self ,
element ,
shape
) 
local count , strides , dimensions = operations . denseShape ( shape )
return self : _allocate ( nil , operations . elementType ( element ) , count , dimensions , strides )
end

function gpu . Context . _allocate (
self ,
elementType ,
element ,
count ,
dimensions ,
strides
) 
local width = storage . sizeOf ( element )
live ( self )
if count < 1 or count > _G.math.floor(( 268435456 ) / ( width )) or count % 1 ~= 0 then
error ( "nupp: browser GPU buffer count is outside the portable limit" , 3 )
end
local answer = response . await (
"gpu" ,
{ operation = "runtime-create-buffer" , bytes = count * width , } ,
destroyOrphanBuffer
)

local handle = answerHandle ( answer , "buffer" )
rememberHandle ( self . _buffers , handle , "buffer" )

return ( _G.setmetatable({ _elementType =
nil ,  _anchor =
self ,  _context =
self ,  _handle =
handle ,  _width =
width ,  _state =
{ released = false } ,  _offset =
0 ,  _capacity =
count ,  _root =
true ,  _shape =
dimensions or { count } ,  _strides =
strides or { 1 } ,  count =
count }, shared.Buffer) )

end

function gpu . Context . compileGenerated (
self ,
artifacts ,
readonlyBuffers ,
writableBuffers ,
uniformBytes ,
threads
) 
live ( self )
local wgsl = artifacts . wgsl
local group = threads or 256
if wgsl == nil or # wgsl == 0 or # artifacts . entrypoint == 0 then
error ( "nupp: browser GPU kernels need WGSL" , 2 )
end
if readonlyBuffers < 0 or writableBuffers < 1 or readonlyBuffers + writableBuffers > 8 then
error ( "nupp: browser GPU kernels take up to eight storage buffers" , 2 )
end
local spans = readonlyBuffers + writableBuffers
if uniformBytes < 4 * ( 1 + 2 * spans )
or uniformBytes > 128
or uniformBytes % 4 ~= 0
or group < 1
or group > 256
then
error ( "nupp: browser GPU kernel has an invalid portable layout" , 2 )
end
local answer = response . await (
"gpu" ,
{
operation = "runtime-compile" ,
wgsl = wgsl ,
entrypoint = artifacts . entrypoint ,
readonly = readonlyBuffers ,
writable = writableBuffers ,
uniformBytes = uniformBytes ,
threads = group ,
} ,
destroyOrphanKernel
)

local handle = answerHandle ( answer , "kernel" )
rememberHandle ( self . _kernels , handle , "kernel" )

return ( _G.setmetatable({ _anchor =
self ,  _handle =
handle ,  _readonlyBuffers =
readonlyBuffers ,  _writableBuffers =
writableBuffers ,  _uniformBytes =
uniformBytes ,  _threads =
group ,  _released =
false }, shared.Kernel) )

end



local function boundStates ( binding , writing ) 
local readonly = binding . _kernel . _readonlyBuffers
local first = writing and readonly + 1 or 1
local last = writing and readonly + binding . _kernel . _writableBuffers or readonly
local states = { }
for index = first , last do
local state = binding . _bufferStates [ index ]
if state ~= nil then
states [ # states + 1 ] = state
end
end

return states
end

function gpu . Binding . setRead (
self ,
slot ,
bufferValue ,
matchCount
) 
local buffer = bufferValue
if self . _released or self . _kernel . _released then
error ( "nupp: browser GPU binding or kernel was released" , 2 )
end
if slot < 0
or slot >= self . _kernel . _readonlyBuffers
or buffer . _context ~= self . _anchor
or buffer . _state . released
then
error ( "nupp: browser GPU read binding is invalid" , 2 )
end
local _ , extent , dense = layoutFacts ( buffer . _shape , buffer . _strides , 2 )
if matchCount and ( not dense or extent ~= self . count ) then
error ( "nupp: browser GPU dispatch-indexed buffer has the wrong count" , 2 )
end
operations . refuseReadWriteAlias ( boundStates ( self , true ) , buffer . _state )
self . _read [ slot + 1 ] = buffer . _handle
self . _bufferStates [ slot + 1 ] = buffer . _state
self . _readCounts [ slot + 1 ] = extent
self . _readOffsets [ slot + 1 ] = buffer . _offset
end

function gpu . Binding . setWrite (
self ,
slot ,
bufferValue ,
matchCount
) 
local buffer = bufferValue
if self . _released or self . _kernel . _released then
error ( "nupp: browser GPU binding or kernel was released" , 2 )
end
if slot < 0
or slot >= self . _kernel . _writableBuffers
or buffer . _context ~= self . _anchor
or buffer . _state . released
then
error ( "nupp: browser GPU write binding is invalid" , 2 )
end
local _ , extent , dense , injective = layoutFacts ( buffer . _shape , buffer . _strides , 2 )
if not injective or extent ~= buffer . count then
error ( "nupp: browser GPU writable buffer is not a disjoint span" , 2 )
end
if matchCount and ( not dense or extent ~= self . count ) then
error ( "nupp: browser GPU dispatch-indexed buffer has the wrong count" , 2 )
end
operations . refuseReadWriteAlias ( boundStates ( self , false ) , buffer . _state )
self . _write [ slot + 1 ] = buffer . _handle
self . _bufferStates [ self . _kernel . _readonlyBuffers + slot + 1 ] = buffer . _state
self . _writeCounts [ slot + 1 ] = extent
self . _writeOffsets [ slot + 1 ] = buffer . _offset
end

function gpu . Binding . dispatchWords ( self , scalars ) 
if self . _released or self . _kernel . _released then
error ( "nupp: browser GPU binding or kernel was released" , 2 )
end
for index = 1 , self . _kernel . _readonlyBuffers do
if self . _read [ index ] == nil then
error ( "nupp: browser GPU binding is incomplete" , 2 )
end
end
for index = 1 , self . _kernel . _writableBuffers do
if self . _write [ index ] == nil then
error ( "nupp: browser GPU binding is incomplete" , 2 )
end
end
for _ , state in ipairs ( self . _bufferStates ) do
if state . released then
error ( "nupp: browser GPU binding contains a released buffer" , 2 )
end
end
local words = { (__nuppBitTobit( self . count )%4294967296) }
for _ , values in ipairs ( { self . _readCounts , self . _writeCounts , self . _readOffsets , self . _writeOffsets , scalars } ) do
for _ , value in ipairs ( values ) do
words [ # words + 1 ] = (__nuppBitTobit( value )%4294967296)
end
end
if # words * 4 ~= self . _kernel . _uniformBytes then
error ( "nupp: browser GPU uniform block has the wrong size" , 2 )
end
local allocation = array . scalar ( array . uint32 , # words )
do local __nuppT33=0; local  __nuppT39 ; local __nuppT40=false ; local __nuppT34,__nuppT35,__nuppT36=__nuppT26(function() do local __nuppT41= allocation : write ( ) ; __nuppT39= __nuppT41 ; __nuppT33=1;  __nuppT40=true;  local writable=__nuppT39;
for index , value in ipairs ( words ) do
writable :set( index , value )
end
do __nuppT40=false; __nuppDrop1( writable ) end
local pointer = allocation : read ( ) : ref ( )
local leasePointer = memory . lease
local lease = leasePointer ( pointer , # words * 4 )
awaitLease ( lease , {
operation = "runtime-dispatch" ,
kernel = self . _kernel . _handle ,
read = self . _read ,
write = self . _write ,
count = self . count ,
lease = lease ,
} ) end; return "normal" end,__nuppT22); local __nuppT37={}; local __nuppT38=0; if __nuppT33>=1 and __nuppT40 then  local __nuppT42,__nuppT43=__nuppT25(__nuppCleanup1,__nuppT39);  if not __nuppT42 then __nuppT38=__nuppT38+1; __nuppT37[__nuppT38]=__nuppT43 end; end; if not __nuppT34 then if __nuppT38>0 then __nuppT27(__nuppT23(__nuppT35,__nuppT37,1),0) else __nuppT27(__nuppT35,0) end end; if __nuppT38>0 then if __nuppT38>1 then __nuppT27(__nuppT23(__nuppT37[1],__nuppT37,2),0) else __nuppT27(__nuppT37[1],0) end end; if __nuppT35=="return" then  return __nuppT28(__nuppT36,1,__nuppT36.n)  end; end
end

function gpu . Context . upload (
self ,
bufferValue ,
source
) 
local buffer = bufferValue
live ( self )
local pointer , count = source : ref ( )
if buffer . _context ~= self or buffer . _state . released or not buffer : isDense ( ) then
error ( "nupp: browser GPU upload buffer is unavailable in this context" , 2 )
end
if count ~= buffer . count then
error ( "nupp: browser GPU upload span length does not match its buffer" , 2 )
end
local leasePointer = memory . lease




local lease = leasePointer ( pointer , count * buffer . _width )
awaitLease ( lease , {
operation = "runtime-upload" ,
buffer = buffer . _handle ,
offset = buffer . _offset * buffer . _width ,
bytes = count * buffer . _width ,
lease = lease ,
} )
end

function gpu . Context . enqueueDownload ( self , bufferValue ) 
local buffer = bufferValue
live ( self )
if buffer . _context ~= self or buffer . _state . released or not buffer : isDense ( ) then
error ( "nupp: browser GPU download buffer is unavailable in this context" , 2 )
end
response . await ( "gpu" , {
operation = "runtime-enqueue-download" ,
buffer = buffer . _handle ,
offset = buffer . _offset * buffer . _width ,
bytes = buffer . count * buffer . _width ,
} )
end

function gpu . Context . synchronize ( self ) 
live ( self )
response . await ( "gpu" , { operation = "runtime-synchronize" , } )
end

function gpu . Context . readDownloaded (
self ,
bufferValue ,
destination
) 
local buffer = bufferValue
live ( self )
local pointer , count = destination : ref ( )
if buffer . _context ~= self or buffer . _state . released or not buffer : isDense ( ) then
error ( "nupp: browser GPU download buffer is unavailable in this context" , 2 )
end
if count ~= buffer . count then
error ( "nupp: browser GPU download span length does not match its buffer" , 2 )
end
local leasePointer = memory . lease
local lease = leasePointer ( pointer , count * buffer . _width , true )
awaitLease ( lease , { operation = "runtime-read-download" , buffer = buffer . _handle , lease = lease , } )
end

function gpu . Context . download (
self ,
bufferValue ,
destination
) 
local buffer = bufferValue
self : enqueueDownload ( buffer )
self : synchronize ( )
self : readDownloaded ( buffer , destination )
end

function gpu . Context . _releaseBuffer ( self , buffer ) 
if self . _closed then
return
end
forgetHandle ( self . _buffers , buffer . _handle )
requestNosuspend (
"gpu" ,
{
operation = "runtime-destroy-buffer" ,
buffer = buffer . _handle ,
} ,
function ( _answer ) 
end
)
end

function gpu . Context . _releaseKernel ( self , handle ) 
if self . _closed then
return
end
forgetHandle ( self . _kernels , handle )
requestNosuspend ( "gpu" , { operation = "runtime-destroy-kernel" , kernel = handle , } , function ( _answer ) 
end )
end

function gpu . Binding . close ( self ) 
local binding = self
binding . _released = true
end

function gpu . Binding . dispatchPacked ( self , uniforms , uniformBytes ) 
error ( "nupp: linear32 GPU dispatch requires scalar words" , 2 )
end

function gpu . Context . bindKernel (
self ,
kernelValue ,
count
) 
local kernel = kernelValue
live ( self )
if kernel . _anchor ~= self then
error ( "nupp: browser GPU kernel belongs to another context" , 2 )
elseif kernel . _released then
error ( "nupp: browser GPU kernel was released" , 2 )
end
if count < 1 or count > 4294967295 or count % 1 ~= 0 then
error ( "nupp: GPU dispatch count must be from 1 through 4294967295" , 2 )
end

return ( _G.setmetatable({ _anchor =
self ,  _context =
self ,  _uniformBytes =
kernel . _uniformBytes ,  _readonlyBuffers =
kernel . _readonlyBuffers ,  _kernel =
kernel ,  _read =
{ } ,  _write =
{ } ,  _readCounts =
{ } ,  _writeCounts =
{ } ,  _readOffsets =
{ } ,  _writeOffsets =
{ } ,  _bufferStates =
{ } ,  _released =
false ,  count =
count }, gpu.Binding) )

end

function gpu . Context . close ( self ) 
local state = self
state . _destroy ( state )
end




function gpu . available ( ) 
local opened , answer = pcall ( response . await , "gpu" , { operation = "runtime-open" , } )
if not opened then
if cancellation . is ( answer ) then
error ( answer , 0 )
end
return false
end
if type ( answer ) ~= "table" or answer . driver ~= "webgpu" then
return false
end
requestNosuspend ( "gpu" , { operation = "runtime-close" , buffers = { } , kernels = { } , } , function ( _answer ) 
end )

return true
end

function gpu . open ( ) 
local answer = response . await ( "gpu" , { operation = "runtime-open" , } )
if type ( answer ) ~= "table" or answer . driver ~= "webgpu" then
error ( "nupp: browser GPU returned an invalid open response" , 2 )
end

return ( _G.setmetatable({ _destroy =  contextdestroyNosuspend ,  _closed =  false ,  _buffers =  { } ,  _kernels =  { } }, gpu.Context) )
end

const available = gpu . available ;__nuppExports["available"]=available
const open = gpu . open ;__nuppExports["open"]=open
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.webgpu.internal"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.webgpu.internal"]=__nuppExports;return __nuppExports