_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.provider.nativegpu"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local native = require ( "nupp.runtime.native" )
local suspension = require ( "nupp.suspension" )
local layoutFacts = require ( "nupp.gpu.layoutfacts" ) . layoutFacts
local span = require ( "nupp.mem.span" )
local ffi = native . ffi
local C = native . C
native . ffi . cdef [[
int32_t nuppNativeGpuCostsOutput(const uint8_t *, size_t);
int32_t nuppNativeGpuCostsEnabled(void);
int32_t nuppNativeGpuCostMetadata(uint64_t, uint64_t, int32_t, const uint8_t *, size_t);
int32_t nuppNativeGpuContextCreate(uint64_t *);
int32_t nuppNativeGpuContextDescription(uint64_t, uint8_t *, size_t, size_t *);
int32_t nuppNativeGpuContextRelease(uint64_t);
int32_t nuppNativeGpuBufferCreate(uint64_t, uint64_t, uint64_t *);
int32_t nuppNativeGpuBufferRelease(uint64_t, uint64_t);
int32_t nuppNativeGpuBufferUpload(uint64_t, uint64_t, uint64_t, const void *, size_t);
int32_t nuppNativeGpuKernelCreate(
    uint64_t, const uint8_t *, size_t, const char *, size_t,
    uint32_t, uint32_t, uint64_t, uint32_t, uint32_t, uint32_t, uint64_t *);
int32_t nuppNativeGpuKernelRelease(uint64_t, uint64_t);
int32_t nuppNativeGpuBindingsCreate(uint64_t, uint64_t, uint64_t *);
int32_t nuppNativeGpuBindingsRelease(uint64_t, uint64_t);
int32_t nuppNativeGpuBindingsSetBuffer(
    uint64_t, uint64_t, int32_t, uint32_t, uint64_t, uint64_t, uint64_t);
int32_t nuppNativeGpuDispatch(
    uint64_t, uint64_t, uint32_t, uint32_t, uint32_t, const uint8_t *, size_t);
int32_t nuppNativeGpuDownloadQueue(uint64_t, uint64_t, uint64_t, uint64_t);
int32_t nuppNativeGpuSynchronize(uint64_t);
int32_t nuppNativeGpuSynchronizeReady(uint64_t, uint32_t *);
int32_t nuppNativeGpuDownloadRead(
    uint64_t, uint64_t, uint64_t, uint64_t, void *, size_t);
]]

local shared = require ( "nupp.gpu.types" )
local api = require ( "nupp.gpu.api" )
local operations = require ( "nupp.gpu.operations" )

local gpu = { }

gpu . Buffer = shared . Buffer

gpu . Kernel = shared . Kernel

gpu . ArtifactSet = shared . ArtifactSet


gpu . Shared = shared . Shared

gpu . Phases = shared . Phases












gpu.Binding = {} gpu.Binding.__index = gpu.Binding























































gpu.Context = {} gpu.Context.__index = gpu.Context






















































































local function live ( self ) 
if self . _closed or self . _handle == nil then
error ( "nupp: GPU context is closed" , 3 )
end
return self . _handle
end

local function whole ( value , what , minimum , maximum ) 
if type ( value ) ~= "number" or value ~= math . floor ( value ) or value < minimum or value > maximum then
error ( ("nupp: GPU %s must be an integer from %d through %d") : format ( what , minimum , maximum ) , 3 )
end

return value
end




local function uploadTyped (
context ,
buffer ,
source ,
offset ,
bytes
) 
local call = C . nuppNativeGpuBufferUpload







return call ( context , buffer , offset , source , bytes )
end

local function readTyped (
context ,
buffer ,
destination ,
offset ,
bytes
) 
local call = C . nuppNativeGpuDownloadRead








return call ( context , buffer , offset , bytes , destination , bytes )
end


const WORKGROUPS_PER_DIMENSION = 65535






local function dispatchNative (
context ,
bindings ,
count ,
threads ,
uniforms ,
bytes
) 
local call = C . nuppNativeGpuDispatch








local groups = math . ceil ( count / threads )
if groups <= 65535 then
return call ( context , bindings , count , 1 , 1 , uniforms , bytes )
end
local rows = math . ceil ( groups / 65535 )

