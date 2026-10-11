_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.provider.nativecrypto"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local randomBytes;__nuppExports["randomBytes"]=function(...) return randomBytes(...) end;











const native = require ( "nupp.runtime.native" )
native . ffi . cdef [[
int32_t nuppNativeRandomBytes(uint8_t *, size_t);
]]





randomBytes=function ( count ) 
if count < 0 or count ~= math . floor ( count ) or count > 1048576 then
error ( "random byte count must be an integer between 0 and 1048576" , 2 )
end
if count == 0 then
return ""
end
local output = native . ffi . new ( "uint8_t[?]" , count )
native . succeeded ( native . C . nuppNativeRandomBytes ( output , count ) , 2 )

return native . ffi . string ( output , count )
end ;__nuppExports["randomBytes"]=randomBytes
local __nuppWorkerSendables=_G.rawget(_G.nupp,"__workerSendables");if _G.type(__nuppWorkerSendables)~="table" then __nuppWorkerSendables=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerSendables",__nuppWorkerSendables) end;__nuppWorkerSendables[__nuppExports["randomBytes"]]={module="nupp.runtime.provider.nativecrypto",member="randomBytes",captures={values={},count=0},input="number",output="string"}; end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativecrypto"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativecrypto"]=__nuppExports;return __nuppExports