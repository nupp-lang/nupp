_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()









const contract = require ( "nupp.compression.spi" )
const native = require ( "nupp.runtime.native" )
const span = require ( "nupp.mem.span" )

native . ffi . cdef [[
int32_t nuppNativeCompressionEncoderCreate(uint32_t, uint32_t, uint64_t *);
int32_t nuppNativeCompressionEncoderWrite(
    uint64_t, const uint8_t *, size_t, uint8_t *, size_t,
    size_t *, size_t *, uint32_t *);
int32_t nuppNativeCompressionEncoderFlush(
    uint64_t, uint8_t *, size_t, size_t *, uint32_t *);
int32_t nuppNativeCompressionEncoderFinish(
    uint64_t, uint8_t *, size_t, size_t *, uint32_t *);
int32_t nuppNativeCompressionEncoderRelease(uint64_t);
int32_t nuppNativeCompressionDecoderCreate(uint32_t, int32_t, uint64_t *);
int32_t nuppNativeCompressionDecoderRead(
    uint64_t, const uint8_t *, size_t, uint8_t *, size_t,
    size_t *, size_t *, uint32_t *);
int32_t nuppNativeCompressionDecoderFinishInput(
    uint64_t, uint8_t *, size_t, size_t *, uint32_t *);
int32_t nuppNativeCompressionDecoderRelease(uint64_t);
]]

const C = native . C

native . requireFeature ( 1024 , "compression" )

local function encoderWrite (
handle ,
input ,
inputLength ,
output ,
outputLength ,
consumed ,
written ,
status
) 
local call = C . nuppNativeCompressionEncoderWrite










return call ( handle , input , inputLength , output , outputLength , consumed , written , status )
end

local function encoderOutput (
operation ,
handle ,
output ,
outputLength ,
written ,
status
) 
local call = operation
return call ( handle , output , outputLength , written , status )
end

local function decoderRead (
handle ,
input ,
inputLength ,
output ,
outputLength ,
consumed ,
written ,
status
) 
local call = C . nuppNativeCompressionDecoderRead










return call ( handle , input , inputLength , output , outputLength , consumed , written , status )
end

local function decoderFinishInput (
handle ,
output ,
outputLength ,
written ,
status
) 
local call = C . nuppNativeCompressionDecoderFinishInput







return call ( handle , output , outputLength , written , status )
end

local function failure ( prefix ) 
return prefix .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) )
end

local Encoder = {} Encoder.__index = Encoder





function Encoder:close() 
native . succeeded ( C . nuppNativeCompressionEncoderRelease ( self . handle ) , 2 )
end

function Encoder:write(input, output) 




local code = encoderWrite (
self . handle ,
input : ref ( ) ,
input .count ,
output : ref ( ) ,
output .count ,
self . consumed ,
self . written ,
self . status
)
if code ~= 0 then
return nil , nil , nil , ( "compression encode failed" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return tonumber (
self . consumed [ 0 ]
) , tonumber ( self . written [ 0 ] ) , tonumber ( self . status [ 0 ] )
end

function Encoder:flush(output) 
local code = encoderOutput (
C . nuppNativeCompressionEncoderFlush ,
self . handle ,
output : ref ( ) ,
output .count ,
self . written ,
self . status
)
if code ~= 0 then
return nil , nil , ( "compression flush failed" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return tonumber ( self . written [ 0 ] ) , tonumber ( self . status [ 0 ] )
end

function Encoder:finish(output) 
local code = encoderOutput (
C . nuppNativeCompressionEncoderFinish ,
self . handle ,
output : ref ( ) ,
output .count ,
self . written ,
self . status
)
if code ~= 0 then
return nil , nil , ( "compression finish failed" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return tonumber ( self . written [ 0 ] ) , tonumber ( self . status [ 0 ] )
end


local Decoder = {} Decoder.__index = Decoder





function Decoder:close() 
native . succeeded ( C . nuppNativeCompressionDecoderRelease ( self . handle ) , 2 )
end

function Decoder:read(input, output) 




local code = decoderRead (
self . handle ,
input : ref ( ) ,
input .count ,
output : ref ( ) ,
output .count ,
self . consumed ,
self . written ,
self . status
)
if code ~= 0 then
return nil , nil , nil , ( "compression decode failed" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return tonumber (
self . consumed [ 0 ]
) , tonumber ( self . written [ 0 ] ) , tonumber ( self . status [ 0 ] )
end

function Decoder:finishInput(output) 
local code = decoderFinishInput ( self . handle , output : ref ( ) , output .count , self . written , self . status )
if code ~= 0 then
return nil , nil , ( "compression decode failed" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return tonumber ( self . written [ 0 ] ) , tonumber ( self . status [ 0 ] )
end


local Format = {} Format.__index = Format



function Format:createEncoder(options) 
local level = options ~= nil and options . level or 6
local handle = native . ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppNativeCompressionEncoderCreate ( self . id , level , handle ) , 2 )
return ( _G.setmetatable({ handle =
handle [ 0 ] ,  consumed =
native . ffi . new ( "size_t[1]" ) ,  written =
native . ffi . new ( "size_t[1]" ) ,  status =
native . ffi . new ( "uint32_t[1]" ) }, Encoder) )

end

function Format:createDecoder(options) 
local concatenatedMembers = self . name == "gzip" and ( options == nil or options . concatenatedMembers ~= false )
local handle = native . ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppNativeCompressionDecoderCreate ( self . id , concatenatedMembers and 1 or 0 , handle ) , 2 )

return ( _G.setmetatable({ handle =
handle [ 0 ] ,  consumed =
native . ffi . new ( "size_t[1]" ) ,  written =
native . ffi . new ( "size_t[1]" ) ,  status =
native . ffi . new ( "uint32_t[1]" ) }, Decoder) )

end


local formats

= {
gzip = _G.setmetatable({ name =  "gzip" ,  id =  1 }, Format) ,
zlib = _G.setmetatable({ name =  "zlib" ,  id =  2 }, Format) ,
[ "deflate-raw" ] = _G.setmetatable({ name =  "deflate-raw" ,  id =  3 }, Format) ,
}

local provider = { formats = formats }
local __nuppExportValue= provider ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativecompression"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativecompression"]=__nuppExports;return __nuppExports