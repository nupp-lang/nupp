_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT27={}; local function __nuppT24(...) return {n=select("#",...),...} end; local __nuppT28,__nuppT29,__nuppT30,__nuppT31,__nuppT32,__nuppT33,__nuppT34,__nuppT35=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT25(value) return value end; local function __nuppT26(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT33({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT34(v.primary) for _,reason in __nuppT35(v.suppressed) do text=text.."\ncleanup: "..__nuppT34(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppT118 = function(__nuppV) return __nuppV:close() end;local __nuppClosureCleanup3 = function(__nuppV) return __nuppV:__nuppRelease() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()























local suspension = require ( "nupp.suspension" )
local tasks = require ( "nupp.tasks" )
local io = require ( "nupp.io" )
local span = require ( "nupp.mem.span" )
local uri = require ( "nupp.io.uri" )
const messages = require ( "nupp.io.http.messages" )
local contracts = require ( "nupp.io.http.spi" )
local http = { }
local redirectState = setmetatable ( { } , { __mode = "k" } )

const transport = require ( "nupp.io.http.internal.transport" )
const native = require ( "nupp.runtime.native" )


const newClient = transport . newClient
const BODY_INLINE = 1
const BODY_UPLOAD = 2
const BODY_FILE = 3














function http . capabilities ( ) 
return ( _G.setmetatable({ streamingResponse =
true ,  streamingRequest =
true ,  transportPolicy =
true ,  connectionPolicy =
true ,  protocolVersion =
true }, messages.Capabilities) )

end





http . ReaderBody = messages . ReaderBody

http . FileBody = messages . FileBody


http . Request = messages . Request

local READ_SIZE = 65536
local UPLOAD_SIZE = 524288
local UPLOAD_PAGE = 65536
local COALESCE_BELOW = 8192
local COPY_TURN = 16777216
local MAX_SAFE_INTEGER = 9007199254740991
local UINT32_MAX = 4294967295





local function whole ( value , what , minimum , maximum ) 
local upper = maximum or 9007199254740991
if type ( value ) ~= "number" or value ~= math . floor ( value ) or value < minimum or value > upper then
error ( ("nupp: HTTP %s must be an integer%s") : format ( what , ( " from " .. minimum .. " through " .. upper ) ) , 3 )
end

return value
end

local function optionInteger ( options , name , fallback , minimum ) 
local value = options and options [ name ]
if value == nil then
return fallback
end

return whole ( value , name , minimum )
end

local function canonicalHost ( text , level ) 
if text == "" or text : find ( "[/?#@*]" ) ~= nil then
error ( "nupp: HTTP insecureHosts entries must be exact host names or IP literals" , level )
end
local spelling = text : sub ( -1 ) == "." and text : sub ( 1 , -2 ) or text
local uri = uri . newURI ( "https://" .. spelling .. "/" )
if uri == nil or uri : username ( ) ~= "" or uri : password ( ) ~= nil or uri : port ( ) ~= nil or uri : path ( ) ~= "/" then
error ( "nupp: HTTP insecureHosts entries must not contain a scheme, port, path, or user information" , level )
end
local host = uri : host ( )
if host == nil or host == "" then
error ( "nupp: HTTP insecureHosts entry is not a host" , level )
end

return host : lower ( )
end

local function mergedHeaders ( first , second , contentType ) 
local byLower = { }
local merged = { }

local function add ( headers ) 
if headers ~= nil and type ( headers ) ~= "table" then
error ( "nupp: HTTP headers must be a table" , 3 )
end
for name , value in pairs ( headers or { } ) do
if type ( name ) ~= "string"
or type ( value ) ~= "string"
or name == ""
or name : find ( "[\13\n:]" ) ~= nil
or value : find ( "[\13\n]" ) ~= nil
then
error ( "nupp: HTTP headers need valid string names and values" , 3 )
end
local lower = name : lower ( )
local previous = byLower [ lower ]
if previous ~= nil then
merged [ previous ] = nil
end
merged [ name ] = value
byLower [ lower ] = name
end
end

add ( first )
add ( second )
if contentType ~= nil and byLower [ "content-type" ] == nil then
merged [ "content-type" ] = contentType
byLower [ "content-type" ] = "content-type"
end
local packed = { }
for name , value in pairs ( merged ) do
packed [ # packed + 1 ] = { name , value }
end

return byLower , merged , packed
end

local function copiedOptions ( options ) 
local given = options or { }
if type ( given ) ~= "table" then
error ( "nupp: HTTP client options must be a table" , 3 )
end
local headers = { }
if given . headers ~= nil and type ( given . headers ) ~= "table" then
error ( "nupp: HTTP default headers must be a table" , 3 )
end
for name , value in pairs ( given . headers or { } ) do
if type ( name ) ~= "string" or type ( value ) ~= "string" then
error ( "nupp: HTTP default headers must have string names and values" , 3 )
end
headers [ name ] = value
end
if given . userAgent ~= nil then
if type ( given . userAgent ) ~= "string" then
error ( "nupp: HTTP userAgent must be a string" , 3 )
end
headers [ "user-agent" ] = given . userAgent
end
local insecure = { }
local insecureHosts = given . insecureHosts or { }
if type ( insecureHosts ) ~= "table" then
error ( "nupp: HTTP insecureHosts must be a dense list" , 3 )
end
local hostCount = 0
for index in pairs ( insecureHosts ) do
if type ( index ) ~= "number" or index < 1 or index ~= math . floor ( index ) then
error ( "nupp: HTTP insecureHosts must be a dense list" , 3 )
end
hostCount = hostCount + 1
end
if hostCount ~= # insecureHosts then
error ( "nupp: HTTP insecureHosts must be a dense list" , 3 )
end
for _ , host in ipairs ( insecureHosts ) do
if type ( host ) ~= "string" then
error ( "nupp: HTTP insecureHosts entries must be strings" , 3 )
end
insecure [ canonicalHost ( host , 3 ) ] = true
end
for _ , name in ipairs ( { "proxy" , "noProxy" , "proxyCredentials" } ) do
if given [ name ] ~= nil and type ( given [ name ] ) ~= "string" then
error ( "nupp: HTTP " .. name .. " must be a string" , 3 )
end
end
if given . compressed ~= nil and type ( given . compressed ) ~= "boolean" then
error ( "nupp: HTTP compressed must be a boolean" , 3 )
end
local _ , _ , packedHeaders = mergedHeaders ( nil , headers , nil )




return {
headers = headers ,
packedHeaders = packedHeaders ,
timeoutMs = optionInteger ( given , "timeoutMs" , 30000 , 1 ) ,
connectTimeoutMs = optionInteger ( given , "connectTimeoutMs" , 10000 , 1 ) ,
stallTimeoutMs = optionInteger ( given , "stallTimeoutMs" , 0 , 0 ) ,
maxRedirects = whole ( given . maxRedirects or 5 , "maxRedirects" , 0 , 4294967295 ) ,
maxPendingRequests = whole ( given . maxPendingRequests or 256 , "maxPendingRequests" , 1 , 4294967295 ) ,
maxConnections = whole ( given . maxConnections or 16 , "maxConnections" , 1 , 4294967295 ) ,
maxConnectionsPerHost = whole ( given . maxConnectionsPerHost or 16 , "maxConnectionsPerHost" , 1 , 4294967295 ) ,
maxBytes = optionInteger ( given , "maxBytes" , 0 , 0 ) ,
compressed = given . compressed ~= false ,
insecureHosts = insecure ,
manualRedirects = true ,
proxy = given . proxy ,
noProxy = given . noProxy ,
proxyCredentials = given . proxyCredentials ,
}
end





local function appendWaiter ( client , transfer , which , cancelNative ) 
suspension . suspend ( "HTTP " .. which , function ( resume , context ) 
local active = true
client : _retainSource ( context )
local forget

local function finish ( ) 
if not active then
return
end
active = false
if forget ~= nil then
forget ( )
end
client : _releaseSource ( )
resume ( true )
end

if which == "response headers" then
forget = transfer : onHead ( finish )
elseif which == "response body" then
forget = transfer : onBody ( finish )
else
forget = transfer : onUpload ( finish )
end

return function ( ) 
if active then
active = false
forget ( )
client : _releaseSource ( )
if cancelNative then
transfer : cancel ( )
end
end
end
end )
end

local function waitAdmission ( client ) 
suspension . suspend ( "HTTP request admission" , function (
resume ,
context
) 
local active = true
client : _retainSource ( context )
local forget

local function finish ( ) 
if not active then
return
end
active = false
if forget ~= nil then
forget ( )
end
client : _releaseSource ( )
resume ( true )
end

forget = client . _native : onAdmission ( finish )

return function ( ) 
if active then
active = false
forget ( )
client : _releaseSource ( )
end
end
end )
end

local function waitHead ( client , transfer , cancelNative ) 
while true do
local state , status , version , url , headers , reason = transfer : head ( )
if state == "ready" then
return { status = status , version = version , url = url , headers = headers }
elseif state == "failed" then
return { reason = reason }
end
appendWaiter ( client , transfer , "response headers" , cancelNative )
end
end

local function fairnessYield ( ) 
suspension . suspend ( "HTTP response copy fairness" , function (
resume ,
context
) 
local active = true
context : source ( "nupp-http-fairness" , 20 , function ( ) 
if not active then
return 0
end
active = false
resume ( true )

return 1
end )

return function ( ) 
active = false
end
end )
end















http.Body = {} http.Body.__index = http.Body




















function http.Body:read(count) 
local wanted = whole ( count , "body read count" , 1 )
return self : _next ( wanted )
end

function http.Body:readSpan(destination) 
local wanted = whole ( # destination , "body destination length" , 1 )
local chunk , reason = self : _next ( wanted )
if chunk == nil then
return nil , reason
end
local input = span . fromString ( chunk )
for index = 1 , # chunk do
destination :set( index , input :get( index ) )
end

return # chunk
end














function http.Body:readInto(destination, offset, count) 





local at = whole ( offset or 0 , "body destination offset" , 0 )
local wanted = whole ( count or READ_SIZE , "body read count" , 1 )
local chunk , reason = self : _next ( wanted )
if chunk == nil then
return nil , reason
end
if # chunk == 0 then
return 0
end
local input = span . fromString ( chunk )
do local __nuppT36=0; local  __nuppT42 ; local __nuppT43=false ; local __nuppT37,__nuppT38,__nuppT39=__nuppT29(function() do local __nuppT44= destination : reserveWrite ( at , wanted ) ; __nuppT42= __nuppT44 ; __nuppT36=1;  __nuppT43=true;  local lease=__nuppT42;
do
do local __nuppT45=0; local  __nuppT51 ; local __nuppT52=false ; local __nuppT46,__nuppT47,__nuppT48=__nuppT29(function() do local __nuppT53= lease : span ( ) ; __nuppT51= __nuppT53 ; __nuppT45=1;  __nuppT52=true;  local output=__nuppT51;
for index = 1 , # chunk do
output :set( index , input :get( index ) )
end
do __nuppT52=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT25); local __nuppT49={}; local __nuppT50=0; if __nuppT45>=1 and __nuppT52 then  local __nuppT54,__nuppT55=__nuppT28(__nuppCleanup1,__nuppT51);  if not __nuppT54 then __nuppT50=__nuppT50+1; __nuppT49[__nuppT50]=__nuppT55 end; end; if not __nuppT46 then if __nuppT50>0 then __nuppT30(__nuppT26(__nuppT47,__nuppT49,1),0) else __nuppT30(__nuppT47,0) end end; if __nuppT50>0 then if __nuppT50>1 then __nuppT30(__nuppT26(__nuppT49[1],__nuppT49,2),0) else __nuppT30(__nuppT49[1],0) end end; if __nuppT47=="return" then  return "return",__nuppT48  end; end
end
do (function(__nuppT56,...)  __nuppT43=false; return __nuppT56:commit(...)  end)( lease , # chunk ) end

return "return",__nuppT24( # chunk ) end; return "normal" end,__nuppT25); local __nuppT40={}; local __nuppT41=0; if __nuppT36>=1 and __nuppT43 then  local __nuppT57,__nuppT58=__nuppT28(__nuppCleanup2,__nuppT42);  if not __nuppT57 then __nuppT41=__nuppT41+1; __nuppT40[__nuppT41]=__nuppT58 end; end; if not __nuppT37 then if __nuppT41>0 then __nuppT30(__nuppT26(__nuppT38,__nuppT40,1),0) else __nuppT30(__nuppT38,0) end end; if __nuppT41>0 then if __nuppT41>1 then __nuppT30(__nuppT26(__nuppT40[1],__nuppT40,2),0) else __nuppT30(__nuppT40[1],0) end end; if __nuppT38=="return" then  return __nuppT31(__nuppT39,1,__nuppT39.n)  end; end
end









function http.Body:transferTo(destination) 
local total = 0
local turn = 0
while true do
local chunk , failure = self : read ( READ_SIZE )
if chunk == nil then
return nil , failure
elseif chunk == "" then
return total
end
local source = span . fromString ( chunk )
local at = 1
while at <= source .count do
local remaining = source : slice ( at )
local wrote , reason = destination : writeSpan ( remaining )
if wrote == nil then
return nil , reason
elseif wrote < 1 then
return nil , "the destination writer made no progress"
end
at = at + wrote
total = total + wrote
turn = turn + wrote
end
if turn >= COPY_TURN then
fairnessYield ( )
turn = 0
end
end
end














function http.Body:close() 
self : release ( )
end



function http . Body . _next ( self , count ) 
if self . _closed then
return nil , "the body is closed"
end
if self . _reading then
error ( "nupp: an HTTP response body may only have one reader" , 3 )
end
self . _reading = true
while true do
local state , value , reason = self . _transfer : bodyRead ( count )
if state == "data" then
self . _reading = false
return value
elseif state == "eof" then
self . _reading = false
return ""
elseif state == "failed" or state == "closed" then
self . _reading = false
return nil , reason
end
local ok , problem = pcall ( appendWaiter , self . _client , self . _transfer , "response body" , true )
if not ok then
self . _reading = false
error ( problem , 0 )
end
end
end

function http . Body . release ( self ) 
if self . _closed then
return
end
self . _closed = true
self . _transfer : close ( )
end

function http . Body . drop ( self ) 



local body = self
do
if not body . _closed then
body . _closed = true
body . _transfer : close ( )
end
end
end

local function makeBody ( client , transfer ) 
return ( _G.setmetatable({ _client =  client ,  _transfer =  transfer ,  _closed =  false ,  _reading =  false }, http.Body) )
end

local function u32 ( bytes , at ) 
local a , b , c , d = bytes : byte ( at , at + 3 )
if d == nil then
error ( "nupp: malformed packed HTTP response headers" , 0 )
end

return ( ( a or 0 ) + ( b or 0 ) * 256 + ( c or 0 ) * 65536 + ( d or 0 ) * 16777216 )
end

local function packedHeader ( bytes , wanted ) 
local count = u32 ( bytes , 1 )
local tableEnd = 4 + count * 16
if tableEnd > # bytes then
return nil
end
for index = 0 , count - 1 do
local at = 5 + index * 16
local nameAt , nameLength = u32 ( bytes , at ) , u32 ( bytes , at + 4 )
local valueAt , valueLength = u32 ( bytes , at + 8 ) , u32 ( bytes , at + 12 )
if nameAt < tableEnd
or valueAt < tableEnd
or nameAt + nameLength > # bytes
or valueAt + valueLength > # bytes
then
return nil
end
if bytes : sub ( nameAt + 1 , nameAt + nameLength ) : lower ( ) == wanted then
return bytes : sub ( valueAt + 1 , valueAt + valueLength )
end
end

return nil
end

local function origin ( uri ) 
local scheme = uri : scheme ( )
local port = uri : port ( ) or ( scheme == "https" and 443 or 80 )
return scheme .. "://" .. ( uri : host ( ) or "" ) : lower ( ) .. ":" .. port
end



















http.Response = {} http.Response.__index = http.Response



























function http.Response:ok() 
return self . status >= 200 and self . status < 300
end










function http.Response:header(name) 
if type ( name ) ~= "string" then
error ( "nupp: HTTP header name must be a string" , 2 )
end
self : _decode ( )
local values = ( self . _values ) [ name : lower ( ) ]
if values == nil then
return nil
end

return name : lower ( ) == "set-cookie" and values [ 1 ] or table . concat ( values , ", " )
end






function http.Response:headerValues(name) 
if type ( name ) ~= "string" then
error ( "nupp: HTTP header name must be a string" , 2 )
end
self : _decode ( )
local found = ( self . _values ) [ name : lower ( ) ] or { }
local out = { }
for index = 1 , # found do
out [ index ] = found [ index ]
end

return out
end







function http.Response:headers() 
if self . _headers == nil then
self : _decode ( )
local out = { }
for name , values in pairs ( self . _values ) do
out [ name ] = name == "set-cookie" and values [ 1 ] or table . concat ( values , ", " )
end
self . _headers = out
end
local copy = { }
for name , value in pairs ( self . _headers ) do
copy [ name ] = value
end

return copy
end







function http.Response:close() 
self . _closed = true
local body = self . body
body : close ( )
end


function http . Response . _decode ( self ) 
if self . _values ~= nil then
return
end
local values = { }
local count = u32 ( self . _packed , 1 )
local tableEnd = 4 + count * 16
if tableEnd > # self . _packed then
error ( "nupp: malformed packed HTTP response headers" , 0 )
end
for index = 0 , count - 1 do
local at = 5 + index * 16
local nameAt , nameLength = u32 ( self . _packed , at ) , u32 ( self . _packed , at + 4 )
local valueAt , valueLength = u32 ( self . _packed , at + 8 ) , u32 ( self . _packed , at + 12 )
if nameAt < tableEnd
or valueAt < tableEnd
or nameAt + nameLength > # self . _packed
or valueAt + valueLength > # self . _packed
then
error ( "nupp: malformed packed HTTP response headers" , 0 )
end
local name = self . _packed : sub ( nameAt + 1 , nameAt + nameLength ) : lower ( )
local value = self . _packed : sub ( valueAt + 1 , valueAt + valueLength )
local list = values [ name ]
if list == nil then
list = { }
values [ name ] = list
end
list [ # list + 1 ] = value
end
self . _values = values
end

function http . Response . drop ( self ) 


do
self . _closed = true
self . body : drop ( )
end
end

local function makeResponse (
status ,
version ,
url ,
body ,
packed
) 
return ( _G.setmetatable({ status =
status ,  version =
version ,  url =
url ,  body =
body ,  _packed =
packed ,  _values =
nil ,  _headers =
nil ,  _closed =
false }, http.Response) )

end









http.Client = {} http.Client.__index = http.Client























function http.Client.__nuppCtor1(options) local self = _G.setmetatable({}, http.Client)  local __nuppT76=self; 
local copied = copiedOptions ( options )
local backend , reason = newClient ( copied )
if backend == nil then
error ( reason or "the HTTP client could not be initialized" , 2 )
end
self . _native = backend
self . _options = copied
self . _source = nil
self . _sourceUsers = 0
self . _closed = false
return __nuppT76 end










function http.Client:pump(timeoutMs) 
local waitMs = timeoutMs or 0
if waitMs < 0 or math . floor ( waitMs ) ~= waitMs then
error ( "nupp: HTTP pump timeoutMs must be a non-negative integer" , 2 )
end
if not self . _closed then



native . snapshot ( )
if self . _native : poll ( ) == 0 and waitMs > 0 then
native . sleep ( waitMs )
self . _native : poll ( )
end
end
end






function http . Client . _retainSource ( self , context ) 
if self . _source == nil then
local backend = self . _native


self . _source = suspension . source (
"nupp-http" ,
native . READINESS_PRIORITY ,
native . pump ( function ( ) 
return backend : poll ( )
end )
)
end
self . _sourceUsers = self . _sourceUsers + 1
context : uses ( self . _source )
end

function http . Client . _releaseSource ( self ) 
self . _sourceUsers = self . _sourceUsers - 1
if self . _sourceUsers == 0 and self . _source ~= nil then
self . _source : release ( )
self . _source = nil
end
end

local function readUpload (
source ,
destination ,
offset ,
count
) 



if type ( ( source ) . readInto ) == "function" then
local got , reason = ( source ) : readInto ( destination , offset , count )
if got ~= nil and ( type ( got ) ~= "number" or got ~= math . floor ( got ) or got < 0 or got > count ) then
error ( "nupp: HTTP request reader returned an invalid byte count" , 3 )
end

return got , reason
end
local chunk , reason = source : read ( count )
if chunk == nil then
return nil , reason
end
if type ( chunk ) ~= "string" or # chunk > count then
error ( "nupp: HTTP request reader returned invalid bytes" , 3 )
end
destination : setString ( chunk , offset )

return # chunk
end


























function http . Client : send ( request ) local __nuppT83;
local given = request
local state = redirectState [ request ] or { }
if self . _closed then
return nil , io . toError ( "the HTTP client is closed" )
end
if given == nil or given . url == nil or type ( given . url . toString ) ~= "function" then
error ( "nupp: HTTP request url must be a URI" , 2 )
end
local scheme = given . url : scheme ( )
if scheme ~= "http" and scheme ~= "https" then
error ( "nupp: HTTP request URL must use http or https" , 2 )
end
local method = given . method
if method == nil then
method = "GET"
elseif type ( method ) ~= "string" or method == "" or method : find ( "[^!#$%%&'*+%.^_`|~%w%-]" ) ~= nil then
error ( "nupp: HTTP method is not a valid token" , 2 )
end
local requestBody = given . body
local body , bodyKind , bodyLength = requestBody , 0 , nil
do local __nuppT84=0; local  __nuppT90,__nuppT91 ; local __nuppT92=false ; local __nuppT85,__nuppT86,__nuppT87=__nuppT29(function() do local __nuppT93= nil ; __nuppT90= __nuppT93 ; __nuppT84=1;  local reader=__nuppT90;
local contentType = nil
if body ~= nil then
local concrete = body
if concrete . reader ~= nil then
reader = concrete . reader
bodyKind = 2
bodyLength = concrete . length
contentType = concrete . contentType
if bodyLength ~= nil then
whole ( bodyLength , "reader body length" , 0 )
end
elseif concrete . path ~= nil then
bodyKind = 3
body = type ( concrete . path ) == "string" and concrete . path or concrete . path : toString ( )
bodyLength = -1
contentType = concrete . contentType
elseif type ( body ) == "string" then
bodyKind = 1
bodyLength = # ( body )
elseif type ( concrete . length ) == "function" and type ( concrete . getString ) == "function" then
bodyKind = 1
bodyLength = concrete : length ( )
body = concrete : getString ( )
else
error ( "nupp: HTTP request body is not bytes, a Buffer, ReaderBody, or FileBody" , 2 )
end
end
local manualRedirects = self . _options . manualRedirects
local byLower , merged , packed
if given . headers == nil and not state . redirected and contentType == nil and not manualRedirects then
packed = self . _options . packedHeaders
else
byLower , merged , packed = mergedHeaders (
not state . redirected and self . _options . headers or nil ,
given . headers ,
contentType
)
end
local insecure = false
if manualRedirects then
local host = ( given . url : host ( ) or "" ) : lower ( )
insecure = self . _options . insecureHosts [ host ] == true
end
local requestTimeout = given . timeoutMs ~= nil and whole ( given . timeoutMs , "timeoutMs" , 1 ) or self . _options . timeoutMs
local now = self . _native : now ( )
local deadline = state . deadline or ( now + requestTimeout )
local remaining = math . floor ( deadline - now )
if remaining < 1 then
return "return",__nuppT24( nil , io . toError ( "HTTP request timed out" ) )
end
local descriptor = {
uri = given . url ,
method = method ,
headers = packed ,
body = body ,
bodyKind = bodyKind ,
bodyLength = bodyLength ,
timeoutMs = remaining ,
stallTimeoutMs = given . stallTimeoutMs ~= nil and whole ( given . stallTimeoutMs , "stallTimeoutMs" , 0 )
or self . _options . stallTimeoutMs ,
maxBytes = given . maxBytes ~= nil and whole ( given . maxBytes , "maxBytes" , 0 ) or self . _options . maxBytes ,
insecure = insecure ,
}
if not suspension . canSuspend ( ) then
error ( "nupp: HTTP request cannot suspend here" , 2 )
end
local transfer , reason
while transfer == nil do
remaining = math . floor ( deadline - self . _native : now ( ) )
if remaining < 1 then
return "return",__nuppT24( nil , io . toError ( "HTTP request timed out waiting for admission" ) )
end
descriptor . timeoutMs = remaining
local full
transfer , reason , full = self . _native : send ( descriptor )
if transfer == nil and not full then
return "return",__nuppT24( nil , io . toError ( reason ) )
elseif transfer == nil then
waitAdmission ( self )
if self . _closed then
return "return",__nuppT24( nil , io . toError ( "the HTTP client is closed" ) )
end
end
end
local head , problem
if reader ~= nil then
do local __nuppT94=0; local  __nuppT100,__nuppT102 ; local __nuppT101=false ; local __nuppT103=false ; local __nuppT95,__nuppT96,__nuppT97=__nuppT29(function() do local __nuppT104= io . newBuffer ( 524288 ) ; __nuppT100= __nuppT104 ; __nuppT94=1;  __nuppT101=true;  local scratch=__nuppT100;
local uploadTransfer = transfer local __nuppT105= (function(scratch) local __nuppT106=true;  __nuppT101=false;  local __nuppT107=function

( ) local __nuppT109; do const  __nuppT116= scratch ; __nuppT109=__nuppT109 or {} ; local __nuppT117=__nuppT109[1]; if not __nuppT117 then __nuppT117=function(scratch) do
local transferred = 0
while true do
scratch : clear ( )
local got , failure = readUpload ( reader , scratch , 0 , 524288 )
if got == nil then
transfer : cancel ( )
error ( failure or "HTTP request reader failed" , 0 )
end
local finished = got == 0
if not finished and ( got ) < 8192 then
while scratch : length ( ) < 65536 do
local more , moreFailure = readUpload (
reader ,
scratch ,
scratch : length ( ) ,
65536 - scratch : length ( )
)
if more == nil then
transfer : cancel ( )
error ( moreFailure or "HTTP request reader failed" , 0 )
elseif more == 0 then
finished = true
do break end
end
end
end
local offered = scratch : length ( )
if offered > 0 then
local source = scratch : getString ( )
while true do
local accepted = uploadTransfer : offer ( source , offered )
if accepted == "accepted" then
do break end
elseif accepted == "closed" then
return "return",__nuppT24( waitHead ( self , transfer , false ) )
end
appendWaiter ( self , transfer , "upload space" , false )
end
transferred = transferred + offered
end
if finished then
if bodyLength ~= nil and transferred ~= bodyLength then
transfer : cancel ( )
error (
("HTTP request reader ended after %d bytes; expected %d") : format ( transferred , bodyLength ) ,
0
)
end
if transfer : finishUpload ( ) == "closed" then
return "return",__nuppT24( waitHead ( self , transfer , false ) )
end
return "return",__nuppT24( waitHead ( self , transfer , false ) )
end
end end; return "normal" end; __nuppT109[1]=__nuppT117 end; const __nuppT111,__nuppT112,__nuppT113=__nuppT29(__nuppT117,__nuppT25,__nuppT116); const __nuppT110=1; local __nuppT114={}; local __nuppT115=0; if __nuppT110>=1 then  local __nuppT119,__nuppT120=__nuppT28(__nuppT118,__nuppT116);  if not __nuppT119 then __nuppT115=__nuppT115+1; __nuppT114[__nuppT115]=__nuppT120 end; end; if not __nuppT111 then if __nuppT115>0 then __nuppT30(__nuppT26(__nuppT112,__nuppT114,1),0) else __nuppT30(__nuppT112,0) end end; if __nuppT115>0 then if __nuppT115>1 then __nuppT30(__nuppT26(__nuppT114[1],__nuppT114,2),0) else __nuppT30(__nuppT114[1],0) end end; if __nuppT112=="return" then  return __nuppT31(__nuppT113,1,__nuppT113.n)  end; end
end ; local __nuppT108={};  __nuppT108.__nuppRelease=function() if not __nuppT106 then return end; __nuppT106=false;  local __nuppT121={}; local __nuppT122=0;  local __nuppT123,__nuppT124=__nuppT28(__nuppT118,scratch); if not __nuppT123 then __nuppT122=__nuppT122+1; __nuppT121[__nuppT122]=__nuppT124 end;  if __nuppT122>0 then if __nuppT122>1 then __nuppT30(__nuppT26(__nuppT121[1],__nuppT121,2),0) else __nuppT30(__nuppT121[1],0) end end end;  return _G.setmetatable(__nuppT108,{__call=function(_,...) if not __nuppT106 then __nuppT30("nupp: affine closure was already called or dropped",2) end;  __nuppT106=false; return __nuppT107(...) end}) end)( scratch ) ; __nuppT102= __nuppT105 ; __nuppT94=2;  __nuppT103=true;  local uploadAndWait=__nuppT102;

local ok , value = pcall ( (function(uploadAndWait) local __nuppT125=true;  __nuppT103=false;  local __nuppT126=function ( )  do local __nuppT129=0; local  __nuppT135 ; local __nuppT136=false ; local __nuppT130,__nuppT131,__nuppT132=__nuppT29(function() do local __nuppT137= uploadAndWait ; __nuppT135= __nuppT137 ; __nuppT129=1;  __nuppT136=true;  local uploadAndWait=__nuppT135;
local answer = (function(__nuppT138,...)  __nuppT136=false; return __nuppT138(...)  end)( tasks . race , {
uploadAndWait ,
function ( ) 
return waitHead ( self , transfer , false )
end
} )

return "return",__nuppT24( answer ) end; return "normal" end,__nuppT25); local __nuppT133={}; local __nuppT134=0; if __nuppT129>=1 and __nuppT136 then  local __nuppT140,__nuppT141=__nuppT28(__nuppClosureCleanup3,__nuppT135);  if not __nuppT140 then __nuppT134=__nuppT134+1; __nuppT133[__nuppT134]=__nuppT141 end; end; if not __nuppT130 then if __nuppT134>0 then __nuppT30(__nuppT26(__nuppT131,__nuppT133,1),0) else __nuppT30(__nuppT131,0) end end; if __nuppT134>0 then if __nuppT134>1 then __nuppT30(__nuppT26(__nuppT133[1],__nuppT133,2),0) else __nuppT30(__nuppT133[1],0) end end; if __nuppT131=="return" then  return __nuppT31(__nuppT132,1,__nuppT132.n)  end; end
end ; local __nuppT127={};  __nuppT127.__nuppRelease=function() if not __nuppT125 then return end; __nuppT125=false;  local __nuppT142={}; local __nuppT143=0;  local __nuppT144,__nuppT145=__nuppT28(__nuppClosureCleanup3,uploadAndWait); if not __nuppT144 then __nuppT143=__nuppT143+1; __nuppT142[__nuppT143]=__nuppT145 end;  if __nuppT143>0 then if __nuppT143>1 then __nuppT30(__nuppT26(__nuppT142[1],__nuppT142,2),0) else __nuppT30(__nuppT142[1],0) end end end;  return _G.setmetatable(__nuppT127,{__call=function(_,...) if not __nuppT125 then __nuppT30("nupp: affine closure was already called or dropped",2) end;  __nuppT125=false; return __nuppT126(...) end}) end)( uploadAndWait ) )
if not ok then
transfer : cancel ( )
transfer : close ( )
error ( value , 0 )
end
head = value end; return "normal" end,__nuppT25); local __nuppT98={}; local __nuppT99=0; if __nuppT94>=2 and __nuppT103 then  local __nuppT146,__nuppT147=__nuppT28(__nuppClosureCleanup3,__nuppT102);  if not __nuppT146 then __nuppT99=__nuppT99+1; __nuppT98[__nuppT99]=__nuppT147 end; end; if __nuppT94>=1 and __nuppT101 then  local __nuppT148,__nuppT149=__nuppT28(__nuppT118,__nuppT100);  if not __nuppT148 then __nuppT99=__nuppT99+1; __nuppT98[__nuppT99]=__nuppT149 end; end; if not __nuppT95 then if __nuppT99>0 then __nuppT30(__nuppT26(__nuppT96,__nuppT98,1),0) else __nuppT30(__nuppT96,0) end end; if __nuppT99>0 then if __nuppT99>1 then __nuppT30(__nuppT26(__nuppT98[1],__nuppT98,2),0) else __nuppT30(__nuppT98[1],0) end end; if __nuppT96=="return" then  return "return",__nuppT97  end; end
else



local ok , value = pcall ( waitHead , self , transfer , true )
if not ok then
transfer : cancel ( )
transfer : close ( )
error ( value , 0 )
end
head = value
end
if head == nil or head . reason ~= nil then
problem = head and head . reason or "HTTP transfer failed"
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( problem ) )
end
local status = head . status
if type ( status ) ~= "number" or status ~= math . floor ( status ) or status < 100 or status > 599 then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "the HTTP provider returned an invalid response status" ) )
end
if head . version ~= 10 and head . version ~= 11 and head . version ~= 20 then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "the HTTP provider returned an invalid protocol version" ) )
end
if type ( head . headers ) ~= "string" then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "the HTTP provider returned invalid response headers" ) )
end
local location = manualRedirects and packedHeader ( head . headers , "location" ) or nil
if manualRedirects
and location ~= nil
and ( status == 301 or status == 302 or status == 303 or status == 307 or status == 308 )
then
local followed = ( state . redirects or 0 )
if followed >= self . _options . maxRedirects then
if self . _options . maxRedirects == 0 then
location = nil
else
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "HTTP request exceeded maxRedirects" ) )
end
end
if location ~= nil then
local target , targetReason = given . url : resolve ( location )
if target == nil then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( targetReason or "HTTP redirect has an invalid location" ) )
end
if target : scheme ( ) ~= "http" and target : scheme ( ) ~= "https" then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "HTTP redirect must use http or https" , "invalid" ) )
end
local nextMethod , nextBody = method , requestBody
local dropsBody = status == 303 and method ~= "HEAD"
or ( status == 301 or status == 302 ) and method == "POST"
if dropsBody then
nextMethod = "GET"
nextBody = nil
for _ , name in ipairs ( { "content-length" , "content-type" , "transfer-encoding" } ) do
local spelling = byLower [ name ]
if spelling ~= nil then
merged [ spelling ] = nil
end
end
elseif reader ~= nil then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "HTTP redirect cannot replay a ReaderBody" , "unsupported" ) )
end
if origin ( given . url ) ~= origin ( target ) then
for _ , name in ipairs ( { "authorization" , "proxy-authorization" , "cookie" , "host" } ) do
local spelling = byLower [ name ]
if spelling ~= nil then
merged [ spelling ] = nil
end
end
end
transfer : close ( )
do const  __nuppT156= _G.setmetatable({ url =
target ,  method =
nextMethod ,  headers =
merged ,  body =
nextBody ,  timeoutMs =
given . timeoutMs ,  stallTimeoutMs =
given . stallTimeoutMs ,  maxBytes =
given . maxBytes }, messages.Request) ; __nuppT83=__nuppT83 or {} ; local __nuppT157=__nuppT83[2]; if not __nuppT157 then __nuppT157=function(redirected) do

