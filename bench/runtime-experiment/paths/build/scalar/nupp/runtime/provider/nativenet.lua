_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

























local contract = require ( "nupp.io.net.spi" )
local shared = require ( "nupp.io.net.types" )
local ffi = require ( "ffi" )
local ffiString = ffi . string
const READ_SIZE = 65536
const HOST_SIZE = 64

const native = require ( "nupp.runtime.native" )

native . ffi . cdef [[
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeNetSlice;
typedef struct {
    NuppNativeNetSlice host;
    uint16_t port;
    uint32_t backlog;
    int32_t reuse_port;
} NuppNativeNetListenOptions;
typedef struct {
    NuppNativeNetSlice host;
    uint16_t port;
    uint64_t timeout_ms;
} NuppNativeNetConnectOptions;
typedef struct {
    NuppNativeNetSlice path;
    uint32_t backlog;
} NuppNativeNetPathListenOptions;
typedef struct {
    NuppNativeNetSlice path;
    uint64_t timeout_ms;
} NuppNativeNetPathConnectOptions;
typedef struct {
    NuppNativeNetSlice host;
    uint16_t port;
    int32_t reuse_port;
} NuppNativeNetDatagramOptions;
typedef struct {
    uint32_t size;
    uint8_t family;
    uint16_t port;
    uint32_t scope_id;
    uint32_t flowinfo;
    uint8_t address[16];
} NuppNativeNetEndpoint;

int32_t nuppNativeNetListenerCreate(const NuppNativeNetListenOptions *, uint64_t *);
int32_t nuppNativeNetPathListenerCreate(const NuppNativeNetPathListenOptions *, uint64_t *);
int32_t nuppNativeNetListenerPort(uint64_t, uint16_t *);
int32_t nuppNativeNetListenerKind(uint64_t, uint32_t *);
int32_t nuppNativeNetListenerAccept(uint64_t, uint32_t *, uint64_t *);
int32_t nuppNativeNetListenerRelease(uint64_t);
int32_t nuppNativeNetConnectCreate(const NuppNativeNetConnectOptions *, uint64_t *);
int32_t nuppNativeNetPathConnectCreate(const NuppNativeNetPathConnectOptions *, uint64_t *);
int32_t nuppNativeNetConnectPoll(uint64_t, uint32_t *, uint64_t *);
int32_t nuppNativeNetConnectRelease(uint64_t);
int32_t nuppNativeNetStreamRead(uint64_t, uint8_t *, size_t, uint32_t *, size_t *);
int32_t nuppNativeNetStreamWrite(uint64_t, const uint8_t *, size_t, uint32_t *, size_t *);
int32_t nuppNativeNetStreamPendingWrite(uint64_t, size_t *);
int32_t nuppNativeNetStreamState(uint64_t, uint32_t *);
int32_t nuppNativeNetStreamShutdownWrite(uint64_t);
int32_t nuppNativeNetStreamLocalEndpoint(uint64_t, NuppNativeNetEndpoint *);
int32_t nuppNativeNetStreamPeerEndpoint(uint64_t, NuppNativeNetEndpoint *);
int32_t nuppNativeNetStreamSetNoDelay(uint64_t, int32_t);
int32_t nuppNativeNetStreamSetKeepAliveMs(uint64_t, int32_t, uint64_t);
int32_t nuppNativeNetStreamRelease(uint64_t);
int32_t nuppNativeNetEndpointParse(NuppNativeNetSlice, uint16_t, NuppNativeNetEndpoint *);
int32_t nuppNativeNetEndpointText(const NuppNativeNetEndpoint *, uint8_t *, size_t, size_t *);
int32_t nuppNativeNetDatagramCreate(const NuppNativeNetDatagramOptions *, uint64_t *);
int32_t nuppNativeNetDatagramPort(uint64_t, uint16_t *);
int32_t nuppNativeNetDatagramReceiveEndpoint(
    uint64_t, uint8_t *, size_t, uint32_t *, size_t *, NuppNativeNetEndpoint *, int32_t *);
int32_t nuppNativeNetDatagramSendEndpoint(
    uint64_t, const NuppNativeNetEndpoint *, const uint8_t *, size_t, uint32_t *, size_t *);
int32_t nuppNativeNetDatagramSetBroadcast(uint64_t, int32_t);
int32_t nuppNativeNetDatagramSetMulticastTtl(uint64_t, uint32_t);
int32_t nuppNativeNetDatagramSetMulticastLoop(uint64_t, int32_t);
int32_t nuppNativeNetDatagramMembership(
    uint64_t, NuppNativeNetSlice, NuppNativeNetSlice, uint32_t, uint8_t, int32_t);
int32_t nuppNativeNetDatagramRelease(uint64_t);
]]

const C = native . C


const PENDING = 1
const READ_EOF = 2
const CONNECT_READY = 1
const CONNECT_FAILED = 2
const LISTENER_PATH = 1
const DATAGRAM_MESSAGE = 0
const DATAGRAM_SENT = 0
const STREAM_READ_EOF = 1
const STREAM_SHUTTING_DOWN = 8
const STREAM_READ_FAILED = 16
const STREAM_WRITE_FAILED = 32

