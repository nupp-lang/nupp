_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT25={}; local function __nuppT22(...) return {n=select("#",...),...} end; local __nuppT26,__nuppT27,__nuppT28,__nuppT29,__nuppT30,__nuppT31,__nuppT32,__nuppT33=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT23(value) return value end; local function __nuppT24(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT31({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT32(v.primary) for _,reason in __nuppT33(v.suppressed) do text=text.."\ncleanup: "..__nuppT32(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT65;__nuppT65=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppT65=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppCleanup2 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local effects = require ( "nupp.runtime.browser.effects" )
local span = require ( "nupp.mem.span" )
local response = require ( "nupp.runtime.browser.response" )
local suspension = require ( "nupp.suspension" )
local uri = require ( "nupp.io.uri" )

local io = require ( "nupp.io" )
local ownedReader = require ( "nupp.io.internal.ownedreader" )
local contracts = require ( "nupp.io.http.spi" )
local memory = require ( "nupp.runtime.browser.memory" )
local http = { }
local MAX_EXACT_INTEGER = 9007199254740991

const messages = require ( "nupp.io.http.messages" )




function http . capabilities ( ) 
return ( _G.setmetatable({ streamingResponse =
false ,  streamingRequest =
false ,  transportPolicy =
false ,  connectionPolicy =
false ,  protocolVersion =
false }, messages.Capabilities) )

end





http . ReaderBody = messages . ReaderBody

http . FileBody = messages . FileBody


http . Request = messages . Request



local function whole ( value , what , minimum ) 
if type ( value ) ~= "number" or value ~= math . floor ( value ) or value < minimum then
error ( ("nupp: HTTP %s must be an integer of at least %d") : format ( what , minimum ) , 3 )
end

return value
end

local function copyHeaders ( values , what ) 
if values ~= nil and type ( values ) ~= "table" then
error ( "nupp: HTTP " .. what .. " must be a table" , 3 )
end
local out = { }
for name , value in pairs ( values or { } ) do
if type ( name ) ~= "string"
or type ( value ) ~= "string"
or name == ""
or name : find ( "[\13\n:]" ) ~= nil
or value : find ( "[\13\n]" ) ~= nil
then
error ( "nupp: HTTP headers need valid string names and values" , 3 )
end
out [ name ] = value
end

return out
end

local function hostInteger ( value , minimum , maximum ) 
if type ( value ) ~= "number" or value ~= math . floor ( value ) or value < minimum or value > maximum then
return nil
end

return value
end

local function responseHeaders ( values ) 
if type ( values ) ~= "table" then
return nil , "browser HTTP host returned invalid response headers"
end
local byName = { }
local count = 0
local highest = 0
for index , pair in pairs ( values ) do
if type ( index ) ~= "number" or index < 1 or index ~= math . floor ( index ) then
return nil , "browser HTTP host returned invalid response headers"
end
count = count + 1
highest = math . max ( highest , index )
if type ( pair ) ~= "table"
or type ( pair [ 1 ] ) ~= "string"
or type ( pair [ 2 ] ) ~= "string"
or pair [ 1 ] == ""
or pair [ 1 ] : find ( "[\13\n:]" ) ~= nil
or pair [ 2 ] : find ( "[\13\n]" ) ~= nil
then
return nil , "browser HTTP host returned invalid response headers"
end
local name = pair [ 1 ] : lower ( )
local entries = byName [ name ] or { }
entries [ # entries + 1 ] = pair [ 2 ]
byName [ name ] = entries
end
if count ~= highest then
return nil , "browser HTTP host returned invalid response headers"
end

return byName , nil
end

local function releaseBody ( handle ) 
effects . request ( "http" , { operation = "release-body" , body = handle , } , function ( ) 
end )
end

local function orphanedResponse ( answer ) 
if type ( answer ) ~= "table" or answer . ok ~= true or type ( answer . value ) ~= "table" then
return
end
local handle = hostInteger ( answer . value . body , 1 , 9007199254740991 )
if handle ~= nil then
releaseBody ( handle )
end
end

http.Response = {} http.Response.__index = http.Response







function http.Response:ok() 
return self . status >= 200 and self . status < 300
end

function http.Response:headerValues(name) 
local values = self . _headers [ name : lower ( ) ] or { }
local copy = { }
for index = 1 , # values do
copy [ index ] = values [ index ]
end

return copy
end

function http.Response:header(name) 
local values = self . _headers [ name : lower ( ) ]
if values == nil then
return nil
end

return name : lower ( ) == "set-cookie" and values [ 1 ] or table . concat ( values , ", " )
end

function http.Response:headers() 
local values = { }
for name , entries in pairs ( self . _headers ) do
values [ name ] = name == "set-cookie" and entries [ 1 ] or table . concat ( entries , ", " )
end

return values
end

function http.Response:close() 
self . _closed = true
self . body : close ( )
end


local function makeResponse (
status ,
url ,
body ,
headers
) 
return ( _G.setmetatable({ status =
status ,  version =
nil ,  url =
url ,  body =
body ,  _headers =
headers ,  _closed =
false }, http.Response) )

end

http.Client = {} http.Client.__index = http.Client




function http.Client.__nuppCtor1(options) local self = _G.setmetatable({}, http.Client)  local __nuppT15=self; 
local given = options or { }
if type ( given ) ~= "table" then
error ( "nupp: HTTP options must be a table" , 2 )
end
for _ , key in ipairs ( {
"userAgent" ,
"connectTimeoutMs" ,
"stallTimeoutMs" ,
"maxRedirects" ,
"maxPendingRequests" ,
"maxConnections" ,
"maxConnectionsPerHost" ,
"insecureHosts" ,
"proxy" ,
"noProxy" ,
"proxyCredentials" ,
"compressed"
} ) do
if given [ key ] ~= nil then
error ( "nupp: browser HTTP does not support option " .. key , 2 )
end
end
self . _options = {
headers = copyHeaders ( given . headers , "default headers" ) ,
timeoutMs = given . timeoutMs == nil and 30000 or whole ( given . timeoutMs , "timeoutMs" , 1 ) ,
maxBytes = given . maxBytes == nil and 0 or whole ( given . maxBytes , "maxBytes" , 0 ) ,
}
self . _closed = false
self . _pending = 0
return __nuppT15 end


function http.Client:pump(timeoutMs) 
end

function http.Client:pending() 
return self . _pending
end

function http.Client:send(request) 
if self . _closed then
return nil , io . toError ( "the HTTP client is closed" )
end
if type ( request ) ~= "table" then
error ( "nupp: HTTP request must be a Request" , 2 )
end
if request . stallTimeoutMs ~= nil then
return nil , io . toError ( "browser HTTP does not support stallTimeoutMs" )
end
local url = request . url
if url == nil or type ( url . toString ) ~= "function" then
error ( "nupp: HTTP request url must be a URI" , 2 )
end
local scheme = url : scheme ( )
if scheme ~= "http" and scheme ~= "https" then
error ( "nupp: HTTP request URL must use http or https" , 2 )
end
local method = request . method or "GET"
if type ( method ) ~= "string" or method == "" or method : find ( "[^!#$%%&'*+%.^_`|~%w%-]" ) ~= nil then
error ( "nupp: HTTP method is not a valid token" , 2 )
end
local headers = { }
local headerPositions = { }

local function addHeaders ( values ) 
for name , value in pairs ( copyHeaders ( values , "headers" ) ) do
local lower = name : lower ( )
local position = headerPositions [ lower ]
if position == nil then
headers [ # headers + 1 ] = { name , value }
headerPositions [ lower ] = # headers
else
headers [ position ] = { name , value }
end
end
end

addHeaders ( self . _options . headers )
addHeaders ( request . headers )
local body = request . body
local upload = nil
if type ( body ) == "string" then
upload = body
elseif ( _G.getmetatable( body )?.__index == require("nupp.io.http.messages").ReaderBody ) then
if body . length ~= nil then
whole ( body . length , "reader body length" , 0 )
end
if body . contentType ~= nil and type ( body . contentType ) ~= "string" then
error ( "nupp: HTTP content type must be a string" , 2 )
end
local chunks = { }
local length = 0
while true do
local bytes , reason = body . reader : read ( 65536 )
if bytes == nil then
return nil , io . toError ( reason )
elseif bytes == "" then
do break end
end
length = length + # bytes
if body . length ~= nil and length > body . length then
return nil , io . toError ( "HTTP upload exceeded its declared length" )
end
chunks [ # chunks + 1 ] = bytes
end
if body . length ~= nil and length ~= body . length then
return nil , io . toError ( "HTTP upload ended before its declared length" )
end
upload = table . concat ( chunks )
if body . contentType ~= nil and headerPositions [ "content-type" ] == nil then
headers [ # headers + 1 ] = { "content-type" , body . contentType }
headerPositions [ "content-type" ] = # headers
end
elseif body ~= nil then
return nil , io . toError ( "browser HTTP file uploads require an available file host" )
end
local descriptor = {
memoryResponse = true ,
url = url : toString ( ) ,
method = method ,
timeoutMs = request . timeoutMs == nil and self . _options . timeoutMs
or whole ( request . timeoutMs , "timeoutMs" , 1 ) ,
maxBytes = request . maxBytes == nil and self . _options . maxBytes or whole ( request . maxBytes , "maxBytes" , 0 ) ,
}
if # headers > 0 then


descriptor . headers = headers
end
local leaseRead = memory . lease




if upload ~= nil then
local input = span . fromString ( upload )
local pointer , count = input : ref ( )
descriptor . bodyLease = leaseRead ( pointer , count , false )
end
self . _pending = self . _pending + 1
local completed , suspended = pcall ( suspension . suspend , "browser HTTP request" , function (
resume
) 
return effects . request ( "http" , descriptor , resume , orphanedResponse )
end )
if descriptor . bodyLease ~= nil then
memory . releaseLease ( descriptor . bodyLease )
end
self . _pending = self . _pending - 1
if not completed then
error ( suspended , 0 )
end
local answer = suspended
if type ( answer ) ~= "table" or type ( answer . ok ) ~= "boolean" then
return nil , io . toError ( "browser HTTP host returned an invalid response" )
end
if not answer . ok then
return nil , io . toError ( type ( answer . error ) == "string" and answer . error or "browser HTTP request failed" )
end
local value = answer . value
if type ( value ) ~= "table" then
return nil , io . toError ( "browser HTTP host returned an invalid response value" )
end
local body = hostInteger ( value . body , 1 , MAX_EXACT_INTEGER )
if body == nil then
return nil , io . toError ( "browser HTTP host returned an invalid body handle" )
end
local bodyBytes = hostInteger ( value . bodyBytes , 0 , MAX_EXACT_INTEGER )
local status = hostInteger ( value . status , 100 , 599 )
local byName , headersProblem = responseHeaders ( value . headers )
if bodyBytes == nil or ( descriptor . maxBytes > 0 and bodyBytes > descriptor . maxBytes ) then
releaseBody ( body )
return nil , io . toError ( "browser HTTP host returned an invalid body length" )
elseif status == nil then
releaseBody ( body )
return nil , io . toError ( "browser HTTP host returned an invalid status" )
elseif byName == nil then
releaseBody ( body )
return nil , io . toError ( headersProblem )
end
do local __nuppT34=0; local  __nuppT40,__nuppT42,__nuppT44 ; local __nuppT41=false ; local __nuppT43=false ; local __nuppT45=false ; local __nuppT35,__nuppT36,__nuppT37=__nuppT27(function() do local __nuppT46= io . newBuffer ( bodyBytes ) ; __nuppT40= __nuppT46 ; __nuppT34=1;  __nuppT41=true;  local storage=__nuppT40;
local __nuppT47= storage : reserveWrite ( 0 , bodyBytes ) ; __nuppT42= __nuppT47 ; __nuppT34=2;  __nuppT43=true;  local lease=__nuppT42;
do
do local __nuppT48=0; local  __nuppT54 ; local __nuppT55=false ; local __nuppT49,__nuppT50,__nuppT51=__nuppT27(function() do local __nuppT56= lease : span ( ) ; __nuppT54= __nuppT56 ; __nuppT48=1;  __nuppT55=true;  local output=__nuppT54;
do
local pointer , count = output : ref ( )
local leaseWrite = memory . lease




local token = leaseWrite ( pointer , count , true )
local copied , result = pcall ( response . await , "http" , {
operation = "read-body" ,
body = body ,
lease = token
} )
memory . releaseLease ( token )
if not copied then
releaseBody ( body )
error ( result , 0 )
end
if type ( result ) ~= "table" or result . bytes ~= bodyBytes then
releaseBody ( body )
error ( "nupp: browser HTTP host returned an invalid copied byte count" , 0 )
end
end
do __nuppT55=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT23); local __nuppT52={}; local __nuppT53=0; if __nuppT48>=1 and __nuppT55 then  local __nuppT57,__nuppT58=__nuppT26(__nuppCleanup1,__nuppT54);  if not __nuppT57 then __nuppT53=__nuppT53+1; __nuppT52[__nuppT53]=__nuppT58 end; end; if not __nuppT49 then if __nuppT53>0 then __nuppT28(__nuppT24(__nuppT50,__nuppT52,1),0) else __nuppT28(__nuppT50,0) end end; if __nuppT53>0 then if __nuppT53>1 then __nuppT28(__nuppT24(__nuppT52[1],__nuppT52,2),0) else __nuppT28(__nuppT52[1],0) end end; if __nuppT50=="return" then  return "return",__nuppT51  end; end
end
do (function(__nuppT59,...)  __nuppT43=false; return __nuppT59:commit(...)  end)( lease , bodyBytes ) end
local __nuppT60= (function(__nuppT61,...)  __nuppT41=false; return __nuppT61(...)  end)( ownedReader . newOwnedReader , storage ) ; __nuppT44= __nuppT60 ; __nuppT34=3;  __nuppT45=true;  local responseBody=__nuppT44;


local finalUrl = request . url
if type ( value . url ) == "string" and value . url ~= "" then
local landed = uri . newURI ( value . url )
if landed ~= nil then
finalUrl = landed
end
end

return "return",__nuppT22( (function(__nuppT62,...)  __nuppT45=false; return __nuppT62(...)  end)( makeResponse , status , finalUrl , responseBody , byName ) ) end; return "normal" end,__nuppT23); local __nuppT38={}; local __nuppT39=0; if __nuppT34>=3 and __nuppT45 then  local __nuppT63,__nuppT64=__nuppT26(__nuppCleanup2,__nuppT44);  if not __nuppT63 then __nuppT39=__nuppT39+1; __nuppT38[__nuppT39]=__nuppT64 end; end; if __nuppT34>=2 and __nuppT43 then  local __nuppT66,__nuppT67=__nuppT26(__nuppT65,__nuppT42);  if not __nuppT66 then __nuppT39=__nuppT39+1; __nuppT38[__nuppT39]=__nuppT67 end; end; if __nuppT34>=1 and __nuppT41 then  local __nuppT68,__nuppT69=__nuppT26(__nuppCleanup2,__nuppT40);  if not __nuppT68 then __nuppT39=__nuppT39+1; __nuppT38[__nuppT39]=__nuppT69 end; end; if not __nuppT35 then if __nuppT39>0 then __nuppT28(__nuppT24(__nuppT36,__nuppT38,1),0) else __nuppT28(__nuppT36,0) end end; if __nuppT39>0 then if __nuppT39>1 then __nuppT28(__nuppT24(__nuppT38[1],__nuppT38,2),0) else __nuppT28(__nuppT38[1],0) end end; if __nuppT36=="return" then  return __nuppT29(__nuppT37,1,__nuppT37.n)  end; end
end

function http.Client:close() 
self . _closed = true
end


local function newClient ( options ) 
return ( http . Client .__nuppCtor1 ( options ) )
end

local __nuppExportValue= { newClient = newClient , capabilities = http . capabilities } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.http"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.http"]=__nuppExports;return __nuppExports