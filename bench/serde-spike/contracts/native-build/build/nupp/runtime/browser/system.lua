_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.browser.system"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local availableParallelism;__nuppExports["availableParallelism"]=function(...) return availableParallelism(...) end;












const response = require ( "nupp.runtime.browser.response" )

const platform = "browser" ;__nuppExports["platform"]=platform
local vm = rawget ( _G , "jit" )
const architecture = vm and vm . arch or "wasm32" ;__nuppExports["architecture"]=architecture
const endianness = "little" ;__nuppExports["endianness"]=endianness
const pointerBits = 32 ;__nuppExports["pointerBits"]=pointerBits

availableParallelism=function ( ) 
local answer = response . await ( "system" , { } )
local count = type ( answer ) == "table" and answer . availableParallelism or nil
if type ( count ) ~= "number" or count ~= math . floor ( count ) or count < 1 or count > 9007199254740991 then
error ( "nupp: browser system returned invalid available parallelism" , 2 )
end

return count
end ;__nuppExports["availableParallelism"]=availableParallelism
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.system"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.system"]=__nuppExports;return __nuppExports