local scratch = nil

native . requireFeature ( 256 , "net" )
native . requireFeature ( 8192 , "network endpoints" )

local function slice ( text ) 
local value = native . ffi . new ( "NuppNativeNetSlice" )



do
value . data = text
end
value . length = # text

return value
end

local function reason ( prefix ) 
return prefix .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) )
end

local function readBuffer ( ) 
if scratch == nil then
scratch = native . ffi . new ( "uint8_t[?]" , 65536 )
end

return scratch
end

local function create ( ) 
const state = native . ffi . new ( "uint32_t[1]" )
const flags = native . ffi . new ( "uint32_t[1]" )
const handle = native . ffi . new ( "uint64_t[1]" )
const count = native . ffi . new ( "size_t[1]" )
const portOutput = native . ffi . new ( "uint16_t[1]" )
const scalar = native . ffi . new ( "int32_t[1]" )

const endpoint = native . ffi . new ( "NuppNativeNetEndpoint[1]" )
endpoint [ 0 ] . size = native . ffi . sizeof ( "NuppNativeNetEndpoint" )
const hostOutput = native . ffi . new ( "uint8_t[?]" , 64 )

local function streamFlags ( stream ) 
if C . nuppNativeNetStreamState ( stream , flags ) ~= 0 then
return 48
end

return tonumber ( flags [ 0 ] )
end

local function textAddress ( value ) 
if value [ 0 ] . family == 0 then
return nil
end
const status = C . nuppNativeNetEndpointText ( value , hostOutput , 64 , count )
if status ~= 0 then
return nil
end

return ffiString ( hostOutput , tonumber ( count [ 0 ] ) ) , tonumber ( value [ 0 ] . port )
end