redirectState [ redirected ] = { redirected = true , redirects = followed + 1 , deadline = deadline }
return "return",__nuppT24( self : send ( redirected ) ) end; return "normal" end; __nuppT83[2]=__nuppT157 end; const __nuppT151,__nuppT152,__nuppT153=__nuppT29(__nuppT157,__nuppT25,__nuppT156); const __nuppT150=1; local __nuppT154={}; local __nuppT155=0; if __nuppT150>=1 then  local __nuppT158,__nuppT159=__nuppT28(__nuppT118,__nuppT156);  if not __nuppT158 then __nuppT155=__nuppT155+1; __nuppT154[__nuppT155]=__nuppT159 end; end; if not __nuppT151 then if __nuppT155>0 then __nuppT30(__nuppT26(__nuppT152,__nuppT154,1),0) else __nuppT30(__nuppT152,0) end end; if __nuppT155>0 then if __nuppT155>1 then __nuppT30(__nuppT26(__nuppT154[1],__nuppT154,2),0) else __nuppT30(__nuppT154[1],0) end end; if __nuppT152=="return" then  return "return",__nuppT153  end; end
end
end
local bodyReady , bodyReason = transfer : takeBody ( )
if not bodyReady then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( bodyReason ) )
end
local effective = head . url == nil and given . url or uri . newURI ( head . url )
if effective == nil then
transfer : close ( )
return "return",__nuppT24( nil , io . toError ( "the HTTP provider returned an invalid effective URL" ) )
end
local version = head . version == 10 and "1.0" or head . version == 20 and "2" or "1.1"
local __nuppT160= makeBody ( self , transfer ) ; __nuppT91= __nuppT160 ; __nuppT84=2;  __nuppT92=true;  local responseBody=__nuppT91;

