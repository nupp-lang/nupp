_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.io.uri"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local isURI;__nuppExports["isURI"]=function(...) return isURI(...) end;local newURI;__nuppExports["newURI"]=function(...) return newURI(...) end;local validate;__nuppExports["validate"]=function(...) return validate(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.uri\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.io.uri\0runtime\0002") };













































































































































































local contracts = require ( "nupp.io.uri.spi" )
const provider = require ( "nupp.io.uri.provider" )
const whatwg = require ( "nupp.io.uri.whatwg" )



local Components = {} Components.__index = Components ;_G.nupp.__reflect.link(Components,__nuppT1[1],{ }) ;__nuppExports["Components"]=Components
























local URI = {} URI.__index = URI














function URI:toString() 
return self . _text
end




function URI:scheme() 
return self . _scheme
end




function URI:authority() 
return self . _authority
end




function URI:username() 
return self . _username
end




function URI:password() 
return self . _password
end




function URI:host() 
return self . _host
end




function URI:port() 
return self . _port
end




function URI:path() 
return self . _path
end




function URI:query() 
return self . _query
end




function URI:fragment() 
return self . _fragment
end




function URI:userInfo() 
if self . _username == "" and self . _password == nil then
return nil
end
return self . _username .. ( self . _password ~= nil and ":" .. self . _password or "" )
end







function URI:withScheme(value) 


