_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.io.http.internal.transport"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local newClient;__nuppExports["newClient"]=function(...) return newClient(...) end;



const time = require ( "nupp.time" )

























const native = require ( "nupp.runtime.native" )

native . ffi . cdef [[
typedef struct { const uint8_t *data; size_t length; } NuppNativeHttpSlice;
typedef struct { NuppNativeHttpSlice name; NuppNativeHttpSlice value; } NuppNativeHttpHeader;

typedef struct {
    uint64_t connect_timeout_ms;
    uint32_t max_redirects;
    uint32_t max_pending_requests;
    uint32_t max_connections;
    uint32_t max_connections_per_host;
    int compressed;
    int has_insecure_hosts;
    int proxy_mode;
    NuppNativeHttpSlice proxy;
    int no_proxy_set;
    NuppNativeHttpSlice no_proxy;
    NuppNativeHttpSlice proxy_credentials;
} NuppNativeHttpClientOptions;

typedef struct {
    NuppNativeHttpSlice url;
    NuppNativeHttpSlice method;
    const NuppNativeHttpHeader *headers;
    size_t header_count;
    NuppNativeHttpSlice body;
    uint32_t body_kind;
    int64_t body_length;
    uint64_t timeout_ms;
    uint64_t stall_timeout_ms;
    uint64_t max_bytes;
    int insecure;
} NuppNativeHttpRequest;

typedef struct {
    uint32_t state;
    uint16_t status;
    uint8_t version;
    size_t url_length;
    size_t headers_length;
} NuppNativeHttpHead;

typedef struct { uint64_t transfer; uint32_t tokens; } NuppNativeHttpReady;

int32_t nuppNativeHttpClientCreate(const NuppNativeHttpClientOptions *, uint64_t *);
int32_t nuppNativeHttpClientRelease(uint64_t);
int32_t nuppNativeHttpClientSend(uint64_t, const NuppNativeHttpRequest *, uint64_t *);
int32_t nuppNativeHttpClientPending(uint64_t, size_t *);
int32_t nuppNativeHttpTransferCancel(uint64_t);
int32_t nuppNativeHttpTransferRelease(uint64_t);
int32_t nuppNativeHttpTransferOffer(uint64_t, const uint8_t *, size_t, int32_t, int32_t *);
int32_t nuppNativeHttpTransferPollHead(
    uint64_t, NuppNativeHttpHead *, uint8_t *, size_t, uint8_t *, size_t);
int32_t nuppNativeHttpTransferError(uint64_t, uint8_t *, size_t, size_t *);
int32_t nuppNativeHttpTransferTakeBody(uint64_t, uint64_t *);
int32_t nuppNativeHttpBodyArm(uint64_t);
int32_t nuppNativeHttpBodyRead(uint64_t, uint8_t *, size_t, uint32_t *, size_t *);
int32_t nuppNativeHttpBodyError(uint64_t, uint8_t *, size_t, size_t *);
int32_t nuppNativeHttpClientPoll(
    uint64_t, NuppNativeHttpReady *, size_t, size_t *, int32_t *);
]]

local ffi = native . ffi
const C = native . C



const ABI_CAPACITY = 2
const ABI_BUFFER_TOO_SMALL = 6


const HEAD_PENDING = 0
const HEAD_FAILED = 2


const BODY_PENDING = 2
const BODY_EOF = 3
const BODY_FAILED = 4
const BODY_CLOSED = 5



const TOKEN_HEADERS = 1
const TOKEN_BODY = 2
const TOKEN_UPLOAD = 4
const TOKEN_FAILED = 8


const BODY_INLINE = 1 ;__nuppExports["BODY_INLINE"]=BODY_INLINE
const BODY_UPLOAD = 2 ;__nuppExports["BODY_UPLOAD"]=BODY_UPLOAD
const BODY_FILE = 3 ;__nuppExports["BODY_FILE"]=BODY_FILE


const UPLOAD_BACKPRESSURE = 0
const UPLOAD_ACCEPTED = 1


const READY_SLOTS = 256



const BODY_READ_BYTES = 65536










local function slice ( value , pointer , length ) 
local out = native . ffi . new ( "NuppNativeHttpSlice" )
if pointer ~= nil then
out . data = pointer
out . length = length
elseif value ~= nil then
out . data = value
out . length = # ( value )
end

return out
end

local function raw ( handle ) 
return handle [ 0 ]
end

local function outputHandle ( ) 
return __nuppFfi.new("uint64_t[1]" )
end

local function releaseTransfer ( handle ) 
if handle [ 0 ] ~= 0 then
C . nuppNativeHttpTransferRelease ( handle [ 0 ] )
handle [ 0 ] = 0
end
end

