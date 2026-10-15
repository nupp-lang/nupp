_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















local native = require ( "nupp.runtime.native" )

native . ffi . cdef (
"uint64_t nuppNativeMonotonicNs(void);\
uint64_t nuppNativeWallMs(void);\
int32_t nuppNativeSleepMs(double);\
"

)

const C = native . C
local __nuppExportValue= require ( "nupp.time.internal.timers" ) . create ( {
now = function ( ) 
return assert ( tonumber ( C . nuppNativeMonotonicNs ( ) ) ) / 1.0e6
end ,
wallTime = function ( ) 
return assert ( tonumber ( C . nuppNativeWallMs ( ) ) )
end ,
sleep = function ( milliseconds ) 
native . succeeded ( C . nuppNativeSleepMs ( milliseconds ) , 3 )
end ,
} ) ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativetime"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativetime"]=__nuppExports;return __nuppExports