_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.provider.nativesystem"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local availableParallelism;__nuppExports["availableParallelism"]=function(...) return availableParallelism(...) end;











const ffi = require ( "ffi" )
const native = require ( "nupp.runtime.native" )
native . ffi . cdef [[
size_t nuppNativeAvailableParallelism(void);
]]

local platforms

= { OSX = "macos" , Linux = "linux" , Windows = "windows" , BSD = "bsd" , POSIX = "posix" }
local architectures = { x64 = "x86_64" , x86 = "x86" , arm64 = "aarch64" }

const platform = platforms [ ffi . os ] or string . lower ( ffi . os ) ;__nuppExports["platform"]=platform
const architecture = architectures [ ffi . arch ] or ffi . arch ;__nuppExports["architecture"]=architecture
const endianness = ffi . abi ( "le" ) and "little" or "big" ;__nuppExports["endianness"]=endianness
const pointerBits = ffi . abi ( "64bit" ) and 64 or 32 ;__nuppExports["pointerBits"]=pointerBits


availableParallelism=function ( ) 
return tonumber ( native . C . nuppNativeAvailableParallelism ( ) )
end ;__nuppExports["availableParallelism"]=availableParallelism
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativesystem"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativesystem"]=__nuppExports;return __nuppExports