return {
listen = function (
self ,
host ,
port ,
backlog ,
reusePort
) 

local options = native . ffi . new ( "NuppNativeNetListenOptions" )
options . host = slice ( host )
options . port = port
options . backlog = backlog
options . reuse_port = reusePort and 1 or 0
if C . nuppNativeNetListenerCreate ( options , handle ) ~= 0 then
return nil , ( "nupp: could not listen" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return handle [ 0 ]
end ,

listenPath = function ( self , path , backlog ) 

local options = native . ffi . new ( "NuppNativeNetPathListenOptions" )
options . path = slice ( path )
options . backlog = backlog
if C . nuppNativeNetPathListenerCreate ( options , handle ) ~= 0 then
return nil , ( "nupp: could not listen" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return handle [ 0 ]
end ,

listenerPort = function ( self , listener ) 
if C . nuppNativeNetListenerKind ( listener , state ) ~= 0 or state [ 0 ] == 1 then
return -1
end
if C . nuppNativeNetListenerPort ( listener , portOutput ) ~= 0 then
return -1
end

return tonumber ( portOutput [ 0 ] )
end ,

accept = function ( self , listener ) 
if C . nuppNativeNetListenerAccept ( listener , state , handle ) ~= 0 then
return nil , ( "nupp: could not accept" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if state [ 0 ] == 1 then
return nil
end

return handle [ 0 ]
end ,

closeListener = function ( self , listener ) 
C . nuppNativeNetListenerRelease ( listener )
end ,

connect = function ( self , host , port , timeoutMs ) 

local options = native . ffi . new ( "NuppNativeNetConnectOptions" )
options . host = slice ( host )
options . port = port
options . timeout_ms = timeoutMs
if C . nuppNativeNetConnectCreate ( options , handle ) ~= 0 then
return nil , ( "nupp: could not connect" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return handle [ 0 ]
end ,

connectPath = function ( self , path , timeoutMs ) 

local options = native . ffi . new ( "NuppNativeNetPathConnectOptions" )
options . path = slice ( path )
options . timeout_ms = timeoutMs
if C . nuppNativeNetPathConnectCreate ( options , handle ) ~= 0 then
return nil , ( "nupp: could not connect" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return handle [ 0 ]
end ,

connectPoll = function ( self , request ) 
if C . nuppNativeNetConnectPoll ( request , state , handle ) ~= 0 then
return nil , ( "nupp: could not connect" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if state [ 0 ] == 2 then
return nil , ( "nupp: could not connect" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if state [ 0 ] ~= 1 then
return nil
end

return handle [ 0 ]
end ,

closeConnect = function ( self , request ) 
C . nuppNativeNetConnectRelease ( request )
end ,

read = function ( self , stream , wanted ) 
const taking = wanted < 65536 and wanted or 65536
const into = readBuffer ( )
if C . nuppNativeNetStreamRead ( stream , into , taking , state , count ) ~= 0 then
return nil , ( "nupp: could not read" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if state [ 0 ] == 1 or state [ 0 ] == 2 then
return ""
end

return ffiString ( into , tonumber ( count [ 0 ] ) )
end ,

ended = function ( self , stream ) 
return streamFlags ( stream ) & 1 ~= 0
end ,

write = function ( self , stream , bytes ) 
if C . nuppNativeNetStreamWrite ( stream , bytes , # bytes , state , count ) ~= 0 then
return nil , ( "nupp: could not write" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if state [ 0 ] == 2 then
return nil , "nupp: could not write: the connection is closed"
end

return tonumber ( count [ 0 ] )
end ,

pending = function ( self , stream ) 
if C . nuppNativeNetStreamPendingWrite ( stream , count ) ~= 0 then
return 0
end

return tonumber ( count [ 0 ] )
end ,

writeFailed = function ( self , stream ) 
return streamFlags ( stream ) & 32 ~= 0
end ,

shuttingDown = function ( self , stream ) 
return streamFlags ( stream ) & 8 ~= 0
end ,

shutdownWrite = function ( self , stream ) 
if C . nuppNativeNetStreamShutdownWrite ( stream ) ~= 0 then
return false , ( "nupp: could not end the sending half" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

address = function ( self , stream , peer ) 
const status = peer and C . nuppNativeNetStreamPeerEndpoint ( stream , endpoint )
or C . nuppNativeNetStreamLocalEndpoint ( stream , endpoint )
if status ~= 0 then
return nil
end
const host , port = textAddress ( endpoint )
if host == nil or port == nil then
return nil
end

return { host = host , port = port }
end ,

noDelay = function ( self , stream , enable ) 
if C . nuppNativeNetStreamSetNoDelay ( stream , enable and 1 or 0 ) ~= 0 then
return false , ( "nupp: could not set the delay option" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

keepAlive = function (
self ,
stream ,
enable ,
delayMs
) 
if C . nuppNativeNetStreamSetKeepAliveMs ( stream , enable and 1 or 0 , delayMs ) ~= 0 then
return false , ( "nupp: could not set the keepalive option" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

broadcast = function ( self , socket , enable ) 
if C . nuppNativeNetDatagramSetBroadcast ( socket , enable and 1 or 0 ) ~= 0 then
return false , ( "nupp: could not set the broadcast option" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

multicastTtl = function ( self , socket , ttl ) 
if C . nuppNativeNetDatagramSetMulticastTtl ( socket , ttl ) ~= 0 then
return false , ( "nupp: could not set the multicast hop limit" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

multicastLoop = function ( self , socket , enable ) 
if C . nuppNativeNetDatagramSetMulticastLoop ( socket , enable and 1 or 0 ) ~= 0 then
return false , ( "nupp: could not set the multicast loop option" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

membership = function (
self ,
socket ,
group ,
interfaceAddress ,
join
) 
const interfaceKind = interfaceAddress == "" and 0 or 4
if C . nuppNativeNetDatagramMembership (
socket ,
slice ( group ) ,
slice ( interfaceAddress ) ,
0 ,
interfaceKind ,
join and 1 or 0
) ~= 0 then
return false , ( "nupp: could not change the multicast group" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return true
end ,

closeStream = function ( self , stream ) 
C . nuppNativeNetStreamRelease ( stream )
end ,

bindDatagram = function (
self ,
host ,
port ,
reusePort
) 

local options = native . ffi . new ( "NuppNativeNetDatagramOptions" )
options . host = slice ( host )
options . port = port
options . reuse_port = reusePort and 1 or 0
if C . nuppNativeNetDatagramCreate ( options , handle ) ~= 0 then
return nil , ( "nupp: could not bind" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return handle [ 0 ]
end ,

datagramPort = function ( self , socket ) 
if C . nuppNativeNetDatagramPort ( socket , portOutput ) ~= 0 then
return -1
end

return tonumber ( portOutput [ 0 ] )
end ,

receive = function (
self ,
socket ,
maximum
) 
const taking = maximum < 65536 and maximum or 65536
const into = readBuffer ( )
if C . nuppNativeNetDatagramReceiveEndpoint ( socket , into , taking , state , count , endpoint , scalar ) ~= 0 then
return nil , nil , nil , nil , ( "nupp: could not receive" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if state [ 0 ] ~= 0 then
return nil
end
const landed = tonumber ( count [ 0 ] )
const host , port = textAddress ( endpoint )
if host == nil or port == nil then
return nil , nil , nil , nil , "nupp: could not read the datagram peer"
end

return ffiString ( into , landed ) , host , port , scalar [ 0 ] ~= 0
end ,

sendTo = function (
self ,
socket ,
host ,
port ,
bytes
) 
if C . nuppNativeNetEndpointParse ( slice ( host ) , port , endpoint ) ~= 0 then
return false , ( "nupp: could not address the datagram" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end
if C . nuppNativeNetDatagramSendEndpoint ( socket , endpoint , bytes , # bytes , state , count ) ~= 0 then
return false , ( "nupp: could not send" .. ": " .. ( native . ffi . string ( C . nuppNativeLastError ( ) ) ) )
end

return state [ 0 ] == 0
end ,

closeDatagram = function ( self , socket ) 
C . nuppNativeNetDatagramRelease ( socket )
end ,

run = function ( self , timeoutMs ) 



if timeoutMs == 0 then
native . snapshot ( )

return
end
native . sleep ( timeoutMs )
end
}
end

local __nuppExportValue= create ( ) ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativenet"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativenet"]=__nuppExports;return __nuppExports