local function releaseClient ( handle ) 
if handle [ 0 ] ~= 0 then
C . nuppNativeHttpClientRelease ( handle [ 0 ] )
handle [ 0 ] = 0
end
end

local function lastError ( ) 
return ffi . string ( C . nuppNativeLastError ( ) )
end


local function copiedError ( call , handle , fallback ) 
local length = ffi . new ( "size_t[1]" )
call ( ( handle [ 0 ] ) , nil , 0 , length )
if length [ 0 ] == 0 then
return fallback
end
local output = ffi . new ( "uint8_t[?]" , length [ 0 ] )
if call ( ( handle [ 0 ] ) , output , length [ 0 ] , length ) ~= 0 then
return ( ffi . string ( C . nuppNativeLastError ( ) ) )
end
local text = ffi . string ( output , length [ 0 ] )

return text ~= "" and text or fallback
end

local function pending ( handle ) 
local output = ffi . new ( "size_t[1]" )
native . succeeded ( C . nuppNativeHttpClientPending ( ( handle [ 0 ] ) , output ) , 3 )

return tonumber ( output [ 0 ] )
end







local function dispatch ( self , field ) 
local waiters = self [ field ]
if waiters == nil then
return 0 , nil
end
self [ field ] = nil
local count = # waiters
local failure = nil
for index = count , 1 , -1 do
local ok , problem = pcall ( waiters [ index ] )
if not ok and failure == nil then
failure = problem
end
end

return count , failure
end





local function dispatchOne ( self , field ) 
local waiters = self [ field ]
if waiters == nil or # waiters == 0 then
return 0
end
local wake = table . remove ( waiters , 1 )
if # waiters == 0 then
self [ field ] = nil
end
wake ( )

return 1
end





