_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.provider.nativeuuid"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local uuid4;__nuppExports["uuid4"]=function(...) return uuid4(...) end;local uuid7;__nuppExports["uuid7"]=function(...) return uuid7(...) end;

















const native = require ( "nupp.runtime.native" )

native . ffi . cdef [[
int32_t nuppNativeUuid4(uint8_t *, size_t);
int32_t nuppNativeUuid7(uint8_t *, size_t);
]]

const C = native . C
native . requireFeature ( 2 , "UUID support" )





uuid4=function ( ) 
local output = native . ffi . new ( "uint8_t[37]" )
native . succeeded ( C . nuppNativeUuid4 ( output , 37 ) , 2 )

return native . ffi . string ( output )
end ;__nuppExports["uuid4"]=uuid4





uuid7=function ( ) 
local output = native . ffi . new ( "uint8_t[37]" )
native . succeeded ( C . nuppNativeUuid7 ( output , 37 ) , 2 )

return native . ffi . string ( output )
end ;__nuppExports["uuid7"]=uuid7
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativeuuid"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativeuuid"]=__nuppExports;return __nuppExports