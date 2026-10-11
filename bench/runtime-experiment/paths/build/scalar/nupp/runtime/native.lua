_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()







local ffi = require ( "ffi" )

ffi . cdef [[
uint32_t nuppNativeAbiVersion(void);
uint64_t nuppNativeFeatures(void);
const char *nuppNativeLastError(void);
int32_t nuppNativeBytesCopy(
    uint64_t handle,
    uint8_t *outputData,
    size_t capacity,
    size_t *outputLength
);
int32_t nuppNativeBytesRelease(uint64_t handle);
int32_t nuppNativePoll(uint64_t *generation);
int32_t nuppNativeWait(uint64_t generation, uint64_t timeout_ms, uint64_t *output_generation);
]]

local native = __nuppNew(0,3)



native . ffi = ffi

const ABI_VERSION = 2
const LIBRARY_KEY = "__nuppNativeLibrary"



native . BUFFER_TOO_SMALL = 6

local function open ( ) 
local wanted = os . getenv ( "NUPP_NATIVE_LIBRARY" )
if wanted then
return ffi . load ( wanted )
end
local source = debug . getinfo ( 1 , "S" ) . source
local root = source : match ( "^@(.+)/[^/]+$" ) or "."
local library = ffi . os == "Windows" and "/lib/nupp_native.dll" or "/lib/nupp_native"
for _ , base in ipairs ( { root , root .. "/.." , root .. "/../.." } ) do
local found , value = pcall ( ffi . load , base .. library )
if found then
return value
end
end






local linked = pcall ( function ( ) 
return ffi . C . nuppNativeAbiVersion
end )
if linked then
return ffi . C
end




return ffi . load ( root .. library )
end

local function library ( ) 
local value = rawget ( _G , "__nuppNativeLibrary" )
if value == nil then
local opened = open ( )
local version = opened . nuppNativeAbiVersion ( )
if version ~= 2 then
error (
("nupp: Rust native ABI mismatch: runtime needs %d, provider has %s")

: format ( 2 , tostring ( version ) ) ,
3
)
end
rawset ( _G , "__nuppNativeLibrary" , opened )
value = opened
end

return value
end



native . C = setmetatable ( { } , {
__index = function ( self , symbol ) 
local found = library ( ) [ symbol ]
rawset ( self , symbol , found )

return found
end ,
} )




function native . succeeded ( status , level ) 
if status ~= 0 then
error ( "nupp: " .. ffi . string ( native . C . nuppNativeLastError ( ) ) , level )
end
end




function native . requireFeature ( bit , name ) 
if native . C . nuppNativeFeatures ( ) & bit == 0 then
error ( "nupp: the Rust native provider was built without " .. name , 3 )
end
end




function native . bytes ( handle ) 
local length = ffi . new ( "size_t[1]" )
local status = native . C . nuppNativeBytesCopy ( handle , nil , 0 , length )
local count = ( tonumber ( length [ 0 ] ) or 0 )
if count == 0 then
local released = native . C . nuppNativeBytesRelease ( handle )
native . succeeded ( status , 3 )
native . succeeded ( released , 3 )

return ""
end

if status ~= 2 then
local released = native . C . nuppNativeBytesRelease ( handle )
native . succeeded ( status , 3 )
native . succeeded ( released , 3 )
end

local buffer = ffi . new ( "uint8_t[?]" , count )
status = native . C . nuppNativeBytesCopy ( handle , buffer , count , length )
local released = native . C . nuppNativeBytesRelease ( handle )
native . succeeded ( status , 3 )
native . succeeded ( released , 3 )

return ffi . string ( buffer , count )
end















const snapshot = ffi . new ( "uint64_t[1]" )
const found = ffi . new ( "uint64_t[1]" )
local snapshotTaken = false



native . READINESS_PRIORITY = 20




function native . snapshot ( ) 
if not snapshotTaken and native . C . nuppNativePoll ( snapshot ) == 0 then
snapshotTaken = true
end
end







function native . sleep ( waitMs ) 
if not snapshotTaken then
native . snapshot ( )

return 0
end
snapshotTaken = false
if waitMs > 0 then
native . C . nuppNativeWait ( snapshot [ 0 ] , waitMs , found )
end

return 0
end












function native . pump ( check ) 
return function ( ) 
native . snapshot ( )

return check ( )
end , native . sleep
end

const AOT_RUNTIME_FEATURE = 4096

local aotRuntime = nil










function native . aotRuntime ( ) 
local cached = aotRuntime
if cached ~= nil then
return cached
end
native . requireFeature ( 4096 , "the AOT runtime" )
ffi . cdef ( "const void *nuppAotRuntime(void);" )
local address = native . C . nuppAotRuntime ( )
if address == nil then
error ( "the AOT runtime found no Lua API in this process" , 2 )
end
local cell = ffi . new ( "const void *[1]" , address )
local bytes = ffi . string ( cell , ffi . sizeof ( "void *" ) )
aotRuntime = bytes

return bytes
end

local __nuppExportValue= native ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.native"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.native"]=__nuppExports;return __nuppExports