local function addWaiter ( self , field , wake ) 
local waiters = self [ field ]
if waiters == nil then
waiters = { }
self [ field ] = waiters
end
waiters [ # waiters + 1 ] = wake
local active = true

return function ( ) 
if not active then
return
end
active = false
for index = 1 , # waiters do
if waiters [ index ] == wake then
table . remove ( waiters , index )
do break end
end
end
end
end









local Transfer = {} Transfer.__index = Transfer











function Transfer:_ready(tokens) 
local moved = 0
local failure = nil
local count
local problem


if bit . band ( tokens , TOKEN_HEADERS + TOKEN_FAILED ) ~= 0 then
count , problem = dispatch ( self , "_headWaiters" )
moved = moved + count
failure = problem
end
if bit . band ( tokens , TOKEN_BODY ) ~= 0 then
count , problem = dispatch ( self , "_bodyWaiters" )
moved = moved + count
if problem ~= nil and failure == nil then
failure = problem
end
end
if bit . band ( tokens , TOKEN_UPLOAD ) ~= 0 then
count , problem = dispatch ( self , "_uploadWaiters" )
moved = moved + count
if problem ~= nil and failure == nil then
failure = problem
end
end
if failure ~= nil then
error ( failure , 0 )
end

return moved
end

function Transfer:onHead(wake) 
return addWaiter ( self , "_headWaiters" , wake )
end

function Transfer:onBody(wake) 
local forget = addWaiter ( self , "_bodyWaiters" , wake )



if self . _body ~= nil then
C . nuppNativeHttpBodyArm ( raw ( self . _body ) )
end

return forget
end

function Transfer:onUpload(wake) 
return addWaiter ( self , "_uploadWaiters" , wake )
end

function Transfer:head() 
local out = native . ffi . new ( "NuppNativeHttpHead[1]" )
local status = C . nuppNativeHttpTransferPollHead ( raw ( self . _handle ) , out , nil , 0 , nil , 0 )
local state = tonumber ( out [ 0 ] . state )
if status ~= 0 and status ~= ABI_BUFFER_TOO_SMALL then
return "failed" , nil , nil , nil , nil , ( ffi . string ( C . nuppNativeLastError ( ) ) )
end
if state == HEAD_PENDING then
return "pending" , nil , nil , nil , nil , nil
end
if state == HEAD_FAILED then
return "failed" , nil , nil , nil , nil , copiedError (
C . nuppNativeHttpTransferError ,
self . _handle ,
"HTTP transfer failed"
)
end
local head = out [ 0 ]
local urlLength = tonumber ( head . url_length )
local headersLength = tonumber ( head . headers_length )
local urlOutput = urlLength > 0 and ffi . new ( "uint8_t[?]" , urlLength ) or nil
local headersOutput = headersLength > 0 and ffi . new ( "uint8_t[?]" , headersLength ) or nil
status = C . nuppNativeHttpTransferPollHead (
raw ( self . _handle ) ,
out ,
urlOutput ,
urlLength ,
headersOutput ,
headersLength
)
if status ~= 0 then
return "failed" , nil , nil , nil , nil , ( ffi . string ( C . nuppNativeLastError ( ) ) )
end
local url = urlLength > 0 and ffi . string ( urlOutput , urlLength ) or nil
local headers = headersLength > 0 and ffi . string ( headersOutput , headersLength ) or ""

return "ready" , tonumber ( head . status ) , tonumber ( head . version ) , url , headers , nil
end

function Transfer:offer(value, count) 
local bytes = value
local length = count or # bytes
if length < 0 or length > # bytes then
error ( "nupp: HTTP upload offer is outside its bytes" , 2 )
end
local answer = __nuppFfi.new("int32_t[1]" )
local status = C . nuppNativeHttpTransferOffer ( raw ( self . _handle ) , bytes , length , 0 , answer )
if status ~= 0 then
return "closed"
end
if answer [ 0 ] == UPLOAD_ACCEPTED then
return "accepted"
end
if answer [ 0 ] == UPLOAD_BACKPRESSURE then
return "backpressure"
end

return "closed"
end

function Transfer:finishUpload() 
local answer = __nuppFfi.new("int32_t[1]" )
local status = C . nuppNativeHttpTransferOffer ( raw ( self . _handle ) , nil , 0 , 1 , answer )
if status == 0 and answer [ 0 ] == UPLOAD_ACCEPTED then
return "accepted"
end

return "closed"
end

function Transfer:takeBody() 
if self . _body == nil then
local handle = outputHandle ( )
if C . nuppNativeHttpTransferTakeBody ( raw ( self . _handle ) , handle ) ~= 0 then
return nil , ( ffi . string ( C . nuppNativeLastError ( ) ) )
end
self . _body = ffi . gc ( handle , releaseTransfer )
end

return true , nil
end




function Transfer:bodyRead(count) 
local capacity = math . min ( count , BODY_READ_BYTES )
local data = ffi . new ( "uint8_t[?]" , capacity )
local length = ffi . new ( "size_t[1]" )
local state = __nuppFfi.new("uint32_t[1]" )
if C . nuppNativeHttpBodyRead ( raw ( self . _body ) , data , capacity , state , length ) ~= 0 then
return "failed" , nil , ( ffi . string ( C . nuppNativeLastError ( ) ) )
end
local kind = tonumber ( state [ 0 ] )
if kind == BODY_PENDING then
return "pending" , nil , nil
end
if kind == BODY_EOF then
return "eof" , nil , nil
end
if kind == BODY_FAILED then
return "failed" , nil , copiedError ( C . nuppNativeHttpBodyError , self . _body , "HTTP response body failed" )
end
if kind == BODY_CLOSED then
return "closed" , nil , "the body is closed"
end
local bytes = ffi . string ( data , length [ 0 ] )

return "data" , bytes , nil
end

function Transfer:cancel() 
if self . _handle ~= nil then
C . nuppNativeHttpTransferCancel ( raw ( self . _handle ) )
end
end






function Transfer:close() 
if self . _closed then
return
end
self . _closed = true
self . _client . _byHandle [ tostring ( raw ( self . _handle ) ) ] = nil
if self . _body ~= nil then
local body = self . _body
self . _body = nil
ffi . gc ( body , nil )
releaseTransfer ( body )
else
C . nuppNativeHttpTransferCancel ( raw ( self . _handle ) )
end
local handle = self . _handle
self . _handle = nil
ffi . gc ( handle , nil )
releaseTransfer ( handle )
end







local Client = {} Client.__index = Client












function Client:onAdmission(wake) 
if self . _closed or pending ( self . _handle ) < self . _maxPending then
wake ( )

return function ( ) 
end
end

return addWaiter ( self , "_admissionWaiters" , wake )
end

function Client:send(descriptor) 
local headers = descriptor . headers or { }
local count = # headers
local packed = count > 0 and native . ffi . new ( "NuppNativeHttpHeader[?]" , count ) or nil
for index = 1 , count do
local item = headers [ index ]
packed [ index - 1 ] . name = slice ( item [ 1 ] )
packed [ index - 1 ] . value = slice ( item [ 2 ] )
end
local bodyPointer = nil
local bodyLength = 0
local value = descriptor . body
if descriptor . bodyKind == BODY_INLINE then
bodyPointer = value
bodyLength = # ( value )
elseif descriptor . bodyKind == BODY_FILE then

bodyPointer = value
bodyLength = # ( value )
end
local request = native . ffi . new ( "NuppNativeHttpRequest" )
request . url = slice ( descriptor . uri : toString ( ) )
request . method = slice ( descriptor . method )
request . headers = packed
request . header_count = count
request . body = slice ( nil , bodyPointer , bodyLength )
request . body_kind = descriptor . bodyKind
request . body_length = descriptor . bodyLength or - 1
request . timeout_ms = descriptor . timeoutMs
request . stall_timeout_ms = descriptor . stallTimeoutMs
request . max_bytes = descriptor . maxBytes
request . insecure = descriptor . insecure and 1 or 0
local handle = outputHandle ( )
local status = C . nuppNativeHttpClientSend ( raw ( self . _handle ) , request , handle )
if status ~= 0 then
local why = ( ffi . string ( C . nuppNativeLastError ( ) ) )

return nil , why , status == ABI_CAPACITY
end
handle = ffi . gc ( handle , releaseTransfer )
local transfer = _G.setmetatable({ _client =  self ,  _handle =  handle ,  _body =  nil ,  _closed =  false }, Transfer)
self . _byHandle [ tostring ( ( handle [ 0 ] ) ) ] = transfer

return transfer , nil , nil
end









function Client:poll() 
local count = ffi . new ( "size_t[1]" )
local moved = 0
local status = C . nuppNativeHttpClientPoll ( raw ( self . _handle ) , self . _ready , READY_SLOTS , count , self . _more )
if status ~= 0 then
error ( "nupp: " .. ( ffi . string ( C . nuppNativeLastError ( ) ) ) , 2 )
end
local failure = nil
for index = 0 , ( tonumber ( count [ 0 ] ) ) - 1 do
local item = self . _ready [ index ]
local transfer = self . _byHandle [ tostring ( item . transfer ) ]
if transfer ~= nil then
local ok , problem = pcall ( function ( ) 
moved = moved + transfer : _ready ( tonumber ( item . tokens ) )
end )
if not ok and failure == nil then
failure = problem
end
end
end
if failure ~= nil then
error ( failure , 0 )
end
if self . _admissionWaiters ~= nil and ( pending ( self . _handle ) ) < self . _maxPending then
moved = moved + dispatchOne ( self , "_admissionWaiters" )
end

return moved
end

function Client:pending() 
if self . _closed then
return 0
end

return pending ( self . _handle )
end





function Client:now() 
return time . now ( )
end







function Client:close() 
if self . _closed then
return
end
self . _closed = true
local _ , failure = dispatch ( self , "_admissionWaiters" )
local transfers = { }
for _ , transfer in pairs ( self . _byHandle ) do
transfers [ # transfers + 1 ] = transfer
end
for index = 1 , # transfers do
transfers [ index ] : close ( )
end
local handle = self . _handle
self . _handle = nil
ffi . gc ( handle , nil )
releaseClient ( handle )
if failure ~= nil then
error ( failure , 0 )
end
end



newClient=function ( options ) 


local proxyMode = options . proxy == nil and 0 or ( options . proxy == "" and 1 or 2 )
native . requireFeature ( 16 , "HTTP support" )
local settings = native . ffi . new ( "NuppNativeHttpClientOptions" )
settings . connect_timeout_ms = options . connectTimeoutMs
settings . max_redirects = options . maxRedirects
settings . max_pending_requests = options . maxPendingRequests
settings . max_connections = options . maxConnections
settings . max_connections_per_host = options . maxConnectionsPerHost
settings . compressed = options . compressed and 1 or 0
settings . has_insecure_hosts = next ( options . insecureHosts ) and 1 or 0
settings . proxy_mode = proxyMode
settings . proxy = slice ( options . proxy or "" )
settings . no_proxy_set = options . noProxy ~= nil and 1 or 0
settings . no_proxy = slice ( options . noProxy or "" )
settings . proxy_credentials = slice ( options . proxyCredentials or "" )
local handle = outputHandle ( )
if C . nuppNativeHttpClientCreate ( settings , handle ) ~= 0 then
return nil , ( ffi . string ( C . nuppNativeLastError ( ) ) )
end

return _G.setmetatable({ _handle =
ffi . gc ( handle , releaseClient ) ,  _closed =
false ,  _byHandle =
{ } ,  _admissionWaiters =
nil ,  _maxPending =
options . maxPendingRequests ,  _ready =
native . ffi . new ( "NuppNativeHttpReady[?]" , READY_SLOTS ) ,  _more =
__nuppFfi.new("int32_t[1]" ) }, Client)
, nil
end ;__nuppExports["newClient"]=newClient
 end);if not __nuppOk then package.loaded["nupp.io.http.internal.transport"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.http.internal.transport"]=__nuppExports;return __nuppExports