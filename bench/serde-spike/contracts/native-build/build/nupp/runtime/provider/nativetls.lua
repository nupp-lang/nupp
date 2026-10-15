_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






















local contract = require ( "nupp.io.tls.spi" )
local ffi = require ( "ffi" )
local ffiString = ffi . string
const READ_SIZE = 65536

const native = require ( "nupp.runtime.native" )

_G.pcall(__nuppFfi.cdef, "struct NuppNativeTlsSlice { const char * data; uint64_t length; };") const NuppNativeTlsSlice = __nuppFfi.typeof("struct NuppNativeTlsSlice")




_G.pcall(__nuppFfi.cdef, "struct NuppNativeTlsOptions { struct NuppNativeTlsSlice hostname; struct NuppNativeTlsSlice certificate; struct NuppNativeTlsSlice private_key; struct NuppNativeTlsSlice authority; struct NuppNativeTlsSlice protocols; int32_t authority_present; int32_t server; int32_t verify; };") const NuppNativeTlsOptions = __nuppFfi.typeof("struct NuppNativeTlsOptions")










native . ffi . cdef [[
int32_t nuppNativeTlsCreate(
    uint64_t, const struct NuppNativeTlsOptions *, uint64_t *);
int32_t nuppNativeTlsHandshake(uint64_t, uint32_t *);
int32_t nuppNativeTlsRead(
    uint64_t, uint8_t *, size_t, uint32_t *, size_t *);
int32_t nuppNativeTlsWrite(
    uint64_t, const uint8_t *, size_t, uint32_t *, size_t *);
int32_t nuppNativeTlsFlushed(uint64_t, int32_t *);
int32_t nuppNativeTlsCloseNotify(uint64_t, int32_t *);
int32_t nuppNativeTlsConnected(uint64_t, int32_t *);
int32_t nuppNativeTlsVerified(uint64_t, int32_t *);
int32_t nuppNativeTlsResumed(uint64_t, int32_t *);
int32_t nuppNativeTlsProtocol(
    uint64_t, uint8_t *, size_t, size_t *, int32_t *);
int32_t nuppNativeTlsRelease(uint64_t);
]]

local ffi = native . ffi
const C = native . C

const TLS_READY = 1
const TLS_READ_PENDING = 1
const TLS_READ_EOF = 2
const TLS_WRITE_PENDING = 1
const TLS_WRITE_CLOSED = 2
const PROTOCOL_SIZE = 256

local scratch = nil

native . requireFeature ( 512 , "tls" )

local function slice ( text ) 
local value = __nuppFfi.new(NuppNativeTlsSlice )



do
value . data = text
end
value . length = # text

return value
end

local function lastError ( prefix ) 
return prefix .. ": " .. ( ffi . string ( C . nuppNativeLastError ( ) ) )
end

local function readBuffer ( ) 
if scratch == nil then
scratch = ffi . new ( "uint8_t[?]" , 65536 )
end

return scratch
end

local function create ( ) 
const scalar = ffi . new ( "int32_t[1]" )
const state = ffi . new ( "uint32_t[1]" )
const length = ffi . new ( "size_t[1]" )
const handleOutput = ffi . new ( "uint64_t[1]" )
const protocolBuffer = ffi . new ( "uint8_t[?]" , 256 )
const present = ffi . new ( "int32_t[1]" )

return {
wrap = function (
self ,
handle ,
server ,
hostname ,
certificate ,
privateKey ,
authority ,
protocols ,
verify
) 

local options = __nuppFfi.new(NuppNativeTlsOptions )
options . hostname = slice ( hostname )
options . certificate = slice ( certificate )
options . private_key = slice ( privateKey )
options . authority = slice ( authority or "" )
options . protocols = slice ( protocols )
options . authority_present = authority ~= nil and 1 or 0
options . server = server and 1 or 0
options . verify = verify and 1 or 0
const status = C . nuppNativeTlsCreate ( handle , options , handleOutput )
if status ~= 0 then
return nil , lastError ( "nupp: could not start the session" )
end

return handleOutput [ 0 ]
end ,

handshake = function ( self , session ) 
const status = C . nuppNativeTlsHandshake ( session , state )
if status ~= 0 then
return nil , lastError ( "nupp: the handshake failed" )
end

return state [ 0 ] == 1
end ,

verified = function ( self , session ) 
if C . nuppNativeTlsVerified ( session , scalar ) ~= 0 then
return false
end

return scalar [ 0 ] ~= 0
end ,

resumed = function ( self , session ) 
if C . nuppNativeTlsResumed ( session , scalar ) ~= 0 then
return false
end

return scalar [ 0 ] ~= 0
end ,

read = function ( self , session , wanted ) 
const taking = wanted < 65536 and wanted or 65536
const into = readBuffer ( )
const status = C . nuppNativeTlsRead ( session , into , taking , state , length )
if status ~= 0 then
return nil , lastError ( "nupp: could not read" )
end
if state [ 0 ] == 1 then
return nil
end
if state [ 0 ] == 2 then
return ""
end

return ffiString ( into , tonumber ( length [ 0 ] ) )
end ,

write = function ( self , session , bytes ) 
const status = C . nuppNativeTlsWrite ( session , bytes , # bytes , state , length )
if status ~= 0 then
return nil , lastError ( "nupp: could not write" )
end
if state [ 0 ] == 1 then
return nil
end
if state [ 0 ] == 2 then
return nil , "nupp: could not write: the connection is closed"
end

return tonumber ( length [ 0 ] )
end ,

flushed = function ( self , session ) 
const status = C . nuppNativeTlsFlushed ( session , scalar )
if status ~= 0 then
return false , lastError ( "nupp: could not flush" )
end

return scalar [ 0 ] ~= 0
end ,

closeNotify = function ( self , session ) 
const status = C . nuppNativeTlsCloseNotify ( session , scalar )
if status ~= 0 then
return false , lastError ( "nupp: could not send close_notify" )
end

return scalar [ 0 ] ~= 0
end ,

destroy = function ( self , session ) 
C . nuppNativeTlsRelease ( session )
end ,

connected = function ( self , session ) 
if C . nuppNativeTlsConnected ( session , scalar ) ~= 0 then
return false
end

return scalar [ 0 ] ~= 0
end ,

protocol = function ( self , session ) 
const status = C . nuppNativeTlsProtocol ( session , protocolBuffer , 256 , length , present )
if status ~= 0 or present [ 0 ] == 0 then
return nil
end

return ffiString ( protocolBuffer , tonumber ( length [ 0 ] ) )
end
}
end

local __nuppExportValue= create ( ) ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativetls"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativetls"]=__nuppExports;return __nuppExports