return call ( context , bindings , 65535 * threads , rows , 1 , uniforms , bytes )
end

local contextdestroy = require ( "nupp.runtime.provider.nativegpurelease" ) . destroy


function gpu . costsOutput ( path ) 
native . requireFeature ( 4 , "GPU cost instrumentation" )
native . succeeded ( C . nuppNativeGpuCostsOutput ( path , path and # path or 0 ) , 2 )
end

local function costMetadata ( context , handle , kernel , metadata ) 
if C . nuppNativeGpuCostsEnabled ( ) == 0 then
return
end
local json = require ( "nupp.codec.json" )
if kernel then
metadata . readonlyNames = json . asArray ( metadata . readonlyNames or { } )
metadata . writableNames = json . asArray ( metadata . writableNames or { } )
end
local encoded = json . encode ( metadata )
native . succeeded ( C . nuppNativeGpuCostMetadata ( context , handle , kernel and 1 or 0 , encoded , # encoded ) , 2 )
end

local function costLayout (
context ,
handle ,
shape ,
strides ,
width ,
offset ,
count
) 
if C . nuppNativeGpuCostsEnabled ( ) == 0 then
return
end
costMetadata ( context , handle , false , {
shape = shape ,
strides = strides ,
elementBytes = width ,
elementOffset = offset ,
count = count ,
conversion = "none: typed span bytes preserved"
} )
end

function gpu . Context . driver ( self ) 
local length = ffi . new ( "size_t[1]" )
local handle = live ( self )
local probed = C . nuppNativeGpuContextDescription ( handle , nil , 0 , length )
if probed ~= native . BUFFER_TOO_SMALL then
native . succeeded ( probed , 2 )
end
local output = ffi . new ( "uint8_t[?]" , length [ 0 ] )
native . succeeded ( C . nuppNativeGpuContextDescription ( handle , output , length [ 0 ] , length ) , 2 )

return ffi . string ( output , length [ 0 ] )
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
count = whole ( count , "buffer count" , 0 , 4294967295 )
local width = ffi . sizeof ( element )
if width <= 0 or count == 0 or count > _G.math.floor(( 4294967295 ) / ( width )) then
error ( "nupp: GPU buffer must contain 1 through 4294967295 bytes" , 3 )
end
local output = ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppNativeGpuBufferCreate ( live ( self ) , width * count , output ) , 3 )
local handle = output [ 0 ]
costMetadata ( live ( self ) , handle , false , { format = tostring ( element ) , elementBytes = width , shape = { count } } )

return ( _G.setmetatable({ _elementType =
nil ,  _anchor =
self ,  _context =
self ,  _handle =
handle ,  _width =
width ,  _offset =
0 ,  _capacity =
count ,  _root =
true ,  _state =
{ released = false } ,  _shape =
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
readonlyBuffers = whole ( readonlyBuffers , "read buffer count" , 0 , 16 )
writableBuffers = whole ( writableBuffers , "write buffer count" , 1 , 16 )
uniformBytes = whole ( uniformBytes , "uniform byte count" , 0 , 128 )
local group = whole ( threads or 256 , "thread group" , 1 , 1024 )
if uniformBytes % 4 ~= 0 then
error ( "nupp: GPU uniform block must be from 0 through 128 bytes and aligned to four bytes" , 2 )
end
local spans = readonlyBuffers + writableBuffers
if uniformBytes < 4 * ( 1 + 2 * spans ) then
error ( "nupp: GPU uniform block does not contain the generated span header" , 2 )
end
local artifact = artifacts
local spirv , entrypoint = artifact . spirv , artifact . entrypoint
if type ( spirv ) ~= "string" or # spirv == 0 or type ( entrypoint ) ~= "string" or # entrypoint == 0 then
error ( "nupp: native GPU kernels need non-empty SPIR-V and an entrypoint" , 2 )
end
local output = ffi . new ( "uint64_t[1]" )
native . succeeded (
C . nuppNativeGpuKernelCreate (
live ( self ) ,
spirv ,
# spirv ,
entrypoint ,
# entrypoint ,
readonlyBuffers ,
writableBuffers ,
uniformBytes ,
group ,
1 ,
1 ,
output
) ,
2
)
local handle = output [ 0 ]
local identity = artifacts
costMetadata ( live ( self ) , handle , true , {
sourceFile = identity . sourceFile ,
sourceLine = identity . sourceLine ,
artifactId = identity . artifactId ,
readonlyNames = identity . readonlyNames ,
writableNames = identity . writableNames ,
entrypoint = entrypoint
} )

return ( _G.setmetatable({ _anchor =
self ,  _handle =
handle ,  _uniformBytes =
uniformBytes ,  _readonlyBuffers =
readonlyBuffers ,  _writableBuffers =
writableBuffers ,  _threads =
group ,  _released =
false }, shared.Kernel) )

end

function gpu . Context . _releaseBuffer ( self , buffer ) 
if self . _closed or self . _handle == nil then
return
end
native . succeeded ( C . nuppNativeGpuBufferRelease ( self . _handle , buffer . _handle ) , 3 )
end

function gpu . Context . _releaseKernel ( self , handle ) 
if self . _closed or self . _handle == nil then
return
end
native . succeeded ( C . nuppNativeGpuKernelRelease ( self . _handle , handle ) , 3 )
end

function gpu . Binding . close ( self ) 
local binding = self
if binding . _released then
return
end
binding . _released = true
local context = binding . _anchor
if context . _closed or context . _handle == nil then
return
end
native . succeeded ( C . nuppNativeGpuBindingsRelease ( context . _handle , binding . _handle ) , 2 )
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
slot = whole ( slot , "read binding slot" , 0 , 15 )
if self . _released or self . _kernel . _released then
error ( "nupp: GPU binding was released" , 2 )
end
if buffer . _context ~= self . _anchor or buffer . _state . released then
error ( "nupp: GPU read buffer is unavailable in this context" , 2 )
end
local _ , extent , dense = layoutFacts ( buffer . _shape , buffer . _strides , 2 )
if matchCount and not dense then
error ( "nupp: dispatch-indexed GPU buffers must be dense" , 2 )
end
if matchCount and extent ~= self . count then
error ( "nupp: a dispatch-indexed buffer must hold one element per dispatched thread" , 2 )
end
if slot < 0 or slot >= self . _readonlyBuffers then
error ( "nupp: read binding slot is outside the compiled kernel" , 2 )
end
operations . refuseReadWriteAlias ( boundStates ( self , true ) , buffer . _state )
costLayout (
self . _context ,
buffer . _handle ,
buffer . _shape ,
buffer . _strides ,
buffer . _width ,
buffer . _offset ,
buffer . count
)
native . succeeded (
C . nuppNativeGpuBindingsSetBuffer (
self . _context ,
self . _handle ,
0 ,
slot ,
buffer . _handle ,
0 ,
buffer . _capacity * buffer . _width
) ,
2
)
self . _read [ slot + 1 ] = 1
self . _bufferStates [ slot + 1 ] = buffer . _state
self . _spanCounts [ slot + 1 ] = extent
self . _spanOffsets [ slot + 1 ] = buffer . _offset
end

function gpu . Binding . setWrite (
self ,
slot ,
bufferValue ,
matchCount
) 
local buffer = bufferValue
slot = whole ( slot , "write binding slot" , 0 , 15 )
if self . _released or self . _kernel . _released then
error ( "nupp: GPU binding was released" , 2 )
end
if buffer . _context ~= self . _anchor or buffer . _state . released then
error ( "nupp: GPU write buffer is unavailable in this context" , 2 )
end
local _ , extent , dense , injective = layoutFacts ( buffer . _shape , buffer . _strides , 2 )
if not injective or extent ~= buffer . count then
error ( "nupp: writable GPU tensor views must be disjoint and cover one complete span extent" , 2 )
end
if matchCount and not dense then
error ( "nupp: dispatch-indexed GPU buffers must be dense" , 2 )
end
if matchCount and extent ~= self . count then
error ( "nupp: a dispatch-indexed buffer must hold one element per dispatched thread" , 2 )
end
local writable = # self . _spanCounts - self . _readonlyBuffers
if slot < 0 or slot >= writable then
error ( "nupp: write binding slot is outside the compiled kernel" , 2 )
end
operations . refuseReadWriteAlias ( boundStates ( self , false ) , buffer . _state )
costLayout (
self . _context ,
buffer . _handle ,
buffer . _shape ,
buffer . _strides ,
buffer . _width ,
buffer . _offset ,
buffer . count
)
native . succeeded (
C . nuppNativeGpuBindingsSetBuffer (
self . _context ,
self . _handle ,
1 ,
slot ,
buffer . _handle ,
0 ,
buffer . _capacity * buffer . _width
) ,
2
)
self . _write [ slot + 1 ] = 1
local position = self . _readonlyBuffers + slot + 1
self . _bufferStates [ position ] = buffer . _state
self . _spanCounts [ position ] = extent
self . _spanOffsets [ position ] = buffer . _offset
end

function gpu . Binding . dispatchPacked ( self , uniforms , uniformBytes ) 
if self . _released or self . _kernel . _released then
error ( "nupp: GPU binding or kernel was released" , 2 )
end
for index = 1 , self . _kernel . _readonlyBuffers do
if self . _read [ index ] == nil then
error ( "nupp: GPU binding is incomplete" , 2 )
end
end
for index = 1 , self . _kernel . _writableBuffers do
if self . _write [ index ] == nil then
error ( "nupp: GPU binding is incomplete" , 2 )
end
end
for _ , state in ipairs ( self . _bufferStates ) do
if state . released then
error ( "nupp: GPU binding contains a released buffer" , 2 )
end
end
if uniformBytes ~= self . _uniformBytes then
error ( "nupp: generated GPU uniform block has the wrong size" , 2 )
end
local spans = # self . _spanCounts
do
local words = __nuppFfi.cast("uint32_t *" , uniforms )
words [ 0 ] = self . count
for index = 1 , spans do
words [ index ] = self . _spanCounts [ index ]
words [ spans + index ] = self . _spanOffsets [ index ]
end
end
local uniformPointer = __nuppFfi.cast("const uint8_t *" , uniforms )
native . succeeded (
dispatchNative ( self . _context , self . _handle , self . count , self . _kernel . _threads , uniformPointer , uniformBytes ) ,
2
)
end

function gpu . Context . upload (
self ,
bufferValue ,
source
) 
local buffer = bufferValue
if buffer . _context ~= self or buffer . _state . released then
error ( "nupp: GPU upload buffer is unavailable in this context" , 2 )
end
if not buffer : isDense ( ) then
error ( "nupp: GPU uploads require a dense tensor view" , 2 )
end
if source .count ~= buffer . count then
error ( "nupp: GPU upload span length does not match its buffer" , 2 )
end
costLayout ( live ( self ) , buffer . _handle , buffer . _shape , buffer . _strides , buffer . _width , buffer . _offset , buffer . count )
local pointer , count = source : ref ( )
native . succeeded (
uploadTyped ( live ( self ) , buffer . _handle , pointer , buffer . _offset * buffer . _width , buffer . _width * count ) ,
2
)
end

function gpu . Context . enqueueDownload ( self , bufferValue ) 
local buffer = bufferValue
if buffer . _context ~= self or buffer . _state . released then
error ( "nupp: GPU download buffer is unavailable in this context" , 2 )
end
if not buffer : isDense ( ) then
error ( "nupp: GPU downloads require a dense tensor view" , 2 )
end
costLayout ( live ( self ) , buffer . _handle , buffer . _shape , buffer . _strides , buffer . _width , buffer . _offset , buffer . count )
native . succeeded (
C . nuppNativeGpuDownloadQueue (
live ( self ) ,
buffer . _handle ,
buffer . _offset * buffer . _width ,
buffer . count * buffer . _width
) ,
2
)
end

const READINESS_FEATURE = 16384




local function workDone ( handle , ready ) 
if C . nuppNativeGpuSynchronizeReady ( handle , ready ) ~= 0 then
return false , "nupp: " .. ffi . string ( C . nuppNativeLastError ( ) )
end

return ready [ 0 ] ~= 0 , nil
end









function gpu . Context . synchronize ( self ) 
local handle = live ( self )
native . requireFeature ( 16384 , "readiness" )
local ready = ffi . new ( "uint32_t[1]" )
local done , failure = workDone ( handle , ready )
if not done and failure == nil then


failure = suspension . suspend ( "GPU synchronize" , function (
resume ,
context
) 
local waiting = true
context : source (
"nupp-gpu" ,
native . READINESS_PRIORITY ,
native . pump ( function ( ) 
if not waiting then
return 0
end
local finished , reason = workDone ( handle , ready )
if not finished and reason == nil then
return 0
end
waiting = false
resume ( reason )

return 1
end )
)

return function ( ) 
waiting = false
end
end )
end
if failure ~= nil then
error ( failure , 2 )
end
native . succeeded ( C . nuppNativeGpuSynchronize ( handle ) , 2 )
end

function gpu . Context . readDownloaded (
self ,
bufferValue ,
destination
) 
local buffer = bufferValue
if buffer . _context ~= self or buffer . _state . released then
error ( "nupp: GPU download buffer is unavailable in this context" , 2 )
end
if not buffer : isDense ( ) then
error ( "nupp: GPU downloads require a dense tensor view" , 2 )
end
if destination .count ~= buffer . count then
error ( "nupp: GPU download span length does not match its buffer" , 2 )
end
local pointer , count = destination : ref ( )
native . succeeded (
readTyped ( live ( self ) , buffer . _handle , pointer , buffer . _offset * buffer . _width , buffer . _width * count ) ,
2
)
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





function gpu . Binding . dispatchWords ( self , scalars ) 
error ( "nupp: native GPU dispatch requires a packed uniform block" , 2 )
end

function gpu . Context . bindKernel (
self ,
kernelValue ,
count
) 
local kernel = kernelValue
if kernel . _anchor ~= self then
error ( "nupp: GPU kernel belongs to another context" , 2 )
elseif kernel . _released then
error ( "nupp: GPU kernel was released" , 2 )
end
count = whole ( count , "dispatch count" , 1 , 4294967295 )
local context = live ( self )
local output = ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppNativeGpuBindingsCreate ( context , kernel . _handle , output ) , 2 )
local handle = output [ 0 ]
local spans = kernel . _readonlyBuffers + kernel . _writableBuffers
local spanCounts = { }
local spanOffsets = { }
for index = 1 , spans do
spanCounts [ index ] = 0
spanOffsets [ index ] = 0
end

return ( _G.setmetatable({ _anchor =
self ,  _kernel =
kernel ,  _read =
{ } ,  _write =
{ } ,  _readCounts =
{ } ,  _writeCounts =
{ } ,  _readOffsets =
{ } ,  _writeOffsets =
{ } ,  _bufferStates =
{ } ,  _context =
context ,  _handle =
handle ,  _uniformBytes =
kernel . _uniformBytes ,  _readonlyBuffers =
kernel . _readonlyBuffers ,  _spanCounts =
spanCounts ,  _spanOffsets =
spanOffsets ,  _released =
false ,  count =
count }, gpu.Binding) )

end

function gpu . Context . close ( self ) 
local state = self
state . _destroy ( state )
end


function gpu . available ( ) 
if not pcall ( native . requireFeature , 4 , "GPU support" ) then
return false
end
local output = ffi . new ( "uint64_t[1]" )
if C . nuppNativeGpuContextCreate ( output ) ~= 0 then
return false
end
C . nuppNativeGpuContextRelease ( output [ 0 ] )

return true
end

function gpu . open ( ) 
native . requireFeature ( 4 , "GPU support" )
local output = ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppNativeGpuContextCreate ( output ) , 2 )
local handle = output [ 0 ]

return ( _G.setmetatable({ _destroy =  contextdestroy ,  _handle =  handle ,  _closed =  false }, gpu.Context) )
end

const available = gpu . available ;__nuppExports["available"]=available
const open = gpu . open ;__nuppExports["open"]=open
const costsOutput = gpu . costsOutput ;__nuppExports["costsOutput"]=costsOutput
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativegpu"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativegpu"]=__nuppExports;return __nuppExports