_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.io"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local classify;__nuppExports["classify"]=function(...) return classify(...) end;local toError;__nuppExports["toError"]=function(...) return toError(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io\0runtime\0001") };







































































































































































































































































































































const bytes = require ( "nupp.io.internal.bytes" )
const scalars = require ( "nupp.io.internal.scalars" )
const lines = require ( "nupp.io.internal.lines" )





































































local Error = {} Error.__index = Error ;_G.nupp.__reflect.link(Error,__nuppT1[1],{ }) ;__nuppExports["Error"]=Error











Error . __tostring = function ( self ) 
return self . message
end

Error . __concat = function ( left , right ) 
return tostring ( left ) .. tostring ( right )
end






local KIND_PATTERNS

= {
{ "timeout" , "timed out" } ,
{ "timeout" , "timeouterror" } ,
{ "timeout" , "deadline" } ,
{ "notFound" , "no such file" } ,
{ "notFound" , "not found" } ,
{ "notFound" , "notfounderror" } ,
{ "notFound" , "cannot find" } ,
{ "notFound" , "does not exist" } ,
{ "notFound" , "no such host" } ,
{ "notFound" , "failed to lookup address" } ,
{ "notFound" , "name or service not known" } ,
{ "notFound" , "nodename nor servname" } ,
{ "refused" , "connection refused" } ,
{ "refused" , "actively refused" } ,
{ "refused" , "connectionrefused" } ,
{ "permission" , "permission denied" } ,
{ "permission" , "access is denied" } ,
{ "permission" , "not permitted" } ,
{ "permission" , "notallowederror" } ,
{ "permission" , "securityerror" } ,
{ "closed" , "broken pipe" } ,
{ "closed" , "connection reset" } ,
{ "closed" , "connection aborted" } ,
{ "closed" , "is closed" } ,
{ "closed" , "was closed" } ,
{ "closed" , "no longer reading" } ,
{ "closed" , "aborterror" } ,
{ "limit" , "exceed" } ,
{ "limit" , "too large" } ,
{ "limit" , "too many" } ,
{ "limit" , "too long" } ,
{ "limit" , "quotaexceedederror" } ,
{ "limit" , "no space" } ,
{ "limit" , "capacity" } ,
{ "unsupported" , "not supported" } ,
{ "unsupported" , "unsupported" } ,
{ "unsupported" , "notsupportederror" } ,
{ "invalid" , "invalid" } ,
{ "invalid" , "malformed" } ,
{ "invalid" , "typemismatcherror" } ,
}







classify=function ( message ) 
const lowered = message : lower ( )
for _ , entry in ipairs ( KIND_PATTERNS ) do
if lowered : find ( entry [ 2 ] , 1 , true ) ~= nil then
return entry [ 1 ]
end
end

return "other"
end ;__nuppExports["classify"]=classify







toError=function ( reason , kind ) 
if reason == nil then
return nil
end
if ( _G.getmetatable( reason )?.__index == Error ) then
return reason
end
const message = tostring ( reason )

return ( _G.setmetatable({ kind =  kind ?? classify ( message ) ,  message =  message }, Error) )
end ;__nuppExports["toError"]=toError








































const newBuffer = bytes . newBuffer ;__nuppExports["newBuffer"]=newBuffer



















const newStringReader = bytes . newStringReader ;__nuppExports["newStringReader"]=newStringReader











const newQueueReader = bytes . newQueueReader ;__nuppExports["newQueueReader"]=newQueueReader























const newScalarReader = scalars . newScalarReader ;__nuppExports["newScalarReader"]=newScalarReader























const newScalarWriter = scalars . newScalarWriter ;__nuppExports["newScalarWriter"]=newScalarWriter












const readAll = bytes . readAll ;__nuppExports["readAll"]=readAll











const newLines = lines . newLines ;__nuppExports["newLines"]=newLines
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Error]="nupp.io\0Error"; end);if not __nuppOk then package.loaded["nupp.io"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io"]=__nuppExports;return __nuppExports