return "return",__nuppT24( (function(__nuppT161,...)  __nuppT92=false; return __nuppT161(...)  end)( makeResponse , status , version , effective , responseBody , head . headers ) ) end; return "normal" end,__nuppT25); local __nuppT88={}; local __nuppT89=0; if __nuppT84>=2 and __nuppT92 then  local __nuppT162,__nuppT163=__nuppT28(__nuppT118,__nuppT91);  if not __nuppT162 then __nuppT89=__nuppT89+1; __nuppT88[__nuppT89]=__nuppT163 end; end; if __nuppT84>=1 and __nuppT90~=nil then  local __nuppT164,__nuppT165=__nuppT28(__nuppT118,__nuppT90);  if not __nuppT164 then __nuppT89=__nuppT89+1; __nuppT88[__nuppT89]=__nuppT165 end; end; if not __nuppT85 then if __nuppT89>0 then __nuppT30(__nuppT26(__nuppT86,__nuppT88,1),0) else __nuppT30(__nuppT86,0) end end; if __nuppT89>0 then if __nuppT89>1 then __nuppT30(__nuppT26(__nuppT88[1],__nuppT88,2),0) else __nuppT30(__nuppT88[1],0) end end; if __nuppT86=="return" then  return __nuppT31(__nuppT87,1,__nuppT87.n)  end; end
end





function http . Client : pending ( ) 
return self . _closed and 0 or self . _native : pending ( )
end





function http . Client . close ( self ) 
do
if not self . _closed then
self . _closed = true
if self . _source ~= nil then
self . _source : release ( )
self . _source = nil
self . _sourceUsers = 0
end
local client = self . _native
client : close ( )
end
end
end





local function openClient ( options ) 
return ( http . Client .__nuppCtor1 ( options ) )
end

local __nuppExportValue= { newClient = openClient , capabilities = http . capabilities } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativehttp"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativehttp"]=__nuppExports;return __nuppExports