if not value : match ( "^[A-Za-z][A-Za-z0-9+.-]*$" ) then
error ( "nupp: a URI scheme is a letter and then letters, digits, +, - or ., not " .. ( "%q" ) : format ( value ) , 2 )
end
local result , reason = newURI ( value .. self . _text : sub ( # self . _scheme + 1 ) )
if result == nil then
error ( "nupp: the scheme " .. value .. " cannot be used here: " .. tostring ( reason ) , 2 )
end


local before , after = self . _host , result : host ( )
if ( before == nil ) ~= ( after == nil ) or ( before ~= nil and before : lower ( ) ~= ( after ) : lower ( ) ) then
error ( "nupp: the scheme " .. value .. " cannot be used here: it would change the host" , 2 )
end

return result
end






function URI:withUserInfo(value) 
return assert (
newURI (
_G.setmetatable({ scheme =
self . _scheme ,  userInfo =
value ,  host =
self . _host ,  port =
self . _port ,  path =
self . _path ,  query =
self . _query ,  fragment =
self . _fragment }, Components)

)
)
end






function URI:withHost(value) 
return assert (
newURI (
_G.setmetatable({ scheme =
self . _scheme ,  userInfo =
value ~= nil and self : userInfo ( ) or nil ,  host =
value ,  port =
value ~= nil and self . _port or nil ,  path =
self . _path ,  query =
self . _query ,  fragment =
self . _fragment }, Components)

)
)
end






function URI:withPort(value) 
return assert (
newURI (
_G.setmetatable({ scheme =
self . _scheme ,  userInfo =
self : userInfo ( ) ,  host =
self . _host ,  port =
value ,  path =
self . _path ,  query =
self . _query ,  fragment =
self . _fragment }, Components)

)
)
end






function URI:withPath(value) 
if self . _authority ~= nil and value ~= "" and value : sub ( 1 , 1 ) ~= "/" then
value = "/" .. value
end
return assert (
newURI (
_G.setmetatable({ scheme =
self . _scheme ,  userInfo =
self : userInfo ( ) ,  host =
self . _host ,  port =
self . _port ,  path =
value ,  query =
self . _query ,  fragment =
self . _fragment }, Components)

)
)
end






function URI:withQuery(value) 
return assert (
newURI (
_G.setmetatable({ scheme =
self . _scheme ,  userInfo =
self : userInfo ( ) ,  host =
self . _host ,  port =
self . _port ,  path =
self . _path ,  query =
value ,  fragment =
self . _fragment }, Components)

)
)
end






function URI:withFragment(value) 
return assert (
newURI (
_G.setmetatable({ scheme =
self . _scheme ,  userInfo =
self : userInfo ( ) ,  host =
self . _host ,  port =
self . _port ,  path =
self . _path ,  query =
self . _query ,  fragment =
value }, Components)

)
)
end






function URI:concatPath(value) 
if value == "" then
return self
end

return self : withPath ( self . _path : gsub ( "/$" , "" ) .. "/" .. value : gsub ( "^/" , "" ) )
end




















function URI:resolve(reference) 
local base = _G.setmetatable({ text =
self . _text ,  scheme =
self . _scheme ,  authority =
self . _authority ,  username =
self . _username ,  password =
self . _password ,  host =
self . _host ,  port =
self . _port ,  path =
self . _path ,  query =
self . _query ,  fragment =
self . _fragment }, contracts.UriParts)




local parts , reason = whatwg . parse ( reference , base , true )
if parts == nil then
return nil , reason
end

return newURI ( parts . text )
end






function URI:withEndpoint(endpoint) 
return endpoint : concatPath ( self . _path ) : withQuery ( self . _query ) : withFragment ( self . _fragment )
end ;_G.nupp.__reflect.link(URI,__nuppT1[2],{ }) ;__nuppExports["URI"]=URI





;
( URI ) . __tostring = function ( self ) 
return self : toString ( )
end ;
( URI ) . __eq = function ( left , right ) 
return left : toString ( ) == right : toString ( )
end

local function fromComponents ( components ) 
if type ( components ) ~= "table" then
return nil , "nupp: io.URI.newURI needs absolute text or URI components"
end
local scheme = components . scheme
if type ( scheme ) ~= "string" or not ( scheme ) : match ( "^[A-Za-z][A-Za-z0-9+.-]*$" ) then
return nil , "nupp: URI components need a non-empty scheme"
end
for _ , name in ipairs ( { "userInfo" , "host" , "path" , "query" , "fragment" , } ) do
local value = components [ name ]
if value ~= nil and type ( value ) ~= "string" then
return nil , "nupp: URI component " .. name .. " must be a string or nil"
end
end
local port = components . port
if port ~= nil and ( type ( port ) ~= "number" or port ~= math . floor ( port ) or port < 0 or port > 65535 ) then
return nil , "nupp: URI component port must be an integer from 0 through 65535 or nil"
end



for name , delimiters in pairs ( { userInfo = "[/?#]" , host = "[/?#@]" , path = "[?#]" , query = "#" , } ) do
local value = components [ name ]
if value ~= nil and ( value ) : find ( delimiters ) ~= nil then
return nil , "nupp: URI component " .. name .. " cannot contain a component delimiter"
end
end


local host = components . host
if host ~= nil and ( host ) : find ( ":" , 1 , true ) ~= nil and not ( host ) : match ( "^%[[^%]]*%]$" ) then
return nil , "nupp: URI component host cannot contain a component delimiter"
end


local path = components . path
if components . host or components . userInfo or port then
if path ~= nil and path ~= "" and ( path ) : sub ( 1 , 1 ) ~= "/" then
return nil , "nupp: URI component path must be empty or begin with \"/\" beside an authority"
end
elseif path ~= nil and ( path ) : sub ( 1 , 2 ) == "//" then
return nil , "nupp: URI component path cannot begin with \"//\" when there is no authority"
end
local out = scheme .. ":"
if components . host or components . userInfo or port then
out = out .. "//"
if components . userInfo then
out = out .. components . userInfo .. "@"
end
out = out .. ( components . host or "" )
if port then
out = out .. ":" .. tostring ( port )
end
end
out = out .. ( components . path or "" )
if components . query then
out = out .. "?" .. components . query
end
if components . fragment then
out = out .. "#" .. components . fragment
end

return out , nil
end

const URI_CACHE_CAPACITY = 1024
local uriCache = { }
local uriCacheSize = 0
local uriCacheNewest = nil
local uriCacheOldest = nil

local function adopt ( value ) 
local text = value : toString ( )
local found = uriCache [ text ]
if found ~= nil then
if found ~= uriCacheNewest then
local older , newer = found . older , found . newer
if older ~= nil then
older . newer = newer
else
uriCacheOldest = newer
end
if newer ~= nil then
newer . older = older
end
found . older = uriCacheNewest
found . newer = nil
uriCacheNewest . newer = found
uriCacheNewest = found
end

return found . value
end

local entry = { value = value , older = uriCacheNewest , newer = nil }
if uriCacheNewest ~= nil then
uriCacheNewest . newer = entry
else
uriCacheOldest = entry
end
uriCacheNewest = entry
uriCache [ text ] = entry
uriCacheSize = uriCacheSize + 1
if uriCacheSize > 1024 then
local evicted = uriCacheOldest
uriCacheOldest = evicted . newer
uriCacheOldest . older = nil
uriCache [ evicted . value : toString ( ) ] = nil
uriCacheSize = uriCacheSize - 1
end

return value
end































newURI=function ( value ) 
local text
if type ( value ) == "string" then
text = value
else
local composed , reason = fromComponents ( value )
if composed == nil then
return nil , reason
end
text = composed
end
local cached = uriCache [ text ]
if cached ~= nil then
return adopt ( cached . value )
end
local parts , reason = provider . parse ( text )
if parts == nil then
return nil , reason
end

return adopt (
setmetatable (
{
_text = parts . text ,
_scheme = parts . scheme ,
_authority = parts . authority ,
_username = parts . username ,
_password = parts . password ,
_host = parts . host ,
_port = parts . port ,
_path = parts . path ,
_query = parts . query ,
_fragment = parts . fragment ,
} ,
URI
)
)

end ;__nuppExports["newURI"]=newURI






validate=function ( value ) 
local parsed , reason = provider . parse ( value )
return parsed ~= nil , reason
end ;__nuppExports["validate"]=validate





isURI=function ( value ) 
return type ( value ) == "table" and getmetatable ( value ) == URI
end ;__nuppExports["isURI"]=isURI
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Components]="nupp.io.uri\0Components";__nuppWorkerRecords[URI]="nupp.io.uri\0URI"; end);if not __nuppOk then package.loaded["nupp.io.uri"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.uri"]=__nuppExports;return __nuppExports